import 'package:betcontrol_main/screens/auth/auth_screen.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _controller = PageController();
  int _currentPage = 0;

  late AnimationController _entryController;
  late Animation<double> _entryFade;
  late Animation<Offset> _entrySlide;

  late AnimationController _pulseController;
  late Animation<double> _pulse;

  static const Color _dark = Color(0xFF1A1A2E);
  static const Color _accent = Color(0xFF00D4AA);
  static const Color _bg = Color(0xFFF8F9FF);

  final List<Map<String, dynamic>> _pages = [
    {
      'tag': 'FREEDOM',
      'title': 'Take Back\nControl',
      'subtitle':
          'Break free from gambling habits with powerful blocking tools built to protect you around the clock.',
      'icon': Icons.shield_rounded,
      'iconColor': const Color(0xFF00D4AA),
      'highlights': ['Blocks gambling sites', 'Blocks gambling apps', 'Works 24/7'],
    },
    {
      'tag': 'PROTECTION',
      'title': 'Set Your\nLimits',
      'subtitle':
          'Choose how long to block gambling sites and apps. One month, one year — or longer. You decide.',
      'icon': Icons.lock_clock_rounded,
      'iconColor': const Color(0xFF6C63FF),
      'highlights': ['1 month to 10 years', 'PIN-protected', 'Cannot be bypassed'],
    },
    {
      'tag': 'PROGRESS',
      'title': 'Save More,\nStress Less',
      'subtitle':
          'Every day blocked is money saved and a step toward a healthier, freer life.',
      'icon': Icons.trending_up_rounded,
      'iconColor': const Color(0xFFFF6B6B),
      'highlights': ['Track your streak', 'See your savings', 'Build new habits'],
    },
  ];

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _entryFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entryController, curve: Curves.easeOut),
    );
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryController, curve: Curves.easeOut));
    _entryController.forward();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _entryController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    } else {
      _goToLogin();
    }
  }

  Future<void> _goToLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const AuthScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _entryFade,
        child: SlideTransition(
          position: _entrySlide,
          child: SafeArea(
            child: Column(
              children: [
                // ── Top bar ─────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: _dark,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.shield_rounded,
                                color: _accent, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'BetControl',
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _dark,
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: _goToLogin,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.grey.shade200, width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            'Skip',
                            style: GoogleFonts.poppins(
                              color: Colors.grey.shade500,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Pages ──────────────────────────────────────────────
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    onPageChanged: (index) =>
                        setState(() => _currentPage = index),
                    itemCount: _pages.length,
                    itemBuilder: (context, index) =>
                        _buildPage(_pages[index]),
                  ),
                ),

                // ── Bottom controls ────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
                  child: Column(
                    children: [
                      SmoothPageIndicator(
                        controller: _controller,
                        count: _pages.length,
                        effect: const ExpandingDotsEffect(
                          activeDotColor: _accent,
                          dotColor: Color(0xFFD1D5DB),
                          dotHeight: 7,
                          dotWidth: 7,
                          expansionFactor: 4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      GestureDetector(
                        onTap: _nextPage,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: double.infinity,
                          height: 58,
                          decoration: BoxDecoration(
                            color: _dark,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: _dark.withValues(alpha: 0.25),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _currentPage == _pages.length - 1
                                      ? 'Get Started'
                                      : 'Next',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: _accent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.arrow_forward_rounded,
                                    color: _dark,
                                    size: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPage(Map<String, dynamic> page) {
    final Color iconColor = page['iconColor'] as Color;
    final List<String> highlights = page['highlights'] as List<String>;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // ── Visual hero ──────────────────────────────────────────
          Expanded(
            flex: 5,
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer glow ring
                  ScaleTransition(
                    scale: _pulse,
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: iconColor.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                  // Mid ring
                  Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: iconColor.withValues(alpha: 0.10),
                    ),
                  ),
                  // Inner filled circle
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: iconColor.withValues(alpha: 0.15),
                    ),
                  ),
                  // Icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: iconColor.withValues(alpha: 0.18),
                    ),
                    child: Icon(
                      page['icon'] as IconData,
                      size: 38,
                      color: iconColor,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Text content ─────────────────────────────────────────
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tag pill
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    page['tag'] as String,
                    style: GoogleFonts.poppins(
                      color: iconColor == const Color(0xFF00D4AA)
                          ? iconColor
                          : iconColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // Title
                Text(
                  page['title'] as String,
                  style: GoogleFonts.poppins(
                    color: _dark,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),

                const SizedBox(height: 12),

                // Subtitle
                Text(
                  page['subtitle'] as String,
                  style: GoogleFonts.poppins(
                    color: Colors.grey.shade500,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 1.65,
                  ),
                ),

                const SizedBox(height: 20),

                // Highlight chips
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: highlights.map((h) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.grey.shade200, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: iconColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          h,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: _dark,
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}