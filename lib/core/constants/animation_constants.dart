import 'package:flutter/widgets.dart';

/// Centralized animation configuration for badge heroine transitions.
abstract class AnimationConstants {
  /// Total flight duration for the heroine spring animation.
  static const heroFlightDuration = Duration(milliseconds: 800);

  /// Spring overshoot factor. Higher = more dramatic bounce past target.
  /// 0.03 gives a subtle ~5° ease-back past 720° without visible oscillation.
  static const springExtraBounce = 0.03;

  /// Number of half-flips during the heroine flight.
  /// 4 half-flips = 2 full rotations = 720°.
  static const flipHalfFlips = 4;

  /// 3D perspective depth for the flip transform.
  /// Smaller = less dramatic, larger = more dramatic (can distort).
  static const flipPerspective = 0.001;

  /// Duration for the info card stagger entrance.
  static const infoCardDelay = Duration(milliseconds: 200);
  static const infoCardDuration = Duration(milliseconds: 400);

  /// Duration for the thumbnail → 3D crossfade.
  static const crossfadeDuration = Duration(milliseconds: 300);

  /// Scale factor for press-down effect on grid tiles.
  static const pressScaleFactor = 0.95;

  /// Curve for the info card entrance animation.
  static const infoCardCurve = Curves.easeOutCubic;
}
