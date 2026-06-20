
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart' as legacy_provider;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:betcontrol_main/screens/auth/profile_check_wrapper.dart';
import 'package:betcontrol_main/services/block_services.dart';
import 'package:betcontrol_main/services/notification_service.dart';
import 'package:betcontrol_main/services/purchase_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'firebase_options.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isIOS) {
    await Purchases.setLogLevel(LogLevel.debug);

    PurchasesConfiguration configuration = PurchasesConfiguration("appl_CMEYfJTGeLxHgFhWocUAsfPoJcF");
    await Purchases.configure(configuration);
  }

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ── Crashlytics — catch all uncaught errors and report them ──────────
  FlutterError.onError = (errorDetails) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  final blockService = BlockService();
  await blockService.init();

  await NotificationService().init();
  await NotificationService().requestPermission();

  runApp(
    legacy_provider.ChangeNotifierProvider.value(
      value: blockService,
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.betcontrol/blocker');

  // ── Single Analytics instance used across the app ─────────────────
  static final _analytics = FirebaseAnalytics.instance;
  static final _analyticsObserver =
      FirebaseAnalyticsObserver(analytics: _analytics);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleRestorationIfNeeded();
      _recoverPaymentInBackground();
      // ── Check for a new Play Store version on every cold start ─────
      // Flexible update — downloads in background, user keeps using the
      // app, then gets a prompt to restart and apply when ready.
      // Silently does nothing in debug mode or when no update exists.
      _checkForUpdate();
    });

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'showProtectionRestoration') {
        _handleRestorationIfNeeded();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleRestorationIfNeeded();
      // Re-check on resume in case the user was away for a while and
      // a new version landed on the Play Store in the meantime.
      _checkForUpdate();
    }
  }

  // ── Flexible in-app update ─────────────────────────────────────────
  // 1. checkForUpdate()        — asks Play Store if a newer version exists
  // 2. startFlexibleUpdate()   — begins downloading in the background
  // 3. completeFlexibleUpdate()— once downloaded, prompts user to restart
  //    and apply. It's safe to call completeFlexibleUpdate() immediately after starting
  //    the update — it internally waits until the download finishes.
  Future<void> _checkForUpdate() async {
    // Only run on release builds against real Play Store — skip in debug
    // so development workflow is never interrupted by update prompts.
    if (kDebugMode) return;
    try {
      final updateInfo = await InAppUpdate.checkForUpdate();
      if (updateInfo.updateAvailability ==
          UpdateAvailability.updateAvailable) {
        await InAppUpdate.startFlexibleUpdate();
        // completeFlexibleUpdate() shows the "Restart to update" prompt
        // once the download finishes. It's safe to call immediately —
        // it waits internally until the download is complete.
        await InAppUpdate.completeFlexibleUpdate();
      }
    } catch (_) {
      // Silently swallow all update errors — a failed update check
      // must never crash the app or interrupt the blocking service.
    }
  }

  Future<void> _handleRestorationIfNeeded() async {
    try {
      final context = navigatorKey.currentContext;
      if (context == null) return;

      final blockService = legacy_provider.Provider.of<BlockService>(
        context,
        listen: false,
      );

      if (!blockService.isBlocking) return;

      await blockService.restartProtection();
      await _channel.invokeMethod('clearRestorationNotification');
    } catch (_) {}
  }

  void _recoverPaymentInBackground() {
    Future.microtask(() async {
      try {
        debugPrint('🔍 BetControl: Starting payment recovery check...');
        final result = await PurchaseService().recoverPendingPayment();

        if (result == null) {
          debugPrint('ℹ️ No recovery needed');
          return;
        }

        if (result.success) {
          debugPrint('✅ Recovery succeeded — subscription activated');
          _showSnackbar(
            message:
                'Your payment was confirmed! Blocking protection is now active.',
            backgroundColor: const Color(0xFF00D4AA),
            icon: Icons.check_circle_rounded,
            duration: const Duration(seconds: 5),
          );
        } else if (result.errorType == PaymentErrorType.incompleteReminder) {
          debugPrint('⚠️ Incomplete payment — showing reminder');
          _showSnackbar(
            message: result.errorMessage ??
                'You have an incomplete payment. If you\'ve already sent the money, '
                    'your subscription will activate automatically.',
            backgroundColor: Colors.amber.shade700,
            icon: Icons.info_outline_rounded,
            duration: const Duration(seconds: 7),
          );
        }
      } catch (e) {
        debugPrint('❌ Payment recovery error: $e');
      }
    });
  }

  void _showSnackbar({
    required String message,
    required Color backgroundColor,
    required IconData icon,
    required Duration duration,
  }) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.poppins(
                    color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {},
      child: MaterialApp(
        title: 'BetControl',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: scaffoldMessengerKey,
        navigatorKey: navigatorKey,
        // ── Analytics observer — auto-tracks every screen transition ──
        navigatorObservers: [_analyticsObserver],
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF1A1A2E),
            secondary: Color(0xFF00D4AA),
            surface: Color(0xFFF8F9FF),
            error: Color(0xFFFF6B6B),
          ),
          textTheme: GoogleFonts.poppinsTextTheme(),
          scaffoldBackgroundColor: const Color(0xFFF8F9FF),
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            titleTextStyle: GoogleFonts.poppins(
              color: const Color(0xFF1A1A2E),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A1A2E),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              textStyle: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(
                  color: Color(0xFF00D4AA), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFFF6B6B)),
            ),
            labelStyle: GoogleFonts.poppins(
                color: const Color(0xFF6B7280), fontSize: 14),
          ),
        ),
        home: const ProfileCheckWrapper(),
      ),
    );
  }
}