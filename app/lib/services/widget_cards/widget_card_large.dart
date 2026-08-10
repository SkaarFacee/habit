import 'package:flutter/material.dart';

import '../stats.dart';
import 'widget_card_style.dart';

/// Expanded 4x4 home-screen widget card (320x320 logical pixels).
///
/// Header stat grid, a ~40-week heatmap and a last-7-days mini bar row.
class WidgetCardLarge extends StatelessWidget {
  final Map<DateTime, int> counts;
  final AppStats stats;
  final bool isDark;

  const WidgetCardLarge({
    super.key,
    required this.counts,
    required this.stats,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final windowStart = today.subtract(const Duration(days: 279));
    final gridStart = windowStart.subtract(
      Duration(days: windowStart.weekday % 7),
    );
    final totalDays = today.difference(gridStart).inDays + 1;
    final cols = (totalDays / 7).ceil();

    const gap = 1.6;
    const sidePadding = 14.0;
    final cell = (320 - sidePadding * 2) / cols - gap;
    final pitch = cell + gap;
    const labelHeight = 12.0;
    final gridWidth = cols * pitch;

    final normalized = <DateTime, int>{};
    counts.forEach((key, value) {
      normalized[DateTime(key.year, key.month, key.day)] = value;
    });

    final labelCols = <int>[];
    final labelTexts = <String>[];
    int? lastMonth;
    for (int c = 0; c < cols; c++) {
      final date = gridStart.add(Duration(days: c * 7));
      if (lastMonth == null || date.month != lastMonth) {
        labelCols.add(c);
        labelTexts.add(WidgetCardStyle.months[date.month - 1]);
      }
      lastMonth = date.month;
    }

    final last7 = <(DateTime, int)>[];
    for (int i = 6; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      last7.add((day, normalized[DateTime(day.year, day.month, day.day)] ?? 0));
    }
    final last7Max = last7.fold(1, (max, e) => e.$2 > max ? e.$2 : max);

    return Container(
      width: 320,
      height: 320,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WidgetCardStyle.background(isDark),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _headerStat(
                  'CURRENT STREAK',
                  '${stats.currentStreak}',
                  flame: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _headerStat('BEST STREAK', '${stats.bestStreak}'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _headerStat('ACTIVE DAYS', '${stats.workDays}')),
              const SizedBox(width: 6),
              Expanded(child: _headerStat('TODAY', '${stats.todayTasks}')),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: WidgetCardStyle.hairline(isDark)),
          const SizedBox(height: 10),
          SizedBox(
            height: labelHeight,
            width: gridWidth,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (int i = 0; i < labelCols.length; i++)
                  Positioned(
                    left: labelCols[i] * pitch,
                    top: 0,
                    child: Text(
                      labelTexts[i],
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: WidgetCardStyle.subtle(isDark),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: gridWidth,
            height: 7 * pitch,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int c = 0; c < cols; c++)
                  SizedBox(
                    width: pitch,
                    height: 7 * pitch,
                    child: Column(
                      children: [
                        for (int d = 0; d < 7; d++)
                          SizedBox(
                            width: pitch,
                            height: pitch,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                right: gap,
                                bottom: gap,
                              ),
                              child: _buildCell(
                                gridStart.add(Duration(days: c * 7 + d)),
                                today,
                                windowStart,
                                normalized,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('LAST 7 DAYS', style: WidgetCardStyle.label(isDark)),
          const SizedBox(height: 6),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (day, count) in last7)
                  Expanded(child: _last7Bar(day, count, last7Max)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerStat(String label, String value, {bool flame = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: WidgetCardStyle.label(isDark, size: 8),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              if (flame) ...[
                const Icon(
                  Icons.local_fire_department_rounded,
                  size: 15,
                  color: WidgetCardStyle.flame,
                ),
                const SizedBox(width: 3),
              ],
              Text(value, style: WidgetCardStyle.value(isDark, size: 17)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _last7Bar(DateTime day, int count, int max) {
    final weekdayLetter = 'MTWTFSS'[(day.weekday - 1) % 7];
    final accent = count > 0
        ? const Color(0xFF1D7AFC)
        : WidgetCardStyle.subtle(isDark);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: Text(
              count > 0 ? '$count' : '',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                widthFactor: 1,
                heightFactor: count == 0 ? 0.0 : (count / max).clamp(0.12, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: count > 0
                        ? const Color(
                            0xFF1D7AFC,
                          ).withOpacity(count >= max ? 1 : 0.5)
                        : WidgetCardStyle.colorForCount(0, isDark),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            weekdayLetter,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: WidgetCardStyle.subtle(isDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCell(
    DateTime day,
    DateTime today,
    DateTime windowStart,
    Map<DateTime, int> normalized,
  ) {
    if (day.isBefore(windowStart) || day.isAfter(today)) {
      return const SizedBox.shrink();
    }

    final normalizedDay = DateTime(day.year, day.month, day.day);
    final count = normalized[normalizedDay] ?? 0;
    return Container(
      decoration: BoxDecoration(
        color: WidgetCardStyle.colorForCount(count, isDark),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
