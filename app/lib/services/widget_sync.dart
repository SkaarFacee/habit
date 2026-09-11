import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/theme.dart';
import 'stats.dart';
import 'widget_heatmap_card.dart';

/// Pushes the heatmap snapshot to the Android home-screen widget.
///
/// The widget displays the main contribution heatmap (trailing ~6 months,
/// GitHub-style) plus streak/today stats, rasterized into a PNG via
/// `HomeWidget.renderFlutterWidget`. All failures are swallowed on purpose:
/// a widget sync problem must never crash the app.
class WidgetSync {
  WidgetSync._();

  static const String _checksumKey = 'widget_checksum_v1';
  static const Duration _debounceDuration = Duration(milliseconds: 1500);

  /// Logical size the widget PNG is rendered at (matches the 4x2 cell grid).
  static const Size widgetLogicalSize = Size(320, 160);

  static Timer? _debounce;

  /// Coalesces Firestore bursts. Use `immediate: true` for user-invoked
  /// changes (save, theme toggle) that should hit the widget quickly.
  static void schedulePush({
    required AppStats stats,
    Map<DateTime, int> dailyCounts = const <DateTime, int>{},
    bool immediate = false,
  }) {
    if (immediate) {
      _debounce?.cancel();
      _debounce = null;
      unawaited(pushNow(stats: stats, dailyCounts: dailyCounts));
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      unawaited(pushNow(stats: stats, dailyCounts: dailyCounts));
    });
  }

  static Future<void> pushNow({
    required AppStats stats,
    Map<DateTime, int> dailyCounts = const <DateTime, int>{},
  }) async {
    try {
      final isDark = themeNotifier.value == ThemeMode.dark;
      final prefs = await SharedPreferences.getInstance();

      var totalTasks = 0;
      dailyCounts.forEach((_, count) => totalTasks += count);

      final checksum = jsonEncode(<String, Object?>{
        'best': stats.bestStreak,
        'cur': stats.currentStreak,
        'days': stats.workDays,
        'today': stats.todayTasks,
        'ago': stats.lastActiveDaysAgo,
        'dark': isDark,
        'cells': dailyCounts.length,
        'total': totalTasks,
      });
      if (prefs.getString(_checksumKey) == checksum) return;

      await _render(
        counts: dailyCounts,
        stats: stats,
        isDark: false,
        key: 'widget_image',
      );
      await _render(
        counts: dailyCounts,
        stats: stats,
        isDark: true,
        key: 'widget_image_dark',
      );

      final statsNext = <String, Object?>{
        'bestStreak': stats.bestStreak,
        'currentStreak': stats.currentStreak,
        'todayTasks': stats.todayTasks,
        'activeDays': stats.workDays,
        'lastActiveDaysAgo': stats.lastActiveDaysAgo,
      };
      await HomeWidget.saveWidgetData('widget_stats', jsonEncode(statsNext));

      await prefs.setString(_checksumKey, checksum);
      await HomeWidget.updateWidget(androidName: 'WidgetProvider');
    } catch (_) {
      // Swallow: widget sync must never break the app.
    }
  }

  static Future<String?> _render({
    required Map<DateTime, int> counts,
    required AppStats stats,
    required bool isDark,
    required String key,
  }) async {
    final card = SizedBox(
      width: widgetLogicalSize.width,
      height: widgetLogicalSize.height,
      child: WidgetHeatmapCard(
        counts: counts,
        stats: stats,
        isDark: isDark,
      ),
    );
    final path = await HomeWidget.renderFlutterWidget(
      card,
      key: key,
      logicalSize: widgetLogicalSize,
      pixelRatio: 3.0,
    );
    await HomeWidget.saveWidgetData(key, path);
    return path;
  }
}
