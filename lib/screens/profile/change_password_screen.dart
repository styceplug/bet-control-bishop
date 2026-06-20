import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _auth = FirebaseAuth.instance;
  bool _isSending = false;
  bool _sent = false;

  static const Color _dark = Color(0xFF1A1A2E);
  static const Color _accent = Color(0xFF00D4AA);
  static const Color _bg = Color(0xFFF8F9FF);

  Future<void> _sendResetEmail() async {
    final email = _auth.currentUser?.email;
    if (email == null) return;

    setState(() => _isSending = true);
    try {
      await _auth.sendPasswordResetEmail(email: email);
      if (mounted) setState(() => _sent = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not send reset email. Please try again.',
              style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = _auth.currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
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
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 16, color: _dark),
          ),
        ),
        title: Text('Security',
            style: GoogleFonts.poppins(
                fontSize: 17, fontWeight: FontWeight.w600, color: _dark)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),

            // Icon
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(Icons.lock_reset_rounded, color: _accent, size: 40),
              ),
            ),

            const SizedBox(height: 24),

            Center(
              child: Text(
                'Change Password',
                style: GoogleFonts.poppins(
                    fontSize: 22, fontWeight: FontWeight.w800, color: _dark),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'We will send a password reset link to your email address.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: Colors.grey.shade500, height: 1.6),
              ),
            ),

            const SizedBox(height: 32),

            // Email display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.email_outlined, color: _accent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(email,
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: _dark)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            if (_sent) ...[
              // Success state
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: Colors.green.shade300, width: 1.5),
                ),
                child: Column(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: Colors.green.shade600, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      'Reset link sent!',
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.green.shade700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Check your email inbox and follow the link to reset your password. Check your spam folder if you don\'t see it.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: Colors.green.shade600,
                          height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    color: _dark,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text('Done',
                        style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ),
              ),
            ] else ...[
              // Send button
              GestureDetector(
                onTap: _isSending ? null : _sendResetEmail,
                child: Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    color: _isSending
                        ? _accent.withValues(alpha: 0.6)
                        : _accent,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: _accent.withValues(alpha: 0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 8)),
                    ],
                  ),
                  child: Center(
                    child: _isSending
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : Text('Send Reset Link',
                            style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: _dark)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'The link will be sent to $email',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.grey.shade400),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}