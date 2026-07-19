import 'dart:async';
import 'dart:io';
import 'package:betcontrol_main/services/analytics_service.dart';
import 'package:betcontrol_main/services/subscription_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BlockService extends ChangeNotifier {
  static const String _keyIsBlocking = 'is_blocking';
  static const String _keyUnlockTime = 'unlock_time';
  static const String _keyPin = 'block_pin';
  static const String _keyVpnInterrupted = 'vpn_interrupted';
  static const String _keyHardCommitment = 'hard_commitment';

  static const _channel = MethodChannel('com.betcontrol/blocker');

  bool _isBlocking = false;
  bool _vpnInterrupted = false;
  bool _accessibilityLost = false;
  bool _hardCommitment = false;
  DateTime? _unlockTime;
  Timer? _timer;
  Timer? _protectionStatusTimer;
  Timer? _accessibilityCheckTimer;
  Timer? _filterDebugTimer;
  bool _nativeStartInFlight = false;
  String? _lastVpnPermissionError;
  bool _dnsSettingsNeedsActivation = false;

  bool get isBlocking => _isBlocking;
  bool get vpnInterrupted => _vpnInterrupted;
  bool get accessibilityLost => _accessibilityLost;
  /// When true (iOS), app uninstall is locked device-wide while protection is on.
  bool get hardCommitment => _hardCommitment;
  String? get lastVpnPermissionError => _lastVpnPermissionError;
  bool get dnsSettingsNeedsActivation => _dnsSettingsNeedsActivation;
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
        // throwOnError: a network/Apple outage must never read as "expired" —
        // deactivating a gambling block on a fetch failure is the worst
        // failure mode. Fail closed: keep protection on.
        final details =
            await SubscriptionService().getDetails(throwOnError: true);
        return !details.isAccessGranted;
      } catch (e) {
        debugPrint("iOS subscription check failed (keeping protection): $e");
        return false;
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
    _hardCommitment = prefs.getBool(_keyHardCommitment) ?? false;

    await _startDnsDebugConsoleLogging();

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
          _unlockTime = DateTime.fromMillisecondsSinceEpoch(nativeUnlockTime);
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
  /// Native protection permission is checked first before saving any state.
  /// On iOS this is Screen Time authorization; on Android this is the VPN path.
  Future<bool> activateBlock({
    required int durationDays,
    required String pin,
    bool hardCommitment = false,
  }) async {
    if (_isBlocking) return false;

    // Write block flags to the app group BEFORE starting the tunnel so the
    // DNS extension can block immediately (it reads isBlocking from app group).
    final prefs = await SharedPreferences.getInstance();
    _unlockTime = DateTime.now().add(Duration(days: durationDays));
    _isBlocking = true;
    _hardCommitment = hardCommitment;
    _vpnInterrupted = false;
    _accessibilityLost = false;

    await prefs.setBool(_keyIsBlocking, true);
    await prefs.setBool(_keyVpnInterrupted, false);
    await prefs.setBool(_keyHardCommitment, hardCommitment);
    await prefs.setInt(_keyUnlockTime, _unlockTime!.millisecondsSinceEpoch);
    await prefs.setString(_keyPin, pin);
    await _syncNativeBlockState(isBlocking: true);

    String? vpnResult;
    try {
      vpnResult = await _channel.invokeMethod<String>('startVpn');
    } catch (e) {
      debugPrint('Native protection start error: $e');
      // Roll back local active state if native shield failed to start.
      _isBlocking = false;
      _hardCommitment = false;
      _unlockTime = null;
      await prefs.setBool(_keyIsBlocking, false);
      await prefs.setBool(_keyHardCommitment, false);
      await _syncNativeBlockState(isBlocking: false);
      return false;
    }

    if (vpnResult == 'requesting_permission') {
      _isBlocking = false;
      _hardCommitment = false;
      _unlockTime = null;
      await prefs.setBool(_keyIsBlocking, false);
      await prefs.setBool(_keyHardCommitment, false);
      await _syncNativeBlockState(isBlocking: false);
      return false;
    }

    if (vpnResult == 'dns_settings_needs_activation') {
      _dnsSettingsNeedsActivation = true;
      _lastVpnPermissionError =
          'Website Shield DNS was installed but is not active yet. Go to Settings > General > VPN & Device Management > DNS and select BetControl Website Shield, then try again.';
      // Keep isBlocking true — apps stay blocked via Screen Time; user must
      // finish DNS activation for websites.
      notifyListeners();
      return false;
    }

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
      final result =
          await _channel.invokeMethod<bool>('isVpnPermissionGranted');
      return result ?? false;
    } catch (e) {
      debugPrint('🛡️ Shield permission check error: $e');
      return false;
    }
  }

  Future<bool> requestVpnPermission() async {
    try {
      _lastVpnPermissionError = null;
      _dnsSettingsNeedsActivation = false;
      debugPrint('🛡️ Shield: requesting permission…');
      final nativeResult = await _channel
          .invokeMethod('requestVpnPermission')
          .timeout(const Duration(seconds: 40));
      if (nativeResult == 'dns_settings_needs_activation') {
        _dnsSettingsNeedsActivation = true;
        _lastVpnPermissionError =
            'Website Shield DNS is installed but not active. Go to Settings > General > VPN & Device Management > DNS and select BetControl Website Shield.';
      } else if (nativeResult is String &&
          (nativeResult.contains('dns_settings') ||
              nativeResult.contains('vpn'))) {
        _lastVpnPermissionError = null;
      }
      final afterDiagnostics = await getWebsiteShieldDiagnostics();
      _printWebsiteShieldDiagnostics('after request', afterDiagnostics);
      final granted = await isVpnPermissionGranted();
      if (!granted && Platform.isIOS) {
        final mode =
            afterDiagnostics['websiteShieldEnforcementMode']?.toString();
        final dnsSettings = afterDiagnostics['dnsSettingsManager'];
        final configured = dnsSettings is Map &&
            dnsSettings['isConfiguredForBetControl'] == true;
        final enabled = dnsSettings is Map && dnsSettings['isEnabled'] == true;
        if (mode == 'dns-settings-needs-activation' ||
            (configured && !enabled)) {
          _dnsSettingsNeedsActivation = true;
          _lastVpnPermissionError =
              'Website Shield DNS was added but iOS has not enabled it yet. Go to Settings > VPN & Device Management > DNS and select BetControl Website Shield.';
        }
      }
      debugPrint(
          '🛡️ Shield: permission granted=$granted mode=${afterDiagnostics['websiteShieldEnforcementMode']} status=${_tunnelStatus(afterDiagnostics)}');
      return granted;
    } on PlatformException catch (e) {
      if (e.message != null &&
          e.message!.contains('configuration is unchanged')) {
        final granted = await isVpnPermissionGranted();
        if (!granted && Platform.isIOS) {
          _lastVpnPermissionError =
              'Website Shield DNS is saved but not enabled. Go to Settings > VPN & Device Management > DNS and select BetControl Website Shield.';
        }
        return granted;
      }
      _lastVpnPermissionError = e.message ?? e.code;
      debugPrint('🛡️ Shield: permission failed ${e.code} ${e.message}');
      return false;
    } on TimeoutException {
      _lastVpnPermissionError =
          'Website Shield is taking too long. Allow the VPN if prompted, or enable BetControl under Settings > VPN & Device Management > DNS.';
      debugPrint('🛡️ Shield: permission timed out');
      return false;
    } catch (e) {
      _lastVpnPermissionError = e.toString();
      debugPrint('🛡️ Shield: permission error: $e');
      return false;
    }
  }

  String _tunnelStatus(Map<String, dynamic> diagnostics) {
    final tunnel = diagnostics['packetTunnelManager'];
    if (tunnel is Map) return tunnel['status']?.toString() ?? '?';
    return '?';
  }

  Future<bool> runManagedWebContentSingleDomainTest() async {
    if (!Platform.isIOS) return false;

    try {
      final result =
          await _channel.invokeMethod('runManagedWebContentSingleDomainTest');
      debugPrint('🛡️ ScreenTimeTest: blockedByFilter result -> $result');
      return true;
    } on PlatformException catch (e) {
      debugPrint(
          '🛡️ ScreenTimeTest: blockedByFilter failed code=${e.code} message=${e.message}');
      return false;
    } catch (e) {
      debugPrint('🛡️ ScreenTimeTest: blockedByFilter error: $e');
      return false;
    }
  }

  Future<bool> runManagedWebDomainShieldSingleDomainTest() async {
    if (!Platform.isIOS) return false;

    try {
      final result = await _channel
          .invokeMethod('runManagedWebDomainShieldSingleDomainTest');
      debugPrint('🛡️ ScreenTimeTest: shield.webDomains result -> $result');
      return true;
    } on PlatformException catch (e) {
      debugPrint(
          '🛡️ ScreenTimeTest: shield.webDomains failed code=${e.code} message=${e.message}');
      return false;
    } catch (e) {
      debugPrint('🛡️ ScreenTimeTest: shield.webDomains error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> getWebsiteShieldDiagnostics() async {
    if (!Platform.isIOS) return const {};

    try {
      final raw = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('getWebsiteShieldDiagnostics');
      return raw?.map((key, value) => MapEntry(key.toString(), value)) ??
          const {};
    } catch (e) {
      return {'diagnosticsError': e.toString()};
    }
  }

  Future<void> logWebsiteShieldDiagnostics(String label) async {
    if (!Platform.isIOS) return;
    final diagnostics = await getWebsiteShieldDiagnostics();
    _printWebsiteShieldDiagnostics(label, diagnostics);
  }

  Future<bool> selectScreenTimeTargets() async {
    if (!Platform.isIOS) return true;

    try {
      debugPrint('🛡️ ProtectionShield: opening Screen Time target picker');
      final raw = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('selectScreenTimeTargets');
      final result =
          raw?.map((key, value) => MapEntry(key.toString(), value)) ??
              const <String, dynamic>{};
      debugPrint('🛡️ ProtectionShield: picker result -> $result');

      final diagnostics = await getWebsiteShieldDiagnostics();
      _printWebsiteShieldDiagnostics('after picker', diagnostics);

      final webTokenCount =
          diagnostics['screenTimeSelectedWebDomainTokenCount'];
      final appTokenCount =
          diagnostics['screenTimeSelectedApplicationTokenCount'];
      final categoryTokenCount =
          diagnostics['screenTimeSelectedCategoryTokenCount'];

      debugPrint(
          '🛡️ ProtectionShield: picker token counts web=$webTokenCount app=$appTokenCount category=$categoryTokenCount');
      return webTokenCount is int && webTokenCount > 0;
    } on PlatformException catch (e) {
      _lastVpnPermissionError = e.message ?? e.code;
      debugPrint(
          '🛡️ ProtectionShield: picker PlatformException code=${e.code} message=${e.message} details=${e.details}');
      return false;
    } catch (e) {
      _lastVpnPermissionError = e.toString();
      debugPrint('🛡️ ProtectionShield: picker error: $e');
      return false;
    }
  }

  void _printWebsiteShieldDiagnostics(
    String label,
    Map<String, dynamic> diagnostics,
  ) {
    final tunnel = diagnostics['packetTunnelManager'];
    final status = tunnel is Map ? tunnel['status'] : null;
    final enabled = tunnel is Map ? tunnel['isEnabled'] : null;
    debugPrint(
      '🛡️ Shield[$label] mode=${diagnostics['websiteShieldEnforcementMode']} '
      'plugin=${diagnostics['pluginExists']} tunnel=$status enabled=$enabled '
      'screenTime=${diagnostics['screenTimeAuthorized']}',
    );
  }

  Future<void> _startNativeServices() async {
    if (_nativeStartInFlight) {
      debugPrint(
          '🛡️ ProtectionShield: native start already running; skipping duplicate start');
      return;
    }
    _nativeStartInFlight = true;

    try {
      await _startDnsDebugConsoleLogging();
      await _syncNativeBlockState(isBlocking: _isBlocking);
      if (Platform.isIOS) {
        if (_isBlocking) {
          final startResult = await _channel.invokeMethod('startVpn');
          if (startResult == 'dns_settings_needs_activation') {
            _dnsSettingsNeedsActivation = true;
            _lastVpnPermissionError =
                'Website Shield DNS needs activation in Settings > VPN & Device Management > DNS.';
          }
          final diagnostics = await getWebsiteShieldDiagnostics();
          _printWebsiteShieldDiagnostics('startup', diagnostics);
        }
        return;
      }
      await _channel.invokeMethod('startVpn');
    } catch (e) {
      debugPrint('Native service error: $e');
    } finally {
      _nativeStartInFlight = false;
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
    // Re-verify before deactivating: the subscription stream can report
    // trialExpired from Firestore while the Apple check silently failed
    // during an outage. Only positive evidence of expiry may end the block.
    final expired = await _isSubscriptionExpired();
    if (!expired) {
      debugPrint(
          '🛡️ ProtectionShield: trial-expiry deactivation skipped — subscription not verifiably expired');
      return;
    }
    await _deactivateBlock();
  }

  Future<void> refreshProtectionStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final interrupted = prefs.getBool(_keyVpnInterrupted) ?? false;
    if (_vpnInterrupted != interrupted) {
      _vpnInterrupted = interrupted;
      notifyListeners();
    }

    if (Platform.isIOS && _isBlocking) {
      await _syncNativeBlockState(isBlocking: true);
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
      final result = await _channel.invokeMethod<bool>('isAlwaysOnVpnEnabled');
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
    if (savedPin == null || savedPin.isEmpty) return false;
    return savedPin == pin.trim();
  }

  Future<bool> hasPin() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_keyPin);
    return saved != null && saved.isNotEmpty;
  }

  /// Ends protection after PIN verification. Used for intentional early stop
  /// and before the user cancels their subscription.
  Future<bool> endProtectionWithPin(String pin) async {
    if (!await verifyPin(pin)) return false;
    await _deactivateBlock();
    return true;
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
    _hardCommitment = false;
    _unlockTime = null;
    _vpnInterrupted = false;
    _accessibilityLost = false;
    _timer?.cancel();
    _protectionStatusTimer?.cancel();
    _accessibilityCheckTimer?.cancel();
    await prefs.setBool(_keyIsBlocking, false);
    await prefs.setBool(_keyHardCommitment, false);
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

      debugPrint(
          "🛡️ Sync native: isBlocking=$isBlocking hasSub=$hasActiveSub");

      await _channel.invokeMethod('syncBlockState', {
        'isBlocking': isBlocking,
        'hasActiveSubscription': hasActiveSub,
        'hardCommitment': isBlocking && _hardCommitment,
        'dnsDebugEnabled': Platform.isIOS && kDebugMode,
        'unlockTime':
            isBlocking ? (_unlockTime?.millisecondsSinceEpoch ?? 0) : 0,
      });
    } catch (e) {
      debugPrint('🟦 FLUTTER: Native block state sync error: $e');
    }
  }

  Future<void> _startDnsDebugConsoleLogging() async {
    // Intentionally quiet: tunnel BLOCK/PASS lines go to device Console
    // (filter "BetControl PacketTunnel"), not the Flutter log flood.
    _filterDebugTimer?.cancel();
    _filterDebugTimer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _protectionStatusTimer?.cancel();
    _accessibilityCheckTimer?.cancel();
    _filterDebugTimer?.cancel();
    super.dispose();
  }
}
