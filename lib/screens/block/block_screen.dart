import 'dart:async';
import 'dart:io' show Platform;
import 'package:betcontrol_main/services/block_services.dart';
import 'package:betcontrol_main/services/connectivity_service.dart';
import 'package:betcontrol_main/services/notification_service.dart';
import 'package:betcontrol_main/services/purchase_service.dart';
import 'package:betcontrol_main/services/subscription_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BlockScreen extends StatefulWidget {
  const BlockScreen({super.key});

  @override
  State<BlockScreen> createState() => _BlockScreenState();
}

class _BlockScreenState extends State<BlockScreen>
    with WidgetsBindingObserver {
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  int _selectedDays = 30;
  bool _isLoading = false;
  bool _accessibilityEnabled = false;
  bool _deviceAdminActive = false;
  bool _vpnPermissionGranted = false;
  bool _alwaysOnVpnEnabled = false;
  bool _autoStartEnabled = false;
  bool _openedAlwaysOnVpnSettings = false;
  bool _openedAutoStartSettings = false;
  bool _obscurePin = true;
  bool _obscureConfirmPin = true;
  bool _isPowerSaveMode = false;
  String _deviceManufacturer = '';
  final _connectivityService = ConnectivityService();

  // ── Change 1: new state variable for battery optimization ────────────────
  bool _batteryOptimizationExempt = false;

  static const _channel = MethodChannel('com.betcontrol/blocker');

  SubscriptionDetails _subscription =
      const SubscriptionDetails(status: SubscriptionStatus.inactive);
  StreamSubscription<SubscriptionDetails>? _subStream;

  static const Color _darkColor = Color(0xFF1A1A2E);
  static const Color _accentColor = Color(0xFF00D4AA);
  static const Color _bgColor = Color(0xFFF8F9FF);

  final List<Map<String, dynamic>> _durationOptions = [
    {'label': '1 Month', 'days': 30},
    {'label': '3 Months', 'days': 90},
    {'label': '6 Months', 'days': 180},
    {'label': '1 Year', 'days': 365},
    {'label': '3 Years', 'days': 1095},
    {'label': '5 Years', 'days': 1825},
    {'label': '10 Years', 'days': 3650},
  ];



  bool get isAndroid => Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (isAndroid) {
      _checkAccessibility();
      _checkDeviceAdmin();
      _checkPowerSaveMode();
      _checkAutoStartStatus();
      _checkBatteryOptimization();
    }
    if (isAndroid) {
      _checkVpnSetup();
    }
    _loadManufacturer();
    _listenToSubscription();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (isAndroid) {
        _checkAccessibility();
        _checkDeviceAdmin();
        _checkPowerSaveMode();
        _checkAutoStartStatus();
        _checkBatteryOptimization();
      }
      if (isAndroid) {
        _checkVpnSetup();
      }
      context.read<BlockService>().refreshProtectionStatus();
    }
  }

  Future<void> _loadManufacturer() async {
    try {
      final result =
          await _channel.invokeMethod<String>('getManufacturer') ?? '';
      if (mounted) setState(() => _deviceManufacturer = result.toLowerCase());
    } catch (_) {
      if (mounted) {
        setState(
            () => _deviceManufacturer = Platform.isAndroid ? 'android' : '');
      }
    }
  }

  Future<void> _checkAutoStartStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final confirmed = prefs.getBool('auto_start_confirmed') ?? false;
    if (mounted) setState(() => _autoStartEnabled = confirmed);
  }

  bool get _needsAutoStartSetup {
    const oemsThatNeedIt = [
      'infinix', 'tecno', 'itel',
      'xiaomi', 'redmi', 'poco',
      'huawei', 'honor',
      'oppo', 'realme', 'oneplus',
      'vivo',
      'samsung',
    ];
    return oemsThatNeedIt.any((oem) => _deviceManufacturer.contains(oem));
  }

 /* Future<void> _checkPowerSaveMode() async {
    try {
      final result = await _channel.invokeMethod<bool>('isPowerSaveModeOn');
      if (mounted) setState(() => _isPowerSaveMode = result ?? false);
    } catch (_) {}
  }

  Future<void> _checkBatteryOptimization() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('isBatteryOptimizationExempt') ??
              false;
      if (mounted) setState(() => _batteryOptimizationExempt = result);
    } catch (_) {
      if (mounted) setState(() => _batteryOptimizationExempt = false);
    }
  }*/

  Future<void> _checkPowerSaveMode() async {
    if (!isAndroid) return;
    try {
      final result = await _channel.invokeMethod<bool>('isPowerSaveModeOn');
      if (mounted) setState(() => _isPowerSaveMode = result ?? false);
    } catch (_) {}
  }

  Future<void> _checkBatteryOptimization() async {
    if (!isAndroid) return;
    try {
      final result = await _channel.invokeMethod<bool>('isBatteryOptimizationExempt') ?? false;
      if (mounted) setState(() => _batteryOptimizationExempt = result);
    } catch (_) {
      if (mounted) setState(() => _batteryOptimizationExempt = false);
    }
  }

  Future<void> _checkDeviceAdmin() async {
    final service = context.read<BlockService>();
    final active = await service.isDeviceAdminActive();
    if (mounted) setState(() => _deviceAdminActive = active);
  }

  Future<void> _checkVpnSetup() async {
    final service = context.read<BlockService>();
    final permissionGranted = await service.isVpnPermissionGranted();
    final alwaysOnEnabled =
        isAndroid ? await service.isAlwaysOnVpnEnabled() : permissionGranted;
    if (mounted) {
      setState(() {
        _vpnPermissionGranted = permissionGranted;
        _alwaysOnVpnEnabled = alwaysOnEnabled;
      });
    }
  }

  void _listenToSubscription() {
    _subStream = SubscriptionService().detailsStream().listen((details) {
      if (!mounted) return;
      setState(() => _subscription = details);

      if (details.status == SubscriptionStatus.active &&
          !context.read<BlockService>().isBlocking &&
          _pinController.text.trim().length == 6) {
        _doActivateBlock();
      }

      if (details.status == SubscriptionStatus.trialExpired) {
        final blockService = context.read<BlockService>();
        if (blockService.isBlocking) {
          blockService.deactivateBlockDueToTrialExpiry().then((_) {
            if (mounted) {
              _showSnack(
                'Your free trial has expired. Subscribe to re-activate protection.',
              );
            }
          });
        }
      }

      if (details.isTrial && details.expiry != null) {
        NotificationService().scheduleTrialWarning(details.expiry!);
        NotificationService().scheduleTrialExpired(details.expiry!);
      }

      if (details.status == SubscriptionStatus.active) {
  NotificationService().cancelTrialNotifications();
  // Schedule expiry warnings for paid subscribers
  if (details.expiry != null) {
    NotificationService().scheduleSubscriptionWarnings(details.expiry!);
  }
}
    });
  }

  Future<void> _checkAccessibility() async {
    final service = context.read<BlockService>();
    final enabled = await service.isAccessibilityEnabled();
    if (mounted) setState(() => _accessibilityEnabled = enabled);
  }

  Future<void> _onActivateTapped(BlockService service) async {
    if (_isLoading) return;
    if (service.isBlocking) return;

    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();
    if (pin.length != 6) {
      _showSnack('PIN must be exactly 6 digits');
      return;
    }
    if (pin != confirmPin) {
      _showSnack('PINs do not match');
      return;
    }

    if (isAndroid) {
      final accessibilityEnabled = await service.isAccessibilityEnabled();
      if (!accessibilityEnabled) {
        _showSnack('Enable app blocking first.');
        return;
      }

      // ── Condition 2: Device Admin ─────────────────────────────────────────
      final deviceAdminActive = await service.isDeviceAdminActive();
      if (mounted) setState(() => _deviceAdminActive = deviceAdminActive);
      if (!deviceAdminActive) {
        _showSnack('Enable uninstall protection first — tap the banner above.');
        return;
      }

      // ── Condition 3: VPN permission ───────────────────────────────────────
      final vpnPermissionGranted = await service.isVpnPermissionGranted();
      if (mounted) setState(() => _vpnPermissionGranted = vpnPermissionGranted);
      if (!vpnPermissionGranted) {
        await service.requestVpnPermission();
        _showSnack('Grant VPN permission first — tap the orange banner above.');
        return;
      }

      // ── Condition 4: Always-on VPN ────────────────────────────────────────
      // final alwaysOnEnabled = await service.isAlwaysOnVpnEnabled();
      // if (mounted) setState(() => _alwaysOnVpnEnabled = alwaysOnEnabled);
      // if (!alwaysOnEnabled) {
      //   _showSnack(
      //       'Enable Always-on VPN first — tap the orange banner above and follow the steps.');
      //   return;
      // }

      // ── Condition 5: Auto-start (OEM devices only) ────────────────────────
      if (_needsAutoStartSetup && !_autoStartEnabled) {
        _showSnack(
            'Enable persistent protection first — tap the red banner above.');
        return;
      }
    }





    if (isAndroid && !_batteryOptimizationExempt) {
      _showSnack(
          'Enable background protection mode — tap the orange banner above.');
      return;
    }

    // ── All conditions met — proceed ──────────────────────────────────────
    switch (_subscription.status) {
      case SubscriptionStatus.active:
        await _doActivateBlock();
        return;
      case SubscriptionStatus.trial:
        await _doActivateBlock();
        return;
      case SubscriptionStatus.trialExpired:
        await _handlePaymentThenBlock(service);
        return;
      case SubscriptionStatus.inactive:
        final hasInternet = await _connectivityService.hasInternetConnection();
        if (!mounted) return;
        if (!hasInternet) {
          _showSnack('No internet connection. Please try again.');
          return;
        }
        final trialActivated = await SubscriptionService().activateTrial();
        if (!trialActivated) {
          await _handlePaymentThenBlock(service);
          return;
        }
        _showSuccessSnack(
            '3-day free trial started! Your protection is now activating.');
        await _doActivateBlock();
        return;
    }
  }

  Future<void> _handlePaymentThenBlock(BlockService service) async {
    final confirmed = await _showConfirmDialog();
    if (!confirmed) return;

    if (!mounted) return;
    final hasInternet = await _connectivityService.hasInternetConnection();
    if (!mounted) return;
    if (!hasInternet) {
      _showSnack('No internet connection. Please try again.');
      return;
    }

    setState(() => _isLoading = true);

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final purchaseService = PurchaseService();
    final result = await purchaseService.payAndSubscribe(navigator.context);

    if (!mounted) return;

    if (result.success) {
      await _doActivateBlock();
    } else if (result.errorType == PaymentErrorType.cancelled) {
      setState(() => _isLoading = false);
    } else if (result.errorType == PaymentErrorType.verification) {
      messenger.showSnackBar(SnackBar(
        content: Text(
          'Bank transfer detected. Block will activate automatically once confirmed.',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        backgroundColor: Colors.amber.shade700,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } else {
      setState(() => _isLoading = false);
      messenger.showSnackBar(SnackBar(
        content: Text(
          result.errorMessage ?? 'Payment failed. Please try again.',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  Future<void> _doActivateBlock() async {
    final service = context.read<BlockService>();
    if (service.isBlocking) return;

    final pin = _pinController.text.trim();

    final hasConflictingVpn = await service.hasConflictingVpn();
    if (hasConflictingVpn) {
      final proceed = await _showVpnConflictDialog(service);
      if (!proceed) {
        setState(() => _isLoading = false);
        return;
      }
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    final activated = await service.activateBlock(
      durationDays: _selectedDays,
      pin: pin,
    );

    if (!mounted) return;

    if (!activated) {
      setState(() => _isLoading = false);
      _showSnack('Protection could not start. Please check VPN permission.');
      return;
    }

    setState(() => _isLoading = false);
    _showSuccessSnack('Protection is active.');
  }

  Future<void> _showAlwaysOnVpnInfoDialog() async {
    _openedAlwaysOnVpnSettings = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('⚡ Enable Background Protection',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700, color: _darkColor)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Always-on VPN makes blocking resume automatically after your '
                'phone restarts.\n\n'
                '1. Tap "Open VPN Settings" below\n'
                '2. Tap the ⚙️ icon next to BetControl\n'
                '3. Enable "Always-on VPN"\n'
                '4. Come back here\n'
                '5. Tap "I\'ve enabled it" to confirm',
                style: GoogleFonts.poppins(
                    fontSize: 13, color: Colors.grey.shade600, height: 1.6),
              ),
              if (!_openedAlwaysOnVpnSettings) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Text(
                    '⚠️ You must tap "Open VPN Settings" first before "I\'ve enabled it" will work.',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.orange.shade800),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Later',
                  style: GoogleFonts.poppins(color: Colors.grey.shade400)),
            ),
            TextButton(
              onPressed: () async {
                await _channel.invokeMethod('openAlwaysOnVpnSettings');
                _openedAlwaysOnVpnSettings = true;
                setDialogState(() {});
              },
              child: Text('Open VPN Settings',
                  style: GoogleFonts.poppins(color: _darkColor)),
            ),
            ElevatedButton(
              onPressed: _openedAlwaysOnVpnSettings
                  ? () async {
                      Navigator.pop(ctx);
                      await _confirmAlwaysOnVpn();
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _openedAlwaysOnVpnSettings ? _darkColor : Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('I\'ve enabled it',
                  style: GoogleFonts.poppins(
                      color: _openedAlwaysOnVpnSettings
                          ? Colors.white
                          : Colors.grey.shade500)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAlwaysOnVpn() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('always_on_vpn_confirmed', true);
    if (mounted) {
      setState(() => _alwaysOnVpnEnabled = true);
      _showSuccessSnack('Always-on VPN confirmed. Auto-restart is enabled.');
    }
  }

  // ── Auto-start dialog for OEMs that kill background processes ────────────
  Future<void> _showAutoStartDialog() async {
    _openedAutoStartSettings = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: Text('🔋 Enable Persistent Protection',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700, color: _darkColor)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _autoStartInstructions(),
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      height: 1.6),
                ),
                if (!_openedAutoStartSettings) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Text(
                      '⚠️ Tap "Open Settings" first, then come back and tap "I\'ve done it".',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: Colors.orange.shade800),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Later',
                    style:
                        GoogleFonts.poppins(color: Colors.grey.shade400)),
              ),
              TextButton(
                onPressed: () async {
                  await _channel.invokeMethod('openAutoStartSettings');
                  // User has returned from settings — now update the button
                  setState(() => _openedAutoStartSettings = true);
                  setDialogState(() {});
                },
                child: Text('Open Settings',
                    style: GoogleFonts.poppins(color: _darkColor)),
              ),
              ElevatedButton(
                onPressed: _openedAutoStartSettings
                    ? () async {
                        Navigator.pop(ctx);
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('auto_start_confirmed', true);
                        if (mounted) {
                          setState(() => _autoStartEnabled = true);
                          _showSuccessSnack(
                              'Background run enabled. Blocking will resume after reboot.');
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _openedAutoStartSettings ? _darkColor : Colors.grey.shade300,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('I\'ve done it',
                    style: GoogleFonts.poppins(
                        color: _openedAutoStartSettings
                            ? Colors.white
                            : Colors.grey.shade500)),
              ),
            ],
          );
        },
      ),
    );
  }

  String _autoStartInstructions() {
    final m = _deviceManufacturer;
    if (m.contains('infinix') ||
        m.contains('tecno') ||
        m.contains('itel')) {
      return 'To ensure blocking resumes after reboot:\n\n'
          '1. Tap "Open Settings" below\n'
          '2. Find BetControl and enable Auto-start\n'
          '3. Also go to Settings → Battery → App launch → BetControl → enable all toggles\n'
          '4. Come back and tap "I\'ve done it"';
    } else if (m.contains('xiaomi') ||
        m.contains('redmi') ||
        m.contains('poco')) {
      return 'To ensure blocking resumes after reboot:\n\n'
          '1. Tap "Open Settings" below\n'
          '2. Enable Auto-start for BetControl\n'
          '3. Go to Battery & Performance → App battery saver → BetControl → No restrictions\n'
          '4. Come back and tap "I\'ve done it"';
    } else if (m.contains('huawei') || m.contains('honor')) {
      return 'To ensure blocking resumes after reboot:\n\n'
          '1. Tap "Open Settings" below\n'
          '2. Enable Auto-launch for BetControl\n'
          '3. Go to Settings → Battery → App launch → BetControl → Manage manually → enable all\n'
          '4. Come back and tap "I\'ve done it"';
    } else if (m.contains('oppo') || m.contains('realme')) {
      return 'To ensure blocking resumes after reboot:\n\n'
          '1. Tap "Open Settings" below\n'
          '2. Enable Auto-start for BetControl\n'
          '3. Go to Battery → Battery optimization → BetControl → Don\'t optimize\n'
          '4. Come back and tap "I\'ve done it"';
    } else if (m.contains('vivo')) {
      return 'To ensure blocking resumes after reboot:\n\n'
          '1. Tap "Open Settings" below\n'
          '2. Enable Auto-start for BetControl\n'
          '3. Go to Battery → High background power consumption → add BetControl\n'
          '4. Come back and tap "I\'ve done it"';
    } else {
      return 'To ensure blocking resumes after reboot:\n\n'
          '1. Tap "Open Settings" below\n'
          '2. Find BetControl and enable Auto-start or Background run\n'
          '3. Go to Battery settings → set BetControl to Unrestricted\n'
          '4. Come back and tap "I\'ve done it"';
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: GoogleFonts.poppins(color: Colors.white)),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 4),
    ));
  }

  void _showSuccessSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(
            child: Text(message,
                style:
                    GoogleFonts.poppins(color: Colors.white, fontSize: 13))),
      ]),
      backgroundColor: _accentColor,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 4),
    ));
  }

  Future<bool> _showVpnConflictDialog(BlockService service) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: Text('Another VPN Is Active',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700, color: _darkColor)),
            content: Text(
              'Android allows only one VPN at a time. BetControl must become '
              'the active VPN to block gambling websites.\n\n'
              'If you continue, your current VPN may be disconnected.',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey.shade600),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel',
                    style:
                        GoogleFonts.poppins(color: Colors.grey.shade500)),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context, false);
                  await service.openVpnSettings();
                },
                child: Text('VPN Settings',
                    style: GoogleFonts.poppins(color: _accentColor)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _darkColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Use BetControl',
                    style: GoogleFonts.poppins(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _showConfirmDialog() async {
    final option =
        _durationOptions.firstWhere((o) => o['days'] == _selectedDays);
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: Text('Activate Protection?',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700, color: _darkColor)),
            content: Text(
              'You are about to block all gambling sites and apps for '
              '${option['label']}.\n\nThis CANNOT be undone until the '
              'timer expires. Are you ready?',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey.shade600),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel',
                    style:
                        GoogleFonts.poppins(color: Colors.grey.shade500)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Yes, Activate',
                    style: GoogleFonts.poppins(
                        color: _darkColor,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subStream?.cancel();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<BlockService>();



    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 16, color: _darkColor),
          ),
        ),
        title: Text('Site & App Blocker',
            style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: _darkColor)),
        centerTitle: true,
      ),
      body: service.isBlocking
          ? _buildActiveBlockView(service)
          : _buildSetupView(service),
    );
  }

  Widget _buildActiveBlockView(BlockService service) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: _darkColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: _darkColor.withValues(alpha: 0.3),
                    blurRadius: 30,
                    spreadRadius: 5),
              ],
            ),
            child: const Icon(Icons.shield_rounded,
                size: 60, color: _accentColor),
          ),
          const SizedBox(height: 24),
          Text('Protection Active',
              style: GoogleFonts.poppins(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: _darkColor)),
          const SizedBox(height: 8),
          Text('Gambling sites and apps are blocked',
              style: GoogleFonts.poppins(
                  fontSize: 14, color: Colors.grey.shade500)),
          if (_subscription.isTrial) ...[
            const SizedBox(height: 12),
            _buildTrialBadge(compact: true),
          ],
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 8)),
              ],
            ),
            child: Column(
              children: [
                Text('Time Remaining',
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 12),
                Text(service.timeRemainingText,
                    style: GoogleFonts.poppins(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: _darkColor)),
                if (service.unlockTime != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                        color: _bgColor,
                        borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_clock_rounded,
                            size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 6),
                        Text(
                            'Unlocks ${_formatDate(service.unlockTime!)}',
                            style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (service.accessibilityLost) ...[
            GestureDetector(
              onTap: () async => await service.openAccessibilitySettings(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: Colors.red.shade300, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_rounded,
                            color: Colors.red.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('App blocking disabled!',
                              style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.red.shade700)),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded,
                            size: 14, color: Colors.red.shade700),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Accessibility was disabled. Tap here to re-enable '
                      'BetControl in Accessibility Settings. Gambling apps '
                      'are not being blocked right now.',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: Colors.red.shade700),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (isAndroid && _isPowerSaveMode) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: Colors.orange.shade300, width: 1.5),
              ),
              child: Row(
                children: [
                  Icon(Icons.battery_alert_rounded,
                      color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Power Save Mode is ON — may stop website blocking. '
                      'Turn it off to keep full protection.',
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.orange.shade800),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (service.vpnInterrupted) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: Colors.red.shade200, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.error_outline_rounded,
                          color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 8),
                      Text('Website protection interrupted',
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.red.shade700)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                      'Another VPN may have replaced BetControl. Tap below to restart.',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: Colors.red.shade600)),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () async => await service.restartProtection(),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                          color: Colors.red.shade700,
                          borderRadius: BorderRadius.circular(12)),
                      child: Center(
                          child: Text('Restart Protection',
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14))),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (isAndroid) ...[
            _buildAccessibilityBanner(service),
            const SizedBox(height: 24),
          ],
          Text('Stay strong — you\'re doing great! 💪',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic)),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSetupView(BlockService service) {
    final allReady = isAndroid
        ? _accessibilityEnabled &&
            _deviceAdminActive &&
            _vpnPermissionGranted &&
            _alwaysOnVpnEnabled &&
            _batteryOptimizationExempt &&
            (!_needsAutoStartSetup || _autoStartEnabled)
        : _vpnPermissionGranted;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isAndroid && !_accessibilityEnabled) ...[
            _buildAccessibilityBanner(service),
            const SizedBox(height: 12),
          ],
          if (isAndroid && !_deviceAdminActive) ...[
            _buildDeviceAdminBanner(service),
            const SizedBox(height: 12),
          ],
          if (isAndroid && !_batteryOptimizationExempt) ...[
            _buildBatteryOptimizationBanner(),
            const SizedBox(height: 12),
          ],
          if ((isAndroid && (!_vpnPermissionGranted || !_alwaysOnVpnEnabled)) ||
              (!isAndroid && !_vpnPermissionGranted)) ...[
            _buildVpnSetupBanner(service),
            const SizedBox(height: 12),
          ],
          if (isAndroid && _needsAutoStartSetup && !_autoStartEnabled) ...[
            _buildAutoStartBanner(),
            const SizedBox(height: 12),
          ],
          _buildSubscriptionBanner(),
          const SizedBox(height: 28),
          Text('Activate Protection',
              style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _darkColor)),
          const SizedBox(height: 6),
          Text(
            'Choose a duration and set a PIN. Once activated, '
            'the block cannot be turned off until the timer expires.',
            style: GoogleFonts.poppins(
                fontSize: 13, color: Colors.grey.shade500, height: 1.5),
          ),
          // Show which steps still need completing
          if (!allReady) ...[
            const SizedBox(height: 12),
            _buildPendingStepsHint(),
          ],
          const SizedBox(height: 28),
          Text('Select Duration',
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _darkColor)),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 3.0,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: _durationOptions.map((option) {
              final isSelected = _selectedDays == option['days'];
              return GestureDetector(
                onTap: () =>
                    setState(() => _selectedDays = option['days'] as int),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: isSelected ? _darkColor : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? _darkColor
                          : Colors.grey.shade200,
                      width: 1.5,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                                color: _darkColor.withValues(alpha: 0.2),
                                blurRadius: 8,
                                offset: const Offset(0, 4))
                          ]
                        : [
                            BoxShadow(
                                color:
                                    Colors.black.withValues(alpha: 0.04),
                                blurRadius: 6,
                                offset: const Offset(0, 2))
                          ],
                  ),
                  child: Center(
                    child: Text(
                      option['label'] as String,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected ? _accentColor : _darkColor,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 15,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lock_rounded,
                        color: _accentColor, size: 20),
                    const SizedBox(width: 8),
                    Text('Set Your PIN',
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _darkColor)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'This PIN protects your settings. It does NOT disable the block early.',
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                      height: 1.5),
                ),
                const SizedBox(height: 16),
                _pinField(
                  controller: _pinController,
                  label: '6-Digit PIN',
                  obscure: _obscurePin,
                  onToggle: () =>
                      setState(() => _obscurePin = !_obscurePin),
                ),
                const SizedBox(height: 14),
                _pinField(
                  controller: _confirmPinController,
                  label: 'Confirm PIN',
                  obscure: _obscureConfirmPin,
                  onToggle: () => setState(
                      () => _obscureConfirmPin = !_obscureConfirmPin),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: _isLoading ? null : () => _onActivateTapped(service),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              height: 58,
              decoration: BoxDecoration(
                color: _isLoading
                    ? _accentColor.withValues(alpha: 0.6)
                    : allReady
                        ? _accentColor
                        : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(18),
                boxShadow: allReady && !_isLoading
                    ? [
                        BoxShadow(
                            color: _accentColor.withValues(alpha: 0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 8)),
                      ]
                    : [],
              ),
              child: Center(
                child: _isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : Text(
                        _activateButtonLabel(),
                        style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: allReady
                                ? _darkColor
                                : Colors.grey.shade500),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              '⚠️ This action cannot be reversed until the timer expires',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 11, color: Colors.grey.shade400),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingStepsHint() {
    final pending = <String>[];
    if (isAndroid && !_accessibilityEnabled) pending.add('Enable app blocking');
    if (isAndroid && !_deviceAdminActive) pending.add('Enable tamper protection');
    if (!_vpnPermissionGranted) pending.add('Enable website shield');
    if (isAndroid && !_alwaysOnVpnEnabled) {
      pending.add('Enable background protection');
    }
    if (isAndroid && !_batteryOptimizationExempt) {
      pending.add('Enable background protection mode');
    }
    if (isAndroid && _needsAutoStartSetup && !_autoStartEnabled) {
      pending.add('Enable persistent protection');
    }

    if (pending.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Complete these steps to activate:',
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade800)),
          const SizedBox(height: 6),
          ...pending.map((step) => Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  children: [
                    Icon(Icons.circle, size: 6, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(step,
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: Colors.orange.shade800)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ── Change 8: battery optimization banner widget ──────────────────────────
  // Tapping this banner opens Android's system dialog that asks the user to
  // exempt BetControl from battery optimization. After they confirm in that
  // dialog and return to the app, we wait 800ms (for the OS to register the
  // change) then re-check. The banner turns green automatically — no need for
  // an "I've done it" button like the VPN/auto-start flows because Android
  // tells us directly whether the exemption is in place.
  Widget _buildBatteryOptimizationBanner() {
    return GestureDetector(
      onTap: _batteryOptimizationExempt
          ? null
          : () async {
              await _channel
                  .invokeMethod('requestBatteryOptimizationExemption');
              await Future.delayed(const Duration(milliseconds: 800));
              await _checkBatteryOptimization();
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _batteryOptimizationExempt
              ? Colors.green.shade50
              : Colors.orange.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _batteryOptimizationExempt
                ? Colors.green.shade300
                : Colors.orange.shade300,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _batteryOptimizationExempt
                  ? Icons.battery_charging_full_rounded
                  : Icons.battery_saver_outlined,
              color: _batteryOptimizationExempt
                  ? Colors.green.shade600
                  : Colors.orange.shade700,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _batteryOptimizationExempt
                        ? 'Background protection mode enabled ✓'
                        : 'Tap to enable background protection mode',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _batteryOptimizationExempt
                          ? Colors.green.shade700
                          : Colors.orange.shade800,
                    ),
                  ),
                  if (!_batteryOptimizationExempt) ...[
                    const SizedBox(height: 3),
                    Text(
                      'Keeps protection running at all times',
                      style: GoogleFonts.poppins(
                          fontSize: 11, color: Colors.orange.shade700),
                    ),
                  ],
                ],
              ),
            ),
            if (!_batteryOptimizationExempt)
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: Colors.orange.shade700),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoStartBanner() {
    return GestureDetector(
      onTap: _autoStartEnabled ? null : _showAutoStartDialog,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
              _autoStartEnabled ? Colors.green.shade50 : Colors.red.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _autoStartEnabled
                ? Colors.green.shade300
                : Colors.red.shade300,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _autoStartEnabled
                  ? Icons.battery_charging_full_rounded
                  : Icons.battery_alert_rounded,
              color: _autoStartEnabled
                  ? Colors.green.shade600
                  : Colors.red.shade700,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _autoStartEnabled
                    ? 'Persistent protection enabled ✓'
                    : 'Tap to enable persistent protection',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _autoStartEnabled
                      ? Colors.green.shade700
                      : Colors.red.shade800,
                ),
              ),
            ),
            if (!_autoStartEnabled)
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: Colors.red.shade700),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceAdminBanner(BlockService service) {
    return GestureDetector(
      onTap: _deviceAdminActive
          ? null
          : () async {
              await service.requestDeviceAdmin();
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _deviceAdminActive
              ? Colors.green.shade50
              : Colors.orange.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _deviceAdminActive
                ? Colors.green.shade300
                : Colors.orange.shade300,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _deviceAdminActive
                  ? Icons.admin_panel_settings_rounded
                  : Icons.admin_panel_settings_outlined,
              color: _deviceAdminActive
                  ? Colors.green.shade600
                  : Colors.orange.shade700,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _deviceAdminActive
                    ? 'Tamper protection enabled ✓'
                    : 'Tap here to enable tamper protection',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _deviceAdminActive
                      ? Colors.green.shade700
                      : Colors.orange.shade800,
                ),
              ),
            ),
            if (!_deviceAdminActive)
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: Colors.orange.shade700),
          ],
        ),
      ),
    );
  }

  Widget _buildVpnSetupBanner(BlockService service) {
    final vpnReady = _vpnPermissionGranted;
    final alwaysOnReady = !isAndroid || _alwaysOnVpnEnabled;

    if (vpnReady && alwaysOnReady) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.green.shade300, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(Icons.vpn_lock_rounded,
                color: Colors.green.shade600, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Full website protection enabled ✓',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.green.shade700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Row 1: VPN permission
        GestureDetector(
          onTap: vpnReady
              ? null
              : () async {
                  await service.requestVpnPermission();
                  await _checkVpnSetup();
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:
                  vpnReady ? Colors.green.shade50 : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: vpnReady
                    ? Colors.green.shade300
                    : Colors.orange.shade300,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  vpnReady
                      ? Icons.vpn_key_rounded
                      : Icons.vpn_key_off_rounded,
                  color: vpnReady
                      ? Colors.green.shade600
                      : Colors.orange.shade700,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    vpnReady
                        ? 'Website shield enabled ✓'
                        : 'Tap here to enable website shield',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: vpnReady
                          ? Colors.green.shade700
                          : Colors.orange.shade800,
                    ),
                  ),
                ),
                if (!vpnReady)
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 14, color: Colors.orange.shade700),
              ],
            ),
          ),
        ),

        // Row 2: Always-on VPN — only visible after VPN permission is granted
        if (vpnReady) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: alwaysOnReady ? null : _showAlwaysOnVpnInfoDialog,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: alwaysOnReady
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: alwaysOnReady
                      ? Colors.green.shade300
                      : Colors.orange.shade300,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    alwaysOnReady
                        ? Icons.replay_circle_filled_rounded
                        : Icons.replay_circle_filled_outlined,
                    color: alwaysOnReady
                        ? Colors.green.shade600
                        : Colors.orange.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alwaysOnReady
                              ? 'Background protection enabled ✓'
                              : 'Tap here to enable background protection mode',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: alwaysOnReady
                                ? Colors.green.shade700
                                : Colors.orange.shade800,
                          ),
                        ),
                        if (!alwaysOnReady) ...[
                          const SizedBox(height: 3),
                          Text(
                            'Follow the steps, then come back and tap "I\'ve enabled it"',
                            style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.orange.shade700),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!alwaysOnReady)
                    Icon(Icons.arrow_forward_ios_rounded,
                        size: 14, color: Colors.orange.shade700),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSubscriptionBanner() {
    switch (_subscription.status) {
      case SubscriptionStatus.active:
        final daysLeft = _subscription.expiry != null
            ? _subscription.expiry!.difference(DateTime.now()).inDays
            : 0;
        final expiringSoon = daysLeft <= 5;
        return Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: expiringSoon
                ? Colors.orange.shade50
                : Colors.green.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: expiringSoon
                  ? Colors.orange.shade300
                  : Colors.green.shade300,
            ),
          ),
          child: Row(
            children: [
              Icon(
                expiringSoon
                    ? Icons.warning_amber_rounded
                    : Icons.verified_rounded,
                color: expiringSoon
                    ? Colors.orange.shade700
                    : Colors.green.shade600,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  expiringSoon
                      ? 'Subscription expires in $daysLeft days — renew soon'
                      : 'Subscription active',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: expiringSoon
                        ? Colors.orange.shade800
                        : Colors.green.shade700,
                  ),
                ),
              ),
            ],
          ),
        );
      case SubscriptionStatus.trial:
        return _buildTrialBadge(compact: false);
      case SubscriptionStatus.trialExpired:
        return Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.red.shade300),
          ),
          child: Row(
            children: [
              Icon(Icons.timer_off_rounded,
                  color: Colors.red.shade700, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Free trial expired — subscribe to activate blocking',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.red.shade800,
                  ),
                ),
              ),
            ],
          ),
        );
      case SubscriptionStatus.inactive:
        return Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _darkColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.redeem_rounded,
                  color: _accentColor, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Start your 3-day free trial — no payment required',
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white),
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildTrialBadge({required bool compact}) {
    final timeLeft = _subscription.timeRemaining;
    final hoursLeft = timeLeft != null ? timeLeft.inHours : 0;
    final isExpiringSoon = hoursLeft <= 24;

    final label = compact
        ? (isExpiringSoon
            ? '⚠️ Free trial expires in ${hoursLeft}h'
            : '🎁 Free trial active')
        : (isExpiringSoon
            ? '⚠️ Trial expires in ${hoursLeft}h — subscribe to keep protection'
            : '🎁 Free trial active — ${hoursLeft}h remaining. Subscribe before it ends.');

    return Container(
      width: double.infinity,
      padding:
          EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 10 : 12),
      decoration: BoxDecoration(
        color: isExpiringSoon
            ? Colors.orange.shade50
            : _accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isExpiringSoon
              ? Colors.orange.shade300
              : _accentColor.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: isExpiringSoon
              ? Colors.orange.shade800
              : const Color(0xFF007A63),
        ),
      ),
    );
  }

  Widget _buildAccessibilityBanner(BlockService service) {
    return GestureDetector(
      onTap: () async => await service.openAccessibilitySettings(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _accessibilityEnabled
              ? Colors.green.shade50
              : Colors.orange.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _accessibilityEnabled
                ? Colors.green.shade300
                : Colors.orange.shade300,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _accessibilityEnabled
                  ? Icons.check_circle_rounded
                  : Icons.warning_amber_rounded,
              color: _accessibilityEnabled
                  ? Colors.green.shade600
                  : Colors.orange.shade700,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _accessibilityEnabled
                    ? 'App blocking enabled ✓'
                    : 'Tap here to enable app blocking',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _accessibilityEnabled
                      ? Colors.green.shade700
                      : Colors.orange.shade800,
                ),
              ),
            ),
            if (!_accessibilityEnabled)
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: Colors.orange.shade700),
          ],
        ),
      ),
    );
  }

  String _activateButtonLabel() {
    switch (_subscription.status) {
      case SubscriptionStatus.active:
      case SubscriptionStatus.trial:
        return 'Activate Protection';
      case SubscriptionStatus.inactive:
        return '🎁  Start Free Trial';
      case SubscriptionStatus.trialExpired:
        return '🔒  Subscribe — ₦1,500/month';
    }
  }

  Widget _pinField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: TextInputType.number,
      maxLength: 6,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: GoogleFonts.poppins(fontSize: 14, color: _darkColor),
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        labelStyle:
            GoogleFonts.poppins(color: Colors.grey.shade500, fontSize: 14),
        prefixIcon:
            const Icon(Icons.pin_outlined, color: _accentColor, size: 20),
        suffixIcon: GestureDetector(
          onTap: onToggle,
          child: Icon(
            obscure
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: Colors.grey.shade400,
            size: 20,
          ),
        ),
        filled: true,
        fillColor: _bgColor,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: _accentColor, width: 1.5)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year} at '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
