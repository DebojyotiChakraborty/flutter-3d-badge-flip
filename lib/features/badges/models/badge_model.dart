import 'package:flutter/material.dart';

/// Category of the achievement badge.
enum BadgeCategory {
  closeYourRings,
  workouts,
  milestones,
  limitedEdition,
}

/// Represents a single fitness achievement badge.
///
/// Named [AwardBadge] to avoid conflict with Flutter's built-in [Badge] widget.
class AwardBadge {
  final String id;
  final String name;
  final String description;
  final String glbAssetPath;
  final BadgeCategory category;
  final Color accentColor;
  final bool isEarned;
  final DateTime? dateEarned;
  final double? progress; // 0.0–1.0
  final String? progressLabel; // e.g., '8 of 100'
  final Map<String, dynamic>? metadata;

  const AwardBadge({
    required this.id,
    required this.name,
    required this.description,
    required this.glbAssetPath,
    required this.category,
    required this.accentColor,
    this.isEarned = false,
    this.dateEarned,
    this.progress,
    this.progressLabel,
    this.metadata,
  });

  /// Unique hero tag for heroine transitions.
  /// Must match between grid tile and detail screen.
  String get heroTag => 'badge_hero_$id';

  /// Path to the GLB asset file for direct 3D rendering.
  String get modelAssetPath => glbAssetPath;
}
