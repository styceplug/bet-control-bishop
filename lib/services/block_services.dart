import 'dart:async';
import 'dart:io';
import 'package:betcontrol_main/services/analytics_service.dart';
import 'package:betcontrol_main/services/subscription_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BlockService extends ChangeNotifier {
  static const String _keyIsBlocking = 'is_blocking';
  static const String _keyUnlockTime = 'unlock_time';
  static const String _keyPin = 'block_pin';
  static const String _keyVpnInterrupted = 'vpn_interrupted';

  static const _channel = MethodChannel('com.betcontrol/blocker');

  bool _isBlocking = false;
  bool _vpnInterrupted = false;
  bool _accessibilityLost = false;
  DateTime? _unlockTime;
  Timer? _timer;
  Timer? _protectionStatusTimer;
  Timer? _accessibilityCheckTimer;

  bool get isBlocking => _isBlocking;
  bool get vpnInterrupted => _vpnInterrupted;
  bool get accessibilityLost => _accessibilityLost;
  DateTime? get unlockTime => _unlockTime;

  Duration get timeRemaining {
    if (_unlockTime == null) return Duration.zero;
    final remaining = _unlockTime!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  String get timeRemainingText {
    final d = timeRemaining;
    if (d == Duration.zero) return 'Block expired';
    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    if (days > 0) return '$days days, $hours hrs remaining';
    if (hours > 0) return '$hours hrs, $minutes min remaining';
    return '$minutes minutes remaining';
  }

  Future<bool> _isSubscriptionExpired() async {
    if (Platform.isIOS) {
      try {
        CustomerInfo customerInfo = await Purchases.getCustomerInfo();
        bool isActive = customerInfo.entitlements.all["BetControl"]?.isActive == true;
        return !isActive; // If not active, it's expired
      } catch (e) {
        debugPrint("RevenueCat check failed: $e");
        return true; // Assume expired if check fails
      }
    }

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return false;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 5));

      if (!doc.exists) return false;
      final data = doc.data()!;

      if (data['adminOverride'] == true) return false;

      final active = data['subscriptionActive'] ?? false;
      if (active && data['subscriptionExpiry'] != null) {
        final expiry = (data['subscriptionExpiry'] as Timestamp).toDate();
        if (DateTime.now().isBefore(expiry)) return false;
      }

      if (data['trialStartedAt'] != null) {
        final trialStart = (data['trialStartedAt'] as Timestamp).toDate();
        final trialEnd = trialStart.add(const Duration(days: 3));
        if (DateTime.now().isBefore(trialEnd)) return false;
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isBlocking = prefs.getBool(_keyIsBlocking) ?? false;
    _vpnInterrupted = prefs.getBool(_keyVpnInterrupted) ?? false;

    // Flutter stores unlock_time via setInt which overflows for ms timestamps
    // (ms epoch > Int32 max). Read it, but treat 0 or obviously wrong values
    // as missing and fall back to the native ProtectionStateStore Long.
    final unlockMillis = prefs.getInt(_keyUnlockTime);
    if (unlockMillis != null && unlockMillis > 0) {
      _unlockTime = DateTime.fromMillisecondsSinceEpoch(unlockMillis);
    }

    // If Flutter prefs gave us no valid unlock time (overflow, missing, or
    // already in the past) but blocking is still flagged as active, ask the
    // native layer for the correct Long value from ProtectionStateStore.
    if (_isBlocking &&
        (_unlockTime == null || _unlockTime!.isBefore(DateTime.now()))) {
      try {
        final nativeUnlockTime =
            await _channel.invokeMethod<int>('getNativeUnlockTime');
        if (nativeUnlockTime != null && nativeUnlockTime > 0) {
          _unlockTime =
              DateTime.fromMillisecondsSinceEpoch(nativeUnlockTime);
        }
      } catch (_) {}
    }

    if (_isBlocking) {
      final timeExpired =
          _unlockTime != null && DateTime.now().isAfter(_unlockTime!);
      final subExpired = await _isSubscriptionExpired();

      if (timeExpired || subExpired) {
        await _deactivateBlock();
      } else {
        _startTimer();
        _startProtectionStatusTimer();
        _startAccessibilityCheckTimer();
        await _startNativeServices();
      }
    }

    notifyListeners();
  }

  /// Activates the block.
  ///
  /// VPN permission is checked FIRST before saving any state — if the system
  /// dialog needs to show, we return false immediately and the UI stays on
  /// the setup screen. State is only saved after VPN is confirmed started.
  Future<bool> activateBlock({
    required int durationDays,
    required String pin,
  }) async {
    if (_isBlocking) return false;

    String? vpnResult;
    try {
      vpnResult = await _channel.invokeMethod<String>('startVpn');
    } catch (e) {
      debugPrint('VPN start error: $e');
      return false;
    }

    if (vpnResult == 'requesting_permission') {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    _unlockTime = DateTime.now().add(Duration(days: durationDays));
    _isBlocking = true;
    _vpnInterrupted = false;
    _accessibilityLost = false;

    await prefs.setBool(_keyIsBlocking, true);
    await prefs.setBool(_keyVpnInterrupted, false);
    await prefs.setInt(_keyUnlockTime, _unlockTime!.millisecondsSinceEpoch);
    await prefs.setString(_keyPin, pin);

    // Sync native state — also schedules the expiry alarm
    await _syncNativeBlockState(isBlocking: true);

    _startTimer();
    _startProtectionStatusTimer();
    _startAccessibilityCheckTimer();

    notifyListeners();

    // ── Analytics ─────────────────────────────────────────────────────────
    // Log how long the user chose to block for — this tells us which
    // durations are most popular and how serious users are about recovery.
    await AnalyticsService.logBlockActivated(durationDays: durationDays);
    await AnalyticsService.setBlockingStatus(true);

    return true;
  }

  Future<void> requestDeviceAdmin() async {
    try {
      await _channel.invokeMethod('requestDeviceAdmin');
    } catch (e) {
      debugPrint('Device admin request error: $e');
    }
  }

  Future<bool> isDeviceAdminActive() async {
    try {
      final result = await _channel.invokeMethod<bool>('isDeviceAdminActive');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> isVpnPermissionGranted() async {
    try {
      final result = await _channel.invokeMethod<bool>('isVpnPermissionGranted');
      return result ?? false;
    } catch (e) {
      debugPrint('VPN permission check error: $e');
      return false;
    }
  }



  Future<void> requestVpnPermission() async {
    try {
      await _channel.invokeMethod('requestVpnPermission');
    } on PlatformException catch (e) {
      if (e.message != null && e.message!.contains('configuration is unchanged')) {
        debugPrint('VPN already configured, skipping.');
        return;
      }
      rethrow;
    }
  }

  Future<void> _startNativeServices() async {
    try {
      await _channel.invokeMethod('syncBlockState', {
        'isBlocking': _isBlocking,
        'unlockTime': _unlockTime?.millisecondsSinceEpoch ?? 0,
      });
      await _channel.invokeMethod('startVpn');
    } catch (e) {
      debugPrint('Native service error: $e');
    }
  }

  Future<void> restartProtection() async {
    if (!_isBlocking) return;
    _vpnInterrupted = false;
    _accessibilityLost = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyVpnInterrupted, false);
    await _startNativeServices();
    await refreshProtectionStatus();

    // ── Analytics ─────────────────────────────────────────────────────────
    // Fires when the VPN restarts after a reboot or interruption.
    // Tells us how often users are experiencing recovery events.
    await AnalyticsService.logBlockRestored();
  }

  Future<void> deactivateBlockDueToTrialExpiry() async {
    if (!_isBlocking) return;
    await _deactivateBlock();
  }

  Future<void> refreshProtectionStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final interrupted = prefs.getBool(_keyVpnInterrupted) ?? false;
    if (_vpnInterrupted != interrupted) {
      _vpnInterrupted = interrupted;
      notifyListeners();
    }
  }

  void _startAccessibilityCheckTimer() {
    _accessibilityCheckTimer?.cancel();
    _accessibilityCheckTimer =
        Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!_isBlocking) return;
      try {
        final enabled =
            await _channel.invokeMethod<bool>('isAccessibilityEnabled') ??
                false;
        if (_accessibilityLost != !enabled) {
          _accessibilityLost = !enabled;
          notifyListeners();
        }
      } catch (_) {}
    });
  }

  Future<bool> hasConflictingVpn() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasConflictingVpn');
      return result ?? false;
    } catch (e) {
      debugPrint('VPN conflict check error: $e');
      return false;
    }
  }

  Future<bool> isAlwaysOnVpnEnabled() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('isAlwaysOnVpnEnabled');
      return result ?? false;
    } catch (e) {
      debugPrint('Always-on VPN check error: $e');
      return false;
    }
  }

  Future<void> openVpnSettings() async {
    try {
      await _channel.invokeMethod('openVpnSettings');
    } catch (e) {
      debugPrint('VPN settings error: $e');
    }
  }

  Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (e) {
      debugPrint('Accessibility settings error: $e');
    }
  }

  Future<bool> isAccessibilityEnabled() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('isAccessibilityEnabled');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final savedPin = prefs.getString(_keyPin);
    return savedPin == pin;
  }

  Future<bool> hasPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_keyPin);
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      final timeExpired =
          _unlockTime != null && DateTime.now().isAfter(_unlockTime!);

      // Only check subscription every 30 minutes to avoid hammering Firebase
      // and to prevent false expiry when app is backgrounded on slow networks.
      final subExpired = DateTime.now().minute % 30 == 0
          ? await _isSubscriptionExpired()
          : false;

      if (timeExpired || subExpired) {
        await _deactivateBlock();
        timer.cancel();
      }
      notifyListeners();
    });
  }

  void _startProtectionStatusTimer() {
    _protectionStatusTimer?.cancel();
    _protectionStatusTimer =
        Timer.periodic(const Duration(seconds: 5), (_) async {
      await refreshProtectionStatus();
    });
  }

  Future<void> _deactivateBlock() async {
    final prefs = await SharedPreferences.getInstance();
    _isBlocking = false;
    _unlockTime = null;
    _vpnInterrupted = false;
    _accessibilityLost = false;
    _timer?.cancel();
    _protectionStatusTimer?.cancel();
    _accessibilityCheckTimer?.cancel();
    await prefs.setBool(_keyIsBlocking, false);
    await prefs.setBool(_keyVpnInterrupted, false);
    await prefs.remove(_keyUnlockTime);
    await prefs.remove(_keyPin);
    await _syncNativeBlockState(isBlocking: false);
    try {
      await _channel.invokeMethod('stopVpn');
    } catch (e) {
      debugPrint('Stop VPN error: $e');
    }
    notifyListeners();

    // ── Analytics ─────────────────────────────────────────────────────────
    // Fires when the block ends — either timer expired or subscription lapsed.
    // Update the user property so Analytics can segment currently-blocking
    // users from those whose block has ended.
    await AnalyticsService.logBlockExpired();
    await AnalyticsService.setBlockingStatus(false);
  }

  /*Future<void> _syncNativeBlockState({required bool isBlocking}) async {
    try {
      await _channel.invokeMethod('syncBlockState', {
        'isBlocking': isBlocking,
        'unlockTime': isBlocking
            ? (_unlockTime?.millisecondsSinceEpoch ?? 0)
            : 0,
      });
    } catch (e) {
      debugPrint('Native block state sync error: $e');
    }
  }*/

  Future<void> _syncNativeBlockState({required bool isBlocking}) async {
    try {
      final subscriptionService = SubscriptionService();
      final hasActiveSub = await subscriptionService.isSubscriptionActive();

      await _channel.invokeMethod('syncBlockState', {
        'isBlocking': isBlocking,
        'hasActiveSubscription': hasActiveSub,
        'unlockTime': isBlocking
            ? (_unlockTime?.millisecondsSinceEpoch ?? 0)
            : 0,
      });
    } catch (e) {
      debugPrint('Native block state sync error: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _protectionStatusTimer?.cancel();
    _accessibilityCheckTimer?.cancel();
    super.dispose();
  }
}