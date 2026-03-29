import 'package:flutter/widgets.dart';

/// Centralized animation configuration for badge heroine transitions.
abstract class AnimationConstants {
  /// Total flight duration for the heroine spring animation.
  static const heroFlightDuration = Duration(milliseconds: 1200);

  /// Spring overshoot factor. Higher = more dramatic bounce past target.
  /// 0.01 gives a very subtle ease-back without visible oscillation.
  static const springExtraBounce = 0.01;

  /// Number of half-flips during the heroine flight.
  /// 2 half-flips = 1 full rotation = 360°.
  static const flipHalfFlips = 1;

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
