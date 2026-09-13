import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences cold-start cache for the tracker snapshot.
///
/// On app launch the dashboard renders the last-known data immediately while
/// the Firestore stream refreshes, so there is no blank-load flicker when the
/// device is offline or the network is slow.
class TrackerCache {
  static const String _prefsKey = 'tracker_cache_v1';

  static Future<Map<String, dynamic>?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Corrupt cache is treated as "no cache".
    }
    return null;
  }

  static Future<void> save(Map<String, dynamic> tracker) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(trimToWindow(tracker)));
    } catch (_) {
      // Cache writes must never crash the app.
    }
  }

  /// Keeps only the trailing 365 days per list (mirrors the heatmap window)
  /// so SharedPreferences stays lean.
  static Map<String, dynamic> trimToWindow(Map<String, dynamic> tracker,
      {DateTime? now}) {
    final today = now ?? DateTime.now();
    final cutoff = DateTime(today.year, today.month, today.day)
        .subtract(const Duration(days: 365));

    final out = <String, dynamic>{};
    tracker.forEach((listName, listData) {
      if (listData is Map<String, dynamic>) {
        final trimmed = <String, dynamic>{};
        listData.forEach((dateStr, activities) {
          try {
            final parts = dateStr.split('-');
            if (parts.length != 3) return;
            final date =
                DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
            if (!date.isBefore(cutoff)) trimmed[dateStr] = activities;
          } catch (_) {
            // Malformed dates are dropped during cache writes only.
          }
        });
        out[listName] = trimmed;
      }
    });
    return out;
  }
}