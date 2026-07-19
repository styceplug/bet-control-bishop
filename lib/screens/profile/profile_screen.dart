import 'dart:io';

import 'package:betcontrol_main/screens/auth/auth_screen.dart';
import 'package:betcontrol_main/screens/profile/manage_subscription_screen.dart';
import 'package:betcontrol_main/services/block_services.dart';
import 'package:betcontrol_main/services/user_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/connectivity_service.dart';
import '../../services/profile_image_service.dart';
import 'package:betcontrol_main/screens/profile/change_password_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color _dark = Color(0xFF1A1A2E);
  static const Color _accent = Color(0xFF00D4AA);
  static const Color _bg = Color(0xFFF8F9FF);
  static const String _websiteUrl = 'https://usebetcontrol.com/';
  static const String _privacyPolicyUrl =
      'https://betcontrol-privacy.netlify.app';

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _imageService = ProfileImageService();
  final _connectivityService = ConnectivityService();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingImage = false;

  Map<String, dynamic> _profileData = {};

  bool _editingName = false;
  bool _editingPhone = false;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  String? _selectedGender;
  String? _selectedGamblingType;
  String? _selectedGamblingDuration;
  String? _selectedTrigger;

  bool _editingGender = false;
  bool _editingGamblingType = false;
  bool _editingGamblingDuration = false;
  bool _editingTrigger = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _profileData = data;
          _nameController.text = data['fullName'] ?? '';
          _phoneController.text = data['phone'] ?? '';
          _selectedGender = data['gender'];
          _selectedGamblingType = data['gamblingType'];
          _selectedGamblingDuration = data['gamblingDuration'];
          _selectedTrigger = data['trigger'];
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleImageUpload() async {
    final hasInternet = await _connectivityService.hasInternetConnection();
    if (!mounted) return;
    if (!hasInternet) {
      _showSnack('No internet connection. Please try again.');
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            Text('Profile Photo',
                style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w700, color: _dark)),
            const SizedBox(height: 20),
            _sheetOption(
              icon: Icons.photo_library_rounded,
              label: 'Choose from gallery',
              onTap: () async {
                Navigator.pop(ctx);
                setState(() => _isUploadingImage = true);
                final url = await _imageService.pickAndUploadImage();
                if (url != null && mounted) {
                  setState(() => _profileData['profileImageUrl'] = url);
                  _showSnack('Profile photo updated', isError: false);
                } else if (mounted) {
                  _showSnack('Could not upload photo. Try again.');
                }
                if (mounted) setState(() => _isUploadingImage = false);
              },
            ),
            if (_profileData['profileImageUrl'] != null) ...[
              const SizedBox(height: 12),
              _sheetOption(
                icon: Icons.delete_outline_rounded,
                label: 'Remove photo',
                color: Colors.red.shade700,
                onTap: () async {
                  Navigator.pop(ctx);
                  setState(() => _isUploadingImage = true);
                  await _imageService.removeImage();
                  if (mounted) {
                    setState(() {
                      _profileData.remove('profileImageUrl');
                      _isUploadingImage = false;
                    });
                    _showSnack('Profile photo removed', isError: false);
                  }
                },
              ),
            ],
            const SizedBox(height: 12),
            _sheetOption(
              icon: Icons.close_rounded,
              label: 'Cancel',
              color: Colors.grey.shade500,
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final c = color ?? _dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: c, size: 20),
            const SizedBox(width: 12),
            Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w500, color: c)),
          ],
        ),
      ),
    );
  }

  Future<void> _saveField(String field, dynamic value) async {
    setState(() => _isSaving = true);
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;
      await _firestore.collection('users').doc(uid).update({field: value});
      setState(() => _profileData[field] = value);
      _showSnack('Updated successfully', isError: false);
    } catch (_) {
      _showSnack('Could not save. Try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  bool _isValidFullName(String name) {
    final trimmed = name.trim();
    if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(trimmed)) return false;
    final parts =
        trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    return parts.length >= 2 && parts.every((p) => p.length >= 2);
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

  void _showSnack(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: GoogleFonts.poppins(
              color: Colors.white, fontWeight: FontWeight.w500)),
      backgroundColor: isError ? Colors.red.shade700 : _accent,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  String _formatBlockExpiry(DateTime? dt) {
    if (dt == null) return 'the timer expires';
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
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  Future<void> _confirmSignOut() async {
    final blockService = context.read<BlockService>();
    if (blockService.isBlocking) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Cannot Sign Out',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700, color: _dark)),
          content: Text(
            'Protection is currently active until ${_formatBlockExpiry(blockService.unlockTime)}. '
            'End protection first (Blocker → End protection early) with your PIN, then sign out.',
            style:
                GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: _dark,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child:
                  Text('OK', style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Sign out?',
            style:
                GoogleFonts.poppins(fontWeight: FontWeight.w700, color: _dark)),
        content: Text('You will need to sign in again to access your account.',
            style:
                GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: Colors.grey.shade500)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Sign out',
                style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final hasInternet = await _connectivityService.hasInternetConnection();
      if (!mounted) return;
      if (!hasInternet) {
        _showSnack('No internet connection. Please try again.');
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_seen_onboarding', true);
      await UserService().clearProfileCache();
      if (Platform.isIOS) {
        try {
          await Purchases.logOut().timeout(const Duration(seconds: 5));
        } catch (_) {
          // Non-critical; Firebase sign-out should not be blocked by RevenueCat.
        }
      }
      await GoogleSignIn().signOut();
      await _auth.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
          (route) => false,
        );
      }
    }
  }

  // ── Shimmer helpers ───────────────────────────────────────────────────────
  Widget _shimmerBox(
      {required double width, required double height, required double radius}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _shimmerCircle(double size) {
    return Container(
      width: size,
      height: size,
      decoration:
          BoxDecoration(color: Colors.grey.shade300, shape: BoxShape.circle),
    );
  }

  Widget _shimmerField() {
    return Container(
      width: double.infinity,
      height: 68,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _shimmerBox(width: 80, height: 10, radius: 4),
          const SizedBox(height: 8),
          _shimmerBox(width: 160, height: 14, radius: 5),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 112),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _shimmerBox(width: 100, height: 26, radius: 8),
                const SizedBox(height: 6),
                _shimmerBox(width: 200, height: 14, radius: 6),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _shimmerCircle(72),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _shimmerBox(width: 140, height: 16, radius: 6),
                                const SizedBox(height: 8),
                                _shimmerBox(width: 180, height: 12, radius: 5),
                                const SizedBox(height: 6),
                                _shimmerBox(width: 100, height: 10, radius: 5),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                              child: _shimmerBox(
                                  width: double.infinity,
                                  height: 48,
                                  radius: 12)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _shimmerBox(
                                  width: double.infinity,
                                  height: 48,
                                  radius: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                _shimmerBox(width: 140, height: 13, radius: 6),
                const SizedBox(height: 12),
                _shimmerField(),
                const SizedBox(height: 12),
                _shimmerField(),
                const SizedBox(height: 12),
                _shimmerField(),
                const SizedBox(height: 28),
                _shimmerBox(width: 120, height: 13, radius: 6),
                const SizedBox(height: 12),
                _shimmerField(),
                const SizedBox(height: 12),
                _shimmerField(),
                const SizedBox(height: 28),
                _shimmerBox(width: 160, height: 13, radius: 6),
                const SizedBox(height: 12),
                _shimmerField(),
                const SizedBox(height: 12),
                _shimmerField(),
                const SizedBox(height: 12),
                _shimmerField(),
              ],
            ),
          ),
        ),
      );
    }

    final firstName =
        (_profileData['fullName'] ?? '').toString().split(' ').first;
    final email = _auth.currentUser?.email ?? '';
    final memberSince = _profileData['createdAt'] != null
        ? _formatDate((_profileData['createdAt'] as Timestamp).toDate())
        : 'N/A';
    final profileImageUrl = _profileData['profileImageUrl'] as String?;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          // 112px accounts for glass nav bar height + bottom padding
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 112),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Page header ───────────────────────────────────────────────
              Text('Profile',
                  style: GoogleFonts.poppins(
                      fontSize: 26, fontWeight: FontWeight.w800, color: _dark)),
              const SizedBox(height: 2),
              Text('Manage your account',
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: Colors.grey.shade500)),

              const SizedBox(height: 24),

              // ── Profile hero card ─────────────────────────────────────────
              _buildProfileHeroCard(
                  firstName, email, memberSince, profileImageUrl),

              const SizedBox(height: 28),

              // ── Personal Information ──────────────────────────────────────
              _sectionHeader(
                  Icons.person_outline_rounded, 'Personal Information'),
              const SizedBox(height: 12),

              _editableTextField(
                label: 'Full Name',
                value: _profileData['fullName'] ?? '',
                controller: _nameController,
                isEditing: _editingName,
                icon: Icons.badge_outlined,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]'))
                ],
                keyboardType: TextInputType.name,
                onEdit: () => setState(() => _editingName = true),
                onCancel: () {
                  _nameController.text = _profileData['fullName'] ?? '';
                  setState(() => _editingName = false);
                },
                onSave: () {
                  final name = _nameController.text.trim();
                  if (!_isValidFullName(name)) {
                    _showSnack('Enter your surname and first name only');
                    return;
                  }
                  _saveField('fullName', name);
                  setState(() => _editingName = false);
                },
              ),

              const SizedBox(height: 10),

              _editableTextField(
                label: 'Phone Number',
                value: _profileData['phone'] ?? '',
                controller: _phoneController,
                isEditing: _editingPhone,
                icon: Icons.phone_outlined,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s()]'))
                ],
                keyboardType: TextInputType.phone,
                onEdit: () => setState(() => _editingPhone = true),
                onCancel: () {
                  _phoneController.text = _profileData['phone'] ?? '';
                  setState(() => _editingPhone = false);
                },
                onSave: () {
                  if (!_isValidNigerianPhone(_phoneController.text)) {
                    _showSnack(
                        'Enter a valid Nigerian number (e.g. 08012345678)');
                    return;
                  }
                  _saveField('phone', _phoneController.text.trim());
                  setState(() => _editingPhone = false);
                },
              ),

              const SizedBox(height: 10),

              _editableSelectionField(
                label: 'Gender',
                value: _profileData['gender'] ?? '',
                isEditing: _editingGender,
                icon: Icons.person_pin_outlined,
                options: ['Male', 'Female', 'Prefer not to say'],
                selectedValue: _selectedGender,
                onEdit: () => setState(() => _editingGender = true),
                onCancel: () {
                  setState(() {
                    _selectedGender = _profileData['gender'];
                    _editingGender = false;
                  });
                },
                onOptionTap: (v) => setState(() => _selectedGender = v),
                onSave: () {
                  if (_selectedGender == null) {
                    _showSnack('Please select a gender');
                    return;
                  }
                  _saveField('gender', _selectedGender);
                  setState(() => _editingGender = false);
                },
              ),

              const SizedBox(height: 28),

              // ── Account Details ───────────────────────────────────────────
              _sectionHeader(Icons.info_outline_rounded, 'Account Details'),
              const SizedBox(height: 12),

              // Group read-only fields in a single card
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  children: [
                    _readOnlyFieldInCard(
                      label: 'Age Range',
                      value: _ageLabel(_profileData['age']),
                      icon: Icons.cake_outlined,
                      hasDivider: true,
                    ),
                    _readOnlyFieldInCard(
                      label: 'Email',
                      value: email,
                      icon: Icons.email_outlined,
                      note: 'Cannot be changed here',
                      hasDivider: false,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ── Subscription ────────────────────────────────────────────────
              _sectionHeader(Icons.workspace_premium_outlined, 'Subscription'),
              const SizedBox(height: 12),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4)),
                  ],
                ),
                child: _groupedInfoButton(
                  icon: Icons.workspace_premium_outlined,
                  label: 'Manage Subscription',
                  subtitle: 'Renew, cancel, or restore your Apple plan',
                  hasDivider: false,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ManageSubscriptionScreen()),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ── Gambling Background ───────────────────────────────────────
              _sectionHeader(Icons.psychology_outlined, 'Gambling Background'),
              const SizedBox(height: 4),
              Text('Private — helps us personalise your support.',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.grey.shade400)),
              const SizedBox(height: 12),

              _editableSelectionField(
                label: 'Primary Gambling Type',
                value: _profileData['gamblingType'] ?? '',
                isEditing: _editingGamblingType,
                icon: Icons.casino_outlined,
                options: [
                  'Sports Betting',
                  'Casino',
                  'Lottery',
                  'Multiple Types',
                  'Other'
                ],
                selectedValue: _selectedGamblingType,
                onEdit: () => setState(() => _editingGamblingType = true),
                onCancel: () {
                  setState(() {
                    _selectedGamblingType = _profileData['gamblingType'];
                    _editingGamblingType = false;
                  });
                },
                onOptionTap: (v) => setState(() => _selectedGamblingType = v),
                onSave: () {
                  if (_selectedGamblingType == null) return;
                  _saveField('gamblingType', _selectedGamblingType);
                  setState(() => _editingGamblingType = false);
                },
              ),

              const SizedBox(height: 10),

              _editableSelectionField(
                label: 'How long gambling?',
                value: _profileData['gamblingDuration'] ?? '',
                isEditing: _editingGamblingDuration,
                icon: Icons.history_rounded,
                options: [
                  'Less than 1 year',
                  '1 - 3 years',
                  '3 - 5 years',
                  '5+ years'
                ],
                selectedValue: _selectedGamblingDuration,
                onEdit: () => setState(() => _editingGamblingDuration = true),
                onCancel: () {
                  setState(() {
                    _selectedGamblingDuration =
                        _profileData['gamblingDuration'];
                    _editingGamblingDuration = false;
                  });
                },
                onOptionTap: (v) =>
                    setState(() => _selectedGamblingDuration = v),
                onSave: () {
                  if (_selectedGamblingDuration == null) return;
                  _saveField('gamblingDuration', _selectedGamblingDuration);
                  setState(() => _editingGamblingDuration = false);
                },
              ),

              const SizedBox(height: 10),

              _editableSelectionField(
                label: 'What brought you to BetControl?',
                value: _profileData['trigger'] ?? '',
                isEditing: _editingTrigger,
                icon: Icons.lightbulb_outline_rounded,
                options: [
                  'My own decision',
                  'Family pressure',
                  'Financial loss',
                  'Health concerns',
                  'Friend recommendation',
                  'Other',
                ],
                selectedValue: _selectedTrigger,
                onEdit: () => setState(() => _editingTrigger = true),
                onCancel: () {
                  setState(() {
                    _selectedTrigger = _profileData['trigger'];
                    _editingTrigger = false;
                  });
                },
                onOptionTap: (v) => setState(() => _selectedTrigger = v),
                onSave: () {
                  if (_selectedTrigger == null) return;
                  _saveField('trigger', _selectedTrigger);
                  setState(() => _editingTrigger = false);
                },
              ),

              const SizedBox(height: 28),

              // ── Support & Security (grouped card) ─────────────────────────
              _sectionHeader(Icons.help_outline_rounded, 'Support & Security'),
              const SizedBox(height: 12),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  children: [
                    _groupedInfoButton(
                      icon: Icons.mail_outline_rounded,
                      label: 'Contact Us',
                      subtitle: 'betcontrolhq@gmail.com',
                      hasDivider: true,
                      onTap: () async {
                        final uri = Uri.parse(
                            'mailto:betcontrolhq@gmail.com?subject=BetControl Support');
                        try {
                          await launchUrl(uri);
                        } catch (_) {
                          _showSnack('Could not open email app.');
                        }
                      },
                    ),
                    _groupedInfoButton(
                      icon: Icons.language_rounded,
                      label: 'Website',
                      subtitle: 'usebetcontrol.com',
                      hasDivider: true,
                      onTap: () async {
                        try {
                          await launchUrl(Uri.parse(_websiteUrl),
                              mode: LaunchMode.externalApplication);
                        } catch (_) {
                          _showSnack('Could not open website.');
                        }
                      },
                    ),
                    _groupedInfoButton(
                      icon: Icons.shield_outlined,
                      label: 'Privacy Policy',
                      subtitle: 'Read our privacy policy',
                      hasDivider: true,
                      onTap: () async {
                        try {
                          await launchUrl(Uri.parse(_privacyPolicyUrl),
                              mode: LaunchMode.externalApplication);
                        } catch (_) {
                          _showSnack('Could not open Privacy Policy.');
                        }
                      },
                    ),
                    _groupedInfoButton(
                      icon: Icons.lock_reset_rounded,
                      label: 'Change Password',
                      subtitle: 'Send a reset link to your email',
                      hasDivider: false,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ChangePasswordScreen()),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ── Sign Out ──────────────────────────────────────────────────
              GestureDetector(
                onTap: _confirmSignOut,
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.logout_rounded,
                            color: _dark, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Text('Sign Out',
                          style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _dark)),
                      const Spacer(),
                      Icon(Icons.arrow_forward_ios_rounded,
                          size: 14, color: Colors.grey.shade400),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── Version ───────────────────────────────────────────────────
              Center(
                child: Text(
                  'BetControl v1.0.0',
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: Colors.grey.shade400),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Profile hero card ─────────────────────────────────────────────────────
  Widget _buildProfileHeroCard(String firstName, String email,
      String memberSince, String? profileImageUrl) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: _dark.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: _accent.withValues(alpha: 0.1),
            blurRadius: 40,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // Gradient background
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1F2D45), _dark],
                ),
              ),
            ),

            // Decorative glow blob — top right
            Positioned(
              top: -30,
              right: -20,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accent.withValues(alpha: 0.1),
                ),
              ),
            ),

            // Decorative glow blob — bottom left
            Positioned(
              bottom: -20,
              left: -10,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accent.withValues(alpha: 0.06),
                ),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Avatar
                      GestureDetector(
                        onTap: _isUploadingImage ? null : _handleImageUpload,
                        child: Stack(
                          children: [
                            Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                color: _dark.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: _bg.withValues(alpha: 0.5),
                                    width: 2.5),
                              ),
                              child: ClipOval(
                                child: _isUploadingImage
                                    ? const Center(
                                        child: SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                              color: _accent, strokeWidth: 2),
                                        ),
                                      )
                                    : profileImageUrl != null
                                        ? Image.network(
                                            profileImageUrl,
                                            fit: BoxFit.cover,
                                            width: 76,
                                            height: 76,
                                            errorBuilder: (_, __, ___) =>
                                                _avatarFallback(firstName),
                                          )
                                        : _avatarFallback(firstName),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: _dark,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: _dark, width: 2),
                                ),
                                child: const Icon(Icons.camera_alt_rounded,
                                    size: 12, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 16),

                      // Name + email
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _profileData['fullName'] ?? '',
                              style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  height: 1.2),
                            ),
                            const SizedBox(height: 4),
                            Text(email,
                                style: GoogleFonts.poppins(
                                    fontSize: 12, color: Colors.white)),
                            const SizedBox(height: 2),
                            Text('Member since $memberSince',
                                style: GoogleFonts.poppins(
                                    fontSize: 11, color: Colors.white)),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Divider
                  Container(
                    height: 1,
                    color: Colors.black.withValues(alpha: 0.08),
                  ),

                  const SizedBox(height: 16),

                  // Stats row
                  Row(
                    children: [
                      _heroStat(
                        label: 'Archetype',
                        value: _profileData['gamblingType'] != null
                            ? _shortGamblingType(_profileData['gamblingType'])
                            : 'Not set',
                      ),
                      _heroStatDivider(),
                      _heroStat(
                        label: 'Duration',
                        value: _profileData['gamblingDuration'] != null
                            ? _shortDuration(_profileData['gamblingDuration'])
                            : 'Not set',
                      ),
                      _heroStatDivider(),
                      _heroStat(
                        label: 'Motivation',
                        value: _profileData['trigger'] != null
                            ? _shortTrigger(_profileData['trigger'])
                            : 'Not set',
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Change photo link
                  GestureDetector(
                    onTap: _isUploadingImage ? null : _handleImageUpload,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.camera_alt_outlined,
                            color: _dark, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          profileImageUrl != null
                              ? 'Change profile photo'
                              : 'Add profile photo',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: const Color.fromARGB(255, 253, 253, 253),
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                            decorationColor: _bg,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroStat({required String label, required String value}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 10, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Widget _heroStatDivider() {
    return Container(
      width: 1,
      height: 32,
      color: Colors.white.withValues(alpha: 0.1),
      margin: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  // ── Section header with icon ──────────────────────────────────────────────
  Widget _sectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: _accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Icon(icon, size: 15, color: _dark),
        const SizedBox(width: 6),
        Text(
          title,
          style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _dark,
              letterSpacing: 0.2),
        ),
      ],
    );
  }

  // ── Grouped card button (for Support & Security) ──────────────────────────
  Widget _groupedInfoButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool hasDivider,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: _accent, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _dark)),
                      const SizedBox(height: 1),
                      Text(subtitle,
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded,
                    size: 14, color: Colors.grey.shade300),
              ],
            ),
          ),
          if (hasDivider)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 1,
                color: Colors.grey.shade100,
              ),
            ),
        ],
      ),
    );
  }

  // ── Read-only field in grouped card ───────────────────────────────────────
  Widget _readOnlyFieldInCard({
    required String label,
    required String value,
    required IconData icon,
    String? note,
    required bool hasDivider,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.grey.shade400, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: Colors.grey.shade400,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(value.isNotEmpty ? value : '—',
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500)),
                    if (note != null)
                      Text(note,
                          style: GoogleFonts.poppins(
                              fontSize: 11, color: Colors.grey.shade400)),
                  ],
                ),
              ),
              Icon(Icons.lock_outline_rounded,
                  size: 14, color: Colors.grey.shade300),
            ],
          ),
        ),
        if (hasDivider)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(height: 1, color: Colors.grey.shade100),
          ),
      ],
    );
  }

  Widget _avatarFallback(String firstName) {
    return Container(
      color: _accent.withValues(alpha: 0.2),
      child: Center(
        child: firstName.isNotEmpty
            ? Text(
                firstName[0].toUpperCase(),
                style: GoogleFonts.poppins(
                    fontSize: 28, fontWeight: FontWeight.w800, color: _accent),
              )
            : const Icon(Icons.person_rounded, color: _accent, size: 36),
      ),
    );
  }

  Widget _editableTextField({
    required String label,
    required String value,
    required TextEditingController controller,
    required bool isEditing,
    required IconData icon,
    required VoidCallback onEdit,
    required VoidCallback onCancel,
    required VoidCallback onSave,
    List<TextInputFormatter>? inputFormatters,
    TextInputType? keyboardType,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isEditing ? Border.all(color: _accent, width: 1.5) : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: _accent),
              const SizedBox(width: 8),
              Text(label,
                  style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500)),
              const Spacer(),
              if (!isEditing)
                GestureDetector(
                  onTap: onEdit,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('Edit',
                        style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: _accent,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (!isEditing)
            Text(value.isNotEmpty ? value : '—',
                style: GoogleFonts.poppins(
                    fontSize: 14, color: _dark, fontWeight: FontWeight.w500))
          else ...[
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              style: GoogleFonts.poppins(fontSize: 14, color: _dark),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
                border: InputBorder.none,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onCancel,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12)),
                      child: Center(
                          child: Text('Cancel',
                              style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500))),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: _isSaving ? null : onSave,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                          color: _accent,
                          borderRadius: BorderRadius.circular(12)),
                      child: Center(
                        child: _isSaving
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : Text('Save',
                                style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: _dark,
                                    fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _editableSelectionField({
    required String label,
    required String value,
    required bool isEditing,
    required IconData icon,
    required List<String> options,
    required String? selectedValue,
    required VoidCallback onEdit,
    required VoidCallback onCancel,
    required void Function(String) onOptionTap,
    required VoidCallback onSave,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isEditing ? Border.all(color: _accent, width: 1.5) : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: _accent),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(label,
                      style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500))),
              if (!isEditing)
                GestureDetector(
                  onTap: onEdit,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text('Edit',
                        style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: _accent,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (!isEditing)
            Text(value.isNotEmpty ? value : '—',
                style: GoogleFonts.poppins(
                    fontSize: 14, color: _dark, fontWeight: FontWeight.w500))
          else ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options.map((opt) {
                final isSelected = selectedValue == opt;
                return GestureDetector(
                  onTap: () => onOptionTap(opt),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? _dark : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(opt,
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w400,
                            color:
                                isSelected ? _accent : Colors.grey.shade700)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onCancel,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12)),
                      child: Center(
                          child: Text('Cancel',
                              style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500))),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: _isSaving ? null : onSave,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                          color: _accent,
                          borderRadius: BorderRadius.circular(12)),
                      child: Center(
                        child: _isSaving
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : Text('Save',
                                style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: _dark,
                                    fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
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
    return '${months[dt.month - 1]} ${dt.year}';
  }

  String _ageLabel(dynamic age) {
    if (age == null) return '—';
    final a = int.tryParse(age.toString());
    if (a == null) return '—';
    const labels = {
      18: '18 - 24',
      25: '25 - 34',
      35: '35 - 44',
      45: '45 - 54',
      55: '55+'
    };
    return labels[a] ?? '$a+';
  }

  String _shortGamblingType(dynamic val) {
    if (val == null) return 'Not set';
    final s = val.toString();
    if (s == 'Sports Betting') return 'Sports';
    if (s == 'Multiple Types') return 'Multiple';
    return s;
  }

  String _shortDuration(dynamic val) {
    if (val == null) return 'Not set';
    final s = val.toString();
    if (s == 'Less than 1 year') return '< 1 year';
    if (s == '1 - 3 years') return '1–3 yrs';
    if (s == '3 - 5 years') return '3–5 yrs';
    if (s == '5+ years') return '5+ yrs';
    return s;
  }

  String _shortTrigger(dynamic val) {
    if (val == null) return 'Not set';
    final s = val.toString();
    if (s == 'My own decision') return 'Self';
    if (s == 'Family pressure') return 'Family';
    if (s == 'Financial loss') return 'Finance';
    if (s == 'Health concerns') return 'Health';
    if (s == 'Friend recommendation') return 'Friend';
    return s;
  }
}
