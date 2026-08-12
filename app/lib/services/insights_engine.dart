import 'dart:math' as math;

import 'stats.dart';

/// Range selector for the insights dashboard.
enum InsightsRange { week, month, all }

/// Pure-Dart aggregation for the insights dashboard.
///
/// Input is the inner Firestore tracker map `{list: {'dd-MM-yyyy': [...]}}`.
/// Streaks are global (not range-scoped); everything else is computed over
/// the selected window and the equal-length window immediately before it.
///
/// All date math runs on UTC day numbers (fixed 24h days) because local
/// `Duration` arithmetic drifts across DST transitions.
class InsightsReport {
  const InsightsReport({
    required this.range,
    required this.rangeLabel,
    required this.rangeStart,
    required this.rangeEnd,
    required this.totalTasks,
    required this.activeDays,
    required this.currentStreak,
    required this.bestStreak,
    required this.thisPeriod,
    required this.previousPeriod,
    required this.dailyCounts,
    required this.weeklyCounts,
    required this.categoryCounts,
    required this.difficultyCounts,
    required this.weekdayHistogram,
    required this.topTasks,
  });

  final InsightsRange range;
  final String rangeLabel;
  final DateTime rangeStart;
  final DateTime rangeEnd;

  final int totalTasks;
  final int activeDays;
  final int currentStreak;
  final int bestStreak;

  /// Tasks within the selected window.
  final int thisPeriod;

  /// Tasks in the equal-length window right before it.
  final int previousPeriod;

  /// Per-day counts within the window (week/month); per-week buckets for
  /// [InsightsRange.all]. Keys are local-midnight dates.
  final List<({DateTime day, int count})> dailyCounts;

  /// Per-week buckets covering the whole history (all-range chart).
  final List<({DateTime weekStart, int count})> weeklyCounts;

  final Map<String, int> categoryCounts;
  final Map<String, int> difficultyCounts;

  /// Monday-first counts of tasks per weekday inside the window.
  final List<int> weekdayHistogram;

  final List<({String title, int count})> topTasks;

  bool get isEmpty => totalTasks == 0;

  int get delta => thisPeriod - previousPeriod;
}

/// Fixed-length window in days per range (All uses full history).
int _windowDays(InsightsRange range) {
  switch (range) {
    case InsightsRange.week:
      return 7;
    case InsightsRange.month:
      return 28;
    case InsightsRange.all:
      return 0;
  }
}

int _dayNum(int year, int month, int day) =>
    DateTime.utc(year, month, day).millisecondsSinceEpoch ~/ 86400000;

/// Rebuilds a local-midnight date from a canonical day number.
DateTime _dateFromNum(int n) {
  final utc = DateTime.fromMillisecondsSinceEpoch(n * 86400000, isUtc: true);
  return DateTime(utc.year, utc.month, utc.day);
}

/// Computes the [InsightsReport] for [tracker] (the `Tracker` map) at [range].
/// `now` is injectable for tests.
InsightsReport computeInsights(
  Map<String, dynamic> tracker, {
  required InsightsRange range,
  DateTime? now,
}) {
  final nowDate = now ?? DateTime.now();
  final todayNum = _dayNum(nowDate.year, nowDate.month, nowDate.day);

  // Full history flattened to day-number -> count, plus rolling tallies.
  final perDay = <int, int>{};
  final categories = <String, int>{};
  final difficulties = <String, int>{};
  final titles = <String, int>{};

  tracker.forEach((_, listData) {
    if (listData is! Map<String, dynamic>) return;
    listData.forEach((dateStr, activities) {
      if (activities is! List || activities.isEmpty) return;
      final date = parseDayOnly(dateStr);
      if (date == null) return;
      final num = _dayNum(date.year, date.month, date.day);
      perDay[num] = (perDay[num] ?? 0) + activities.length;

      for (final activity in activities) {
        if (activity is! Map<String, dynamic>) continue;
        final category = activity['category']?.toString();
        if (category != null && category.isNotEmpty) {
          categories[category] = (categories[category] ?? 0) + 1;
        }
        final difficulty = activity['difficulty']?.toString().toUpperCase();
        if (difficulty != null && difficulty.isNotEmpty) {
          difficulties[difficulty] = (difficulties[difficulty] ?? 0) + 1;
        }
        final title = activity['title']?.toString();
        if (title != null && title.isNotEmpty) {
          titles[title] = (titles[title] ?? 0) + 1;
        }
      }
    });
  });

  // Global streaks on consecutive day numbers (same semantics as
  // computeAppStats: yesterday keeps the streak alive).
  int currentStreak = 0;
  int bestStreak = 0;
  final sortedNums = perDay.keys.toList()..sort((a, b) => b.compareTo(a));
  if (sortedNums.isNotEmpty) {
    if (sortedNums.first == todayNum ||
        sortedNums.first == todayNum - 1) {
      currentStreak = 1;
      for (int i = 0; i < sortedNums.length - 1; i++) {
        if (sortedNums[i] - sortedNums[i + 1] == 1) {
          currentStreak++;
        } else {
          break;
        }
      }
    }
    int chain = 1;
    bestStreak = 1;
    for (int i = 0; i < sortedNums.length - 1; i++) {
      if (sortedNums[i] - sortedNums[i + 1] == 1) {
        chain++;
        if (chain > bestStreak) bestStreak = chain;
      } else {
        chain = 1;
      }
    }
  }

  // Window bounds as day numbers. Week = calendar week (Mon–Sun) containing
  // today; Month = rolling 28 days ending today.
  final days = _windowDays(range);
  late int startNum;
  late int endNum;
  late int prevStartNum;
  final weekdayMonIndex = nowDate.weekday - 1; // Mon=0 .. Sun=6
  if (range == InsightsRange.all) {
    startNum = _dayNum(2000, 1, 1);
    endNum = todayNum;
    prevStartNum = startNum;
  } else if (range == InsightsRange.week) {
    startNum = todayNum - weekdayMonIndex;
    endNum = startNum + days - 1;
    prevStartNum = startNum - days;
  } else {
    endNum = todayNum;
    startNum = todayNum - (days - 1);
    prevStartNum = startNum - days;
  }

  int thisPeriod = 0;
  int previousPeriod = 0;
  int activeDays = 0;
  final weekdayHistogram = List<int>.filled(7, 0);

  final orderedNums = perDay.keys.toList()..sort((a, b) => a.compareTo(b));
  for (final num in orderedNums) {
    final count = perDay[num]!;
    if (num >= startNum && num <= endNum) {
      thisPeriod += count;
      activeDays++;
      final weekday = _dateFromNum(num).weekday; // Mon=1..Sun=7
      weekdayHistogram[weekday - 1] += count;
    }
    if (num >= prevStartNum && num < startNum) {
      previousPeriod += count;
    }
  }

  // Per-week buckets (Monday-aligned) for the All chart.
  final weekly = <({DateTime weekStart, int count})>[];
  if (range == InsightsRange.all && orderedNums.isNotEmpty) {
    final firstNum = orderedNums.first;
    final firstWeekday = _dateFromNum(firstNum).weekday; // Mon=1..Sun=7
    var weekNum = firstNum - (firstWeekday - 1);
    while (weekNum <= todayNum) {
      final weekEnd = weekNum + 6;
      int sum = 0;
      for (final num in orderedNums) {
        if (num >= weekNum && num <= weekEnd) sum += perDay[num]!;
      }
      weekly.add((weekStart: _dateFromNum(weekNum), count: sum));
      weekNum += 7;
    }
    // Trim leading all-zero weeks for a tighter chart.
    while (weekly.length > 1 && weekly.first.count == 0) {
      weekly.removeAt(0);
    }
  }

  // Sparse day list -> dense per-day series (gaps = 0) for week/month charts.
  final denseDaily = <({DateTime day, int count})>[];
  if (range != InsightsRange.all) {
    for (var num = startNum; num <= endNum; num++) {
      denseDaily.add((day: _dateFromNum(num), count: perDay[num] ?? 0));
    }
  }

  final topTasks = (titles.entries.toList()
        ..sort((a, b) {
          final byCount = b.value.compareTo(a.value);
          if (byCount != 0) return byCount;
          return a.key.toLowerCase().compareTo(b.key.toLowerCase());
        }))
      .take(5)
      .map((e) => (title: e.key, count: e.value))
      .toList();

  return InsightsReport(
    range: range,
    rangeLabel: _labelFor(range, _dateFromNum(startNum), _dateFromNum(endNum)),
    rangeStart: _dateFromNum(startNum),
    rangeEnd: _dateFromNum(endNum),
    totalTasks: perDay.values.fold(0, (a, b) => a + b),
    activeDays: activeDays,
    currentStreak: currentStreak,
    bestStreak: bestStreak,
    thisPeriod: thisPeriod,
    previousPeriod: previousPeriod,
    dailyCounts:
        range == InsightsRange.all ? weeklyToDaily(weekly) : denseDaily,
    weeklyCounts: weekly,
    categoryCounts: categories,
    difficultyCounts: difficulties,
    weekdayHistogram: weekdayHistogram,
    topTasks: topTasks,
  );
}

/// Adapts weekly buckets into the daily-count shape (day = week start) so the
/// chart can consume one type for all ranges.
List<({DateTime day, int count})> weeklyToDaily(
  List<({DateTime weekStart, int count})> weekly,
) {
  return weekly.map((w) => (day: w.weekStart, count: w.count)).toList();
}

String _labelFor(InsightsRange range, DateTime start, DateTime end) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  switch (range) {
    case InsightsRange.week:
    case InsightsRange.month:
      return '${months[start.month - 1]} ${start.day} – ${months[end.month - 1]} ${end.day}';
    case InsightsRange.all:
      return 'All time';
  }
}

/// Trend helper for delta chips.
String deltaLabel(int delta) {
  if (delta > 0) return '+$delta';
  return '$delta';
}

/// Peak weekday index (Mon-first) with a nonzero count, or null when flat.
int? peakWeekday(List<int> histogram) {
  final maxVal = histogram.fold(0, math.max);
  if (maxVal == 0) return null;
  return histogram.indexOf(maxVal);
}
