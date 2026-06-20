import 'dart:ui';
import '../../services/user_service.dart';
import 'package:betcontrol_main/screens/auth/email_verification_screen.dart';
import 'package:betcontrol_main/screens/auth/profile_check_wrapper.dart';
import 'package:betcontrol_main/utils/pin_utils.dart';
import 'package:betcontrol_main/widgets/betcontrol_logo.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/connectivity_service.dart';
import 'package:betcontrol_main/services/analytics_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with TickerProviderStateMixin {
  // ── Tab state ─────────────────────────────────────────────────────────────
  bool _isLogin = true;

  // ── Login controllers ─────────────────────────────────────────────────────
  final _loginEmailCtrl = TextEditingController();
  final _loginPinCtrl = TextEditingController();

  // ── Signup controllers ────────────────────────────────────────────────────
  final _signupEmailCtrl = TextEditingController();
  final _signupPinCtrl = TextEditingController();
  final _signupConfirmPinCtrl = TextEditingController();

  final _auth = FirebaseAuth.instance;
  final _connectivity = ConnectivityService();

  bool _isLoading = false;
  bool _obscureLoginPin = true;
  bool _obscureSignupPin = true;
  bool _obscureConfirmPin = true;
  bool _agreedToPolicy = false;
  bool _sheetOpen = false;

  // ── Animations ────────────────────────────────────────────────────────────
  late AnimationController _entryCtrl;
  late AnimationController _toggleCtrl;
  late AnimationController _formCtrl;
  late AnimationController _decorCtrl;

  late Animation<double> _entryFade;
  late Animation<Offset> _entrySlide;
  late Animation<double> _formFade;
  late Animation<Offset> _formSlide;
  late Animation<double> _decorFloat;

  // ── Constants ─────────────────────────────────────────────────────────────
  static const Color _bg = Color(0xFFF8F9FF);
  static const Color _accent = Color(0xFF00D4AA);
  static const Color _dark = Color(0xFF1A1A2E);
  static const String _privacyUrl = 'https://betcontrol-privacy.netlify.app';

  final List<String> _allowedDomains = [
    'gmail.com', 'yahoo.com', 'outlook.com', 'hotmail.com',
    'icloud.com', 'aol.com', 'protonmail.com', 'mail.com',
    'zoho.com', 'yandex.com', 'gmx.com', 'live.com',
    'msn.com', 'me.com', 'mac.com', 'yahoo.co.uk', 'outlook.co.uk',
  ];

  @override
  void initState() {
    super.initState();

    // Entry animation — runs once on screen open
    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _entryFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut));
    _entrySlide = Tween<Offset>(
            begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut));

    // Toggle pill animation
    _toggleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));

    // Form switch animation
    _formCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _formFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _formCtrl, curve: Curves.easeOut));
    _formSlide = Tween<Offset>(
            begin: const Offset(0.04, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _formCtrl, curve: Curves.easeOut));

    // Decorative element floating
    _decorCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3000))
      ..repeat(reverse: true);
    _decorFloat = Tween<double>(begin: -6.0, end: 6.0).animate(
        CurvedAnimation(parent: _decorCtrl, curve: Curves.easeInOut));

    _entryCtrl.forward();
    _formCtrl.forward();
  }

  @override
  void dispose() {
    _loginEmailCtrl.dispose();
    _loginPinCtrl.dispose();
    _signupEmailCtrl.dispose();
    _signupPinCtrl.dispose();
    _signupConfirmPinCtrl.dispose();
    _entryCtrl.dispose();
    _toggleCtrl.dispose();
    _formCtrl.dispose();
    _decorCtrl.dispose();
    super.dispose();
  }

  // ── Tab switch ────────────────────────────────────────────────────────────
  Future<void> _switchTab(bool toLogin) async {
    if (_isLogin == toLogin || _isLoading) return;
    await _formCtrl.reverse();
    setState(() => _isLogin = toLogin);
    if (toLogin) {
      _toggleCtrl.reverse();
    } else {
      _toggleCtrl.forward();
    }
    _formCtrl.forward();
  }

  // ── Snackbar ──────────────────────────────────────────────────────────────
  void _snack(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: GoogleFonts.poppins(
              color: Colors.white, fontWeight: FontWeight.w500)),
      backgroundColor: isError ? Colors.red.shade700 : _accent,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 4),
    ));
  }

  // ── Validation ────────────────────────────────────────────────────────────
  bool _validEmailFormat(String e) =>
      RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(e);

  bool _validEmailDomain(String e) {
    if (!e.contains('@')) return false;
    return _allowedDomains.contains(e.split('@').last.toLowerCase());
  }

  // ── Login ─────────────────────────────────────────────────────────────────
  Future<void> _signIn() async {
    final email = _loginEmailCtrl.text.trim();
    final pin = _loginPinCtrl.text.trim();
    if (email.isEmpty || pin.isEmpty) {
      _snack('Please enter your email and PIN');
      return;
    }
    if (pin.length != 4) {
      _snack('PIN must be exactly 4 digits');
      return;
    }
    setState(() => _isLoading = true);
    // Capture navigator before any await to avoid using BuildContext
    // across async gaps — satisfies the dart async lint warning.
    final navigator = Navigator.of(context);
    try {
      final ok = await _connectivity.hasInternetConnection();
      if (!mounted) return;
      if (!ok) { _snack('No internet connection.'); return; }
      await _auth.signInWithEmailAndPassword(
          email: email, password: PinUtils.encode(pin));
      if (mounted) {
        final user = _auth.currentUser;
        await user?.reload();
        if (!mounted) return;
        if (user != null && !user.emailVerified) {
          navigator.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const EmailVerificationScreen()),
            (r) => false,
          );
        } else {
          await AnalyticsService.logLogin(method: 'email');
          navigator.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const ProfileCheckWrapper()),
            (r) => false,
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _snack(switch (e.code) {
        'invalid-email' => 'Invalid email address',
        'user-disabled' => 'This account has been disabled',
        'user-not-found' || 'wrong-password' || 'invalid-credential' =>
          'Incorrect email or PIN',
        'too-many-requests' =>
          'Too many failed attempts. Try again later.',
        _ => 'An error occurred. Please try again.',
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Google ────────────────────────────────────────────────────────────────
  Future<void> _googleSignIn() async {
    setState(() => _isLoading = true);
    // Capture navigator before any await to avoid using BuildContext
    // across async gaps — satisfies the dart async lint warning.
    final navigator = Navigator.of(context);
    try {
      final ok = await _connectivity.hasInternetConnection();
      if (!mounted) return;
      if (!ok) { _snack('No internet connection.'); return; }
      final gs = GoogleSignIn();
      await _auth.signOut();
      await gs.signOut();
      final gUser = await gs.signIn();
      if (gUser == null) { setState(() => _isLoading = false); return; }
      final gAuth = await gUser.authentication;
      await _auth.signInWithCredential(GoogleAuthProvider.credential(
        accessToken: gAuth.accessToken, idToken: gAuth.idToken,
      ));
      final u = _auth.currentUser;
      if (u != null) {
        await UserService().createUserProfileIfNew(
            fullName: u.displayName ?? '', email: u.email ?? '');
      }
      if (mounted) {
        await AnalyticsService.logLogin(method: 'google');
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ProfileCheckWrapper()),
          (r) => false,
        );
      }
    } catch (_) {
      if (mounted) _snack('Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Sign up ───────────────────────────────────────────────────────────────
  Future<void> _signUp() async {
    if (!_agreedToPolicy) {
      _snack('Please agree to the Privacy Policy');
      return;
    }
    final email = _signupEmailCtrl.text.trim();
    final pin = _signupPinCtrl.text.trim();
    final confirm = _signupConfirmPinCtrl.text.trim();
    if (email.isEmpty || pin.isEmpty || confirm.isEmpty) {
      _snack('Please fill in all fields');
      return;
    }
    if (pin.length != 4) { _snack('PIN must be exactly 4 digits'); return; }
    if (pin != confirm) { _snack('PINs do not match'); return; }
    if (!_validEmailFormat(email)) {
      _snack('Please enter a valid email address');
      return;
    }
    if (!_validEmailDomain(email)) {
      _snack('Use Gmail, Yahoo, Outlook or similar');
      return;
    }
    setState(() => _isLoading = true);
    // Capture navigator before any await to avoid using BuildContext
    // across async gaps — satisfies the dart async lint warning.
    final navigator = Navigator.of(context);
    try {
      final ok = await _connectivity.hasInternetConnection();
      if (!mounted) return;
      if (!ok) { _snack('No internet connection.'); return; }
      final cred = await _auth.createUserWithEmailAndPassword(
          email: email, password: PinUtils.encode(pin));
      await cred.user?.sendEmailVerification();
      await UserService().createUserProfile(fullName: '', email: email);
      await AnalyticsService.logSignUp(method: 'email');
      if (mounted) {
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const EmailVerificationScreen()),
          (r) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _snack(switch (e.code) {
        'email-already-in-use' =>
          'This email is already registered. Try logging in.',
        'weak-password' => 'PIN is too weak. Please choose another.',
        'invalid-email' => 'Invalid email address',
        'network-request-failed' => 'Connection error. Please try again.',
        _ => 'An error occurred. Please try again.',
      });
    } catch (_) {
      if (mounted) _snack('An error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Reset PIN sheet ───────────────────────────────────────────────────────
  Future<void> _sendReset(String email) async {
    try {
      final ok = await _connectivity.hasInternetConnection();
      if (!ok) { _snack('No internet connection.'); return; }
      await _auth.sendPasswordResetEmail(email: email);
      if (mounted) _snack('Reset link sent to $email', isError: false);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _snack(switch (e.code) {
        'invalid-email' => 'Invalid email address',
        'user-not-found' => 'No account found with this email',
        _ => 'An error occurred. Please try again.',
      });
    }
  }

  void _showResetSheet() {
    final ctrl = TextEditingController();
    setState(() => _sheetOpen = true);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 28, right: 28, top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Text('Reset PIN 🔐',
                style: GoogleFonts.poppins(
                    fontSize: 22, fontWeight: FontWeight.w800, color: _dark)),
            const SizedBox(height: 6),
            Text('Enter your email to receive a reset link.',
                style: GoogleFonts.poppins(
                    fontSize: 13, color: Colors.grey.shade500)),
            const SizedBox(height: 20),
            _field(
              controller: ctrl,
              label: 'Email',
              icon: Icons.email_outlined,
              inputType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () async {
                final email = ctrl.text.trim();
                if (email.isEmpty) { _snack('Please enter your email'); return; }
                final nav = Navigator.of(ctx);
                await _sendReset(email);
                if (!mounted) return;
                nav.pop();
              },
              child: Container(
                width: double.infinity, height: 56,
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: _accent.withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8))
                  ],
                ),
                child: Center(
                  child: Text('Send Reset Link',
                      style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _dark)),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _sheetOpen = false);
    });
  }

  Future<void> _openPrivacy() async {
    try {
      await launchUrl(Uri.parse(_privacyUrl),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      _snack('Could not open Privacy Policy.');
    }
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // ── Decorative background blobs ───────────────────────────────
          Positioned(
            top: -80,
            right: -80,
            child: AnimatedBuilder(
              animation: _decorFloat,
              builder: (_, child) =>
                  Transform.translate(offset: Offset(0, _decorFloat.value), child: child),
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accent.withValues(alpha: 0.07),
                ),
              ),
            ),
          ),
          Positioned(
            top: 60,
            right: 10,
            child: AnimatedBuilder(
              animation: _decorFloat,
              builder: (_, child) =>
                  Transform.translate(offset: Offset(0, -_decorFloat.value * 0.6), child: child),
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _dark.withValues(alpha: 0.04),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 120,
            left: -40,
            child: AnimatedBuilder(
              animation: _decorFloat,
              builder: (_, child) =>
                  Transform.translate(offset: Offset(0, _decorFloat.value * 0.8), child: child),
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accent.withValues(alpha: 0.05),
                ),
              ),
            ),
          ),

          // ── Main scrollable content ───────────────────────────────────
          SafeArea(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: FadeTransition(
                opacity: _entryFade,
                child: SlideTransition(
                  position: _entrySlide,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // ── Logo + tagline ─────────────────────────────
                        _buildHeader(),

                        const SizedBox(height: 32),

                        // ── Tab toggle ─────────────────────────────────
                        _buildToggle(),

                        const SizedBox(height: 28),

                        // ── Animated form card ─────────────────────────
                        _buildFormCard(),

                        const SizedBox(height: 28),

                        // ── Bottom switch link ─────────────────────────
                        _buildSwitchLink(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Blur when bottom sheet is open ────────────────────────────
          if (_sheetOpen)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Container(color: Colors.black.withValues(alpha: 0.04)),
              ),
            ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: _accent.withValues(alpha: 0.2),
                blurRadius: 30,
                spreadRadius: 4,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Center(child: BetControlLogo(size: 56)),
        ),
        const SizedBox(height: 14),
        Text('BetControl',
            style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _dark,
                letterSpacing: -0.3)),
        const SizedBox(height: 4),
        Text('Your protection. Your control.',
            style: GoogleFonts.poppins(
                fontSize: 13, color: Colors.grey.shade500)),
      ],
    );
  }

  // ── Toggle ────────────────────────────────────────────────────────────────
  Widget _buildToggle() {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Sliding active pill
          AnimatedAlign(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            alignment:
                _isLogin ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: _dark,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: _dark.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Labels
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _switchTab(true),
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _isLogin
                            ? _accent
                            : Colors.grey.shade500,
                      ),
                      child: const Text('Log In'),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => _switchTab(false),
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: !_isLogin
                            ? _accent
                            : Colors.grey.shade500,
                      ),
                      child: const Text('Sign Up'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Form card ─────────────────────────────────────────────────────────────
  Widget _buildFormCard() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: _accent.withValues(alpha: 0.04),
              blurRadius: 40,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FadeTransition(
          opacity: _formFade,
          child: SlideTransition(
            position: _formSlide,
            child: _isLogin ? _loginForm() : _signupForm(),
          ),
        ),
      ),
    );
  }

  // ── Login form ────────────────────────────────────────────────────────────
  Widget _loginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formHeading('Welcome\nback! 👋', 'Sign in to continue your journey'),
        const SizedBox(height: 20),
        _field(
          controller: _loginEmailCtrl,
          label: 'Email',
          icon: Icons.email_outlined,
          inputType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        _field(
          controller: _loginPinCtrl,
          label: '4-Digit PIN',
          icon: Icons.pin_outlined,
          inputType: TextInputType.number,
          obscure: _obscureLoginPin,
          maxLen: 4,
          onToggle: () => setState(() => _obscureLoginPin = !_obscureLoginPin),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _isLoading ? null : _showResetSheet,
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            child: Text('Forgot PIN?',
                style: GoogleFonts.poppins(
                    color: _accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ),
        ),
        const SizedBox(height: 6),
        _primaryBtn('Sign In', _isLoading ? null : _signIn),
        const SizedBox(height: 20),
        _orDivider(),
        const SizedBox(height: 18),
        _googleBtn(),
      ],
    );
  }

  // ── Signup form ───────────────────────────────────────────────────────────
  Widget _signupForm() {
    final canSubmit = _agreedToPolicy && !_isLoading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formHeading('Create\naccount ✨', 'Join and take back control'),
        const SizedBox(height: 18),
        _field(
          controller: _signupEmailCtrl,
          label: 'Email',
          icon: Icons.email_outlined,
          inputType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        _field(
          controller: _signupPinCtrl,
          label: '4-Digit PIN',
          icon: Icons.pin_outlined,
          inputType: TextInputType.number,
          obscure: _obscureSignupPin,
          maxLen: 4,
          onToggle: () => setState(() => _obscureSignupPin = !_obscureSignupPin),
        ),
        const SizedBox(height: 14),
        _field(
          controller: _signupConfirmPinCtrl,
          label: 'Confirm PIN',
          icon: Icons.pin_outlined,
          inputType: TextInputType.number,
          obscure: _obscureConfirmPin,
          maxLen: 4,
          onToggle: () =>
              setState(() => _obscureConfirmPin = !_obscureConfirmPin),
        ),
        const SizedBox(height: 20),
        // Privacy policy checkbox
        GestureDetector(
          onTap: _isLoading
              ? null
              : () => setState(() => _agreedToPolicy = !_agreedToPolicy),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: _agreedToPolicy ? _dark : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _agreedToPolicy ? _dark : Colors.grey.shade400,
                    width: 1.5,
                  ),
                ),
                child: _agreedToPolicy
                    ? const Icon(Icons.check_rounded,
                        color: _accent, size: 14)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        height: 1.4),
                    children: [
                      const TextSpan(text: 'I agree to the '),
                      TextSpan(
                        text: 'Privacy Policy',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: _accent,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          decorationColor: _accent,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = _openPrivacy,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _primaryBtn(
          'Create Account',
          canSubmit ? _signUp : null,
          disabled: !canSubmit,
        ),
      ],
    );
  }

  // ── Bottom switch link ────────────────────────────────────────────────────
  Widget _buildSwitchLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _isLogin ? "Don't have an account? " : 'Already have an account? ',
          style: GoogleFonts.poppins(
              color: Colors.grey.shade500, fontSize: 14),
        ),
        GestureDetector(
          onTap: _isLoading ? null : () => _switchTab(!_isLogin),
          child: Text(
            _isLogin ? 'Sign Up' : 'Log In',
            style: GoogleFonts.poppins(
                color: _accent,
                fontWeight: FontWeight.w700,
                fontSize: 14),
          ),
        ),
      ],
    );
  }

  // ── Reusable UI pieces ────────────────────────────────────────────────────

  Widget _formHeading(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: GoogleFonts.poppins(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: _dark,
                height: 1.2)),
        const SizedBox(height: 6),
        Text(subtitle,
            style: GoogleFonts.poppins(
                fontSize: 13, color: Colors.grey.shade500)),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required TextInputType inputType,
    bool obscure = false,
    int? maxLen,
    VoidCallback? onToggle,
  }) {
    return TextField(
      controller: controller,
      keyboardType: inputType,
      obscureText: obscure,
      maxLength: maxLen,
      enabled: !_isLoading,
      inputFormatters:
          maxLen != null ? [FilteringTextInputFormatter.digitsOnly] : null,
      style: GoogleFonts.poppins(fontSize: 14, color: _dark),
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        labelStyle:
            GoogleFonts.poppins(color: Colors.grey.shade500, fontSize: 14),
        prefixIcon: Icon(icon, color: _accent, size: 20),
        suffixIcon: onToggle != null
            ? GestureDetector(
                onTap: _isLoading ? null : onToggle,
                child: Icon(
                  obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: Colors.grey.shade400,
                  size: 20,
                ),
              )
            : null,
        filled: true,
        fillColor: _isLoading ? Colors.grey.shade50 : _bg,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _accent, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _primaryBtn(String label, VoidCallback? onTap,
      {bool disabled = false}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: disabled
              ? Colors.grey.shade200
              : _isLoading
                  ? _accent.withValues(alpha: 0.6)
                  : _accent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: disabled || _isLoading
              ? []
              : [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.38),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: Center(
          child: _isLoading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5))
              : Text(label,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: disabled ? Colors.grey.shade400 : _dark,
                  )),
        ),
      ),
    );
  }

  Widget _orDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.shade200)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text('or',
              style: GoogleFonts.poppins(
                  color: Colors.grey.shade400, fontSize: 13)),
        ),
        Expanded(child: Divider(color: Colors.grey.shade200)),
      ],
    );
  }

  Widget _googleBtn() {
    return GestureDetector(
      onTap: _isLoading ? null : _googleSignIn,
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.network(
              'https://www.google.com/favicon.ico',
              height: 20, width: 20,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.g_mobiledata, size: 22),
            ),
            const SizedBox(width: 12),
            Text('Continue with Google',
                style: GoogleFonts.poppins(
                    color: _dark, fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}