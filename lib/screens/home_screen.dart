import 'package:betcontrol_main/screens/block/block_screen.dart';
import 'package:betcontrol_main/screens/assessment/assessment_screen.dart';
import 'package:betcontrol_main/screens/coming_soon_screen.dart';
import 'package:betcontrol_main/screens/profile/profile_screen.dart';
import 'package:betcontrol_main/screens/progress_screen.dart';
import 'package:betcontrol_main/services/block_services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const Color _bg = Color(0xFFF8F9FF);

  @override
  Widget build(BuildContext context) {
    final screens = [
      const _HomeTab(),
      const ProgressScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: _bg,
      body: screens[_selectedIndex],
      bottomNavigationBar: _buildNav(),
    );
  }

  Widget _buildNav() {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      height: 58 + bottomInset,
      decoration: const BoxDecoration(
        color: Color(0xFFFAFAFA),
        border: Border(
          top: BorderSide(
            color: Color(0xFFEEEEEE),
            width: 1.0,
          ),
        ),
      ),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          children: [
            SizedBox(
              height: 58,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _navItem(
                    index: 0,
                    label: 'Home',
                    iconBuilder: (isSelected) => Image.asset(
                      'assets/icons/house2.png',
                      width: 20,
                      height: 20,
                      color: isSelected
                          ? const Color(0xFF1A1A2E)
                          : const Color(0xFFB0B0B8),
                      colorBlendMode: BlendMode.srcIn,
                    ),
                  ),
                  _navItem(
                    index: 1,
                    label: 'Progress',
                    iconBuilder: (isSelected) => Icon(
                      CupertinoIcons.chart_bar,
                      size: 20,
                      color: isSelected
                          ? const Color(0xFF1A1A2E)
                          : const Color(0xFFB0B0B8),
                    ),
                  ),
                  _navItem(
                    index: 2,
                    label: 'Profile',
                    iconBuilder: (isSelected) => Icon(
                      CupertinoIcons.person,
                      size: 20,
                      color: isSelected
                          ? const Color(0xFF1A1A2E)
                          : const Color(0xFFB0B0B8),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: bottomInset),
          ],
        ),
      ),
    );
  }

  Widget _navItem({
    required int index,
    required String label,
    required Widget Function(bool isSelected) iconBuilder,
  }) {
    final isSelected = _selectedIndex == index;

    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 80,
        height: 58,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              scale: isSelected ? 1.08 : 1.0,
              child: iconBuilder(isSelected),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w400,
                color: isSelected
                    ? const Color(0xFF1A1A2E)
                    : const Color(0xFFB0B0B8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _HomeTab extends StatefulWidget {
  const _HomeTab();

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> with TickerProviderStateMixin {
  String _firstName = '';
  String? _profileImageUrl;
  bool _isLoadingUser = true;

  late AnimationController _pageController;
  late Animation<double> _pageFade;
  late Animation<Offset> _pageSlide;

  late AnimationController _shieldController;
  late Animation<double> _shieldScale;

  static const Color _dark = Color(0xFF1A1A2E);
  static const Color _accent = Color(0xFF00D4AA);

  final List<String> _tips = [
    'Every day without gambling is a victory worth celebrating.',
    'Your finances are recovering. Keep the streak going.',
    'Urges pass in minutes. Ride it out — you are stronger than you think.',
    'The money you save today compounds into freedom tomorrow.',
    'You chose BetControl because you want better. That decision matters.',
    'One day at a time. That is all it takes.',
    'Talk to someone you trust today. Connection beats temptation.',
    'Your brain is rewiring itself every day you stay away.',
    'Replace the habit — exercise, reading, a walk. Anything but gambling.',
    'The house always wins. You win by not playing.',
    'Financial freedom starts with a single decision. You already made it.',
    'Celebrate small wins. Every hour counts.',
    'You are not your past choices. Today is a new page.',
    'The strongest person in the room is the one who walks away.',
    'Progress is not always visible but it is always happening.',
    'Boredom is not a reason to gamble. Find your thing.',
    'Your future self is counting on the decisions you make right now.',
    'Saying no to gambling is saying yes to your family.',
    'Discipline today means options tomorrow.',
    'You downloaded BetControl for a reason. Remember that reason.',
    'Check in with yourself. How are you feeling right now?',
    'It gets easier. Not immediately, but it does.',
    'Your bank account is not a scoreboard.',
    'Every naira saved is a naira working for you.',
    'The urge will pass. It always does.',
    'You are breaking a cycle. That takes real courage.',
    'Focus on what you are building, not what you are avoiding.',
    'Small consistent actions create massive change over time.',
    'You deserve peace more than you deserve a win.',
    'Today is a good day to stay in control.',
  ];

  String get _todaysTip {
    final dayOfYear =
        DateTime.now().difference(DateTime(DateTime.now().year, 1, 1)).inDays;
    return _tips[dayOfYear % _tips.length];
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  String get _greetingEmoji {
    final hour = DateTime.now().hour;
    if (hour < 12) return '☀️';
    if (hour < 17) return '🌤️';
    return '🌙';
  }

  @override
  void initState() {
    super.initState();

    _pageController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _pageFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _pageController, curve: Curves.easeOut));
    _pageSlide =
        Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
            .animate(CurvedAnimation(
                parent: _pageController, curve: Curves.easeOut));
    _pageController.forward();

    _shieldController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _shieldScale = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _shieldController, curve: Curves.easeInOut),
    );

    _loadData();
  }

  @override
  void dispose() {
    _shieldController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
  // ── Step 1: show cached data instantly ──────────────────────────
  // Read from local storage first so the greeting and avatar appear
  // immediately without waiting for any network call.
  final prefs = await SharedPreferences.getInstance();
  final cachedName = prefs.getString('cached_first_name') ?? '';
  final cachedImage = prefs.getString('cached_profile_image_url');
  if (mounted && cachedName.isNotEmpty) {
    setState(() {
      _firstName = cachedName;
      _profileImageUrl = cachedImage;
      _isLoadingUser = false;
    });
  }

  // ── Step 2: refresh from Firestore in the background ────────────
  // Silently updates the UI and cache if anything changed since
  // last open — user never sees a loading state for this.
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (doc.exists && mounted) {
      final data = doc.data()!;
      final freshName =
          (data['fullName'] ?? '').toString().split(' ').first;
      final freshImage = data['profileImageUrl'] as String?;

      // Save to cache for next open
      await prefs.setString('cached_first_name', freshName);
      if (freshImage != null) {
        await prefs.setString('cached_profile_image_url', freshImage);
      } else {
        await prefs.remove('cached_profile_image_url');
      }

      if (mounted) {
        setState(() {
          _firstName = freshName;
          _profileImageUrl = freshImage;
          _isLoadingUser = false;
        });
      }
    }
  } catch (_) {
    if (mounted) setState(() => _isLoadingUser = false);
  }
}

  String _formatExpiry(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  void _openComingSoon({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required List<String> features,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ComingSoonScreen(
          title: title,
          subtitle: subtitle,
          icon: icon,
          iconColor: iconColor,
          plannedFeatures: features,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blockService = context.watch<BlockService>();
    final isBlocking = blockService.isBlocking;

    return SafeArea(
      bottom: false,
      child: FadeTransition(
        opacity: _pageFade,
        child: SlideTransition(
          position: _pageSlide,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Greeting row ──────────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_greeting,
                              style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Colors.grey.shade500)),
                          if (!_isLoadingUser && _firstName.isNotEmpty)
                            Text(
                              '$_firstName! $_greetingEmoji',
                              style: GoogleFonts.poppins(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: _dark,
                                  height: 1.1),
                            )
                          else
                            Text(_greetingEmoji,
                                style: const TextStyle(fontSize: 20)),
                          const SizedBox(height: 4),
                          Text(
                            isBlocking
                                ? 'Protection is active — stay strong!'
                                : 'Ready to take control today?',
                            style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        final homeState = context
                            .findAncestorStateOfType<_HomeScreenState>();
                        homeState?.setState(
                            () => homeState._selectedIndex = 2);
                      },
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: _dark,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: _accent.withValues(alpha: 0.3),
                              width: 2),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: _buildAvatarContent(),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // ── Block hero card ───────────────────────────────────
                GestureDetector(
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const BlockScreen())),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isBlocking ? _dark : Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: isBlocking
                              ? _dark.withValues(alpha: 0.35)
                              : Colors.black.withValues(alpha: 0.06),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                        if (isBlocking)
                          BoxShadow(
                            color: _accent.withValues(alpha: 0.15),
                            blurRadius: 40,
                            offset: const Offset(0, 4),
                          ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: isBlocking
                          ? _buildActiveBlockCard(blockService)
                          : _buildInactiveBlockCard(),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Feature cards ─────────────────────────────────────
                _sectionLabel('Features'),
                const SizedBox(height: 12),

                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AssessmentScreen()),
                  ),
                  child: _featureCard(
                    icon: Icons.assignment_rounded,
                    iconColor: const Color(0xFF6C63FF),
                    title: 'Self Assessment',
                    subtitle: 'Evaluate your gambling habits',
                    isComingSoon: false,
                  ),
                ),

                const SizedBox(height: 12),

                GestureDetector(
                  onTap: () => _openComingSoon(
                    title: 'Budget Calculator',
                    subtitle:
                        'Track every naira saved and understand the true cost of gambling.',
                    icon: Icons.calculate_outlined,
                    iconColor: const Color(0xFFFF6B6B),
                    features: [
                      'Calculate total money spent on gambling over time',
                      'See how much you have saved since you stopped',
                      'Set monthly savings goals and track progress',
                      'Visualise your financial recovery over weeks and months',
                    ],
                  ),
                  child: _featureCard(
                    icon: Icons.calculate_outlined,
                    iconColor: const Color(0xFFFF6B6B),
                    title: 'Budget Calculator',
                    subtitle: 'Track your savings and spending',
                    isComingSoon: true,
                  ),
                ),

                const SizedBox(height: 12),

                GestureDetector(
                  onTap: () => _openComingSoon(
                    title: 'Report Card',
                    subtitle:
                        'Your recovery journey in numbers — see how far you have come.',
                    icon: Icons.bar_chart_rounded,
                    iconColor: const Color(0xFFFFB830),
                    features: [
                      'Weekly and monthly streak tracking',
                      'Block activation history and duration stats',
                      'Relapse risk indicators and trend analysis',
                      'Shareable progress milestones',
                    ],
                  ),
                  child: _featureCard(
                    icon: Icons.bar_chart_rounded,
                    iconColor: const Color(0xFFFFB830),
                    title: 'Report Card',
                    subtitle: 'View your progress over time',
                    isComingSoon: true,
                  ),
                ),

                const SizedBox(height: 12),

                GestureDetector(
                  onTap: () => _openComingSoon(
                    title: 'Community',
                    subtitle:
                        'You are not alone. Connect with others on the same journey.',
                    icon: Icons.people_outline_rounded,
                    iconColor: const Color(0xFF00C4B4),
                    features: [
                      'Anonymous peer support and shared stories',
                      'Weekly challenges and group streaks',
                      'Celebrate milestones with others who understand',
                      'Moderated safe space with zero judgment',
                    ],
                  ),
                  child: _featureCard(
                    icon: Icons.people_outline_rounded,
                    iconColor: const Color(0xFF00C4B4),
                    title: 'Community',
                    subtitle: 'Connect with others on the journey',
                    isComingSoon: true,
                  ),
                ),

                const SizedBox(height: 24),

                // ── Daily Tip ─────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _dark,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _dark.withValues(alpha: 0.18),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: const Icon(
                          Icons.lightbulb_rounded,
                          color: Color(0xFFFFD166),
                          size: 17,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Tip of the Day',
                                style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFFFFD166),
                                    letterSpacing: 0.5)),
                            const SizedBox(height: 4),
                            Text(_todaysTip,
                                style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: Colors.white
                                        .withValues(alpha: 0.82),
                                    height: 1.5)),
                          ],
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

  Widget _buildActiveBlockCard(BlockService service) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [Color(0xFF1F2D45), _dark],
              ),
            ),
          ),
        ),
        Positioned(
          right: -20,
          top: -20,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _accent.withValues(alpha: 0.12),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 0, 22),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: _accent.withValues(alpha: 0.35),
                            width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ScaleTransition(
                            scale: _shieldScale,
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                  color: _accent, shape: BoxShape.circle),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text('Active',
                              style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _accent)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text("Protection Active",
                        style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.15)),
                    const SizedBox(height: 10),
                    Text(service.timeRemainingText,
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: _accent,
                            fontWeight: FontWeight.w600)),
                    if (service.unlockTime != null) ...[
                      const SizedBox(height: 4),
                      Text(
                          'Unlocks ${_formatExpiry(service.unlockTime!)}',
                          style: GoogleFonts.poppins(
                              fontSize: 11, color: Colors.white38)),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.touch_app_rounded,
                            color: Colors.white38, size: 14),
                        const SizedBox(width: 4),
                        Text('Tap to manage',
                            style: GoogleFonts.poppins(
                                fontSize: 11, color: Colors.white38)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInactiveBlockCard() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: Container(color: Colors.white)),
        Positioned(
          right: 0,
          top: 0,
          child: Container(
            width: 140,
            height: 100,
            decoration: BoxDecoration(
              borderRadius:
                  const BorderRadius.only(topRight: Radius.circular(28)),
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF00D4AA).withValues(alpha: 0.08),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 0, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                    color: Colors.grey.shade400,
                                    shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Text('Inactive',
                                style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade500)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text('Site & App\nBlocker',
                          style: GoogleFonts.poppins(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: _dark,
                              height: 1.15)),
                      const SizedBox(height: 8),
                      Text('Block gambling sites\nand apps now',
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.grey.shade500,
                              height: 1.4)),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: _dark,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Get started',
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: const Color.fromARGB(
                                        255, 255, 255, 255))),
                            const SizedBox(width: 6),
                            const Icon(Icons.arrow_forward_rounded,
                                color: Color(0xFF00D4AA), size: 14),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 145,
                height: 185,
                child: Image.asset(
                  'assets/images/betcontrol image.png',
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomRight,
                  errorBuilder: (_, __, ___) => Container(
                    margin: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(Icons.shield_outlined,
                        color: Colors.grey.shade400, size: 48),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarContent() {
    if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
      return Image.network(
        _profileImageUrl!,
        fit: BoxFit.cover,
        width: 52,
        height: 52,
        errorBuilder: (_, __, ___) => _defaultAvatar(),
        loadingBuilder: (_, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _defaultAvatar();
        },
      );
    }
    return _defaultAvatar();
  }

  Widget _defaultAvatar() {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.14),
                  _accent.withValues(alpha: 0.08),
                  Colors.black.withValues(alpha: 0.08),
                ],
              ),
            ),
          ),
        ),
        Center(
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.10),
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.person_rounded,
              color: _accent,
              size: 23,
            ),
          ),
        ),
        Positioned(
          right: 7,
          bottom: 7,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _accent,
              shape: BoxShape.circle,
              border: Border.all(color: _dark, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String label) {
    return Text(label,
        style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _dark,
            letterSpacing: 0.3));
  }

  Widget _featureCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isComingSoon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color:
                  iconColor.withValues(alpha: isComingSoon ? 0.06 : 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon,
                color: iconColor
                    .withValues(alpha: isComingSoon ? 0.5 : 1.0),
                size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title,
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isComingSoon
                                ? Colors.grey.shade400
                                : _dark)),
                    if (isComingSoon) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(20)),
                        child: Text('Soon',
                            style: GoogleFonts.poppins(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade400)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: isComingSoon
                            ? Colors.grey.shade300
                            : Colors.grey.shade500)),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_ios_rounded,
            size: 14,
            color: isComingSoon
                ? Colors.grey.shade200
                : Colors.grey.shade400,
          ),
        ],
      ),
    );
  }
}