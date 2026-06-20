import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:betcontrol_main/screens/block/block_screen.dart';

class AssessmentScreen extends StatefulWidget {
  const AssessmentScreen({super.key});

  @override
  State<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends State<AssessmentScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final Map<int, int> _selectedAnswers = {};
  bool _isSubmitting = false;
  bool _showResults = false;
  int _totalScore = 0;

  static const Color _dark = Color(0xFF1A1A2E);
  static const Color _accent = Color(0xFF00D4AA);
  static const Color _bg = Color(0xFFF8F9FF);

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  final List<Map<String, dynamic>> _questions = [
    {
      'question': 'How often do you bet?',
      'subInterpretation':
          'Your betting frequency can significantly influence your habits.',
      'answers': ['Daily', 'Weekly', 'Occasionally', 'Rarely'],
      'scores': [3, 2, 1, 0],
    },
    {
      'question': 'How much do you spend per bet?',
      'subInterpretation':
          'Understanding your spending helps identify the scale of your betting habits.',
      'answers': [
        'High — more than ₦10,000',
        'Medium — ₦5,000 to ₦10,000',
        'Low — under ₦5,000',
        'I don\'t track my spending',
      ],
      'scores': [3, 2, 1, 2],
    },
    {
      'question': 'Do you ever bet more to try to win back losses?',
      'subInterpretation':
          'Chasing losses is one of the most common warning signs of problem gambling.',
      'answers': ['Always', 'Sometimes', 'Rarely', 'Never'],
      'scores': [3, 2, 1, 0],
    },
    {
      'question': 'How do you feel after losing a bet?',
      'subInterpretation':
          'Your emotional response to losing can reveal how gambling affects your wellbeing.',
      'answers': [
        'Frustrated and I want to keep betting',
        'Disappointed but I can stop',
        'I accept the loss and move on',
      ],
      'scores': [3, 1, 0],
    },
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onAnswerSelected(int answerIndex) {
    setState(() => _selectedAnswers[_currentPage] = answerIndex);
  }

  void _nextPage() {
    if (_selectedAnswers[_currentPage] == null) return;

    if (_currentPage < _questions.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPage++);
    } else {
      _submitAssessment();
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPage--);
    }
  }

  Future<void> _submitAssessment() async {
    setState(() => _isSubmitting = true);

    int score = 0;
    for (int i = 0; i < _questions.length; i++) {
      final answerIndex = _selectedAnswers[i] ?? 0;
      final scores = _questions[i]['scores'] as List<int>;
      score += scores[answerIndex];
    }

    if (mounted) {
      setState(() {
        _totalScore = score;
        _isSubmitting = false;
        _showResults = true;
      });
      _fadeController.reset();
      _fadeController.forward();
    }

    unawaited(_saveAssessmentInBackground(score));
  }

  Future<void> _saveAssessmentInBackground(int score) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('assessments')
          .add({
        'score': score,
        'takenAt': FieldValue.serverTimestamp(),
        'answers': _selectedAnswers.map((k, v) => MapEntry(k.toString(), v)),
      }).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Assessment results are intentionally available offline.
    }
  }

  String get _resultTitle {
    if (_totalScore <= 2) return 'Low Risk';
    if (_totalScore <= 5) return 'Moderate Risk';
    return 'High Risk';
  }

  String get _resultMessage {
    if (_totalScore <= 2) {
      return 'Your gambling habits appear to be under control. Keep making healthy choices and stay aware of your patterns.';
    }
    if (_totalScore <= 5) {
      return 'There are some signs that gambling may be affecting you. Consider setting limits and monitoring your habits more closely.';
    }
    return 'Your responses suggest gambling may be significantly impacting your life. We strongly recommend using the blocking feature and reaching out for support.';
  }

  Color get _resultColor {
    if (_totalScore <= 2) return Colors.green.shade600;
    if (_totalScore <= 5) return Colors.orange.shade700;
    return Colors.red.shade700;
  }

  Color get _resultBgColor {
    if (_totalScore <= 2) return Colors.green.shade50;
    if (_totalScore <= 5) return Colors.orange.shade50;
    return Colors.red.shade50;
  }

  IconData get _resultIcon {
    if (_totalScore <= 2) return Icons.check_circle_rounded;
    if (_totalScore <= 5) return Icons.warning_amber_rounded;
    return Icons.error_rounded;
  }

  @override
  Widget build(BuildContext context) {
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
        title: Text(
          'Self Assessment',
          style: GoogleFonts.poppins(
              fontSize: 17, fontWeight: FontWeight.w600, color: _dark),
        ),
        centerTitle: true,
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: _showResults ? _buildResults() : _buildQuestions(),
      ),
    );
  }

  Widget _buildQuestions() {
    return Column(
      children: [
        // Progress bar
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Question ${_currentPage + 1} of ${_questions.length}',
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500),
                  ),
                  Text(
                    '${((_currentPage + 1) / _questions.length * 100).round()}%',
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: _accent,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (_currentPage + 1) / _questions.length,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation<Color>(_accent),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),

        // Questions
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _questions.length,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemBuilder: (context, index) {
              final q = _questions[index];
              final answers = q['answers'] as List<String>;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Question
                    Text(
                      q['question'],
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _dark,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      q['subInterpretation'],
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                          height: 1.5),
                    ),
                    const SizedBox(height: 28),

                    // Answer options
                    ...List.generate(answers.length, (answerIndex) {
                      final isSelected =
                          _selectedAnswers[index] == answerIndex;
                      return GestureDetector(
                        onTap: () => _onAnswerSelected(answerIndex),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 16),
                          decoration: BoxDecoration(
                            color: isSelected ? _dark : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? _dark
                                  : Colors.grey.shade200,
                              width: 1.5,
                            ),
                            boxShadow: isSelected
                                ? []
                                : [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.04),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                          ),
                          child: Row(
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected
                                      ? _accent
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: isSelected
                                        ? _accent
                                        : Colors.grey.shade300,
                                    width: 2,
                                  ),
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check_rounded,
                                        size: 14, color: _dark)
                                    : null,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  answers[answerIndex],
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: isSelected
                                        ? Colors.white
                                        : _dark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ),

        // Navigation buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Row(
            children: [
              if (_currentPage > 0) ...[
                GestureDetector(
                  onTap: _prevPage,
                  child: Container(
                    height: 56,
                    width: 56,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: Colors.grey.shade200, width: 1.5),
                    ),
                    child: Icon(Icons.arrow_back_ios_new_rounded,
                        size: 16, color: Colors.grey.shade600),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: GestureDetector(
                  onTap: _selectedAnswers[_currentPage] == null
                      ? null
                      : _nextPage,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 56,
                    decoration: BoxDecoration(
                      color: _selectedAnswers[_currentPage] == null
                          ? Colors.grey.shade300
                          : _isSubmitting
                              ? _accent.withValues(alpha: 0.6)
                              : _accent,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: _selectedAnswers[_currentPage] != null
                          ? [
                              BoxShadow(
                                color: _accent.withValues(alpha: 0.35),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ]
                          : [],
                    ),
                    child: Center(
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5))
                          : Text(
                              _currentPage == _questions.length - 1
                                  ? 'See Results'
                                  : 'Next',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: _selectedAnswers[_currentPage] == null
                                    ? Colors.grey.shade500
                                    : _dark,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResults() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),

          // Result badge
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: _resultBgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(_resultIcon, color: _resultColor, size: 52),
          ),

          const SizedBox(height: 24),

          Text(
            'Assessment Complete',
            style: GoogleFonts.poppins(
                fontSize: 22, fontWeight: FontWeight.w800, color: _dark),
          ),
          const SizedBox(height: 8),
          Text(
            'Based on your answers',
            style: GoogleFonts.poppins(
                fontSize: 14, color: Colors.grey.shade500),
          ),

          const SizedBox(height: 28),

          // Score card
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
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: _resultBgColor,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    _resultTitle,
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _resultColor,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _resultMessage,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Score breakdown
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your answers',
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _dark),
                ),
                const SizedBox(height: 16),
                ...List.generate(_questions.length, (i) {
                  final q = _questions[i];
                  final answerIndex = _selectedAnswers[i] ?? 0;
                  final answers = q['answers'] as List<String>;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          q['question'],
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          answers[answerIndex],
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: _dark,
                              fontWeight: FontWeight.w600),
                        ),
                        if (i < _questions.length - 1) ...[
                          const SizedBox(height: 14),
                          Divider(color: Colors.grey.shade100, height: 1),
                        ],
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // Done / Activate Protection button
GestureDetector(
  onTap: () {
    if (_totalScore > 5) {
      // High risk — go to block screen
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BlockScreen()),
      );
    } else {
      Navigator.pop(context);
    }
  },
  child: Container(
    width: double.infinity,
    height: 56,
    decoration: BoxDecoration(
      color: _totalScore > 5 ? _accent : _dark,
      borderRadius: BorderRadius.circular(16),
      boxShadow: _totalScore > 5
          ? [
              BoxShadow(
                color: _accent.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ]
          : [],
    ),
    child: Center(
      child: Text(
        _totalScore > 5
            ? '🛡️  Activate Protection Now'
            : 'Done',
        style: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: _totalScore > 5 ? _dark : Colors.white,
        ),
      ),
    ),
  ),
),

          const SizedBox(height: 16),

          // Retake
          GestureDetector(
            onTap: () {
              setState(() {
                _showResults = false;
                _currentPage = 0;
                _selectedAnswers.clear();
              });
              _pageController.jumpToPage(0);
              _fadeController.reset();
              _fadeController.forward();
            },
            child: Text(
              'Retake assessment',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: Colors.grey.shade500,
                decoration: TextDecoration.underline,
                decorationColor: Colors.grey.shade400,
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
