import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared/chunked_contribution_grid.dart';
import 'shared/neon_ribbon_background.dart';
import 'shared/pressable_scale.dart';
import 'shared/theme.dart';
import 'services/stats.dart';
import 'services/tracker_cache.dart';
import 'services/widget_sync.dart';
import 'insights_screen.dart';
import 'routines_screen.dart';

// Main app entry point
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

/// Latest inner tracker map (`{list: {date: [entries]}}`), shared with the
/// Insights tab so both tabs read one stream.
final ValueNotifier<Map<String, dynamic>> trackerDataNotifier = ValueNotifier(
  const {},
);

// Root application widget
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Work Tracker',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          home: const HomeShell(),
        );
      },
    );
  }
}

/// Bottom-navigation shell hosting Dashboard, Insights and Routines in a
/// state-preserving stack with cross-fade page transitions.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final GlobalKey<WorkTrackerScreenState> _dashboardKey =
      GlobalKey<WorkTrackerScreenState>();

  void _goTo(int index) {
    if (index == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          ShellPage(
            visible: _index == 0,
            child: WorkTrackerScreen(
              key: _dashboardKey,
              onOpenInsights: () => _goTo(1),
            ),
          ),
          ShellPage(
            visible: _index == 1,
            child: ValueListenableBuilder<Map<String, dynamic>>(
              valueListenable: trackerDataNotifier,
              builder: (_, trackerData, __) =>
                  InsightsScreen(trackerData: trackerData),
            ),
          ),
          ShellPage(visible: _index == 2, child: const RoutinesScreen()),
        ],
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton(
              heroTag: 'add-lap-button',
              onPressed: () => _dashboardKey.currentState?.showAddWorkDialog(),
              child: const Icon(Icons.add, color: Colors.white),
            ).animate().scale(delay: 300.ms)
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _goTo,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          const NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded),
            label: 'Insights',
          ),
          const NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome_rounded),
            label: 'Routines',
          ),
        ],
      ),
    );
  }
}

/// Fades/slides a shell page in and out while keeping it mounted (streams
/// stay alive).
///
/// Uses an explicit [AnimationController] that always ticks: implicit
/// animations under a `TickerMode` freeze when their ticker is disabled
/// mid-transition, which used to leave the outgoing page fully opaque and
/// visually stacked on top of the page underneath.
class ShellPage extends StatefulWidget {
  final bool visible;
  final Widget child;

  const ShellPage({super.key, required this.visible, required this.child});

  @override
  State<ShellPage> createState() => ShellPageState();
}

class ShellPageState extends State<ShellPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Motion.standard,
      value: widget.visible ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(ShellPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      widget.visible ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary keeps the cross-fade's translate/opacity from dirtying
    // sibling pages (and their rasters) during tab switches.
    return RepaintBoundary(
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = Motion.emphasizedCurve.transform(_controller.value);
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 12),
                child: child,
              ),
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}

// Main screen for tracking work
class WorkTrackerScreen extends StatefulWidget {
  final VoidCallback? onOpenInsights;

  const WorkTrackerScreen({super.key, this.onOpenInsights});

  @override
  State<WorkTrackerScreen> createState() => WorkTrackerScreenState();
}

class WorkTrackerScreenState extends State<WorkTrackerScreen> {
  static const String _pinCardDismissedKey = 'pin_card_dismissed_v1';

  final DocumentReference<Map<String, dynamic>> trackerDoc = FirebaseFirestore
      .instance
      .collection('habit')
      .doc('tracker');

  // Cold-start cache + snapshot-driven state.
  Map<String, dynamic>? _cachedTracker;
  Map<String, dynamic>? _lastTracker;
  AppStats? _lastStats;
  Map<DateTime, int> _lastDailyCounts = const {};
  Map<String, dynamic>? _processedData;

  // Stable instances for rendering: the stream builder hands out a fresh map
  // per snapshot, so content is built from these cached references instead —
  // identical across unrelated rebuilds (theme flips, setState, haptics),
  // which keeps ContributionGraph from re-parsing its grid every build.
  Map<String, dynamic> _renderTracker = const {};
  List<String>? _renderListNames;

  // Widget pin onboarding card.
  bool _showPinWidgetCard = false;
  bool _pinCardChecked = false;

  // Flush the widget immediately on the next tracker update (after a save).
  bool _flushWidgetNext = false;

  @override
  void initState() {
    super.initState();
    _loadCache();
    _initPinWidgetCard();
    themeNotifier.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    themeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  Future<void> _loadCache() async {
    final cached = await TrackerCache.load();
    if (!mounted || cached == null) return;
    setState(() => _cachedTracker = cached);
    _publishTrackerData(cached);
  }

  void _publishTrackerData(Map<String, dynamic> docData) {
    final tracker = (docData['Tracker'] as Map<String, dynamic>?) ?? {};
    if (!identical(tracker, trackerDataNotifier.value)) {
      trackerDataNotifier.value = tracker;
    }
  }

  void _onThemeChanged() {
    final stats = _lastStats;
    if (stats != null) {
      WidgetSync.schedulePush(
        stats: stats,
        dailyCounts: _lastDailyCounts,
        immediate: true,
      );
    }
  }

  void _handleTrackerData(Map<String, dynamic> data) {
    if (identical(_processedData, data) && _lastStats != null) return;
    _processedData = data;
    _lastTracker = data;

    final tracker = (data['Tracker'] as Map<String, dynamic>?) ?? const {};
    _renderTracker = tracker;
    _renderListNames = tracker.keys.toList();
    _publishTrackerData(data);
    final stats = computeAppStats(tracker);
    _lastStats = stats;
    _lastDailyCounts = dailyTaskCounts(tracker);

    WidgetSync.schedulePush(
      stats: stats,
      dailyCounts: _lastDailyCounts,
      immediate: _flushWidgetNext,
    );
    _flushWidgetNext = false;

    unawaited(TrackerCache.save(data));
  }

  void _buildTrackerStream(
    AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
  ) {
    if (snapshot.hasError) return;
    if (snapshot.hasData && snapshot.data!.exists) {
      final data = snapshot.data!.data() ?? {};
      if (!identical(data, _processedData)) {
        _handleTrackerData(data);
      }
    }
  }

  void _onTaskSaved() {
    _flushWidgetNext = true;
    unawaited(HapticFeedback.mediumImpact());
  }

  AppStats _statsFor(Map<String, dynamic> tracker) {
    if (identical(_lastTracker, tracker) && _lastStats != null) {
      return _lastStats!;
    }
    final stats = computeAppStats(tracker);
    _lastTracker = tracker;
    _lastStats = stats;
    return stats;
  }

  Future<void> _initPinWidgetCard() async {
    if (_pinCardChecked) return;
    _pinCardChecked = true;
    try {
      final supported = await HomeWidget.isRequestPinWidgetSupported() ?? false;
      if (!supported || !mounted) return;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_pinCardDismissedKey) ?? false) return;
      final installed = await HomeWidget.getInstalledWidgets();
      if (installed.isEmpty && mounted) {
        setState(() => _showPinWidgetCard = true);
      }
    } catch (_) {
      // Plugin missing/unsupported: pin card simply never shows.
    }
  }

  Future<void> _dismissPinCard() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_pinCardDismissedKey, true);
    } catch (_) {}
    if (mounted) {
      setState(() => _showPinWidgetCard = false);
    }
  }

  Future<void> _pinWidget() async {
    try {
      await HomeWidget.requestPinWidget(androidName: 'WidgetProvider');
    } catch (_) {}
    await _dismissPinCard();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Dashboard'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_outlined),
            tooltip: 'Routines',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RoutinesScreen()),
              );
            },
          ).animate().fade(delay: 200.ms).scale(),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              themeNotifier.value == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
            onPressed: () {
              themeNotifier.value = themeNotifier.value == ThemeMode.dark
                  ? ThemeMode.light
                  : ThemeMode.dark;
            },
          ).animate().fade(delay: 200.ms).scale(),
        ],
      ),
      body: Stack(
        children: [
          const NeonRibbonBackground(),
          SafeArea(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: trackerDoc.snapshots(),
              builder: (context, snapshot) {
                _buildTrackerStream(snapshot);

                if (snapshot.hasData &&
                    snapshot.data!.exists &&
                    _renderListNames != null) {
                  return _buildContent(
                    context,
                    _renderTracker,
                    _renderListNames!,
                  );
                }

                // Offline / waiting / missing-doc fallbacks.
                if (_cachedTracker != null) {
                  final trackerData =
                      (_cachedTracker!['Tracker'] as Map<String, dynamic>?) ??
                      {};
                  final listNames = trackerData.keys.toList();
                  return _buildContent(context, trackerData, listNames);
                }

                if (snapshot.hasError) return _buildErrorState();
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildLoadingState(context);
                }
                return _buildEmptyState(() => _showAddWorkDialog(const []));
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the log-task dialog from the shell FAB. Falls back to fetching
  /// the tracker doc when the dashboard stream hasn't populated yet.
  Future<void> showAddWorkDialog() async {
    final listNames = _currentListNames();
    if (listNames != null) {
      _showAddWorkDialog(listNames);
      return;
    }
    try {
      final doc = await trackerDoc.get();
      final data = doc.data();
      final trackerData = data?['Tracker'] as Map<String, dynamic>? ?? {};
      _showAddWorkDialog(trackerData.keys.toList());
    } catch (_) {
      _showAddWorkDialog(const []);
    }
  }

  List<String>? _currentListNames() {
    if (_lastTracker != null) {
      final tracker = (_lastTracker!['Tracker'] as Map<String, dynamic>?);
      if (tracker != null) return tracker.keys.toList();
    }
    if (_cachedTracker != null) {
      final tracker = (_cachedTracker!['Tracker'] as Map<String, dynamic>?);
      if (tracker != null) return tracker.keys.toList();
    }
    return null;
  }

  void _showAddWorkDialog(List<String> listNames) {
    if (!mounted) return;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      pageBuilder: (context, animation, secondaryAnimation) {
        return AddWorkDialog(existingLists: listNames, onSaved: _onTaskSaved);
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeInOutCubic,
                ),
              ),
          child: child,
        );
      },
      transitionDuration: 400.ms,
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white10 : Colors.grey.shade200;
    final highlightColor = isDark
        ? Colors.white.withOpacity(0.2)
        : Colors.grey.shade50;

    // RepaintBoundary keeps the looping shimmer from repainting the static
    // aurora and anything else beneath it.
    return RepaintBoundary(
      child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  height: 230,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  height: 400,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ],
            ),
          )
          .animate(onPlay: (controller) => controller.repeat())
          .shimmer(duration: 1200.ms, color: highlightColor),
    );
  }

  Widget _buildErrorState() {
    return const Center(child: Text('Something went wrong'));
  }

  Widget _buildEmptyState(VoidCallback onAdd) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stepColor = isDark ? Colors.white60 : Colors.grey.shade700;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.flag_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No Tracks Yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onAdd,
              child: const Text('Tap + to start a new track'),
            ),
            const SizedBox(height: 28),
            _buildEmptyStep(
              icon: Icons.playlist_add,
              title: 'Add a track',
              subtitle: 'Tap + and log your first task.',
              color: stepColor,
            ),
            const SizedBox(height: 16),
            _buildEmptyStep(
              icon: Icons.insights_outlined,
              title: 'Check insights',
              subtitle: 'Your streaks and weekly review land here.',
              color: stepColor,
            ),
            const SizedBox(height: 16),
            _buildEmptyStep(
              icon: Icons.calendar_month_outlined,
              title: 'Grow your heatmap',
              subtitle: 'Every logged task colors the grid.',
              color: stepColor,
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 500.ms);
  }

  Widget _buildEmptyStep({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    Map<String, dynamic> trackerData,
    List<String> listNames,
  ) {
    if (listNames.isEmpty) {
      return _buildEmptyState(() => _showAddWorkDialog(const []));
    }

    final workListCards = listNames.map((listName) {
      final listData =
          trackerData[listName] as Map<String, dynamic>? ?? const {};
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: WorkListCard(title: listName, data: listData),
      );
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_showPinWidgetCard) ...[
            _buildPinWidgetCard(context),
            const SizedBox(height: 16),
          ],
          _buildSummaryCard(context, trackerData)
              .animate()
              .fadeIn(duration: 600.ms)
              .slideY(begin: 0.2, curve: Curves.easeOutCubic),
          const SizedBox(height: 24),
          ...workListCards
              .animate(interval: 100.ms)
              .fadeIn(duration: 500.ms)
              .slideX(begin: -0.2, curve: Curves.easeOutCubic),
        ],
      ),
    );
  }

  Widget _buildPinWidgetCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? const Color(0xFFE84545) : const Color(0xFF0066CC);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.widgets_outlined, color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pin your widget',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Your heatmap, streak and today\'s count right on your home screen.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Add widget',
            onPressed: _pinWidget,
            icon: Icon(Icons.add_circle_outline, color: accent),
          ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: _dismissPinCard,
            icon: const Icon(Icons.close, size: 18, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, Map<String, dynamic> tracker) {
    final stats = _statsFor(tracker);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cardColor = isDark ? const Color(0xFF1D1D1D) : Colors.white;

    final primaryAccent = isDark
        ? const Color(0xFFE84545)
        : const Color(0xFF0066CC);

    final subtitleColor = isDark ? Colors.white60 : Colors.black54;
    final dividerColor = isDark
        ? Colors.white12
        : Colors.black.withOpacity(0.06);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withOpacity(0.06),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OVERVIEW',
            style: TextStyle(
              color: primaryAccent,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Quick summary of your tracker',
            style: TextStyle(fontSize: 13, color: subtitleColor),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  context,
                  'Active Days',
                  stats.workDays,
                  Icons.calendar_today_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryItem(
                  context,
                  'Total Tasks',
                  stats.totalTasks,
                  Icons.outlined_flag,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  context,
                  'Current Streak',
                  stats.currentStreak,
                  Icons.local_fire_department_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryItem(
                  context,
                  'This Week',
                  stats.thisWeek,
                  Icons.date_range_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Divider(color: dividerColor, height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: widget.onOpenInsights,
                  icon: const Icon(Icons.insights_outlined),
                  label: const Text('Insights'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RoutinesScreen()),
                    );
                  },
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Atomic Habits'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(
    BuildContext context,
    String label,
    int value,
    IconData icon,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? Colors.white70 : Colors.black54;
    final labelColor = isDark ? Colors.grey[400]! : Colors.grey[700]!;

    return PressableScale(
      onTap: () => HapticFeedback.lightImpact(),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : const Color(0xFFF7F9FC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Animate()
                      .custom(
                        duration: 1000.ms,
                        curve: Curves.easeOutCubic,
                        begin: 0,
                        end: value.toDouble(),
                        builder: (_, val, __) => Text(
                          val.toInt().toString(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                      .fadeIn(),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(fontSize: 12, color: labelColor),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Dialog for adding a new work entry
class AddWorkDialog extends StatefulWidget {
  final List<String> existingLists;
  final VoidCallback? onSaved;

  const AddWorkDialog({super.key, required this.existingLists, this.onSaved});

  @override
  State<AddWorkDialog> createState() => _AddWorkDialogState();
}

class _AddWorkDialogState extends State<AddWorkDialog> {
  final _titleController = TextEditingController();
  final _newListController = TextEditingController();
  String? _selectedList;
  bool _isNewList = false;

  String _selectedDifficulty = 'EASY';
  String _selectedCategory = 'Work';
  DateTime _selectedDate = DateTime.now();

  final List<String> _difficulties = ['EASY', 'MEDIUM', 'HARD'];
  final List<String> _categories = ['Work', 'Health', 'Play'];

  @override
  void initState() {
    super.initState();
    if (widget.existingLists.isNotEmpty) {
      _selectedList = widget.existingLists.first;
    } else {
      _isNewList = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Hero(
      tag: 'add-lap-button',
      child: AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        title: const Text('Log a Task'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.existingLists.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: _isNewList ? '---NEW---' : _selectedList,
                  decoration: const InputDecoration(
                    labelText: 'Track',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    ...widget.existingLists.map(
                      (list) =>
                          DropdownMenuItem(value: list, child: Text(list)),
                    ),
                    const DropdownMenuItem(
                      value: '---NEW---',
                      child: Text('Create New Track...'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      if (value == '---NEW---') {
                        _isNewList = true;
                        _selectedList = null;
                      } else {
                        _isNewList = false;
                        _selectedList = value;
                      }
                    });
                  },
                ),
              if (_isNewList)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: TextField(
                    controller: _newListController,
                    decoration: const InputDecoration(
                      labelText: 'New Track Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Lap Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Sector',
                  border: OutlineInputBorder(),
                ),
                items: _categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (value) {
                  setState(() => _selectedCategory = value!);
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedDifficulty,
                decoration: const InputDecoration(
                  labelText: 'Tire Compound',
                  border: OutlineInputBorder(),
                ),
                items: _difficulties
                    .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                    .toList(),
                onChanged: (value) {
                  setState(() => _selectedDifficulty = value!);
                },
              ),
              const SizedBox(height: 16),
              ListTile(
                title: Text(
                  'Date: ${_selectedDate.toLocal().toString().split(' ')[0]}',
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: _selectDate,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _saveWorkEntry,
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark
                  ? const Color(0xFFE84545)
                  : const Color(0xFF0066CC),
              foregroundColor: Colors.white,
            ),
            child: const Text('Save Lap'),
          ),
        ],
      ).animate().fadeIn(),
    );
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _saveWorkEntry() async {
    final listName = _isNewList
        ? _newListController.text.trim()
        : _selectedList;

    if (listName == null || listName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or create a track.')),
      );
      return;
    }

    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a task description.')),
      );
      return;
    }

    final dateStr =
        '${_selectedDate.day.toString().padLeft(2, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.year}';

    final newEntry = {
      'title': _titleController.text.trim(),
      'category': _selectedCategory,
      'difficulty': _selectedDifficulty,
    };

    final trackerRef = FirebaseFirestore.instance
        .collection('habit')
        .doc('tracker');

    try {
      await trackerRef.set({
        'Tracker': {
          listName: {
            dateStr: FieldValue.arrayUnion([newEntry]),
          },
        },
      }, SetOptions(merge: true));

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSaved?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lap saved!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving task: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _newListController.dispose();
    super.dispose();
  }
}

// Card for displaying a list of work items
class WorkListCard extends StatelessWidget {
  final String title;
  final Map<String, dynamic> data;

  const WorkListCard({super.key, required this.title, required this.data});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1D1D1D) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 5),
                  ),
                ],
        ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: ContributionGraph(data: data),
            ),
            if (_getRecentWorkEntries().isNotEmpty) ...[
              Divider(
                height: 1,
                indent: 20,
                endIndent: 20,
                color: isDark ? Colors.white12 : Colors.grey.shade200,
              ),
              _buildRecentWork(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? const Color(0xFFE84545) : const Color(0xFF0066CC);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Last 365 Days',
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentWork(BuildContext context) {
    final recentEntries = _getRecentWorkEntries();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Tasks',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          ...recentEntries
              .take(3)
              .map((entry) => _buildWorkItem(context, entry))
              .toList()
              .animate(interval: 50.ms)
              .fadeIn(duration: 300.ms)
              .slideX(begin: -0.1, curve: Curves.easeOutCubic),
        ],
      ),
    );
  }

  Widget _buildWorkItem(BuildContext context, Map<String, dynamic> entry) {
    final category = entry['category']?.toString() ?? 'Work';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            _getIconForCategory(category),
            color: _getDifficultyColor(
              entry['difficulty']?.toString() ?? 'EASY',
            ),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry['title']?.toString() ?? 'No title',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (entry['date'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${entry['date']} - $category',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _getRecentWorkEntries() {
    final entries = <Map<String, dynamic>>[];

    data.forEach((dateStr, activities) {
      if (activities is List) {
        for (final activity in activities) {
          if (activity is Map<String, dynamic>) {
            entries.add({
              ...Map<String, dynamic>.from(activity),
              'date': dateStr,
            });
          }
        }
      }
    });

    entries.sort(
      (a, b) =>
          _parseDate(b['date'] ?? '').compareTo(_parseDate(a['date'] ?? '')),
    );

    return entries;
  }

  DateTime _parseDate(String dateStr) {
    final parts = dateStr.split('-');
    return parts.length == 3
        ? DateTime(
            int.parse(parts[2]),
            int.parse(parts[1]),
            int.parse(parts[0]),
          )
        : DateTime.now();
  }

  IconData _getIconForCategory(String category) {
    switch (category) {
      case 'Health':
        return Icons.directions_run;
      case 'Work':
        return Icons.menu_book;
      case 'Play':
        return Icons.sentiment_satisfied;
      default:
        return Icons.flag;
    }
  }

  Color _getDifficultyColor(String difficulty) {
    switch (difficulty.toUpperCase()) {
      case 'EASY':
        return const Color(0xFF34C759);
      case 'MEDIUM':
        return const Color(0xFFFF9500);
      case 'HARD':
        return const Color(0xFFE84545);
      default:
        return Colors.grey;
    }
  }
}

// GitHub-style contribution graph widget
class ContributionGraph extends StatefulWidget {
  final Map<String, dynamic> data;
  const ContributionGraph({super.key, required this.data});

  @override
  State<ContributionGraph> createState() => _ContributionGraphState();
}

class _ContributionGraphState extends State<ContributionGraph> {
  Map<DateTime, Map<String, dynamic>> _workDataMap = const {};
  Map<DateTime, int> _counts = const {};
  Map<DateTime, String> _categories = const {};
  Map<String, dynamic>? _parsedFrom;

  @override
  void initState() {
    super.initState();
    _parseData();
  }

  @override
  void didUpdateWidget(ContributionGraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    _parseData();
  }

  /// Re-parses only when the raw data instance actually changes. The parent
  /// passes stable tracker map instances across unrelated rebuilds, so theme
  /// flips / setState no longer re-parse the whole year and rebuild ~180
  /// heatmap cells.
  void _parseData() {
    if (identical(_parsedFrom, widget.data)) return;
    _parsedFrom = widget.data;
    _workDataMap = _getWorkDataMap();

    final counts = <DateTime, int>{};
    final categories = <DateTime, String>{};
    _workDataMap.forEach((date, entry) {
      counts[date] = (entry['count'] as int?) ?? 0;
      final category = entry['category'] as String?;
      if (category != null) categories[date] = category;
    });
    _counts = counts;
    _categories = categories;
  }

  DateTime _parseDate(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length != 3) return DateTime.now();
    return DateTime(
      int.parse(parts[2]),
      int.parse(parts[1]),
      int.parse(parts[0]),
    );
  }

  Map<DateTime, Map<String, dynamic>> _getWorkDataMap() {
    final Map<DateTime, Map<String, dynamic>> dataMap = {};

    widget.data.forEach((dateStr, activities) {
      if (activities is List && activities.isNotEmpty) {
        try {
          final date = _parseDate(dateStr);
          final normalized = DateTime(date.year, date.month, date.day);
          String? firstCategory;

          if (activities.first is Map) {
            firstCategory = activities.first['category']?.toString();
          }

          if (firstCategory != null) {
            dataMap[normalized] = {
              'category': firstCategory,
              'count': activities.length,
            };
          }
        } catch (_) {}
      }
    });

    return dataMap;
  }

  Color _getColorForCategory(BuildContext context, String? category) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (category) {
      case 'Work':
        return isDark ? const Color(0xFF5E5CE6) : const Color(0xFF0066CC);
      case 'Health':
        return const Color(0xFF34C759);
      case 'Play':
        return const Color(0xFFFF9500);
      default:
        return isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RepaintBoundary(
          child: ChunkedContributionGrid(
            counts: _counts,
            categories: _categories,
            colorFor: (day, count, category) =>
                _getColorForCategory(context, count > 0 ? category : null),
            tooltipFor: _tooltipFor,
          ),
        ).animate().fadeIn(duration: 450.ms),
        const SizedBox(height: 12),
        _buildLegend(context),
      ],
    );
  }

  String _tooltipFor(DateTime day) {
    final normalized = DateTime(day.year, day.month, day.day);
    final dayData = _workDataMap[normalized];
    final category = dayData?['category'] as String?;
    final count = dayData?['count'] as int? ?? 0;

    final buffer = StringBuffer('${day.day}-${day.month}-${day.year}\n');
    if (count > 0 && category != null) {
      buffer.write(
        '$count ${category.toLowerCase()} ${count == 1 ? 'task' : 'tasks'}',
      );
    } else {
      buffer.write('No tasks');
    }

    return buffer.toString();
  }

  Widget _buildLegend(BuildContext context) {
    const categories = ['Work', 'Health', 'Play'];

    final legendItems = categories
        .expand(
          (category) => [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _getColorForCategory(context, category),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              category,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(width: 10),
          ],
        )
        .toList();

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: legendItems
          .animate(interval: 50.ms)
          .fadeIn(duration: 300.ms)
          .slideX(begin: -0.1),
    );
  }
}
