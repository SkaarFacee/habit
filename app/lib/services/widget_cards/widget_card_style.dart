import 'package:flutter/material.dart';

/// Shared visual language for all home-screen widget cards.
class WidgetCardStyle {
  const WidgetCardStyle._();

  static const List<String> months = [
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
  static Color background(bool isDark) =>
      isDark ? const Color(0xFF15171C) : Colors.white;

  static Color hairline(bool isDark) =>
      (isDark ? Colors.white : Colors.black).withOpacity(0.06);

  static Color subtle(bool isDark) => isDark ? Colors.white54 : Colors.black54;

  static Color strong(bool isDark) => isDark ? Colors.white : Colors.black87;

  static const Color flame = Color(0xFFFF9F0A);

  /// GitHub-style intensity ramp for daily counts.
  static Color colorForCount(int count, bool isDark) {
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

  /// Small caps-style section label (SF Pro-like hierarchy).
  static TextStyle label(bool isDark, {double size = 8}) => TextStyle(
    fontSize: size,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.1,
    color: subtle(isDark),
  );

  static TextStyle value(bool isDark, {double size = 18}) => TextStyle(
    fontSize: size,
    fontWeight: FontWeight.w800,
    color: strong(isDark),
    letterSpacing: -0.3,
  );
}
