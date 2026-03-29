import 'package:flutter/widgets.dart';
import 'package:heroine/heroine.dart';

import '../constants/animation_constants.dart';
import '../transitions/bouncy_flip_shuttle_builder.dart';

/// Factory for consistent Heroine motion configuration.
///
/// Used by both the grid tile and detail screen to ensure
/// matching Heroine configs (mismatched configs = broken transitions).
Motion badgeMotion() => Motion.snappySpring(
      duration: AnimationConstants.heroFlightDuration,
      extraBounce: AnimationConstants.springExtraBounce,
    );

/// Shared shuttle builder instance for all badge heroine transitions.
final badgeShuttleBuilder = BouncyFlipShuttleBuilder(
  axis: Axis.vertical,
  halfFlips: AnimationConstants.flipHalfFlips,
  flipForward: true,
  perspective: AnimationConstants.flipPerspective,
);
