import 'package:flutter/material.dart';

class GameTheme {
  static const background = Color(0xFF0F1923);
  static const surface = Color(0xFF1A2634);
  static const surfaceLight = Color(0xFF243442);
  static const accent = Color(0xFF4ECDC4);
  static const accentAlt = Color(0xFFFF6B6B);
  static const gold = Color(0xFFFFD93D);
  static const textPrimary = Color(0xFFF0F0F0);
  static const textSecondary = Color(0xFF8899AA);
  static const border = Color(0xFF2A3A4A);

  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      secondary: accentAlt,
      surface: surface,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: 0.5,
      ),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: textPrimary),
      headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: textPrimary),
      bodyLarge: TextStyle(fontSize: 16, color: textPrimary),
      bodyMedium: TextStyle(fontSize: 14, color: textSecondary),
    ),
  );
}
