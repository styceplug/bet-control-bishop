import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:betcontrol_main/services/block_services.dart';
import 'package:provider/provider.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen>
    with TickerProviderStateMixin {
  static const Color _dark = Color(0xFF1A1A2E);
  static const Color _accent = Color(0xFF00D4AA);
  static const Color _bg = Color(0xFFF8F9FF);

  final _noteController = TextEditingController();
  String? _selectedMood;
  bool _gamblingFree = true;
  bool _isSaving = false;
  bool _hasEntryToday = false;
  bool _isLoading = true;

  Map<String, dynamic>? _todayEntry;
  List<Map<String, dynamic>> _recentEntries = [];
  int _streakDays = 0;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;
  late AnimationController _loadingController;
  late Animation<double> _loadingPulse;
  late Animation<double> _loadingFloat;

  final List<Map<String, dynamic>> _moods = [
    {'emoji': '😤', 'label': 'Struggling', 'color': const Color(0xFFFF6B6B)},
    {'emoji': '😐', 'label': 'Neutral', 'color': const Color(0xFFFFB830)},
    {'emoji': '🙂', 'label': 'Okay', 'color': const Color(0xFF00D4AA)},
    {'emoji': '😊', 'label': 'Good', 'color': const Color(0xFF6C63FF)},
    {'emoji': '🌟', 'label': 'Great', 'color': const Color(0xFF00D4AA)},
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
    _loadingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _loadingPulse = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _loadingController, curve: Curves.easeInOut),
    );
    _loadingFloat = Tween<double>(begin: -6, end: 6).animate(
      CurvedAnimation(parent: _loadingController, curve: Curves.easeInOut),
    );
    _loadData();
  }

  @override
  void dispose() {
    _loadingController.dispose();
    _fadeController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String get _todayId {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final today = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('journal')
          .doc(_todayId)
          .get();

      final recent = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('journal')
          .orderBy('createdAt', descending: true)
          .limit(14)
          .get();

      if (mounted) {
        final entries = recent.docs
            .map((d) => {'id': d.id, ...d.data()})
            .toList();

        // Calculate streak
        int streak = 0;
        final now = DateTime.now();
        for (int i = 0; i < 365; i++) {
          final day = now.subtract(Duration(days: i));
          final id =
              '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
          final entry = entries.firstWhere(
            (e) => e['id'] == id,
            orElse: () => {},
          );
          if (entry.isEmpty) break;
          if (entry['gamblingFree'] == true) {
            streak++;
          } else {
            break;
          }
        }

        setState(() {
          _hasEntryToday = today.exists;
          _todayEntry = today.exists ? today.data() : null;
          _recentEntries = entries;
          _streakDays = streak;
          _isLoading = false;
        });
        _fadeController.forward();
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveEntry() async {
  final messenger = ScaffoldMessenger.of(context);

  if (_selectedMood == null) {
    messenger.showSnackBar(SnackBar(
      content: Text('Pick a mood first',
          style: GoogleFonts.poppins(color: Colors.white)),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
    return;
  }

  setState(() => _isSaving = true);

  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('journal')
        .doc(_todayId)
        .set({
      'mood': _selectedMood,
      'note': _noteController.text.trim(),
      'gamblingFree': _gamblingFree,
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      setState(() => _isSaving = false);
      _noteController.clear();
      _selectedMood = null;
      await _loadData();
      messenger.showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text('Check-in saved! Keep going 💪',
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
        ]),
        backgroundColor: _accent,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ));
    }
  } catch (_) {
    if (mounted) setState(() => _isSaving = false);
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: _isLoading
            ? _buildLoadingState()
            : FadeTransition(
                opacity: _fadeAnim,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 112),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Text('Progress',
                          style: GoogleFonts.poppins(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: _dark)),
                      Text('Your recovery journey',
                          style: GoogleFonts.poppins(
                              fontSize: 13, color: Colors.grey.shade500)),

                      const SizedBox(height: 24),

                      // Streak card
                      _buildStreakCard(),

                      const SizedBox(height: 20),

                      // Today's check-in
                      _hasEntryToday
                          ? _buildTodayDone()
                          : _buildCheckInForm(),

                      const SizedBox(height: 24),

                      // Recent entries
                      if (_recentEntries.isNotEmpty) ...[
                        Text('Recent Check-ins',
                            style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _dark,
                                letterSpacing: 0.3)),
                        const SizedBox(height: 12),
                        _buildRecentEntries(),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: AnimatedBuilder(
        animation: _loadingController,
        builder: (context, child) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.translate(
                offset: Offset(0, _loadingFloat.value),
                child: Transform.scale(
                  scale: _loadingPulse.value,
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.22),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _accent.withValues(alpha: 0.18),
                              width: 2,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.show_chart_rounded,
                          color: _accent,
                          size: 34,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Preparing your progress',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _dark,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (index) {
                  final phase = (_loadingController.value + (index * 0.22)) % 1;
                  final opacity = 0.35 + (phase * 0.65);
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: opacity),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStreakCard() {
  final blockService = context.watch<BlockService>();
  final isBlocking = blockService.isBlocking;
  final unlockTime = blockService.unlockTime;

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: _dark,
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
            color: _dark.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8)),
        BoxShadow(
            color: _accent.withValues(alpha: 0.1),
            blurRadius: 30,
            offset: const Offset(0, 4)),
      ],
    ),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('Gamble-free streak',
                        style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _accent)),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$_streakDays',
                          style: GoogleFonts.poppins(
                              fontSize: 52,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.0)),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                            _streakDays == 1 ? 'day' : 'days',
                            style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: Colors.white54)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _streakDays == 0
                        ? 'Start your streak with today\'s check-in'
                        : _streakDays < 7
                            ? 'Keep going — you\'re building momentum!'
                            : _streakDays < 30
                                ? 'Over a week strong. Incredible! 🔥'
                                : 'You\'re unstoppable. Month+ streak! 🏆',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.white38),
                  ),
                ],
              ),
            ),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  _streakDays == 0
                      ? '🎯'
                      : _streakDays < 7
                          ? '🔥'
                          : _streakDays < 30
                              ? '⚡'
                              : '🏆',
                  style: const TextStyle(fontSize: 28),
                ),
              ),
            ),
          ],
        ),

        // ── Blocking duration stat ──────────────────────────────────
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              Icon(
                isBlocking
                    ? Icons.shield_rounded
                    : Icons.shield_outlined,
                color: isBlocking ? _accent : Colors.white38,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: isBlocking
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Blocking active',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _accent,
                            ),
                          ),
                          Text(
                            blockService.timeRemainingText,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        'Blocking not active',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.white38,
                        ),
                      ),
              ),
              if (isBlocking && unlockTime != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Until ${_formatUnlockDate(unlockTime)}',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _accent,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

String _formatUnlockDate(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${dt.day} ${months[dt.month - 1]}';
}

  Widget _buildTodayDone() {
    final entry = _todayEntry!;
    final mood = entry['mood'] as String? ?? '';
    final moodData = _moods.firstWhere(
      (m) => m['label'] == mood,
      orElse: () => _moods[2],
    );
    final note = entry['note'] as String? ?? '';
    final gamblingFree = entry['gamblingFree'] as bool? ?? true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4)),
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
                  color: _accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.check_circle_rounded,
                    color: _accent, size: 18),
              ),
              const SizedBox(width: 10),
              Text("Today's check-in done ✓",
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _dark)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(moodData['emoji'] as String,
                  style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Feeling ${moodData['label']}',
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _dark)),
                  Text(
                    gamblingFree
                        ? '✅ Gamble-free today'
                        : '⚠️ Had a setback today',
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: gamblingFree
                            ? _accent
                            : Colors.orange.shade600),
                  ),
                ],
              ),
            ],
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(note,
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      height: 1.5)),
            ),
          ],
          const SizedBox(height: 12),
          Text('Come back tomorrow to keep your streak going!',
              style: GoogleFonts.poppins(
                  fontSize: 11, color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  Widget _buildCheckInForm() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Today's Check-in",
              style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _dark)),
          const SizedBox(height: 4),
          Text('A quick daily log helps track your recovery.',
              style: GoogleFonts.poppins(
                  fontSize: 12, color: Colors.grey.shade500)),

          const SizedBox(height: 20),

          // Mood selector
          Text('How are you feeling?',
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _dark)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: _moods.map((mood) {
              final isSelected = _selectedMood == mood['label'];
              return GestureDetector(
                onTap: () =>
                    setState(() => _selectedMood = mood['label'] as String),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 58,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (mood['color'] as Color).withValues(alpha: 0.12)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? mood['color'] as Color
                          : Colors.grey.shade200,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(mood['emoji'] as String,
                          style: const TextStyle(fontSize: 22)),
                      const SizedBox(height: 4),
                      Text(mood['label'] as String,
                          style: GoogleFonts.poppins(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? mood['color'] as Color
                                  : Colors.grey.shade400)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          // Gambling free toggle
          GestureDetector(
            onTap: () => setState(() => _gamblingFree = !_gamblingFree),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _gamblingFree
                    ? _accent.withValues(alpha: 0.08)
                    : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _gamblingFree
                      ? _accent.withValues(alpha: 0.3)
                      : Colors.orange.shade300,
                ),
              ),
              child: Row(
                children: [
                  Text(_gamblingFree ? '✅' : '⚠️',
                      style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _gamblingFree
                              ? 'Gamble-free today'
                              : 'Had a setback today',
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _gamblingFree
                                  ? _dark
                                  : Colors.orange.shade800),
                        ),
                        Text('Tap to change',
                            style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.grey.shade400)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Note field
          TextField(
            controller: _noteController,
            maxLines: 3,
            style: GoogleFonts.poppins(fontSize: 13, color: _dark),
            decoration: InputDecoration(
              hintText: 'Add a note... (optional)',
              hintStyle: GoogleFonts.poppins(
                  color: Colors.grey.shade400, fontSize: 13),
              filled: true,
              fillColor: _bg,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: _accent, width: 1.5)),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),

          const SizedBox(height: 16),

          // Save button
          GestureDetector(
            onTap: _isSaving ? null : _saveEntry,
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                color: _isSaving
                    ? _accent.withValues(alpha: 0.6)
                    : _accent,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: _accent.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 6)),
                ],
              ),
              child: Center(
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text('Save Check-in',
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _dark)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentEntries() {
    return Column(
      children: _recentEntries.take(7).map((entry) {
        final mood = entry['mood'] as String? ?? '';
        final moodData = _moods.firstWhere(
          (m) => m['label'] == mood,
          orElse: () => _moods[2],
        );
        final gamblingFree = entry['gamblingFree'] as bool? ?? true;
        final note = entry['note'] as String? ?? '';
        final id = entry['id'] as String? ?? '';

        // Parse date from id (YYYY-MM-DD)
        String dateLabel = id;
        try {
          final parts = id.split('-');
          final dt = DateTime(
              int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
          final now = DateTime.now();
          final diff = now.difference(dt).inDays;
          if (diff == 0) {
            dateLabel = 'Today';
          } else if (diff == 1) {
            dateLabel = 'Yesterday';
          } else {
            const months = [
              'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
              'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
            ];
            dateLabel = '${dt.day} ${months[dt.month - 1]}';
          }
        } catch (_) {}

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: Row(
            children: [
              Text(moodData['emoji'] as String,
                  style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(mood,
                            style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _dark)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: gamblingFree
                                ? _accent.withValues(alpha: 0.1)
                                : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            gamblingFree ? 'Gamble-free' : 'Setback',
                            style: GoogleFonts.poppins(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: gamblingFree
                                    ? _accent
                                    : Colors.orange.shade700),
                          ),
                        ),
                      ],
                    ),
                    if (note.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(note,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: Colors.grey.shade500)),
                    ],
                  ],
                ),
              ),
              Text(dateLabel,
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: Colors.grey.shade400)),
            ],
          ),
        );
      }).toList(),
    );
  }
}
