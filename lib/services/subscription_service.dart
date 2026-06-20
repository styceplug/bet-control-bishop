import 'package:betcontrol_main/services/analytics_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum SubscriptionStatus {
  active,       // paid and valid
  trial,        // free trial active
  trialExpired, // trial ended, not paid
  inactive,     // never had trial or subscription
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

  static const int trialDays = 3;
  static const int trialWarningHours = 1;

  // ── Simple bool check (used by existing code) ─────────────────────────────
  Future<bool> isSubscriptionActive() async {
    final details = await getDetails();
    return details.isAccessGranted;
  }

  // ── Full details (used by BlockScreen) ────────────────────────────────────
  Future<SubscriptionDetails> getDetails() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const SubscriptionDetails(status: SubscriptionStatus.inactive);
    }

    try {
      final doc =
          await _firestore.collection('users').doc(user.uid).get();
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
        .map((snap) {
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

  // ── Activate trial (once per account) ────────────────────────────────────
  /// Returns true if trial was freshly activated, false if already used.
  Future<bool> activateTrial() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final doc =
          await _firestore.collection('users').doc(user.uid).get();
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
      final doc =
          await _firestore.collection('users').doc(user.uid).get();
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
      final doc =
          await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return null;
      return doc.data();
    } catch (_) {
      return null;
    }
  }
}