import 'package:flutter/material.dart';

import '../stats.dart';
import 'widget_card_style.dart';

/// The main contribution heatmap rendered as a static 4x2 card (320x160
/// logical pixels) for the Android home-screen widget.
///
/// Same visual language as the dashboard grid: trailing ~26 weeks (six
/// months), Sunday-aligned columns, month labels, GitHub-style intensity
/// colors. No interactions — this is rasterized into the widget PNG via
/// `HomeWidget.renderFlutterWidget`.
class WidgetHeatmapCard extends StatelessWidget {
  final Map<DateTime, int> counts;
  final AppStats stats;
  final bool isDark;

  const WidgetHeatmapCard({
    super.key,
    required this.counts,
    required this.stats,
    required this.isDark,
  });

  Color _colorForCount(int count) =>
      WidgetCardStyle.colorForCount(count, isDark);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final windowStart = today.subtract(const Duration(days: 181));
    final gridStart = windowStart.subtract(
      Duration(days: windowStart.weekday % 7),
    );
    final totalDays = today.difference(gridStart).inDays + 1;
    final cols = (totalDays / 7).ceil();

    const gap = 1.5;
    const sidePadding = 14.0;
    // Each cell occupies pitch = cell + gap (trailing gap included), so
    // cols * pitch must equal the available width exactly.
    final cell = (320 - sidePadding * 2) / cols - gap;
    final pitch = cell + gap;
    const labelHeight = 11.0;
    final gridWidth = cols * pitch;

    final normalized = <DateTime, int>{};
    counts.forEach((key, value) {
      normalized[DateTime(key.year, key.month, key.day)] = value;
    });

    // Month labels: first week of every month within the window.
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

    final background = WidgetCardStyle.background(isDark);

    return Container(
      width: 320,
      height: 160,
      padding: const EdgeInsets.fromLTRB(sidePadding, 10, sidePadding, 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CURRENT STREAK', style: WidgetCardStyle.label(isDark)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.local_fire_department_rounded,
                        size: 15,
                        color: WidgetCardStyle.flame,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${stats.currentStreak}',
                        style: WidgetCardStyle.value(isDark),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('TASKS TODAY', style: WidgetCardStyle.label(isDark)),
                  const SizedBox(height: 2),
                  Text(
                    '${stats.todayTasks}',
                    style: WidgetCardStyle.value(isDark),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
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
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: WidgetCardStyle.subtle(isDark),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 3),
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
                                cell,
                              ),
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

  Widget _buildCell(
    DateTime day,
    DateTime today,
    DateTime windowStart,
    Map<DateTime, int> normalized,
    double size,
  ) {
    if (day.isBefore(windowStart) || day.isAfter(today)) {
      return SizedBox(width: size, height: size);
    }

    final normalizedDay = DateTime(day.year, day.month, day.day);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _colorForCount(normalized[normalizedDay] ?? 0),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
