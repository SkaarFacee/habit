import 'package:flutter/material.dart';

import 'shared/neon_ribbon_background.dart';

class HabitTaskEntry {
  final DateTime date;
  final String title;
  final String category;
  final String difficulty;
  final String habit;

  const HabitTaskEntry({
    required this.date,
    required this.title,
    required this.category,
    required this.difficulty,
    required this.habit,
  });

  String get formattedDate {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day-$month-$year';
  }
}

class HabitDetailsScreen extends StatelessWidget {
  final String habit;
  final List<HabitTaskEntry> entries;
  final Map<DateTime, int> dates;
  final bool isFavorite;

  const HabitDetailsScreen({
    super.key,
    required this.habit,
    required this.entries,
    required this.dates,
    required this.isFavorite,
  });

  int get _totalOccurrences => entries.length;

  int get _activeDays => dates.keys.length;

  int get _streak {
    if (dates.isEmpty) return 0;

    final normalized = dates.keys
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet();

    final today = DateTime.now();
    var cursor = DateTime(today.year, today.month, today.day);
    var streak = 0;

    while (normalized.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return streak;
  }

  Map<String, int> get _categoryBreakdown {
    final map = <String, int>{};
    for (final entry in entries) {
      map[entry.category] = (map[entry.category] ?? 0) + 1;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF15171C) : Colors.white;
    final topCategories = _categoryBreakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Habit Details'),
      ),
      body: Stack(
        children: [
          const RepaintBoundary(
            child: NeonRibbonBackground(),
          ),
          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: RepaintBoundary(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: cardColor.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: isDark
                                ? Colors.white12
                                : Colors.black.withOpacity(0.05),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isDark
                                  ? Colors.black.withOpacity(0.16)
                                  : Colors.black.withOpacity(0.045),
                              blurRadius: 12,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isFavorite)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFFFFD54F).withOpacity(0.14)
                                      : const Color(0xFFFFF3CD),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 14,
                                      color: Color(0xFFF59E0B),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Favorite Habit',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFFF59E0B),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            if (isFavorite) const SizedBox(height: 12),
                            Text(
                              habit,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'A complete view of this habit, including the activity heatmap and task history.',
                              style:
                                  Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.65),
                                      ),
                            ),
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                InfoChip(
                                  icon: Icons.check_circle_outline_rounded,
                                  label: '$_totalOccurrences tasks',
                                  isDark: isDark,
                                ),
                                InfoChip(
                                  icon: Icons.calendar_today_rounded,
                                  label: '$_activeDays active days',
                                  isDark: isDark,
                                ),
                                InfoChip(
                                  icon: Icons.local_fire_department_rounded,
                                  label: '$_streak day streak',
                                  isDark: isDark,
                                ),
                              ],
                            ),
                            if (topCategories.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: topCategories
                                    .take(3)
                                    .map(
                                      (e) => _CategoryChip(
                                        label: '${e.key} · ${e.value}',
                                        isDark: isDark,
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                            ],
                            const SizedBox(height: 18),
                            HabitHeatmap(
                              dates: dates,
                              isDark: isDark,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                    child: Row(
                      children: [
                        Text(
                          'Task History',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${entries.length}',
                          style: TextStyle(
                            color: isDark ? Colors.white54 : Colors.black45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (entries.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No tasks logged for this habit yet.',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.65),
                              ),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final entry = entries[index];
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: index == entries.length - 1 ? 0 : 10,
                            ),
                            child: _HabitTaskTile(
                              entry: entry,
                            ),
                          );
                        },
                        childCount: entries.length,
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
}

class HabitHeatmap extends StatelessWidget {
  final Map<DateTime, int> dates;
  final bool isDark;

  const HabitHeatmap({
    super.key,
    required this.dates,
    required this.isDark,
  });

  static const double _cell = 10;
  static const double _gap = 3;
  static const int _rows = 7;
  static const double _monthLabelHeight = 16;
  static const double _monthLabelGap = 6;

  Color _colorForCount(int count) {
    if (count <= 0) {
      return isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFE9EDF3);
    }

    if (isDark) {
      if (count == 1) return const Color(0xFF1D7AFC).withOpacity(0.45);
      if (count == 2) return const Color(0xFF1D7AFC).withOpacity(0.65);
      if (count == 3) return const Color(0xFF1D7AFC).withOpacity(0.82);
      return const Color(0xFF63A4FF);
    }

    if (count == 1) return const Color(0xFFD6E8FF);
    if (count == 2) return const Color(0xFFA9CEFF);
    if (count == 3) return const Color(0xFF6FAEFF);
    return const Color(0xFF1D7AFC);
  }

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final firstVisibleDay = today.subtract(const Duration(days: 364));
    final gridStart =
        firstVisibleDay.subtract(Duration(days: firstVisibleDay.weekday % 7));
    final totalDays = today.difference(gridStart).inDays + 1;
    final totalWeeks = (totalDays / 7).ceil();

    final columnWidth = _cell + _gap;
    final contentWidth = totalWeeks * columnWidth;
    final gridHeight = (_rows * (_cell + _gap)) - _gap;
    final chartHeight = _monthLabelHeight + _monthLabelGap + gridHeight;

    final normalizedDates = <DateTime, int>{};
    dates.forEach((key, value) {
      normalizedDates[DateUtils.dateOnly(key)] = value;
    });

    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.04)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              physics: const BouncingScrollPhysics(),
              child: SizedBox(
                width: contentWidth,
                height: chartHeight,
                child: CustomPaint(
                  painter: _HeatmapPainter(
                    dateCounts: normalizedDates,
                    isDark: isDark,
                    today: today,
                    firstVisibleDay: firstVisibleDay,
                    gridStart: gridStart,
                    totalWeeks: totalWeeks,
                    cell: _cell,
                    gap: _gap,
                    rows: _rows,
                    monthLabelHeight: _monthLabelHeight,
                    monthLabelGap: _monthLabelGap,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Less',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                for (int i = 0; i < 5; i++)
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _colorForCount(i),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                Text(
                  'More',
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
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  final Map<DateTime, int> dateCounts;
  final bool isDark;
  final DateTime today;
  final DateTime firstVisibleDay;
  final DateTime gridStart;
  final int totalWeeks;
  final double cell;
  final double gap;
  final int rows;
  final double monthLabelHeight;
  final double monthLabelGap;

  const _HeatmapPainter({
    required this.dateCounts,
    required this.isDark,
    required this.today,
    required this.firstVisibleDay,
    required this.gridStart,
    required this.totalWeeks,
    required this.cell,
    required this.gap,
    required this.rows,
    required this.monthLabelHeight,
    required this.monthLabelGap,
  });

  static const List<String> _months = [
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
    'Dec',
  ];

  Color _colorForCount(int count) {
    if (count <= 0) {
      return isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFE9EDF3);
    }

    if (isDark) {
      if (count == 1) return const Color(0xFF1D7AFC).withOpacity(0.45);
      if (count == 2) return const Color(0xFF1D7AFC).withOpacity(0.65);
      if (count == 3) return const Color(0xFF1D7AFC).withOpacity(0.82);
      return const Color(0xFF63A4FF);
    }

    if (count == 1) return const Color(0xFFD6E8FF);
    if (count == 2) return const Color(0xFFA9CEFF);
    if (count == 3) return const Color(0xFF6FAEFF);
    return const Color(0xFF1D7AFC);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final columnWidth = cell + gap;
    final gridTop = monthLabelHeight + monthLabelGap;
    final textStyle = TextStyle(
      fontSize: 10,
      color: isDark ? Colors.white54 : Colors.black54,
      fontWeight: FontWeight.w500,
    );

    final paint = Paint()..style = PaintingStyle.fill;

    for (int weekIndex = 0; weekIndex < totalWeeks; weekIndex++) {
      final weekDate = gridStart.add(Duration(days: weekIndex * 7));
      final previousWeekDate =
          weekIndex == 0 ? null : gridStart.add(Duration(days: (weekIndex - 1) * 7));

      final showLabel = weekIndex == 0 ||
          (previousWeekDate != null && weekDate.month != previousWeekDate.month);

      if (showLabel) {
        final tp = TextPainter(
          text: TextSpan(
            text: _months[weekDate.month - 1],
            style: textStyle,
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout(maxWidth: columnWidth + 20);

        tp.paint(canvas, Offset(weekIndex * columnWidth, 0));
      }

      for (int dayIndex = 0; dayIndex < rows; dayIndex++) {
        final date = gridStart.add(Duration(days: weekIndex * 7 + dayIndex));
        final isOutsideRange =
            date.isBefore(firstVisibleDay) || date.isAfter(today);

        if (isOutsideRange) continue;

        final count = dateCounts[date] ?? 0;
        paint.color = _colorForCount(count);

        final rect = Rect.fromLTWH(
          weekIndex * columnWidth,
          gridTop + dayIndex * (cell + gap),
          cell,
          cell,
        );

        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter oldDelegate) {
    return oldDelegate.dateCounts != dateCounts ||
        oldDelegate.isDark != isDark ||
        oldDelegate.today != today ||
        oldDelegate.firstVisibleDay != firstVisibleDay ||
        oldDelegate.gridStart != gridStart ||
        oldDelegate.totalWeeks != totalWeeks;
  }
}

class _HabitTaskTile extends StatelessWidget {
  final HabitTaskEntry entry;

  const _HabitTaskTile({
    required this.entry,
  });

  Color _difficultyColor(String difficulty) {
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

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Health':
        return Icons.favorite_outline_rounded;
      case 'Work':
        return Icons.work_outline_rounded;
      case 'Play':
        return Icons.sports_esports_outlined;
      default:
        return Icons.check_circle_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
              (isDark ? const Color(0xFF15171C) : Colors.white).withOpacity(0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withOpacity(0.14)
                  : Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _difficultyColor(entry.difficulty).withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _categoryIcon(entry.category),
                color: _difficultyColor(entry.difficulty),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _TinyMetaChip(
                        icon: Icons.event_outlined,
                        label: entry.formattedDate,
                      ),
                      _TinyMetaChip(
                        icon: Icons.category_outlined,
                        label: entry.category,
                      ),
                      _TinyMetaChip(
                        icon: Icons.bolt_outlined,
                        label: entry.difficulty.toUpperCase(),
                        color: _difficultyColor(entry.difficulty),
                      ),
                    ],
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

class _TinyMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _TinyMetaChip({
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = color ?? (isDark ? Colors.white60 : Colors.black54);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.06)
            : const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isDark;

  const _CategoryChip({
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.06)
            : const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white70 : Colors.black87,
        ),
      ),
    );
  }
}

class InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;

  const InfoChip({
    super.key,
    required this.icon,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF15171C).withOpacity(0.92)
            : Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}