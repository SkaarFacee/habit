/// Shared tracker stats used by the dashboard, widget sync and heatmap
/// rendering.
///
/// Mirrors the dashboard's existing streak semantics: a day counts as part of
/// the *current* streak if the most recent activity was today OR yesterday.
library;

/// Aggregated stats derived from a Firestore `Tracker` map.
class AppStats {
  const AppStats({
    required this.workDays,
    required this.totalTasks,
    required this.thisWeek,
    required this.currentStreak,
    required this.bestStreak,
    required this.todayTasks,
    required this.lastActiveDaysAgo,
  });

  final int workDays;
  final int totalTasks;
  final int thisWeek;
  final int currentStreak;
  final int bestStreak;
  final int todayTasks;

  /// Days since the most recent active day, or `null` when there has never
  /// been any activity.
  final int? lastActiveDaysAgo;
}

/// Parses `dd-MM-yyyy` (leading zeros allowed) into a date-only `DateTime`.
/// Returns `null` for malformed strings.
DateTime? parseDayOnly(String dateStr) {
  final parts = dateStr.split('-');
  if (parts.length != 3) return null;
  try {
    return DateTime(
      int.parse(parts[2]),
      int.parse(parts[1]),
      int.parse(parts[0]),
    );
  } catch (_) {
    return null;
  }
}

/// Daily task counts (date-only keys) across every tracked list.
///
/// Used by the widget heatmap and dashboard rendering; malformed dates are
/// skipped, mirroring `computeAppStats`.
Map<DateTime, int> dailyTaskCounts(Map<String, dynamic> tracker) {
  final counts = <DateTime, int>{};

  tracker.forEach((listName, listData) {
    if (listData is! Map<String, dynamic>) return;
    listData.forEach((dateStr, activities) {
      if (activities is! List || activities.isEmpty) return;
      final date = parseDayOnly(dateStr);
      if (date == null) return;

      final day = DateTime(date.year, date.month, date.day);
      counts[day] = (counts[day] ?? 0) + activities.length;
    });
  });

  return counts;
}

/// Computes stats from the inner tracker map `{list: {date: [...]}}`.
///
/// Pass `firestoreDoc['Tracker']` — not the whole Firestore document.
///
/// `now` is injectable for tests. Malformed dates are skipped (same tolerance
/// as the previous dashboard implementation).
AppStats computeAppStats(Map<String, dynamic> tracker, {DateTime? now}) {
  final nowDate = now ?? DateTime.now();
  final today = DateTime(nowDate.year, nowDate.month, nowDate.day);
  final weekStartRaw = nowDate.subtract(Duration(days: nowDate.weekday - 1));
  final weekStart = DateTime(weekStartRaw.year, weekStartRaw.month, weekStartRaw.day);

  int totalTasks = 0;
  int thisWeekTasks = 0;
  int todayTasks = 0;
  final Set<DateTime> workDays = {};

  tracker.forEach((listName, listData) {
    if (listData is! Map<String, dynamic>) return;
    listData.forEach((dateStr, activities) {
      if (activities is! List || activities.isEmpty) return;
      final date = parseDayOnly(dateStr);
      if (date == null) return;

      workDays.add(date);
      totalTasks += activities.length;
      if (!date.isBefore(weekStart)) {
        thisWeekTasks += activities.length;
      }
      if (date.isAtSameMomentAs(today)) {
        todayTasks += activities.length;
      }
    });
  });

  final sortedDays = workDays.toList()..sort((a, b) => b.compareTo(a));

  int currentStreak = 0;
  int bestStreak = 0;
  if (sortedDays.isNotEmpty) {
    final yesterday = today.subtract(const Duration(days: 1));
    if (sortedDays.first.isAtSameMomentAs(today) ||
        sortedDays.first.isAtSameMomentAs(yesterday)) {
      currentStreak = 1;
      for (int i = 0; i < sortedDays.length - 1; i++) {
        if (sortedDays[i].difference(sortedDays[i + 1]).inDays == 1) {
          currentStreak++;
        } else {
          break;
        }
      }
    }

    int chain = 1;
    bestStreak = 1;
    for (int i = 0; i < sortedDays.length - 1; i++) {
      if (sortedDays[i].difference(sortedDays[i + 1]).inDays == 1) {
        chain++;
        if (chain > bestStreak) bestStreak = chain;
      } else {
        chain = 1;
      }
    }
  }

  final int? lastActiveDaysAgo;
  if (sortedDays.isEmpty) {
    lastActiveDaysAgo = null;
  } else {
    lastActiveDaysAgo = today.difference(sortedDays.first).inDays;
  }

  return AppStats(
    workDays: workDays.length,
    totalTasks: totalTasks,
    thisWeek: thisWeekTasks,
    currentStreak: currentStreak,
    bestStreak: bestStreak,
    todayTasks: todayTasks,
    lastActiveDaysAgo: lastActiveDaysAgo,
  );
}