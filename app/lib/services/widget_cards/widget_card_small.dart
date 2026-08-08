import 'package:flutter/material.dart';

import '../stats.dart';
import 'widget_card_style.dart';

/// Compact 2x2 home-screen widget card (~110x110 logical pixels).
///
/// Shows the current streak, today's count and a 14-day micro dot strip.
class WidgetCardSmall extends StatelessWidget {
  final Map<DateTime, int> counts;
  final AppStats stats;
  final bool isDark;

  const WidgetCardSmall({
    super.key,
    required this.counts,
    required this.stats,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final normalized = <DateTime, int>{};
    counts.forEach((key, value) {
      normalized[DateTime(key.year, key.month, key.day)] = value;
    });

    final last14 = <int>[];
    for (int i = 13; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      last14.add(normalized[day] ?? 0);
    }

    return Container(
      width: 110,
      height: 110,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: WidgetCardStyle.background(isDark),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.local_fire_department_rounded,
                size: 16,
                color: WidgetCardStyle.flame,
              ),
              const SizedBox(width: 3),
              Text(
                '${stats.currentStreak}',
                style: WidgetCardStyle.value(isDark, size: 22),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'TODAY',
                    style: WidgetCardStyle.label(isDark, size: 6.5),
                  ),
                  Text(
                    '${stats.todayTasks}',
                    style: WidgetCardStyle.value(isDark, size: 12),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                for (int row = 0; row < 2; row++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (int col = 0; col < 7; col++)
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: WidgetCardStyle.colorForCount(
                                last14[row * 7 + col],
                                isDark,
                              ),
                              borderRadius: BorderRadius.circular(3),
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
