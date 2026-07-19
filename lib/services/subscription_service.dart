import 'dart:async';
import 'dart:io';

import 'package:betcontrol_main/services/analytics_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

enum SubscriptionStatus {
  active, // paid and valid
  trial, // free trial active
  trialExpired, // trial ended, not paid
  inactive, // never had trial or subscription
}

class SubscriptionDetails {
  final SubscriptionStatus status;
  final DateTime? expiry;
  final bool adminOverride;

  const SubscriptionDetails({
    required this.status,
    this.expiry,
    this.adminOverride = false,
  });

  bool get isAccessGranted =>
      adminOverride ||
      status == SubscriptionStatus.active ||
      status == SubscriptionStatus.trial;

  bool get isTrial => status == SubscriptionStatus.trial;

  Duration? get timeRemaining {
    if (expiry == null) return null;
    final remaining = expiry!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }
}

class SubscriptionService {
  final _firestore = FirebaseFirestore.instance;
  static const _channel = MethodChannel('com.betcontrol/blocker');
  static const String entitlementId = 'BetControl';

  static const int trialDays = 3;
  static const int trialWarningHours = 1;

  // ── Simple bool check (used by existing code) ─────────────────────────────
  Future<bool> isSubscriptionActive() async {
    final details = await getDetails();
    return details.isAccessGranted;
  }

  // ── Fresh re-check (bypasses the RevenueCat cache) ────────────────────────
  /// Use on app launch/resume so an existing subscription is detected even
  /// when the cached customer info is stale or was fetched before purchase.
  Future<SubscriptionDetails> refreshDetails() async {
    if (Platform.isIOS) {
      try {
        await Purchases.invalidateCustomerInfoCache();
      } catch (_) {}
    }
    return getDetails();
  }

  // ── Full details (used by BlockScreen) ────────────────────────────────────
  /// With [throwOnError] the method rethrows verification failures instead of
  /// reporting `inactive`. Callers that DEACTIVATE protection must use it so a
  /// network/Apple outage is never mistaken for an expired subscription.
  Future<SubscriptionDetails> getDetails({bool throwOnError = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const SubscriptionDetails(status: SubscriptionStatus.inactive);
    }

    try {
      final appleDetails =
          await _getAppleSubscriptionDetails(throwOnError: throwOnError);
      if (appleDetails?.isAccessGranted == true) {
        return appleDetails!;
      }

      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) {
        return const SubscriptionDetails(status: SubscriptionStatus.inactive);
      }

      final data = doc.data()!;

      // Admin override
      if (data['adminOverride'] == true) {
        return const SubscriptionDetails(
            status: SubscriptionStatus.active, adminOverride: true);
      }

      // Check paid subscription first
      final active = data['subscriptionActive'] ?? false;
      if (active && data['subscriptionExpiry'] != null) {
        final expiry = (data['subscriptionExpiry'] as Timestamp).toDate();
        if (DateTime.now().isBefore(expiry)) {
          return SubscriptionDetails(
              status: SubscriptionStatus.active, expiry: expiry);
        }
      }

      final appleSandboxExpiry = _appleSandboxFallbackExpiry(data);
      if (appleSandboxExpiry != null) {
        return SubscriptionDetails(
            status: SubscriptionStatus.active, expiry: appleSandboxExpiry);
      }

      // Check trial
      if (data['trialStartedAt'] != null) {
        final trialStart = (data['trialStartedAt'] as Timestamp).toDate();
        final trialEnd = trialStart.add(const Duration(days: trialDays));
        if (DateTime.now().isBefore(trialEnd)) {
          return SubscriptionDetails(
              status: SubscriptionStatus.trial, expiry: trialEnd);
        }
        return SubscriptionDetails(
            status: SubscriptionStatus.trialExpired, expiry: trialEnd);
      }

      return const SubscriptionDetails(status: SubscriptionStatus.inactive);
    } catch (_) {
      if (throwOnError) rethrow;
      return const SubscriptionDetails(status: SubscriptionStatus.inactive);
    }
  }

  // ── Stream version — BlockScreen listens to this ─────────────────────────
  Stream<SubscriptionDetails> detailsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream.value(
          const SubscriptionDetails(status: SubscriptionStatus.inactive));
    }

    return _firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .asyncMap((snap) async {
      final appleDetails = await _getAppleSubscriptionDetails();
      if (appleDetails?.isAccessGranted == true) {
        return appleDetails!;
      }

      if (!snap.exists) {
        return const SubscriptionDetails(status: SubscriptionStatus.inactive);
      }

      final data = snap.data()!;

      if (data['adminOverride'] == true) {
        return const SubscriptionDetails(
            status: SubscriptionStatus.active, adminOverride: true);
      }

      final active = data['subscriptionActive'] ?? false;
      if (active && data['subscriptionExpiry'] != null) {
        final expiry = (data['subscriptionExpiry'] as Timestamp).toDate();
        if (DateTime.now().isBefore(expiry)) {
          return SubscriptionDetails(
              status: SubscriptionStatus.active, expiry: expiry);
        }
      }

      final appleSandboxExpiry = _appleSandboxFallbackExpiry(data);
      if (appleSandboxExpiry != null) {
        return SubscriptionDetails(
            status: SubscriptionStatus.active, expiry: appleSandboxExpiry);
      }

      if (data['trialStartedAt'] != null) {
        final trialStart = (data['trialStartedAt'] as Timestamp).toDate();
        final trialEnd = trialStart.add(const Duration(days: trialDays));
        if (DateTime.now().isBefore(trialEnd)) {
          return SubscriptionDetails(
              status: SubscriptionStatus.trial, expiry: trialEnd);
        }
        return SubscriptionDetails(
            status: SubscriptionStatus.trialExpired, expiry: trialEnd);
      }

      return const SubscriptionDetails(status: SubscriptionStatus.inactive);
    });
  }

  Future<SubscriptionDetails?> _getAppleSubscriptionDetails(
      {bool throwOnError = false}) async {
    if (!Platform.isIOS) return null;

    try {
      final customerInfo = await Purchases.getCustomerInfo();
      final entitlement = customerInfo.entitlements.all[entitlementId];
      if (entitlement?.isActive != true) {
        // Verified: RevenueCat reachable, no active entitlement. Still confirm
        // with native StoreKit before concluding there is no subscription.
        return _getNativeAppleSubscriptionDetails(throwOnError: throwOnError);
      }

      final expiry = _parseRevenueCatDate(entitlement!.expirationDate);
      final status = entitlement.periodType == PeriodType.trial
          ? SubscriptionStatus.trial
          : SubscriptionStatus.active;

      return SubscriptionDetails(status: status, expiry: expiry);
    } catch (_) {
      // RevenueCat failed (outage/offline). Native StoreKit reads local
      // transactions, so it usually still works; if it also fails, surface
      // the error when requested so callers don't mistake it for "expired".
      return _getNativeAppleSubscriptionDetails(throwOnError: throwOnError);
    }
  }

  Future<SubscriptionDetails?> _getNativeAppleSubscriptionDetails(
      {bool throwOnError = false}) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getAppleSubscriptionStatus',
      );
      if (result?['active'] != true) return null;

      final expiryMillis = result?['expiryMillis'];
      final expiry = expiryMillis is int
          ? DateTime.fromMillisecondsSinceEpoch(expiryMillis)
          : null;

      return SubscriptionDetails(
        status: SubscriptionStatus.active,
        expiry: expiry,
      );
    } catch (_) {
      if (throwOnError) rethrow;
      return null;
    }
  }

  DateTime? _parseRevenueCatDate(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  DateTime? _appleSandboxFallbackExpiry(Map<String, dynamic> data) {
    if (!Platform.isIOS || data['appleIsSandbox'] != true) return null;

    final lastPaymentDate = data['lastPaymentDate'];
    if (lastPaymentDate is! Timestamp) return null;

    final fallbackExpiry =
        lastPaymentDate.toDate().add(const Duration(days: 30));
    if (DateTime.now().isBefore(fallbackExpiry)) {
      return fallbackExpiry;
    }

    return null;
  }

  // ── Activate trial (once per account) ────────────────────────────────────
  /// Returns true if trial was freshly activated, false if already used.
  Future<bool> activateTrial() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return false;

      final data = doc.data()!;

      // Already has trial or paid sub — don't overwrite
      if (data['trialStartedAt'] != null ||
          data['subscriptionActive'] == true) {
        return false;
      }

      await _firestore.collection('users').doc(user.uid).update({
        'trialStartedAt': FieldValue.serverTimestamp(),
        'trialUsed': true,
      });

      // ── Analytics ─────────────────────────────────────────────────────────
      // Log trial started and update the user property so the Analytics
      // dashboard can segment trial users from paid and inactive users.
      await AnalyticsService.logTrialStarted();
      await AnalyticsService.setSubscriptionStatus('trial');

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Whether this account has ever had a trial
  Future<bool> hasUsedTrial() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return false;
      return doc.data()!['trialUsed'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getSubscriptionDetails() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return null;
      return doc.data();
    } catch (_) {
      return null;
    }
  }
}
