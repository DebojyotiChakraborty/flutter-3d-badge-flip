import 'package:flutter/material.dart';

/// App-wide dark theme matching the Apple Fitness aesthetic.
class AppTheme {
  AppTheme._();

  static const _secondaryGrey = Color(0xFF8E8E93);
  static const _background = Colors.black;

  static ThemeData get darkTheme => ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _background,
        colorScheme: const ColorScheme.dark(
          surface: _background,
          primary: Colors.white,
          secondary: _secondaryGrey,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          headlineMedium: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          titleMedium: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          bodyMedium: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          bodySmall: TextStyle(
            color: _secondaryGrey,
            fontSize: 12,
            fontWeight: FontWeight.w400,
          ),
          labelSmall: TextStyle(
            color: _secondaryGrey,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      );
}
