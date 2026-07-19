import 'dart:io';

import 'package:betcontrol_main/screens/auth/auth_screen.dart';
import 'package:betcontrol_main/screens/auth/complete_profile_screen.dart';
import 'package:betcontrol_main/screens/auth/email_verification_screen.dart';
import 'package:betcontrol_main/screens/home_screen.dart';
import 'package:betcontrol_main/screens/onboarding_screen.dart';
import 'package:betcontrol_main/services/notification_service.dart';
import 'package:betcontrol_main/services/user_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileCheckWrapper extends StatefulWidget {
  const ProfileCheckWrapper({super.key});

  @override
  State<ProfileCheckWrapper> createState() => _ProfileCheckWrapperState();
}

class _ProfileCheckWrapperState extends State<ProfileCheckWrapper>
    with TickerProviderStateMixin {
  static const Color _bg = Color(0xFF1A1A2E);
  static const Color _accent = Color(0xFF00D4AA);
  static const String _appName = 'BetControl';

  late AnimationController _logoController;
  late Animation<double> _logoScale;
  late Animation<double> _logoFade;

  final List<AnimationController> _letterControllers = [];
  final List<Animation<double>> _letterFades = [];
  final List<Animation<Offset>> _letterSlides = [];

  late AnimationController _taglineController;
  late Animation<double> _taglineFade;

  late AnimationController _loadingController;
  late Animation<double> _loadingFade;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startSequence();
  }

  void _setupAnimations() {
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOut),
    );

    for (int i = 0; i < _appName.length; i++) {
      final ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
      );
      final fade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: ctrl, curve: Curves.easeOut),
      );
      final slide = Tween<Offset>(
        begin: const Offset(0, 0.4),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: ctrl, curve: Curves.easeOut));

      _letterControllers.add(ctrl);
      _letterFades.add(fade);
      _letterSlides.add(slide);
    }

    _taglineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _taglineFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _taglineController, curve: Curves.easeOut),
    );

    _loadingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _loadingFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _loadingController, curve: Curves.easeOut),
    );
  }

  Future<void> _startSequence() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) _logoController.forward();

    await Future.delayed(const Duration(milliseconds: 700));
    for (int i = 0; i < _appName.length; i++) {
      await Future.delayed(const Duration(milliseconds: 80));
      if (mounted) _letterControllers[i].forward();
    }

    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) _taglineController.forward();
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) _loadingController.forward();

    await _checkAndNavigate();
  }

  Future<void> _checkAndNavigate() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      final prefs = await SharedPreferences.getInstance();
      final hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;
      _go(hasSeenOnboarding ? const AuthScreen() : const OnboardingScreen());
      return;
    }

    // Fire reload and profile check simultaneously
    final results = await Future.wait([
      user
          .reload()
          .timeout(const Duration(seconds: 3))
          .then((_) => true)
          .catchError((_) => false),
      UserService()
          .isProfileComplete()
          .timeout(const Duration(seconds: 5), onTimeout: () => false),
    ]);

    final refreshed = FirebaseAuth.instance.currentUser;

    if (refreshed == null) {
      _go(const AuthScreen());
      return;
    }

    if (!refreshed.emailVerified) {
      final isGoogle =
          refreshed.providerData.any((p) => p.providerId == 'google.com');
      if (!isGoogle) {
        _go(const EmailVerificationScreen());
        return;
      }
    }

    _syncRevenueCatUser(refreshed.uid);

    // Save FCM token to Firestore so Cloud Functions can send push notifications
    _saveFcmToken(refreshed.uid);

    if (!mounted) return;
    final isComplete = results[1];
    _go(isComplete ? const HomeScreen() : const CompleteProfileScreen());
  }

  Future<void> _syncRevenueCatUser(String uid) async {
    if (!Platform.isIOS) return;

    try {
      await Purchases.logIn(uid).timeout(const Duration(seconds: 5));
    } catch (_) {
      // RevenueCat will keep using its cached user and retry on later launches.
    }
  }

  // ── Save FCM token — fire and forget, never blocks navigation ────────────
  Future<void> _saveFcmToken(String uid) async {
    try {
      final token = await NotificationService().getFcmToken();
      if (token == null) return;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'fcmToken': token}).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Non-critical — if this fails, FCM push won't work but app still functions
    }
  }

  void _go(Widget screen) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => screen,
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  void dispose() {
    _logoController.dispose();
    for (final c in _letterControllers) {
      c.dispose();
    }
    _taglineController.dispose();
    _loadingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FadeTransition(
              opacity: _logoFade,
              child: ScaleTransition(
                scale: _logoScale,
                child: _buildLogo(),
              ),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(_appName.length, (i) {
                return FadeTransition(
                  opacity: _letterFades[i],
                  child: SlideTransition(
                    position: _letterSlides[i],
                    child: Text(
                      _appName[i],
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),
            FadeTransition(
              opacity: _taglineFade,
              child: Text(
                'TAKE BACK CONTROL',
                style: GoogleFonts.poppins(
                  color: _accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 4,
                ),
              ),
            ),
            const SizedBox(height: 48),
            FadeTransition(
              opacity: _loadingFade,
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: _accent,
                  strokeWidth: 2.5,
                  backgroundColor: _accent.withValues(alpha: 0.2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return SizedBox(
      width: 130,
      height: 130,
      child: CustomPaint(painter: _LogoPainter()),
    );
  }
}

class _LogoPainter extends CustomPainter {
  static const Color _dark = Color(0xFF1A1A2E);
  static const Color _accent = Color(0xFF00D4AA);
  static const Color _white = Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    final bgPaint = Paint()..color = _accent;
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: w, height: h),
      const Radius.circular(28),
    );
    canvas.drawRRect(bgRect, bgPaint);

    final innerPaint = Paint()..color = _dark;
    final innerRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset(cx, cy), width: w * 0.82, height: h * 0.82),
      const Radius.circular(20),
    );
    canvas.drawRRect(innerRect, innerPaint);

    final shieldPaint = Paint()
      ..color = _accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final shieldPath = Path();
    shieldPath.moveTo(cx - 22, cy - 18);
    shieldPath.lineTo(cx, cy - 24);
    shieldPath.lineTo(cx + 22, cy - 18);
    shieldPath.lineTo(cx + 22, cy + 4);
    shieldPath.quadraticBezierTo(cx + 22, cy + 24, cx, cy + 32);
    shieldPath.quadraticBezierTo(cx - 22, cy + 24, cx - 22, cy + 4);
    shieldPath.close();
    canvas.drawPath(shieldPath, shieldPaint);

    final shacklePaint = Paint()
      ..color = _white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final shacklePath = Path();
    shacklePath.moveTo(cx - 12, cy + 2);
    shacklePath.lineTo(cx - 12, cy - 8);
    shacklePath.arcToPoint(
      Offset(cx + 12, cy - 8),
      radius: const Radius.circular(12),
      clockwise: false,
    );
    shacklePath.lineTo(cx + 12, cy + 2);
    canvas.drawPath(shacklePath, shacklePaint);

    final bodyPaint = Paint()..color = _white;
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy + 12), width: 30, height: 22),
      const Radius.circular(5),
    );
    canvas.drawRRect(bodyRect, bodyPaint);

    final keyholePaint = Paint()..color = _dark;
    canvas.drawCircle(Offset(cx, cy + 10), 4.5, keyholePaint);

    final slotRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy + 17), width: 4, height: 7),
      const Radius.circular(2),
    );
    canvas.drawRRect(slotRect, keyholePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
