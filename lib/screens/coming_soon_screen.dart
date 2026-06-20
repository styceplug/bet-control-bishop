import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ComingSoonScreen extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final List<String> plannedFeatures;

  const ComingSoonScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.plannedFeatures,
  });

  @override
  State<ComingSoonScreen> createState() => _ComingSoonScreenState();
}

class _ComingSoonScreenState extends State<ComingSoonScreen>
    with TickerProviderStateMixin {
  static const Color _dark = Color(0xFF1A1A2E);
  static const Color _accent = Color(0xFF00D4AA);
  static const Color _bg = Color(0xFFF8F9FF);

  late AnimationController _floatController;
  late AnimationController _fadeController;
  late Animation<double> _floatAnim;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _floatAnim = Tween<double>(begin: 0, end: 10).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );

    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _slideAnim =
        Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _floatController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Column(
              children: [
                // ── App bar ─────────────────────────────────────────────
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.arrow_back_ios_new_rounded,
                              size: 16, color: _dark),
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 8, 28, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Illustration ───────────────────────────────
                        Center(
                          child: AnimatedBuilder(
                            animation: _floatAnim,
                            builder: (_, __) => Transform.translate(
                              offset: Offset(0, -_floatAnim.value),
                              child: _buildIconIllustration(),
                            ),
                          ),
                        ),

                        const SizedBox(height: 36),

                        // ── Coming Soon badge ──────────────────────────
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: widget.iconColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color:
                                    widget.iconColor.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: widget.iconColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  'Coming Soon',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: widget.iconColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // ── Title ──────────────────────────────────────
                        Center(
                          child: Text(
                            widget.title,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: _dark,
                              height: 1.2,
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // ── Subtitle ───────────────────────────────────
                        Center(
                          child: Text(
                            widget.subtitle,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Colors.grey.shade500,
                              height: 1.6,
                            ),
                          ),
                        ),

                        const SizedBox(height: 36),

                        // ── What's planned ─────────────────────────────
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: widget.iconColor
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(Icons.checklist_rounded,
                                        color: widget.iconColor, size: 16),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    "What's planned",
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _dark,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              ...widget.plannedFeatures
                                  .asMap()
                                  .entries
                                  .map((entry) {
                                final index = entry.key;
                                final feature = entry.value;
                                return Padding(
                                  padding: EdgeInsets.only(
                                  bottom: (index < widget.plannedFeatures.length - 1) ? 12.0 : 0.0),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 22,
                                        height: 22,
                                        margin:
                                            const EdgeInsets.only(top: 1),
                                        decoration: BoxDecoration(
                                          color: widget.iconColor
                                              .withValues(alpha: 0.12),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(Icons.check_rounded,
                                            size: 13,
                                            color: widget.iconColor),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          feature,
                                          style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            color: Colors.grey.shade700,
                                            height: 1.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // ── Bottom note ────────────────────────────────
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: _accent.withValues(alpha: 0.2),
                                width: 1),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.construction_rounded,
                                  color: _accent, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'We are actively building this. Focus on your recovery while we work.',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: const Color(0xFF007A63),
                                    height: 1.5,
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconIllustration() {
    final color = widget.iconColor;

    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outermost ring — faint
          Container(
            width: 210,
            height: 210,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.05),
            ),
          ),

          // Middle ring
          Container(
            width: 166,
            height: 166,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.09),
            ),
          ),

          // Inner circle
          Container(
            width: 116,
            height: 116,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
            ),
          ),

          // Core icon container
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(widget.icon, color: Colors.white, size: 36),
          ),

          // Floating accent dot — top right
          Positioned(
            top: 22,
            right: 26,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _dark,
                boxShadow: [
                  BoxShadow(
                    color: _dark.withValues(alpha: 0.2),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ),

          // Floating accent dot — bottom left
          Positioned(
            bottom: 28,
            left: 30,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.5),
              ),
            ),
          ),

          // Floating accent dot — top left
          Positioned(
            top: 40,
            left: 20,
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

          // Floating accent dot — bottom right
          Positioned(
            bottom: 36,
            right: 20,
            child: Transform.rotate(
              angle: math.pi / 6,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _dark.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}