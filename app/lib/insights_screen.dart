import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:async';

import 'services/insights_engine.dart';
import 'shared/neon_ribbon_background.dart';
import 'shared/pressable_scale.dart';
import 'shared/theme.dart';

/// Google-style insights dashboard: range selector, animated stat cards,
/// charts and ranked lists in a single responsive scroll view.
class InsightsScreen extends StatefulWidget {
  final Map<String, dynamic> trackerData;

  const InsightsScreen({super.key, required this.trackerData});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  InsightsRange _range = InsightsRange.week;

  // On cold start the tracker data may still be loading; keep a shimmer
  // placeholder up briefly before showing the empty state.
  static const _bootWindow = Duration(milliseconds: 700);
  Timer? _bootTimer;
  bool _bootCheckDone = false;

  @override
  void initState() {
    super.initState();
    _bootCheckDone = widget.trackerData.isNotEmpty;
    _bootTimer = Timer(_bootWindow, () {
      if (mounted) setState(() => _bootCheckDone = true);
    });
  }

  @override
  void didUpdateWidget(InsightsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trackerData.isNotEmpty && !_bootCheckDone) {
      _bootTimer?.cancel();
      _bootCheckDone = true;
    }
  }

  @override
  void dispose() {
    _bootTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final report = computeInsights(widget.trackerData, range: _range);
    final showShimmer = report.isEmpty && !_bootCheckDone;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          const NeonRibbonBackground(),
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                SliverAppBar.large(
                  backgroundColor: Colors.transparent,
                  title: const Text('Insights'),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _SlidingSegments(
                        selected: _range,
                        onChanged: _onRangeChanged,
                      ),
                      const SizedBox(height: 16),
                      AnimatedSwitcher(
                        duration: Motion.standard,
                        switchInCurve: Motion.standardCurve,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.03),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: report.isEmpty
                            ? (showShimmer
                                  ? _buildShimmer(isDark)
                                  : _buildEmptyState(context, isDark))
                            : KeyedSubtree(
                                key: ValueKey(_range),
                                child: _buildSections(context, report, isDark),
                              ),
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onRangeChanged(InsightsRange range) {
    if (range == _range) return;
    HapticFeedback.selectionClick();
    setState(() => _range = range);
  }

  Widget _buildShimmer(bool isDark) {
    final base = isDark ? Colors.white10 : Colors.grey.shade200;
    final highlight = isDark
        ? Colors.white.withOpacity(0.2)
        : Colors.grey.shade50;

    // RepaintBoundary keeps the looping shimmer from repainting the static
    // aurora and anything else beneath it.
    return RepaintBoundary(
      child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              children: [
                Container(
                  height: 110,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  height: 220,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
              ],
            ),
          )
          .animate(onPlay: (controller) => controller.repeat())
          .shimmer(duration: 1200.ms, color: highlight),
    );
  }

  Widget _buildSections(
    BuildContext context,
    InsightsReport report,
    bool isDark,
  ) {
    final wide = MediaQuery.sizeOf(context).width >= 640;
    final sections = <Widget>[
      _buildHeroStats(context, report, isDark, wide),
      _buildInsightChips(report, isDark),
      _ResponsivePair(
        wide: wide,
        first: _InsightCard(
          title: 'Category mix',
          isDark: isDark,
          child: _CategoryDonut(report: report, isDark: isDark),
        ),
        second: _InsightCard(
          title: 'Activity',
          isDark: isDark,
          child: _ActivityBars(report: report, isDark: isDark),
        ),
      ),
      _ResponsivePair(
        wide: wide,
        first: _InsightCard(
          title: 'Weekday rhythm',
          isDark: isDark,
          child: _WeekdayRhythm(report: report, isDark: isDark),
        ),
        second: _InsightCard(
          title: 'Effort split',
          isDark: isDark,
          child: _DifficultyBar(report: report, isDark: isDark),
        ),
      ),
      _InsightCard(
        title: 'Top habits',
        isDark: isDark,
        child: _TopHabitsList(report: report, isDark: isDark),
      ),
    ];

    final staggered = <Widget>[];
    for (int i = 0; i < sections.length; i++) {
      staggered.add(
        sections[i]
            .animate(delay: (i * 70).ms)
            .fadeIn(duration: 400.ms, curve: Motion.standardCurve)
            .slideY(begin: 0.06, curve: Motion.standardCurve),
      );
      if (i < sections.length - 1) staggered.add(const SizedBox(height: 16));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: staggered,
    );
  }

  Widget _buildHeroStats(
    BuildContext context,
    InsightsReport report,
    bool isDark,
    bool wide,
  ) {
    final cards = <_HeroStat>[
      _HeroStat(
        label: 'Tasks',
        value: report.thisPeriod,
        icon: Icons.task_alt_rounded,
        delta: report.delta,
        deltaOf: report.previousPeriod,
      ),
      _HeroStat(
        label: 'Active days',
        value: report.activeDays,
        icon: Icons.event_available_rounded,
      ),
      _HeroStat(
        label: 'Streak',
        value: report.currentStreak,
        icon: Icons.local_fire_department_rounded,
        sub: 'Best ${report.bestStreak}',
        accent: const Color(0xFFFF9F0A),
      ),
      _HeroStat(
        label: 'All tasks',
        value: report.totalTasks,
        icon: Icons.outlined_flag_rounded,
      ),
    ];

    final crossCount = wide ? 4 : 2;
    final rows = <Widget>[];
    for (int i = 0; i < cards.length; i += crossCount) {
      final rowCards = cards.sublist(
        i,
        (i + crossCount).clamp(0, cards.length),
      );
      rows.add(
        Row(
          children: [
            for (final card in rowCards) ...[
              Expanded(
                child: _HeroStatCard(stat: card, isDark: isDark),
              ),
              if (card != rowCards.last) const SizedBox(width: 12),
            ],
          ],
        ),
      );
      if (i + crossCount < cards.length) rows.add(const SizedBox(height: 12));
    }

    return Column(children: rows);
  }

  Widget _buildInsightChips(InsightsReport report, bool isDark) {
    final chips = <String>[];
    if (report.delta > 0) {
      chips.add('Up ${deltaLabel(report.delta)} vs previous');
    } else if (report.delta < 0) {
      chips.add('${deltaLabel(report.delta)} vs previous');
    }
    final peak = peakWeekday(report.weekdayHistogram);
    if (peak != null) {
      chips.add('Peak on ${_weekdayName(peak)}');
    }
    if (report.categoryCounts.isNotEmpty) {
      final top = report.categoryCounts.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      chips.add('${top.key} leads with ${top.value}');
    }
    if (chips.isEmpty) {
      chips.add('Log a task to unlock insights');
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips
          .map(
            (text) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: (isDark ? Colors.white : Colors.black).withOpacity(0.05),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 13,
                    color: accentFor(isDark).withOpacity(0.9),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    final accent = accentFor(isDark);
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.query_stats_rounded,
              size: 42,
              color: accent.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No activity yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Log your first task and insights\nwill start flowing in.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: isDark ? Colors.white54 : Colors.black54,
              height: 1.4,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  static String _weekdayName(int monIndex) {
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return names[monIndex.clamp(0, 6)];
  }
}

class _HeroStat {
  final String label;
  final int value;
  final IconData icon;
  final int? delta;
  final int? deltaOf;
  final String? sub;
  final Color? accent;

  const _HeroStat({
    required this.label,
    required this.value,
    required this.icon,
    this.delta,
    this.deltaOf,
    this.sub,
    this.accent,
  });
}

class _HeroStatCard extends StatelessWidget {
  final _HeroStat stat;
  final bool isDark;

  const _HeroStatCard({required this.stat, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final accent = stat.accent ?? accentFor(isDark);
    return PressableScale(
      onTap: () => HapticFeedback.lightImpact(),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _cardDecoration(isDark),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(stat.icon, size: 16, color: accent),
                const Spacer(),
                if (stat.delta != null && stat.deltaOf != null)
                  _DeltaChip(delta: stat.delta!, isDark: isDark),
              ],
            ),
            const SizedBox(height: 10),
            Animate()
                .custom(
                  duration: 900.ms,
                  curve: Motion.standardCurve,
                  begin: 0,
                  end: stat.value.toDouble(),
                  builder: (_, val, _) => Text(
                    val.toInt().toString(),
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.black87,
                      letterSpacing: -0.5,
                    ),
                  ),
                )
                .fadeIn(),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    stat.sub != null
                        ? '${stat.label} · ${stat.sub}'
                        : stat.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  final int delta;
  final bool isDark;

  const _DeltaChip({required this.delta, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (delta == 0) {
      return _chip(
        icon: Icons.drag_handle_rounded,
        text: '0',
        color: (isDark ? Colors.white : Colors.black).withOpacity(0.35),
      );
    }
    final up = delta > 0;
    final color = up ? const Color(0xFF30D158) : const Color(0xFFFF453A);
    return _chip(
      icon: up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
      text: deltaLabel(delta),
      color: color,
    );
  }

  Widget _chip({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 2),
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Segmented range control with a sliding thumb.
class _SlidingSegments extends StatelessWidget {
  final InsightsRange selected;
  final ValueChanged<InsightsRange> onChanged;

  const _SlidingSegments({required this.selected, required this.onChanged});

  static const _options = [
    (InsightsRange.week, 'Week'),
    (InsightsRange.month, 'Month'),
    (InsightsRange.all, 'All'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = accentFor(isDark);
    final index = _options.indexWhere((o) => o.$1 == selected).clamp(0, 2);

    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withOpacity(0.05),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: Motion.standard,
            curve: Motion.emphasizedCurve,
            alignment: Alignment(-1.0 + index, 0),
            child: FractionallySizedBox(
              widthFactor: 1 / 3,
              child: Container(
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(100),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final (range, label) in _options)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(range),
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: Motion.fast,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: range == selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: range == selected
                              ? Colors.white
                              : (isDark ? Colors.white60 : Colors.black54),
                        ),
                        child: Text(label),
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
}

class _ResponsivePair extends StatelessWidget {
  final bool wide;
  final Widget first;
  final Widget second;

  const _ResponsivePair({
    required this.wide,
    required this.first,
    required this.second,
  });

  @override
  Widget build(BuildContext context) {
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: 16),
          Expanded(child: second),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [first, const SizedBox(height: 16), second],
    );
  }
}

class _InsightCard extends StatelessWidget {
  final String title;
  final bool isDark;
  final Widget child;

  const _InsightCard({
    required this.title,
    required this.isDark,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Charts repaint on touch/data changes; a boundary keeps that local.
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: _cardDecoration(isDark),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: accentFor(isDark),
              ),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

/// Tap-highlighted donut of category mix.
class _CategoryDonut extends StatefulWidget {
  final InsightsReport report;
  final bool isDark;

  const _CategoryDonut({required this.report, required this.isDark});

  @override
  State<_CategoryDonut> createState() => _CategoryDonutState();
}

class _CategoryDonutState extends State<_CategoryDonut> {
  int _touched = -1;

  static const _order = ['Work', 'Health', 'Play'];

  Color _categoryColor(String category, bool isDark) {
    switch (category) {
      case 'Work':
        return isDark ? const Color(0xFF7B79FF) : const Color(0xFF0066CC);
      case 'Health':
        return const Color(0xFF34C759);
      case 'Play':
        return const Color(0xFFFF9500);
      default:
        return isDark ? Colors.white24 : Colors.grey.shade400;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final entries = <MapEntry<String, int>>[];
    for (final key in _order) {
      final value = widget.report.categoryCounts[key];
      if (value != null && value > 0) entries.add(MapEntry(key, value));
    }
    widget.report.categoryCounts.forEach((key, value) {
      if (!_order.contains(key) && value > 0) {
        entries.add(MapEntry(key, value));
      }
    });

    final total = entries.fold(0, (sum, e) => sum + e.value);

    return SizedBox(
      height: 190,
      child: total == 0
          ? _chartEmptyLabel(isDark, 'No categories in this range')
          : Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        duration: Motion.emphasized,
                        curve: Motion.emphasizedCurve,
                        PieChartData(
                          sectionsSpace: 3,
                          centerSpaceRadius: 42,
                          startDegreeOffset: -90,
                          pieTouchData: PieTouchData(
                            touchCallback: (event, response) {
                              if (event is FlLongPressEnd ||
                                  event is FlPanEndEvent) {
                                setState(() => _touched = -1);
                                return;
                              }
                              final index =
                                  response?.touchedSection?.touchedSectionIndex;
                              if (index != null && index != _touched) {
                                HapticFeedback.selectionClick();
                                setState(() => _touched = index);
                              }
                            },
                          ),
                          sections: List.generate(entries.length, (i) {
                            final entry = entries[i];
                            final selected = _touched == i;
                            final dimmed = _touched >= 0 && !selected;
                            return PieChartSectionData(
                              value: entry.value.toDouble(),
                              color: _categoryColor(
                                entry.key,
                                isDark,
                              ).withOpacity(dimmed ? 0.35 : 1),
                              radius: selected ? 40.0 : 32.0,
                              showTitle: false,
                            );
                          }),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSwitcher(
                            duration: Motion.fast,
                            child: Text(
                              _touched >= 0 && _touched < entries.length
                                  ? '${entries[_touched].value}'
                                  : '$total',
                              key: ValueKey(_touched),
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                          Text(
                            _touched >= 0 && _touched < entries.length
                                ? entries[_touched].key
                                : 'tasks',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: _categoryColor(entry.key, isDark),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  entry.key,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              Text(
                                '${(entry.value / total * 100).round()}%',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.black54,
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
    );
  }
}

/// Daily (or weekly, for the All range) bar chart of task counts.
class _ActivityBars extends StatelessWidget {
  final InsightsReport report;
  final bool isDark;

  const _ActivityBars({required this.report, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final series = report.dailyCounts;
    if (series.isEmpty) {
      return SizedBox(
        height: 190,
        child: _chartEmptyLabel(isDark, 'Nothing to chart yet'),
      );
    }

    final maxCount = series.fold(0, (m, e) => m > e.count ? m : e.count);
    final maxY = (maxCount <= 1 ? 2 : maxCount + 1).toDouble();
    final accent = accentFor(isDark);
    final showWeekdayLabels = report.range == InsightsRange.week;

    return SizedBox(
      height: 190,
      child: BarChart(
        duration: Motion.emphasized,
        curve: Motion.emphasizedCurve,
        BarChartData(
          maxY: maxY,
          alignment: BarChartAlignment.spaceBetween,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (value) => FlLine(
              color: (isDark ? Colors.white : Colors.black).withOpacity(0.05),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            show: true,
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= series.length) {
                    return const SizedBox.shrink();
                  }
                  final day = series[index].day;
                  String label;
                  if (showWeekdayLabels) {
                    label = 'MTWTFSS'[day.weekday - 1];
                  } else if (report.range == InsightsRange.month) {
                    label = index % 7 == 0 ? '${day.day}' : '';
                  } else {
                    label = index % 4 == 0 ? '${day.month}/${day.day}' : '';
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            handleBuiltInTouches: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (group) =>
                  isDark ? const Color(0xFF2A2A2E) : const Color(0xFF1C1C1E),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final count = rod.toY.toInt();
                final day = series[group.x.toInt()].day;
                return BarTooltipItem(
                  '$count ${count == 1 ? 'task' : 'tasks'}',
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  children: [
                    TextSpan(
                      text: '\n${day.day}/${day.month}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 10,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          barGroups: List.generate(series.length, (i) {
            final count = series[i].count;
            final isPeak = count == maxCount && count > 0;
            final rodWidth = series.length > 20
                ? 6.0
                : series.length > 10
                    ? 9.0
                    : 14.0;
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: count > 0 ? count.toDouble() : 0.05,
                  color: count > 0
                      ? (isPeak ? accent : accent.withOpacity(0.45))
                      : (isDark
                          ? Colors.white10
                          : Colors.black.withOpacity(0.06)),
                  width: rodWidth,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

/// Custom 7-bar weekday histogram with a highlighted peak day.
class _WeekdayRhythm extends StatelessWidget {
  final InsightsReport report;
  final bool isDark;

  const _WeekdayRhythm({required this.report, required this.isDark});

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final peak = peakWeekday(report.weekdayHistogram);
    final maxVal = report.weekdayHistogram.fold(0, (a, b) => a > b ? a : b);
    final accent = accentFor(isDark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (peak != null)
          Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.emoji_events_rounded, size: 13, color: accent),
                      const SizedBox(width: 5),
                      Text(
                        'Best day: ${_InsightsScreenState._weekdayName(peak)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .animate()
              .fadeIn(duration: 500.ms)
              .scale(
                begin: const Offset(0.9, 0.9),
                curve: Motion.standardCurve,
                duration: 500.ms,
              ),
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (int i = 0; i < 7; i++)
                Expanded(
                  child: _RhythmBar(
                    label: _dayLabels[i],
                    value: report.weekdayHistogram[i],
                    maxValue: maxVal,
                    isPeak: peak == i,
                    isDark: isDark,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RhythmBar extends StatelessWidget {
  final String label;
  final int value;
  final int maxValue;
  final bool isPeak;
  final bool isDark;

  const _RhythmBar({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.isPeak,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentFor(isDark);
    final fraction = maxValue == 0 ? 0.0 : (value / maxValue).clamp(0.04, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AnimatedSwitcher(
            duration: Motion.fast,
            child: Text(
              value > 0 ? '$value' : '',
              key: ValueKey(value),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: isPeak
                    ? accent
                    : (isDark ? Colors.white54 : Colors.black54),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: fraction),
                duration: Motion.emphasized,
                curve: Motion.emphasizedCurve,
                builder: (context, t, child) =>
                    FractionallySizedBox(heightFactor: t, child: child),
                child: Container(
                  width: 14,
                  decoration: BoxDecoration(
                    color: isPeak ? accent : accent.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isPeak ? FontWeight.w800 : FontWeight.w500,
              color: isPeak
                  ? accent
                  : (isDark ? Colors.white38 : Colors.black38),
            ),
          ),
        ],
      ),
    );
  }
}

/// Single stacked difficulty bar with animated segments and a legend.
class _DifficultyBar extends StatelessWidget {
  final InsightsReport report;
  final bool isDark;

  const _DifficultyBar({required this.report, required this.isDark});

  static const _levels = [
    ('EASY', Color(0xFF30D158)),
    ('MEDIUM', Color(0xFFFF9F0A)),
    ('HARD', Color(0xFFFF453A)),
  ];

  @override
  Widget build(BuildContext context) {
    final total = report.difficultyCounts.values.fold(0, (a, b) => a + b);

    if (total == 0) {
      return SizedBox(
        height: 120,
        child: _chartEmptyLabel(isDark, 'No tasks in this range'),
      );
    }

    final segments = <(String, Color, int)>[
      for (final (level, color) in _levels)
        if ((report.difficultyCounts[level] ?? 0) > 0)
          (level, color, report.difficultyCounts[level]!),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 18,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                for (final (_, color, count) in segments)
                  Expanded(
                    flex: count,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: Motion.emphasized,
                      curve: Motion.emphasizedCurve,
                      builder: (context, t, child) => FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: t,
                        child: child,
                      ),
                      child: Container(decoration: BoxDecoration(color: color)),
                    ),
                  ),
              ],
            ),
          ),
        ).animate().fadeIn(duration: 400.ms),
        const SizedBox(height: 14),
        for (final (level, color) in _levels)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _levelName(level),
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const Spacer(),
                Text(
                  '${report.difficultyCounts[level] ?? 0}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${((report.difficultyCounts[level] ?? 0) / total * 100).round()}%',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _levelName(String level) {
    switch (level) {
      case 'EASY':
        return 'Easy';
      case 'MEDIUM':
        return 'Medium';
      default:
        return 'Hard';
    }
  }
}

/// Ranked top-habits list with medal badges.
class _TopHabitsList extends StatelessWidget {
  final InsightsReport report;
  final bool isDark;

  const _TopHabitsList({required this.report, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (report.topHabits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: _chartEmptyLabel(isDark, 'No habits logged in this range'),
      );
    }

    return Column(
      children: [
        for (int i = 0; i < report.topHabits.length; i++)
          Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    _RankBadge(rank: i + 1),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        report.topHabits[i].habit,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: accentFor(isDark).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        '×${report.topHabits[i].count}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: accentFor(isDark),
                        ),
                      ),
                    ),
                  ],
                ),
              )
              .animate(delay: (i * 60).ms)
              .fadeIn(duration: 350.ms)
              .slideX(
                begin: 0.06,
                curve: Motion.standardCurve,
                duration: 350.ms,
              ),
      ],
    );
  }
}

class _RankBadge extends StatelessWidget {
  final int rank;

  const _RankBadge({required this.rank});

  static const _medals = [
    Color(0xFFFFD60A),
    Color(0xFFC7C7CC),
    Color(0xFFBF8970),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final medal = rank <= 3 ? _medals[rank - 1] : null;
    final color =
        medal ?? (isDark ? Colors.white24 : Colors.black.withOpacity(0.15));

    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withOpacity(medal != null ? 0.2 : 1),
        shape: BoxShape.circle,
        border: medal != null ? Border.all(color: medal, width: 1.5) : null,
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: medal ?? (isDark ? Colors.white54 : Colors.black45),
        ),
      ),
    );
  }
}

// --- Shared helpers ---

Decoration _cardDecoration(bool isDark) => BoxDecoration(
  // Opaque surfaces: translucent fills previously blended against the
  // animated background every frame; solid colors rasterize once and cache.
  color: isDark ? const Color(0xFF1D1D1D) : Colors.white,
  borderRadius: BorderRadius.circular(22),
  border: Border.all(
    color: isDark ? Colors.white12 : Colors.black.withOpacity(0.06),
  ),
  boxShadow: isDark
      ? null
      : [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
);

Color accentFor(bool isDark) =>
    isDark ? const Color(0xFFE84545) : const Color(0xFF0066CC);

Widget _chartEmptyLabel(bool isDark, String text) => Center(
  child: Text(
    text,
    style: TextStyle(
      fontSize: 12.5,
      color: isDark ? Colors.white38 : Colors.black38,
    ),
  ),
);
