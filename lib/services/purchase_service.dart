import 'dart:async';
import 'dart:convert';
import 'dart:io';
// import 'package:betcontrol_main/config/paystack_config.dart.dart';
import 'package:betcontrol_main/services/analytics_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_paystack_plus/flutter_paystack_plus.dart';
import 'package:http/http.dart' as http;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PaymentResult {
  final bool success;
  final String? errorMessage;
  final PaymentErrorType? errorType;

  PaymentResult({required this.success, this.errorMessage, this.errorType});
  PaymentResult.success()
      : success = true,
        errorMessage = null,
        errorType = null;
  PaymentResult.error(String message, PaymentErrorType type)
      : success = false,
        errorMessage = message,
        errorType = type;
}

enum PaymentErrorType {
  network,
  verification,
  cancelled,
  timeout,
  server,
  unknown,
  incompleteReminder,
}

class PurchaseService {
  final _firestore = FirebaseFirestore.instance;

  static const _kPendingRef = 'bc_pending_payment_reference';
  static const _kPendingCreatedAt = 'bc_pending_payment_created_at';
  static const _kReminderShown = 'bc_incomplete_reminder_shown';
  static const _kMaxRecoveryMs = 48 * 60 * 60 * 1000; // 48 hours
  static bool _recoveryInProgress = false;

  // ── Cloud Function URL for payment verification ───────────────────────────
  // Secret key never leaves the server — verification happens in Cloud Function
  static const String _verifyFunctionUrl =
      'https://us-central1-betcontrol-7d562.cloudfunctions.net/verifyPayment';

  Future<void> _savePendingPayment(String reference) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPendingRef, reference);
    await prefs.setInt(
        _kPendingCreatedAt, DateTime.now().millisecondsSinceEpoch);
    await prefs.remove(_kReminderShown);
  }

  Future<void> _clearPendingPayment() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPendingRef);
    await prefs.remove(_kPendingCreatedAt);
    await prefs.remove(_kReminderShown);
  }

  Future<bool> _activateSubscription(String reference,
      {bool recovered = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final expiry = DateTime.now().add(
      const Duration(days: PaystackConfig.subscriptionDays),
    );

    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        await _firestore.collection('users').doc(user.uid).update({
          'subscriptionActive': true,
          'subscriptionExpiry': Timestamp.fromDate(expiry),
          'lastPaymentReference': reference,
          'lastPaymentDate': FieldValue.serverTimestamp(),
          if (recovered) 'lastRecoveredAt': FieldValue.serverTimestamp(),
        }).timeout(const Duration(seconds: 15));

        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('payments')
            .add({
          'reference': reference,
          'amount': 1500,
          'currency': 'NGN',
          'mode': PaystackConfig.mode,
          'paidAt': FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromDate(expiry),
          if (recovered) 'recovered': true,
        });

        // ── Analytics ───────────────────────────────────────────────────────
        // Log purchase and update the subscription status user property.
        // This fires whether the payment was made fresh or recovered from
        // a pending reference — both count as a successful subscription.
        await AnalyticsService.logSubscriptionPurchased();
        await AnalyticsService.setSubscriptionStatus('active');

        return true;
      } catch (e) {
        if (attempt < 3) await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    return false;
  }

  // ── Verify payment via Cloud Function (secret key stays server-side) ──────
  Future<String?> _getPaymentStatus(String reference) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      // Get Firebase ID token to authenticate the request
      final idToken = await user.getIdToken();

      final response = await http.post(
        Uri.parse(_verifyFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: json.encode({'reference': reference}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['status'] as String?;
      }
      return null;
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Recovery — called on every cold start ─────────────────────────────────
  Future<PaymentResult?> recoverPendingPayment() async {
    if (_recoveryInProgress) return null;
    _recoveryInProgress = true;
    try {
      return await _doRecovery();
    } finally {
      _recoveryInProgress = false;
    }
  }

  Future<PaymentResult?> _doRecovery() async {
    final prefs = await SharedPreferences.getInstance();
    final ref = prefs.getString(_kPendingRef);
    final createdAt = prefs.getInt(_kPendingCreatedAt) ?? 0;

    if (ref == null) return null;

    final age = DateTime.now().millisecondsSinceEpoch - createdAt;
    if (age > _kMaxRecoveryMs) {
      await _clearPendingPayment();
      return null;
    }

    String? status;
    for (int attempt = 1; attempt <= 3; attempt++) {
      status = await _getPaymentStatus(ref);
      if (status != null) break;
      if (attempt < 3) await Future.delayed(Duration(seconds: attempt * 3));
    }

    if (status == 'success' || status == 'pending') {
      final saved = await _activateSubscription(ref, recovered: true);
      if (saved) {
        await _clearPendingPayment();
        return PaymentResult.success();
      }
      return null;
    }

    if (status == 'failed') {
      await _clearPendingPayment();
      return null;
    }

    if (status == 'abandoned') {
      final alreadyShown = prefs.getBool(_kReminderShown) ?? false;
      if (alreadyShown) return null;
      await prefs.setBool(_kReminderShown, true);

      // ── Analytics ─────────────────────────────────────────────────────────
      // User started the payment flow but never completed it.
      // This tells us how many people are dropping off at the payment step.
      await AnalyticsService.logPaymentAbandoned();

      return PaymentResult.error(
        'You have an incomplete payment. If you\'ve already sent the money, '
            'your subscription will activate automatically when you reopen the app.',
        PaymentErrorType.incompleteReminder,
      );
    }

    return null;
  }



  Future<PaymentResult> payAndSubscribe(BuildContext context, {Package? applePackage}) async {
    if (Platform.isIOS) {
      if (applePackage == null) {
        return PaymentResult.error("No package selected for Apple purchase", PaymentErrorType.unknown);
      }
      return await processAppleSubscription(applePackage);
    } else {
      return await payAndroidPaystack(context);
    }
  }


  Future<PaymentResult> payAndroidPaystack(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return PaymentResult.error(
          'You must be logged in to subscribe', PaymentErrorType.unknown);
    }
    if (!context.mounted) {
      return PaymentResult.error(
          'Screen closed during payment', PaymentErrorType.cancelled);
    }

    final email = user.email ?? 'user@betcontrol.app';
    final reference = 'BC_${DateTime.now().millisecondsSinceEpoch}';

    await _savePendingPayment(reference);
    if (!context.mounted) {
      return PaymentResult.error(
          'Screen closed during payment', PaymentErrorType.cancelled);
    }

    try {
      await FlutterPaystackPlus.openPaystackPopup(
        publicKey: PaystackConfig.publicKey,
        secretKey: PaystackConfig.secretKey,
        context: context,
        customerEmail: email,
        amount: PaystackConfig.subscriptionAmountKobo.toString(),
        reference: reference,
        currency: 'NGN',
        metadata: {
          'userId': user.uid,
          'type': 'subscription',
          'mode': PaystackConfig.mode,
        },
        onClosed: () =>
            debugPrint('Paystack popup closed — ref kept on disk'),
        onSuccess: () => debugPrint('onSuccess fired'),
      );
    } on SocketException {
      await _clearPendingPayment();
      return PaymentResult.error(
          'No internet connection. Please try again.',
          PaymentErrorType.network);
    } on TimeoutException {
      await _clearPendingPayment();
      return PaymentResult.error(
          'Connection timed out. Please try again.',
          PaymentErrorType.timeout);
    } catch (e) {
      if (_isNetworkError(e)) {
        await _clearPendingPayment();
        return PaymentResult.error(
            'No internet connection.', PaymentErrorType.network);
      }
      rethrow;
    }

    await Future.delayed(const Duration(seconds: 2));

    // Verify via Cloud Function — secret key never touches the app
    final status = await _getPaymentStatus(reference);

    if (status == 'success' || status == 'pending') {
      final saved = await _activateSubscription(reference);
      if (saved) {
        await _clearPendingPayment();
        return PaymentResult.success();
      }
      return PaymentResult.error(
        'Payment successful but could not activate. Reopen the app.',
        PaymentErrorType.server,
      );
    }

    if (status == 'failed') {
      await _clearPendingPayment();
      return PaymentResult.error(
          'Payment was not completed. Please try again.',
          PaymentErrorType.verification);
    }

    // abandoned or null — ref stays for recovery
    return PaymentResult.error(
      'If you completed the bank transfer, your subscription will activate '
          'automatically the next time you open the app.',
      PaymentErrorType.verification,
    );
  }

  Future<PaymentResult> processAppleSubscription(Package packageToBuy) async {
    try {
      // 1. Purchase the specific package passed from the UI
      PurchaseResult result = await Purchases.purchasePackage(packageToBuy);

      // 2. Check the CORRECT entitlement ID
      if (result.customerInfo.entitlements.all["BetControl"]?.isActive == true) {
        return PaymentResult.success();
      }

      return PaymentResult.error("Purchase failed", PaymentErrorType.unknown);
    } on PlatformException catch (e) {
      var errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        return PaymentResult.error("Purchase cancelled", PaymentErrorType.cancelled);
      }
      return PaymentResult.error(e.message ?? "Unknown error", PaymentErrorType.unknown);
    } catch (e) {
      return PaymentResult.error(e.toString(), PaymentErrorType.unknown);
    }
  }



  bool _isNetworkError(dynamic e) {
    final s = e.toString().toLowerCase();
    return s.contains('socket') ||
        s.contains('network') ||
        s.contains('connection') ||
        s.contains('unreachable') ||
        s.contains('failed host lookup');
  }
}

class PaystackConfig {
  static const String publicKey = '';
  static const String secretKey = '';

  // 'live' or 'test'
  static const String mode = 'live';

  // ₦1,500 in kobo (multiply naira by 100)
  static const int subscriptionAmountKobo = 150000;

  // How many days a subscription lasts
  static const int subscriptionDays = 30;
}