import 'package:flutter/material.dart';

/// Accent colors for badge categories, matching Apple Fitness visual language.
class BadgeColors {
  BadgeColors._();

  /// Vivid pink — Move Record achievements.
  static const pink = Color(0xFFFF2D55);

  /// Warm orange — Move Goal percentage achievements.
  static const orange = Color(0xFFFF9500);

  /// Cool silver — New Goal achievements.
  static const silver = Color(0xFFB0B8C1);

  /// Activity green — Streak & milestone achievements.
  static const green = Color(0xFF30D158);

  /// Electric blue — Workout achievements.
  static const blue = Color(0xFF0A84FF);

  /// Gold — Limited edition badges.
  static const gold = Color(0xFFFFD700);

  /// Maps a color to its glow variant at 15% opacity for badge shadows.
  static Color glowFor(Color accent) => accent.withValues(alpha: 0.15);

  /// Maps a color to a slightly lighter variant for gradient highlights.
  static Color highlightFor(Color accent) =>
      Color.lerp(accent, Colors.white, 0.3)!;
}
