import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'stats.dart';
import 'widget_cards/widget_card_large.dart';
import 'widget_cards/widget_card_medium.dart';
import 'widget_cards/widget_card_small.dart';

/// Widget size variants rendered for the Android home-screen widget.
enum WidgetSize { small, medium, large }

/// Logical canvas sizes (matching the 2x2 / 4x2 / 4x4 launcher grids).
const Map<WidgetSize, Size> widgetLogicalSizes = {
  WidgetSize.small: Size(110, 110),
  WidgetSize.medium: Size(320, 160),
  WidgetSize.large: Size(320, 320),
};

/// Pushes rendered size-variant snapshots to the Android home-screen widget.
///
/// Each variant is rasterized into a PNG (light + dark) via
/// `HomeWidget.renderFlutterWidget`; the Kotlin provider picks the right PNG
/// per widget instance based on its on-screen size. All failures are
/// swallowed on purpose: a widget sync problem must never crash the app.
class WidgetSync {
  WidgetSync._();

  static const String _checksumKey = 'widget_checksum_v2';
  static const Duration _debounceDuration = Duration(milliseconds: 1500);

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
      final prefs = await SharedPreferences.getInstance();

      var totalTasks = 0;
      dailyCounts.forEach((_, count) => totalTasks += count);

      final checksumBase = <String, Object?>{
        'best': stats.bestStreak,
        'cur': stats.currentStreak,
        'days': stats.workDays,
        'today': stats.todayTasks,
        'ago': stats.lastActiveDaysAgo,
        'cells': dailyCounts.length,
        'total': totalTasks,
        'counts': dailyCounts.keys
            .map((k) => '${k.year}-${k.month}-${k.day}:${dailyCounts[k]}')
            .join(','),
      };

      // Render every variant; skip ones whose content+theme is unchanged.
      final checksums = <String, String>{};
      final checksumsRaw = prefs.getString(_checksumKey);
      if (checksumsRaw != null) {
        (jsonDecode(checksumsRaw) as Map<String, dynamic>).forEach((k, v) {
          checksums[k] = v.toString();
        });
      }

      for (final size in WidgetSize.values) {
        final keyBase = _imageKeyBase(size);
        for (final dark in [false, true]) {
          final key = dark ? '${keyBase}_dark' : keyBase;
          final checksum = jsonEncode(<String, Object?>{
            ...checksumBase,
            'dark': dark,
          });
          if (checksums[key] == checksum) continue;
          await _render(
            size: size,
            counts: dailyCounts,
            stats: stats,
            isDark: dark,
            key: key,
          );
          checksums[key] = checksum;
        }
      }

      final statsNext = <String, Object?>{
        'bestStreak': stats.bestStreak,
        'currentStreak': stats.currentStreak,
        'todayTasks': stats.todayTasks,
        'activeDays': stats.workDays,
        'lastActiveDaysAgo': stats.lastActiveDaysAgo,
      };
      await HomeWidget.saveWidgetData('widget_stats', jsonEncode(statsNext));

      await prefs.setString(_checksumKey, jsonEncode(checksums));
      await HomeWidget.updateWidget(androidName: 'WidgetProvider');
    } catch (_) {
      // Swallow: widget sync must never break the app.
    }
  }

  /// `widget_image_small`, `widget_image_medium`, `widget_image_large` — the
  /// legacy medium-only keys (`widget_image`) stay populated for one release.
  static String _imageKeyBase(WidgetSize size) {
    switch (size) {
      case WidgetSize.small:
        return 'widget_image_small';
      case WidgetSize.medium:
        return 'widget_image_medium';
      case WidgetSize.large:
        return 'widget_image_large';
    }
  }

  static Future<String?> _render({
    required WidgetSize size,
    required Map<DateTime, int> counts,
    required AppStats stats,
    required bool isDark,
    required String key,
  }) async {
    final logicalSize = widgetLogicalSizes[size]!;
    final Widget child;
    switch (size) {
      case WidgetSize.small:
        child = WidgetCardSmall(counts: counts, stats: stats, isDark: isDark);
      case WidgetSize.medium:
        child = WidgetHeatmapCard(counts: counts, stats: stats, isDark: isDark);
      case WidgetSize.large:
        child = WidgetCardLarge(counts: counts, stats: stats, isDark: isDark);
    }

    final card = SizedBox(
      width: logicalSize.width,
      height: logicalSize.height,
      child: child,
    );
    final path = await HomeWidget.renderFlutterWidget(
      card,
      key: key,
      logicalSize: logicalSize,
      pixelRatio: 3.0,
    );
    await HomeWidget.saveWidgetData(key, path);

    // Legacy medium aliases so the previous release keeps working.
    if (size == WidgetSize.medium) {
      final legacy = isDark ? 'widget_image_dark' : 'widget_image';
      await HomeWidget.saveWidgetData(legacy, path);
    }
    return path;
  }
}
