import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  static final _analytics = FirebaseAnalytics.instance;

  // ── Auth events ────────────────────────────────────────────────────
  static Future<void> logSignUp({required String method}) async {
    await _analytics.logSignUp(signUpMethod: method);
  }

  static Future<void> logLogin({required String method}) async {
    await _analytics.logLogin(loginMethod: method);
  }

  static Future<void> logSignOut() async {
    await _analytics.logEvent(name: 'sign_out');
  }

  // ── Block events ───────────────────────────────────────────────────
  static Future<void> logBlockActivated({required int durationDays}) async {
    await _analytics.logEvent(
      name: 'block_activated',
      parameters: {'duration_days': durationDays},
    );
  }

  static Future<void> logBlockExpired() async {
    await _analytics.logEvent(name: 'block_expired');
  }

  static Future<void> logBlockRestored() async {
    await _analytics.logEvent(name: 'block_restored_after_reboot');
  }

  // ── Subscription events ────────────────────────────────────────────
  static Future<void> logTrialStarted() async {
    await _analytics.logEvent(name: 'trial_started');
  }

  static Future<void> logTrialExpired() async {
    await _analytics.logEvent(name: 'trial_expired');
  }

  static Future<void> logSubscriptionPurchased() async {
    await _analytics.logEvent(
      name: 'subscription_purchased',
      parameters: {'amount': 1500, 'currency': 'NGN'},
    );
  }

  static Future<void> logSubscriptionExpired() async {
    await _analytics.logEvent(name: 'subscription_expired');
  }

  static Future<void> logPaymentAbandoned() async {
    await _analytics.logEvent(name: 'payment_abandoned');
  }

  // ── Setup events ───────────────────────────────────────────────────
  static Future<void> logSetupCompleted() async {
    await _analytics.logEvent(name: 'protection_setup_completed');
  }

  // ── Profile events ─────────────────────────────────────────────────
  static Future<void> logProfileCompleted() async {
    await _analytics.logEvent(name: 'profile_completed');
  }

  // ── User properties ────────────────────────────────────────────────
  // These segment your users in the Analytics dashboard
  static Future<void> setSubscriptionStatus(String status) async {
    await _analytics.setUserProperty(
      name: 'subscription_status',
      value: status, // 'trial', 'active', 'expired', 'inactive'
    );
  }

  static Future<void> setBlockingStatus(bool isBlocking) async {
    await _analytics.setUserProperty(
      name: 'is_blocking',
      value: isBlocking.toString(),
    );
  }
}