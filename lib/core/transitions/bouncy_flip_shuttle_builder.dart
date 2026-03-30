import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:heroine/heroine.dart';

/// A custom shuttle builder that enables **bouncy rotation overshoot** during
/// heroine flight transitions.
///
/// ## Why this exists (The Bounce Gap)
///
/// The built-in [FlipShuttleBuilder] extends [SimpleShuttleBuilder], which
/// maps `animation.value` through `Curve.transform(t)`. Flutter's curve
/// transform **clamps t to [0.0, 1.0]**, which kills any spring overshoot
/// on the rotation angle.
///
/// [Motion.bouncySpring] drives `animation.value` past 1.0 during overshoot
/// (e.g., hitting ~1.1 before settling to 1.0). This overshoot makes
/// position/scale bounce naturally. But the clamp in SimpleShuttleBuilder
/// prevents rotation from bouncing.
///
/// This builder extends [HeroineShuttleBuilder] directly and uses the
/// **raw unclamped animation.value**, allowing the rotation to overshoot
/// past the target angle and spring back — matching the Apple Fitness
/// badge flip feel.
///
/// ## Usage
/// ```dart
/// Heroine(
///   tag: 'badge_hero_1',
///   motion: Motion.bouncySpring(
///     duration: Duration(milliseconds: 800),
///     extraBounce: 0.15,
///   ),
///   flightShuttleBuilder: const BouncyFlipShuttleBuilder(
///     halfFlips: 4,  // 2 full rotations = 720°
///   ),
///   child: badgeWidget,
/// )
/// ```
class BouncyFlipShuttleBuilder extends HeroineShuttleBuilder {
  /// The axis of rotation.
  /// [Axis.vertical] = Y-axis flip (like turning a page).
  /// [Axis.horizontal] = X-axis flip (like a split-flap display).
  final Axis axis;

  /// Number of half-flips in the transition.
  /// 1 = 180°, 2 = 360°, 4 = 720° (2 full rotations).
  /// Even values end with the widget in its original orientation.
  final int halfFlips;

  /// Direction of the flip rotation on push.
  /// When true, flips "forward" (page-turn style for vertical axis).
  final bool flipForward;

  /// 3D perspective depth factor for the rotation transform.
  /// Smaller = subtler 3D effect. Larger = more dramatic but can distort.
  /// 0.001 is a good default.
  final double perspective;

  const BouncyFlipShuttleBuilder({
    this.axis = Axis.vertical,
    this.halfFlips = 4,
    this.flipForward = true,
    this.perspective = 0.001,
    super.curve,
  });

  @override
  Widget call(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    // Use the source Heroine widget during flight for both push and pop.
    // This avoids destination-side loading placeholders flashing mid-flight.
    // (e.g. detail view fallback thumbnail before 3D model is ready)
    final fromHero = fromHeroContext.widget;
    final child = fromHero;

    // Direction sign: flip forward on push, reverse on pop.
    final directionSign =
        (flipForward ? 1.0 : -1.0) *
        (flightDirection == HeroFlightDirection.pop ? -1.0 : 1.0);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        // CRITICAL: Use animation.value DIRECTLY.
        // Do NOT map through curve.transform() — that clamps to [0,1]
        // and kills the bounce overshoot from Motion.bouncySpring().
        //
        // For push: animation.value goes 0.0 → ~1.1 → 1.0 (with bounce)
        // For pop: animation.value goes 1.0 → ~-0.1 → 0.0 (with bounce)
        //
        // We remap so the rotation always goes from 0 to target:
        final double rawValue;
        if (flightDirection == HeroFlightDirection.push) {
          rawValue = animation.value;
        } else {
          rawValue = 1.0 - animation.value;
        }

        // Rotation angle in radians.
        // halfFlips * π * rawValue
        // With halfFlips=4 and rawValue overshooting to 1.1:
        //   4 * π * 1.1 = ~792° (72° overshoot past 720°)
        final angle = rawValue * halfFlips * pi * directionSign;

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, perspective)
            ..rotateY(axis == Axis.vertical ? angle : 0)
            ..rotateX(axis == Axis.horizontal ? angle : 0),
          child: child,
        );
      },
    );
  }

  @override
  List<Object?> get props => [axis, halfFlips, flipForward, perspective, curve];
}
