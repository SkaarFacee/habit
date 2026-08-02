// Pure unit tests for the insights engine (no Flutter imports, no plugins).

import 'package:flutter_test/flutter_test.dart';

import 'package:TrackIt/services/insights_engine.dart';

Map<String, dynamic> _entry({
  String category = 'Work',
  String difficulty = 'EASY',
  String title = 'Task',
}) => <String, dynamic>{
  'category': category,
  'difficulty': difficulty,
  'title': title,
};

void main() {
  group('computeInsights — week range', () {
    // 2026-08-10 is a Monday. "now" is Monday 2026-08-10.
    final now = DateTime(2026, 8, 10);

    test('empty tracker yields an empty report with zero streaks', () {
      final report = computeInsights(
        <String, dynamic>{},
        range: InsightsRange.week,
        now: now,
      );

      expect(report.isEmpty, isTrue);
      expect(report.totalTasks, 0);
      expect(report.activeDays, 0);
      expect(report.currentStreak, 0);
      expect(report.bestStreak, 0);
      expect(report.thisPeriod, 0);
      expect(report.previousPeriod, 0);
      expect(report.delta, 0);
      expect(report.dailyCounts, hasLength(7));
      expect(report.dailyCounts.every((d) => d.count == 0), isTrue);
    });

    test('sums tasks and skips malformed dates', () {
      final tracker = <String, dynamic>{
        'Work': <String, dynamic>{
          '10-08-2026': [_entry(), _entry()],
          'not-a-date': [_entry()],
        },
      };

      final report = computeInsights(
        tracker,
        range: InsightsRange.week,
        now: now,
      );

      expect(report.thisPeriod, 2);
      expect(report.activeDays, 1);
      expect(report.totalTasks, 2);
    });

    test('Monday-aligned window and dense daily series', () {
      final tracker = <String, dynamic>{
        'Work': <String, dynamic>{
          // Previous week (Mon 03-08 .. Sun 09-08).
          '04-08-2026': [_entry()],
          // Current week (Mon 10-08 .. Sun 16-08).
          '10-08-2026': [_entry(), _entry()],
          '12-08-2026': [_entry()],
        },
      };

      final report = computeInsights(
        tracker,
        range: InsightsRange.week,
        now: now,
      );

      // Monday-aligned: starts at 2026-08-10.
      expect(report.rangeStart, DateTime(2026, 8, 10));
      expect(report.rangeEnd, DateTime(2026, 8, 16));

      // Dense 7-day series with a zero-gap day at 11-08.
      expect(report.dailyCounts, hasLength(7));
      expect(report.dailyCounts[0].day, DateTime(2026, 8, 10));
      expect(report.dailyCounts[0].count, 2);
      expect(report.dailyCounts[1].count, 0);
      expect(report.dailyCounts[2].count, 1);

      expect(report.thisPeriod, 3);
      expect(report.previousPeriod, 1);
      expect(report.delta, 2);
    });

    test('current streak requires today or yesterday activity', () {
      final tracker = <String, dynamic>{
        'Work': <String, dynamic>{
          // Streak chain 06,07,08 then nothing on 09/10.
          '06-08-2026': [_entry()],
          '07-08-2026': [_entry()],
          '08-08-2026': [_entry()],
        },
      };

      final report = computeInsights(
        tracker,
        range: InsightsRange.week,
        now: now,
      );

      expect(report.currentStreak, 0);
      expect(report.bestStreak, 3);
    });

    test('yesterday keeps the current streak alive', () {
      final tracker = <String, dynamic>{
        'Work': <String, dynamic>{
          '09-08-2026': [_entry()],
          '10-08-2026': [_entry()],
        },
      };

      final report = computeInsights(
        tracker,
        range: InsightsRange.week,
        now: now,
      );

      expect(report.currentStreak, 2);
    });
  });

  group('computeInsights — month range', () {
    final now = DateTime(2026, 8, 10);

    test('uses a 28-day window with equal-length comparison', () {
      final tracker = <String, dynamic>{
        'Work': <String, dynamic>{
          '10-08-2026': [_entry(), _entry()], // inside
          '05-08-2026': [_entry()], // inside
          '12-07-2026': [_entry(), _entry(), _entry()], // previous window
          '01-06-2026': [_entry()], // outside both
        },
      };

      final report = computeInsights(
        tracker,
        range: InsightsRange.month,
        now: now,
      );

      expect(report.dailyCounts, hasLength(28));
      expect(report.thisPeriod, 3);

      // Previous window: 13-07-2026 .. 09-08-2026.
      expect(report.previousPeriod, 3);
      expect(report.delta, 0);
    });
  });

  group('computeInsights — all range', () {
    test('weekly buckets count all history and trim leading zeros', () {
      final tracker = <String, dynamic>{
        'Work': <String, dynamic>{
          // Week of Mon 2026-08-03.
          '04-08-2026': [_entry(), _entry()],
          // Week of Mon 2026-08-10.
          '11-08-2026': [_entry()],
          // Ancient week (should be trimmed away as leading zero).
          '02-01-2026': [_entry()],
        },
      };

      final report = computeInsights(
        tracker,
        range: InsightsRange.all,
        now: DateTime(2026, 8, 12),
      );

      expect(report.totalTasks, 4);
      expect(report.weeklyCounts, isNotEmpty);
      // Buckets are Monday-aligned.
      expect(report.weeklyCounts.first.weekStart.weekday, DateTime.monday);
      expect(report.weeklyCounts.last.weekStart, DateTime(2026, 8, 10));

      // Leading all-zero buckets were trimmed, but the January bucket
      // (count 1) remains so no data is lost.
      final januaryBucket = report.weeklyCounts.firstWhere(
        (w) => w.weekStart.isBefore(DateTime(2026, 1, 5)),
      );
      expect(januaryBucket.count, 1);

      // Daily series mirrors weekly buckets for the chart.
      expect(report.dailyCounts, hasLength(report.weeklyCounts.length));
    });
  });

  group('computeInsights — aggregations', () {
    final now = DateTime(2026, 8, 10);

    test('category, difficulty and weekday histograms', () {
      final tracker = <String, dynamic>{
        'Work': <String, dynamic>{
          // Monday 2026-08-10.
          '10-08-2026': [
            _entry(category: 'Work', difficulty: 'EASY', title: 'Read'),
            _entry(category: 'Health', difficulty: 'HARD', title: 'Run'),
            _entry(category: 'Health', difficulty: 'EASY', title: 'Stretch'),
          ],
          // Tuesday 2026-08-11.
          '11-08-2026': [
            _entry(category: 'Play', difficulty: 'MEDIUM', title: 'Chess'),
          ],
        },
      };

      final report = computeInsights(
        tracker,
        range: InsightsRange.week,
        now: now,
      );

      expect(report.categoryCounts, {'Work': 1, 'Health': 2, 'Play': 1});
      expect(report.difficultyCounts, {'EASY': 2, 'MEDIUM': 1, 'HARD': 1});

      // Mon-first histogram: Mon 3, Tue 1, rest 0.
      expect(report.weekdayHistogram, [3, 1, 0, 0, 0, 0, 0]);
      expect(peakWeekday(report.weekdayHistogram), 0);
    });

    test('top tasks ranked by count with alphabetical tie-break', () {
      final tracker = <String, dynamic>{
        'Work': <String, dynamic>{
          '10-08-2026': [
            _entry(title: 'b-task'),
            _entry(title: 'a-task'),
            _entry(title: 'b-task'),
            _entry(title: 'c-task'),
            _entry(title: 'c-task'),
            _entry(title: 'c-task'),
          ],
        },
      };

      final report = computeInsights(
        tracker,
        range: InsightsRange.week,
        now: now,
      );

      expect(report.topTasks.map((t) => t.title).toList(), [
        'c-task',
        'b-task',
        'a-task',
      ]);
      expect(report.topTasks.first.count, 3);
    });

    test('top tasks capped at five', () {
      final tracker = <String, dynamic>{
        'Work': <String, dynamic>{
          '10-08-2026': [for (int i = 1; i <= 8; i++) _entry(title: 'task-$i')],
        },
      };

      final report = computeInsights(
        tracker,
        range: InsightsRange.week,
        now: now,
      );

      expect(report.topTasks, hasLength(5));
    });

    test('flat histogram has no peak weekday', () {
      expect(peakWeekday([0, 0, 0, 0, 0, 0, 0]), isNull);
    });
  });
}
