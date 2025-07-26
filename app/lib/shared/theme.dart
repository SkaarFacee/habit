import 'package:flutter/material.dart';

// --- Theme Management ---
class AppTheme {
  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primaryColor: const Color(0xFF0066CC),
    scaffoldBackgroundColor: const Color(0xFFF2F2F7),
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF0066CC),
      secondary: Color(0xFFD1E9FF),
      surface: Colors.white,
      onPrimary: Colors.white,
      onSecondary: Color(0xFF0066CC),
      onSurface: Colors.black,
      onError: Colors.white,
    ),
    useMaterial3: true,
    fontFamily: 'Inter',
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent, // Make AppBar transparent
      elevation: 0,
      titleTextStyle: TextStyle(
        color: Colors.black,
        fontSize: 34,
        fontWeight: FontWeight.bold,
        fontFamily: 'Inter',
      ),
      iconTheme: IconThemeData(color: Color(0xFF0066CC)),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(fontFamily: 'Inter', color: Colors.black87),
      bodyMedium: TextStyle(fontFamily: 'Inter', color: Colors.black54),
      titleLarge: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, color: Colors.black),
      headlineSmall: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: Colors.black),
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: const Color(0xFFE84545),
    scaffoldBackgroundColor: const Color(0xFF121212),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFFE84545),
      secondary: Color(0xFF903749),
      surface: Color(0xFF1E1E1E),
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Colors.white,
      onError: Colors.white,
    ),
    useMaterial3: true,
    fontFamily: 'Inter',
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent, // Make AppBar transparent
      elevation: 0,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 34,
        fontWeight: FontWeight.bold,
        fontFamily: 'Inter',
      ),
      iconTheme: IconThemeData(color: Color(0xFFE84545)),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(fontFamily: 'Inter', color: Colors.white),
      bodyMedium: TextStyle(fontFamily: 'Inter', color: Colors.white70),
      titleLarge: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold),
      headlineSmall: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
    ),
  );
}

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);