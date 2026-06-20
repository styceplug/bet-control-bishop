import 'package:betcontrol_main/screens/home_screen.dart';
import 'package:betcontrol_main/services/analytics_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/connectivity_service.dart';
import '../../services/user_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isLoading = false;

  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();

  int? _age;
  String? _gender;
  String? _gamblingType;
  String? _gamblingDuration;
  String? _trigger;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  static const Color _bgColor = Color(0xFFF8F9FF);
  static const Color _accentColor = Color(0xFF00D4AA);
  static const Color _darkColor = Color(0xFF1A1A2E);

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _connectivityService = ConnectivityService();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        duration: const Duration(milliseconds: 500), vsync: this);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _pageController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message,
          style: GoogleFonts.poppins(
              color: Colors.white, fontWeight: FontWeight.w500)),
      backgroundColor: isError ? Colors.red.shade700 : _accentColor,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 4),
    ));
  }

  bool _isValidFullName(String name) {
    final trimmed = name.trim();
    if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(trimmed)) return false;
    final parts =
        trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length < 2) return false;
    for (final part in parts) {
      if (part.length < 2) return false;
    }
    return true;
  }

  bool _isValidNigerianPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10 && digits.length != 11) return false;
    if (digits.length == 11) {
      if (!digits.startsWith('0')) return false;
      return _hasValidPrefix(digits.substring(1));
    }
    return _hasValidPrefix(digits);
  }

  bool _hasValidPrefix(String tenDigits) {
    final validPrefixes = ['70', '80', '81', '90', '91'];
    return validPrefixes.any((p) => tenDigits.startsWith(p));
  }

  void _nextPage() {
    if (_currentPage == 0) {
      final name = _fullNameController.text.trim();
      if (name.isEmpty) {
        _showSnackBar('Please enter your full name');
        return;
      }
      if (!_isValidFullName(name)) {
        _showSnackBar(
            'Please enter your surname and first name (letters only)');
        return;
      }
      if (_age == null) {
        _showSnackBar('Please select your age range');
        return;
      }
      if (_gender == null) {
        _showSnackBar('Please select your gender');
        return;
      }
      final phone = _phoneController.text.trim();
      if (phone.isEmpty) {
        _showSnackBar('Please enter your phone number');
        return;
      }
      if (!_isValidNigerianPhone(phone)) {
        _showSnackBar(
            'Enter a valid Nigerian number (e.g. 08012345678 or 8012345678)');
        return;
      }
    }

    if (_currentPage == 1) {
      if (_gamblingType == null) {
        _showSnackBar('Please select your primary gambling type');
        return;
      }
      if (_gamblingDuration == null) {
        _showSnackBar('Please select how long you have been gambling');
        return;
      }
      if (_trigger == null) {
        _showSnackBar('Please select what brought you here');
        return;
      }
    }

    if (_currentPage < 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPage++);
    } else {
      _saveProfile();
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPage--);
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);
    try {
      final hasInternet = await _connectivityService.hasInternetConnection();
      if (!mounted) return;
      if (!hasInternet) {
        _showSnackBar('No internet connection. Please try again.');
        setState(() => _isLoading = false);
        return;
      }

      final uid = _auth.currentUser?.uid;
      if (uid == null) {
        _showSnackBar('Session expired. Please sign in again.');
        setState(() => _isLoading = false);
        return;
      }

      await _firestore.collection('users').doc(uid).set({
        'fullName': _fullNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'age': _age,
        'gender': _gender,
        'gamblingType': _gamblingType,
        'gamblingDuration': _gamblingDuration,
        'trigger': _trigger,
        'email': _auth.currentUser?.email ?? '',
      }, SetOptions(merge: true));

      await UserService().markProfileComplete();

// ── Pre-warm the home screen cache ────────────────────────────────────
// Save the name immediately so the home screen greeting appears
// instantly on first open without waiting for a Firestore call.
final prefs = await SharedPreferences.getInstance();
await prefs.setString(
  'cached_first_name',
  _fullNameController.text.trim().split(' ').first,
);

// ── Analytics ─────────────────────────────────────────────────────────
// Fires when the user finishes the onboarding questionnaire.
// This tells us how many installs actually convert to completed profiles
// — a key funnel metric between sign-up and first block activation.
await AnalyticsService.logProfileCompleted();

if (!mounted) return;
Navigator.of(context).pushAndRemoveUntil(
  MaterialPageRoute(builder: (_) => const HomeScreen()),
  (route) => false,
);
    } catch (e) {
      if (mounted) {
        _showSnackBar('Something went wrong. Please try again.');
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        if (_currentPage > 0)
                          GestureDetector(
                            onTap: _isLoading ? null : _prevPage,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  size: 16,
                                  color: _darkColor),
                            ),
                          )
                        else
                          const SizedBox(width: 40),
                        const Spacer(),
                        Text(
                          'Step ${_currentPage + 1} of 2',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: List.generate(2, (index) {
                        return Expanded(
                          child: Container(
                            margin:
                                EdgeInsets.only(right: index < 1 ? 6 : 0),
                            height: 6,
                            decoration: BoxDecoration(
                              color: index <= _currentPage
                                  ? _accentColor
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildPage1(),
                    _buildPage2(),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: GestureDetector(
                  onTap: _isLoading ? null : _nextPage,
                  child: Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _isLoading
                          ? _accentColor.withValues(alpha: 0.6)
                          : _accentColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: _accentColor.withValues(alpha: 0.35),
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
                          : Text(
                              _currentPage == 1
                                  ? 'Complete Profile'
                                  : 'Continue',
                              style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: _darkColor)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPage1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tell us about\nyourself 👋',
              style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: _darkColor,
                  height: 1.2)),
          const SizedBox(height: 6),
          Text('This helps us personalize your experience',
              style: GoogleFonts.poppins(
                  fontSize: 14, color: Colors.grey.shade500)),
          const SizedBox(height: 28),

          _sectionLabel('Full Name'),
          const SizedBox(height: 8),
          TextField(
            controller: _fullNameController,
            enabled: !_isLoading,
            keyboardType: TextInputType.name,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
            ],
            style: GoogleFonts.poppins(fontSize: 14, color: _darkColor),
            decoration: _inputDecoration(
              hint: 'e.g. John Doe',
              icon: Icons.person_outline_rounded,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Enter your surname and first name',
            style: GoogleFonts.poppins(
                fontSize: 11, color: Colors.grey.shade400),
          ),

          const SizedBox(height: 24),

          _sectionLabel('Phone Number'),
          const SizedBox(height: 8),
          TextField(
            controller: _phoneController,
            enabled: !_isLoading,
            keyboardType: TextInputType.phone,
            maxLength: 11,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: GoogleFonts.poppins(fontSize: 14, color: _darkColor),
            decoration: _inputDecoration(
              hint: 'e.g. 08012345678',
              icon: Icons.phone_outlined,
            ).copyWith(counterText: ''),
          ),
          const SizedBox(height: 6),
          Text(
            'Enter phone number',
            style: GoogleFonts.poppins(
                fontSize: 11, color: Colors.grey.shade400),
          ),

          const SizedBox(height: 24),

          _sectionLabel('Age Range'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [18, 25, 35, 45, 55].asMap().entries.map((entry) {
              final index = entry.key;
              final age = entry.value;
              final nextAge =
                  index < 4 ? [25, 35, 45, 55, 60][index] : null;
              final label =
                  nextAge != null ? '$age - ${nextAge - 1}' : '$age+';
              final isSelected = _age == age;
              return GestureDetector(
                onTap:
                    _isLoading ? null : () => setState(() => _age = age),
                child: _chipWidget(label, isSelected),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          _sectionLabel('Gender'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: ['Male', 'Female', 'Prefer not to say'].map((g) {
              final isSelected = _gender == g;
              return GestureDetector(
                onTap: _isLoading
                    ? null
                    : () => setState(() => _gender = g),
                child: _chipWidget(g, isSelected),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildPage2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your gambling\nbackground 🎯',
              style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: _darkColor,
                  height: 1.2)),
          const SizedBox(height: 6),
          Text('This stays private and helps us support you better',
              style: GoogleFonts.poppins(
                  fontSize: 14, color: Colors.grey.shade500)),
          const SizedBox(height: 28),

          _sectionLabel('Primary Gambling Type'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              'Sports Betting',
              'Casino',
              'Lottery',
              'Multiple Types',
              'Other',
            ].map((type) {
              final isSelected = _gamblingType == type;
              return GestureDetector(
                onTap: _isLoading
                    ? null
                    : () => setState(() => _gamblingType = type),
                child: _chipWidget(type, isSelected),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          _sectionLabel('How long have you been gambling?'),
          const SizedBox(height: 12),
          Column(
            children: [
              'Less than 1 year',
              '1 - 3 years',
              '3 - 5 years',
              '5+ years',
            ].map((duration) {
              final isSelected = _gamblingDuration == duration;
              return GestureDetector(
                onTap: _isLoading
                    ? null
                    : () => setState(() => _gamblingDuration = duration),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
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
                        ? []
                        : [
                            BoxShadow(
                              color:
                                  Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: isSelected
                            ? _accentColor
                            : Colors.grey.shade400,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        duration,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color:
                              isSelected ? Colors.white : _darkColor,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          _sectionLabel('What brought you to BetControl?'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              'My own decision',
              'Family pressure',
              'Financial loss',
              'Health concerns',
              'Friend recommendation',
              'Other',
            ].map((t) {
              final isSelected = _trigger == t;
              return GestureDetector(
                onTap: _isLoading
                    ? null
                    : () => setState(() => _trigger = t),
                child: _chipWidget(t, isSelected),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: _darkColor,
      ),
    );
  }

  Widget _chipWidget(String label, bool isSelected) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isSelected ? _darkColor : Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: isSelected ? _darkColor : Colors.grey.shade200,
          width: 1.5,
        ),
        boxShadow: isSelected
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          color: isSelected ? _accentColor : Colors.grey.shade600,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle:
          GoogleFonts.poppins(color: Colors.grey.shade300, fontSize: 14),
      prefixIcon: Icon(icon, color: _accentColor, size: 20),
      filled: true,
      fillColor: _isLoading ? Colors.grey.shade100 : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _accentColor, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}