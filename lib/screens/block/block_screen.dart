import 'dart:async';
import 'dart:io' show Platform;
import 'package:betcontrol_main/screens/profile/manage_subscription_screen.dart';
import 'package:betcontrol_main/services/block_services.dart';
import 'package:betcontrol_main/services/connectivity_service.dart';
import 'package:betcontrol_main/services/notification_service.dart';
import 'package:betcontrol_main/services/purchase_service.dart';
import 'package:betcontrol_main/services/subscription_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class BlockScreen extends StatefulWidget {
  const BlockScreen({super.key});

  @override
  State<BlockScreen> createState() => _BlockScreenState();
}

class _BlockScreenState extends State<BlockScreen> with WidgetsBindingObserver {
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  int _selectedDays = 30;
  bool _isLoading = false;
  bool _accessibilityEnabled = false;
  bool _deviceAdminActive = false;
  bool _vpnPermissionGranted = false;
  bool _alwaysOnVpnEnabled = false;
  bool _isShieldPermissionLoading = false;
  bool _awaitingDnsActivation = false;
  int _selectedWebDomainTokenCount = 0;
  bool _autoStartEnabled = false;
  bool _openedAlwaysOnVpnSettings = false;
  bool _openedAutoStartSettings = false;
  bool _obscurePin = true;
  bool _obscureConfirmPin = true;
  bool _isPowerSaveMode = false;
  /// iOS opt-in: lock uninstall of all apps while protection is active.
  bool _hardCommitment = false;
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
  static const String _privacyPolicyUrl =
      'https://betcontrol-privacy.netlify.app';
  static const String _termsOfUseUrl =
      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';
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

  bool get _usesSubscriptionDuration =>
      !isAndroid && _subscription.isAccessGranted;

  int get _effectiveDurationDays {
    if (!_usesSubscriptionDuration) return _selectedDays;
    final remaining = _subscription.timeRemaining;
    if (remaining == null) return 30;
    final roundedDays = (remaining.inHours / 24).ceil();
    return roundedDays.clamp(30, 3650);
  }

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
    _checkVpnSetup();
    _loadManufacturer();
    _listenToSubscription();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final service = context.read<BlockService>();
      if (isAndroid) {
        _checkAccessibility();
        _checkDeviceAdmin();
        _checkPowerSaveMode();
        _checkAutoStartStatus();
        _checkBatteryOptimization();
      }
      _checkVpnSetup().then((_) {
        if (mounted && _awaitingDnsActivation && _vpnPermissionGranted) {
          _awaitingDnsActivation = false;
          _showSuccessSnack(
              'DNS Website Shield is now active. Tap Activate Protection to finish.');
        }
      });
      unawaited(service.refreshProtectionStatus());
      unawaited(_refreshSubscription());
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
      'infinix',
      'tecno',
      'itel',
      'xiaomi',
      'redmi',
      'poco',
      'huawei',
      'honor',
      'oppo',
      'realme',
      'oneplus',
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
      final result =
          await _channel.invokeMethod<bool>('isBatteryOptimizationExempt') ??
              false;
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
    var selectedWebDomainTokenCount = _selectedWebDomainTokenCount;
    if (!isAndroid) {
      final diagnostics = await service.getWebsiteShieldDiagnostics();
      final rawTokenCount =
          diagnostics['screenTimeSelectedWebDomainTokenCount'];
      selectedWebDomainTokenCount =
          rawTokenCount is int ? rawTokenCount : selectedWebDomainTokenCount;
    }
    if (mounted) {
      setState(() {
        _vpnPermissionGranted = permissionGranted;
        _alwaysOnVpnEnabled = alwaysOnEnabled;
        _selectedWebDomainTokenCount = selectedWebDomainTokenCount;
      });
    }
  }

  Future<bool> _requestShieldPermission(BlockService service) async {
    if (_isShieldPermissionLoading) return false;

    FocusScope.of(context).unfocus();
    if (mounted) setState(() => _isShieldPermissionLoading = true);

    try {
      final enabled = await service.requestVpnPermission();
      await _checkVpnSetup();

      if (enabled && !isAndroid && mounted) {
        final warning = service.lastVpnPermissionError;
        if (warning != null && warning.isNotEmpty) {
          _showSnack(warning);
        } else {
          _showSuccessSnack(
              'Website Shield is on. Activate Protection to block gambling sites.');
        }
      } else if (!enabled && mounted) {
        if (!isAndroid && service.dnsSettingsNeedsActivation) {
          _awaitingDnsActivation = true;
          await _showDnsActivationGuide(service);
        } else {
          _showSnack(service.lastVpnPermissionError ??
              (isAndroid
                  ? 'Website shield could not be enabled.'
                  : 'Website Shield permission was not approved.'));
        }
      }

      return enabled;
    } finally {
      if (mounted) setState(() => _isShieldPermissionLoading = false);
    }
  }

  Future<void> _refreshSubscription() async {
    final details = await SubscriptionService().refreshDetails();
    if (!mounted) return;
    setState(() => _subscription = details);
  }

  void _listenToSubscription() {
    // The stream below only re-emits when the Firestore user doc changes, so
    // an existing App Store subscription is re-checked explicitly here.
    unawaited(_refreshSubscription());
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

    FocusScope.of(context).unfocus();

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

      final deviceAdminActive = await service.isDeviceAdminActive();
      if (mounted) setState(() => _deviceAdminActive = deviceAdminActive);
      if (!deviceAdminActive) {
        _showSnack('Enable uninstall protection first — tap the banner above.');
        return;
      }

      final vpnPermissionGranted = await service.isVpnPermissionGranted();
      if (mounted) setState(() => _vpnPermissionGranted = vpnPermissionGranted);
      if (!vpnPermissionGranted) {
        final enabled = await _requestShieldPermission(service);
        if (!enabled) {
          return;
        }
        _showSnack(
            'Grant VPN permission first — tap the orange banner above.');
        return;
      }

      if (_needsAutoStartSetup && !_autoStartEnabled) {
        _showSnack(
            'Enable persistent protection first — tap the red banner above.');
        return;
      }

      if (!_batteryOptimizationExempt) {
        _showSnack(
            'Enable background protection mode — tap the orange banner above.');
        return;
      }
    } else {
      final vpnPermissionGranted = await service.isVpnPermissionGranted();
      if (mounted) setState(() => _vpnPermissionGranted = vpnPermissionGranted);
      if (!vpnPermissionGranted) {
        final enabled = await _requestShieldPermission(service);
        if (!enabled) {
          return;
        }
        _showSnack(
            'Website Shield enabled. Tap Activate Protection again.');
        return;
      }
    }

    // Always re-check Apple/RevenueCat before charging — stale "inactive"
    // status is the main reason existing subscribers see the paywall again.
    setState(() => _isLoading = true);
    final fresh = await SubscriptionService().refreshDetails();
    if (!mounted) return;
    setState(() {
      _subscription = fresh;
      _isLoading = false;
    });

    if (fresh.isAccessGranted) {
      await _doActivateBlock();
      return;
    }

    switch (fresh.status) {
      case SubscriptionStatus.active:
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
          // Trial already used — re-check once more before paywall.
          final recheck = await SubscriptionService().refreshDetails();
          if (!mounted) return;
          setState(() => _subscription = recheck);
          if (recheck.isAccessGranted) {
            await _doActivateBlock();
            return;
          }
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
    // Final entitlement check before any purchase UI.
    final existing = await SubscriptionService().refreshDetails();
    if (!mounted) return;
    setState(() => _subscription = existing);
    if (existing.isAccessGranted) {
      await _doActivateBlock();
      return;
    }

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

    Package? applePackageToBuy;
    StoreProduct? appleProductToBuy;

    // ── Fetch RevenueCat Package for iOS ─────────────────────────────
    if (!isAndroid) {
      try {
        Offerings offerings = await Purchases.getOfferings();
        if (offerings.current != null &&
            offerings.current!.availablePackages.isNotEmpty) {
          // Assuming you set up a monthly package in RevenueCat
          applePackageToBuy = offerings.current!.monthly ??
              offerings.current!.availablePackages.first;
        } else {
          final products =
              await Purchases.getProducts(PurchaseService.appleProductIds);
          for (final product in products) {
            if (product.identifier == PurchaseService.appleMonthlyProductId) {
              appleProductToBuy = product;
              break;
            }
          }
          if (appleProductToBuy == null && products.isNotEmpty) {
            appleProductToBuy = products.first;
          }
          if (appleProductToBuy == null) {
            if (!mounted) return;
            setState(() => _isLoading = false);
            _showSnack('No subscription packages available right now.');
            return;
          }
        }
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        _showSnack('Failed to load subscriptions.');
        return;
      }
    }

    if (!mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final purchaseService = PurchaseService();

    // Pass the fetched package into your purchase service
    final result = await purchaseService.payAndSubscribe(
      navigator.context,
      applePackage: applePackageToBuy,
      appleProduct: appleProductToBuy,
    );

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

    final latestSubscription = await SubscriptionService().getDetails();
    if (!latestSubscription.isAccessGranted) {
      _showSnack('Subscription not found. Please complete payment first.');
      setState(() => _isLoading = false);
      return;
    }

    if (service.isBlocking) return;

    debugPrint("🟦 FLUTTER: _doActivateBlock started.");
    debugPrint("🟦 FLUTTER: Current Sub Status -> ${_subscription.status}");

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

    debugPrint("🟦 FLUTTER: Calling service.activateBlock()...");

    final activated = await service.activateBlock(
      durationDays: _effectiveDurationDays,
      pin: pin,
      hardCommitment: !isAndroid && _hardCommitment,
    );

    debugPrint("🟦 FLUTTER: service.activateBlock() returned -> $activated");

    if (!mounted) return;

    if (!activated) {
      setState(() => _isLoading = false);
      _showSnack(isAndroid
          ? 'Protection could not start. Please check VPN permission.'
          : 'Protection could not start. Please check DNS Website Shield permission.');
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
                backgroundColor: _openedAlwaysOnVpnSettings
                    ? _darkColor
                    : Colors.grey.shade300,
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                      fontSize: 13, color: Colors.grey.shade600, height: 1.6),
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
                    style: GoogleFonts.poppins(color: Colors.grey.shade400)),
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
                  backgroundColor: _openedAutoStartSettings
                      ? _darkColor
                      : Colors.grey.shade300,
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
    if (m.contains('infinix') || m.contains('tecno') || m.contains('itel')) {
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

  Future<void> _showDnsActivationGuide(BlockService service) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _accentColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.shield_rounded,
                      color: _accentColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('One last step',
                      style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _darkColor)),
                ),
              ]),
              const SizedBox(height: 10),
              Text(
                'Apple requires you to switch on BetControl\'s DNS shield yourself. It takes about 20 seconds:',
                style: GoogleFonts.poppins(
                    fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              _dnsGuideStep(1, 'Open the iPhone Settings app'),
              _dnsGuideStep(2, 'Tap General → VPN & Device Management'),
              _dnsGuideStep(3, 'Tap DNS'),
              _dnsGuideStep(4, 'Select "BetControl Website Shield"'),
              const SizedBox(height: 12),
              Row(children: [
                Icon(Icons.autorenew_rounded,
                    size: 16, color: Colors.grey.shade500),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Come back to BetControl afterwards — we\'ll detect it automatically.',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.grey.shade500),
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _darkColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    service.openVpnSettings();
                  },
                  child: Text('Open Settings',
                      style: GoogleFonts.poppins(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: Text('I\'ll do it later',
                      style: GoogleFonts.poppins(
                          fontSize: 13, color: Colors.grey.shade500)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dnsGuideStep(int number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: _darkColor,
            shape: BoxShape.circle,
          ),
          child: Text('$number',
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text,
              style: GoogleFonts.poppins(fontSize: 13.5, color: _darkColor)),
        ),
      ]),
    );
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
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 13))),
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                    style: GoogleFonts.poppins(color: Colors.grey.shade500)),
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                    style: GoogleFonts.poppins(color: Colors.grey.shade500)),
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
                        color: _darkColor, fontWeight: FontWeight.w600)),
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
                fontSize: 17, fontWeight: FontWeight.w600, color: _darkColor)),
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
            child:
                const Icon(Icons.shield_rounded, size: 60, color: _accentColor),
          ),
          const SizedBox(height: 24),
          Text('Protection Active',
              style: GoogleFonts.poppins(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: _darkColor)),
          const SizedBox(height: 8),
          Text(
              _vpnPermissionGranted
                  ? 'Gambling apps and websites are blocked'
                  : 'Gambling apps are blocked. DNS Website Shield needs setup.',
              style: GoogleFonts.poppins(
                  fontSize: 14, color: Colors.grey.shade500)),
          if (_subscription.isTrial) ...[
            const SizedBox(height: 12),
            _buildTrialBadge(compact: true),
          ],
          const SizedBox(height: 20),
          _buildVpnSetupBanner(service),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                        color: _bgColor,
                        borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_clock_rounded,
                            size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 6),
                        Text('Unlocks ${_formatDate(service.unlockTime!)}',
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: Colors.grey.shade500)),
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
                  border: Border.all(color: Colors.red.shade300, width: 1.5),
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
                border: Border.all(color: Colors.orange.shade300, width: 1.5),
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
                border: Border.all(color: Colors.red.shade200, width: 1.5),
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
          if (!isAndroid) ...[
            _buildActiveScreenTimeStatusCard(),
            const SizedBox(height: 24),
          ],
          _buildActiveActionsCard(service),
          const SizedBox(height: 24),
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

  Widget _buildActiveActionsCard(BlockService service) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Protection controls',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _darkColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            service.hardCommitment
                ? 'Hard commitment is on: uninstalling apps is locked until you end protection with your PIN.'
                : 'Your PIN is required to end protection or cancel billing. App deletion stays available unless you enabled Hard commitment.',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.grey.shade500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          if (!isAndroid && service.hardCommitment) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.phonelink_lock_rounded,
                      size: 18, color: _accentColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Commitment mode is on: App deletion is disabled until protection ends.',
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        color: _darkColor,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          _activeActionTile(
            icon: Icons.subscriptions_outlined,
            label: 'Manage subscription',
            subtitle: 'View plan, restore, or cancel in App Store',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ManageSubscriptionScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          _activeActionTile(
            icon: Icons.lock_open_rounded,
            label: 'End protection early',
            subtitle: service.hardCommitment
                ? 'PIN required · also re-enables deleting apps'
                : 'Requires your 6-digit PIN',
            danger: true,
            onTap: () => _promptEndProtection(service),
          ),
        ],
      ),
    );
  }

  Widget _activeActionTile({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final color = danger ? Colors.red.shade700 : _darkColor;
    return Material(
      color: danger ? Colors.red.shade50 : const Color(0xFFF8F9FF),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.grey.shade400, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _promptEndProtection(BlockService service) async {
    final hard = service.hardCommitment;
    final pin = await _showPinChallengeDialog(
      title: 'End protection early?',
      message: hard
          ? 'Enter your 6-digit PIN to turn off blocking and re-enable app uninstall. '
              'Store billing is separate — cancel under Manage subscription if you want charges to stop.'
          : 'Enter your 6-digit PIN to turn off blocking now. '
              'Store billing is separate — cancel under Manage subscription if you want charges to stop.',
    );
    if (pin == null || !mounted) return;

    final ok = await service.endProtectionWithPin(pin);
    if (!mounted) return;
    if (ok) {
      _showSuccessSnack('Protection turned off.');
      setState(() {});
    } else {
      _showSnack('Incorrect PIN. Protection is still active.');
    }
  }

  /// Shared PIN entry sheet used for ending protection / cancel flows.
  Future<String?> _showPinChallengeDialog({
    required String title,
    required String message,
  }) async {
    final controller = TextEditingController();
    var obscure = true;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text(
                title,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  color: _darkColor,
                  fontSize: 17,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    obscureText: obscure,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    autofocus: true,
                    style: GoogleFonts.poppins(
                      letterSpacing: 6,
                      fontWeight: FontWeight.w600,
                      color: _darkColor,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '••••••',
                      filled: true,
                      fillColor: const Color(0xFFF3F4F8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                        ),
                        onPressed: () => setLocal(() => obscure = !obscure),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel',
                      style: GoogleFonts.poppins(color: Colors.grey)),
                ),
                TextButton(
                  onPressed: () {
                    final pin = controller.text.trim();
                    if (pin.length != 6) return;
                    Navigator.pop(ctx, pin);
                  },
                  child: Text(
                    'Confirm',
                    style: GoogleFonts.poppins(
                      color: _accentColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    return result;
  }

  Widget _buildHardCommitmentToggle() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _hardCommitment ? _accentColor.withValues(alpha: 0.5) : Colors.grey.shade200,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (_hardCommitment ? _accentColor : _darkColor)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.phonelink_lock_rounded,
              size: 20,
              color: _hardCommitment ? _accentColor : _darkColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hard commitment',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _darkColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'While protection is on, iOS will block uninstalling any app (including BetControl) so you can\'t delete the shield on impulse. '
                  'This is optional — leave off if you still want to remove other apps normally.',
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Switch.adaptive(
            value: _hardCommitment,
            activeTrackColor: _accentColor,
            onChanged: (value) async {
              if (value) {
                final confirmed = await _confirmHardCommitment();
                if (!mounted) return;
                if (!confirmed) return;
              }
              setState(() => _hardCommitment = value);
            },
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmHardCommitment() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Enable hard commitment?',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            color: _darkColor,
            fontSize: 17,
          ),
        ),
        content: Text(
          'Apple only allows this as a device-wide setting. While protection is active you won\'t be able to delete apps from the Home Screen — not just BetControl.\n\n'
          'End protection with your PIN (or wait for the timer) to unlock app deletion again.',
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: Colors.grey.shade600,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Enable',
              style: GoogleFonts.poppins(
                color: _accentColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }

  Widget _buildActiveScreenTimeStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.rule_folder_rounded,
                color: _accentColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gambling blocklist active',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _darkColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _selectedWebDomainTokenCount > 0
                      ? 'BetControl blocks known gambling apps and your selected gambling websites.'
                      : 'BetControl blocks known gambling apps. Select website shields to block websites.',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.check_circle_rounded, size: 20, color: _accentColor),
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

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
            if ((isAndroid &&
                    (!_vpnPermissionGranted || !_alwaysOnVpnEnabled)) ||
                !isAndroid) ...[
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
              _usesSubscriptionDuration
                  ? 'Your protection will follow your active subscription. Set a PIN to lock your settings.'
                  : 'Choose a duration and set a PIN. Once activated, the block cannot be turned off until the timer expires.',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey.shade500, height: 1.5),
            ),
            // Show which steps still need completing
            if (!allReady) ...[
              const SizedBox(height: 12),
              _buildPendingStepsHint(),
            ],
            const SizedBox(height: 28),
            if (_usesSubscriptionDuration) ...[
              _buildSubscriptionDurationCard(),
              const SizedBox(height: 28),
            ] else ...[
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
                          color: isSelected ? _darkColor : Colors.grey.shade200,
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
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2))
                              ],
                      ),
                      child: Center(
                        child: Text(
                          option['label'] as String,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected ? _accentColor : _darkColor,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 28),
            ],
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
                      Text('Set Your Protection PIN',
                          style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _darkColor)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'This PIN is required to end protection early (and unlock app deletion) or open cancel billing. Choose one only you know.',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.grey.shade500, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  _pinField(
                    controller: _pinController,
                    label: '6-Digit PIN',
                    obscure: _obscurePin,
                    onToggle: () => setState(() => _obscurePin = !_obscurePin),
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
            if (!isAndroid) ...[
              const SizedBox(height: 16),
              _buildHardCommitmentToggle(),
            ],
            const SizedBox(height: 32),
            if (_subscription.status == SubscriptionStatus.trialExpired) ...[
              _buildSubscriptionDisclosure(),
              const SizedBox(height: 14),
            ],
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
                              color:
                                  allReady ? _darkColor : Colors.grey.shade500),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_subscription.status == SubscriptionStatus.trialExpired) ...[
              _buildSubscriptionLegalLinks(),
              const SizedBox(height: 14),
            ],
            Center(
              child: Text(
                isAndroid
                    ? 'Your PIN is required later to end protection early or cancel billing.'
                    : (_hardCommitment
                        ? 'Hard commitment: app uninstall stays locked until you end protection with your PIN.'
                        : 'Default: you can still delete apps. Enable Hard commitment above for stronger lock-in.'),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 11, color: Colors.grey.shade400),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingStepsHint() {
    final pending = <String>[];
    if (isAndroid && !_accessibilityEnabled) pending.add('Enable app blocking');
    if (isAndroid && !_deviceAdminActive) {
      pending.add('Enable tamper protection');
    }
    if (!_vpnPermissionGranted) {
      pending.add(
          isAndroid ? 'Enable website shield' : 'Enable Screen Time Shield');
    }
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

  Widget _buildSubscriptionDisclosure() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accentColor.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _subscriptionDetailRow('Subscription', 'Premium Monthly'),
          const SizedBox(height: 8),
          _subscriptionDetailRow('Price', '₦1,500/month'),
          const SizedBox(height: 8),
          _subscriptionDetailRow('Duration', 'Monthly'),
        ],
      ),
    );
  }

  Widget _subscriptionDetailRow(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: Colors.grey.shade500,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: _darkColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildSubscriptionLegalLinks() {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'By subscribing you agree to our ',
          style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500),
        ),
        _inlineLegalLink('Privacy Policy', _privacyPolicyUrl),
        Text(
          ' and ',
          style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500),
        ),
        _inlineLegalLink('Terms of Use', _termsOfUseUrl),
        Text(
          '.',
          style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  Widget _inlineLegalLink(String label, String url) {
    return GestureDetector(
      onTap: () => _openLegalUrl(url),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 11,
          color: _accentColor,
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.underline,
          decorationColor: _accentColor,
        ),
      ),
    );
  }

  Future<void> _openLegalUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      _showSnack('Could not open link.');
    }
  }

  Widget _buildSubscriptionDurationCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accentColor.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.event_available_rounded,
                color: _accentColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Duration follows subscription',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _darkColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Protection will run for your active billing period.',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
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
          color: _autoStartEnabled ? Colors.green.shade50 : Colors.red.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                _autoStartEnabled ? Colors.green.shade300 : Colors.red.shade300,
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
          color:
              _deviceAdminActive ? Colors.green.shade50 : Colors.orange.shade50,
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
    final isPreparingShield = _isShieldPermissionLoading && !vpnReady;
    final shieldName = isAndroid ? 'Website shield' : 'Website Shield';
    final shieldEnabledText =
        isAndroid ? 'Website shield enabled ✓' : 'DNS Website Shield enabled ✓';
    final shieldPromptText = isPreparingShield
        ? (isAndroid
            ? 'Preparing website shield...'
            : 'Preparing DNS Website Shield prompt...')
        : (isAndroid
            ? 'Tap here to enable website shield'
            : 'Tap here to enable DNS Website Shield');
    final fullProtectionText = isAndroid
        ? 'Full website protection enabled ✓'
        : 'Website Shield ready ✓';

    if (isAndroid && vpnReady && alwaysOnReady) {
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
                fullProtectionText,
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
        // Row 1: VPN permission on Android, Screen Time authorization on iOS
        GestureDetector(
          onTap: vpnReady || isPreparingShield
              ? null
              : () async {
                  debugPrint('🛡️ $shieldName UI: banner tapped');
                  await _requestShieldPermission(service);
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: vpnReady
                  ? (isAndroid ? Colors.green.shade50 : Colors.blue.shade50)
                  : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: vpnReady
                    ? (isAndroid ? Colors.green.shade300 : Colors.blue.shade300)
                    : Colors.orange.shade300,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  vpnReady ? Icons.vpn_key_rounded : Icons.vpn_key_off_rounded,
                  color: vpnReady
                      ? (isAndroid
                          ? Colors.green.shade600
                          : Colors.blue.shade600)
                      : Colors.orange.shade700,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    vpnReady ? shieldEnabledText : shieldPromptText,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: vpnReady
                          ? (isAndroid
                              ? Colors.green.shade700
                              : Colors.blue.shade700)
                          : Colors.orange.shade800,
                    ),
                  ),
                ),
                if (isPreparingShield)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.orange.shade700),
                    ),
                  )
                else if (!vpnReady)
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 14, color: Colors.orange.shade700),
              ],
            ),
          ),
        ),

        // Row 2: iOS curated blocklist status, Android always-on VPN
        if (!isAndroid && !vpnReady) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.red.shade200, width: 1.3),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.dns_rounded, color: Colors.red.shade600, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DNS profile is not active yet',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.red.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Open iPhone Settings > VPN & Device Management > DNS, then select BetControl Website Shield. AdGuard will show requests only after this is selected.',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          height: 1.45,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        if (vpnReady) ...[
          if (!isAndroid) ...[
            const SizedBox(height: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.green.shade300,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.rule_folder_rounded,
                      color: Colors.green.shade600, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gambling DNS shield active',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.green.shade700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'BetControl is filtering DNS queries from Safari and other apps.',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.check_circle_rounded,
                      size: 18, color: Colors.green.shade600),
                ],
              ),
            ),
          ],
          if (isAndroid) ...[
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
                                  fontSize: 11, color: Colors.orange.shade700),
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
      ],
    );
  }

  Widget _buildSubscriptionBanner() {
    switch (_subscription.status) {
      case SubscriptionStatus.active:
        final remaining = _subscription.timeRemaining;
        final isSubDayRenewal = remaining != null &&
            remaining > Duration.zero &&
            remaining < const Duration(days: 1);
        final daysLeft =
            remaining != null ? (remaining.inHours / 24).ceil() : null;
        final expiringSoon =
            !isSubDayRenewal && daysLeft != null && daysLeft <= 5;
        final label = expiringSoon
            ? 'Subscription expires in $daysLeft ${daysLeft == 1 ? 'day' : 'days'} — renew soon'
            : 'Subscription active';

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: expiringSoon ? Colors.orange.shade50 : Colors.green.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  expiringSoon ? Colors.orange.shade300 : Colors.green.shade300,
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
                  label,
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _darkColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.redeem_rounded, color: _accentColor, size: 18),
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
          color:
              isExpiringSoon ? Colors.orange.shade800 : const Color(0xFF007A63),
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
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
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
            borderSide: const BorderSide(color: _accentColor, width: 1.5)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year} at '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
