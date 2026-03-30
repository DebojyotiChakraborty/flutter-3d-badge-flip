import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:heroine/heroine.dart';

import 'flight_rotation.dart';

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

  /// Optional curve applied to the rotation progress independently of the
  /// position/scale animation. Use [Curves.easeIn] to back-load the flip
  /// so it finishes after position/scale have settled.
  /// When null, rotation follows the same timing as position/scale.
  final Curve? rotationCurve;

  const BouncyFlipShuttleBuilder({
    this.axis = Axis.vertical,
    this.halfFlips = 4,
    this.flipForward = true,
    this.perspective = 0.001,
    this.rotationCurve,
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

        // Apply an independent rotation curve if provided.
        // This lets rotation lag behind position/scale (e.g. easeIn
        // back-loads the flip so it finishes after the badge has
        // moved and scaled into its destination).
        double rotationProgress = rawValue;
        if (rotationCurve != null) {
          final clamped = rawValue.clamp(0.0, 1.0);
          rotationProgress = rotationCurve!.transform(clamped);
          // Preserve any overshoot beyond 1.0 for spring bounce.
          if (rawValue > 1.0) {
            rotationProgress += (rawValue - 1.0);
          }
        }

        // Rotation angle in radians.
        // halfFlips * π * rotationProgress
        final angle = rotationProgress * halfFlips * pi * directionSign;

        // Provide the rotation via InheritedWidget so the 3D viewer
        // can apply it directly to the scene graph (model node).
        // This ensures environment lighting and reflections update
        // in real time, unlike a widget-level Transform which only
        // rotates the already-rendered 2D output.
        return FlightRotation(
          angle: angle,
          axis: axis,
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.center,
              child: fromHero,
            ),
          ),
        );
      },
    );
  }

  @override
  List<Object?> get props =>
      [axis, halfFlips, flipForward, perspective, rotationCurve, curve];
}
