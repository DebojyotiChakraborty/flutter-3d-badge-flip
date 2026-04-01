import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:heroine/heroine.dart';

import 'flight_rotation.dart';

/// A custom shuttle builder that slightly over-rotates past the landing face
/// during heroine flight transitions.
///
/// The settle-back can then happen in the destination badge layer so the
/// landing doesn't pause and then re-accelerate inside the shuttle itself.
///
/// ## Usage
/// ```dart
/// Heroine(
///   tag: 'badge_hero_1',
///   motion: Motion.curved(
///     const Duration(milliseconds: 1200),
///     Curves.easeOut,
///   ),
///   flightShuttleBuilder: const BouncyFlipShuttleBuilder(
///     halfFlips: 2,
///     rotationCurve: Curves.easeOut,
///     landingOvershootRadians: 0.30,
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

  /// Curve used for the main rotation.
  final Curve rotationCurve;

  /// Extra angle added after the badge reaches the face-forward pose.
  final double landingOvershootRadians;

  const BouncyFlipShuttleBuilder({
    this.axis = Axis.vertical,
    this.halfFlips = 4,
    this.flipForward = true,
    this.perspective = 0.001,
    this.rotationCurve = Curves.easeOut,
    this.landingOvershootRadians = 0,
    super.curve = Curves.linear,
  }) : assert(landingOvershootRadians >= 0);

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
        final double rawValue;
        if (flightDirection == HeroFlightDirection.push) {
          rawValue = animation.value;
        } else {
          rawValue = 1.0 - animation.value;
        }

        final progress = rawValue.clamp(0.0, 1.0).toDouble();
        final rotationProgress = rotationCurve.transform(progress);
        final targetAngle =
            (halfFlips * pi) +
            (flightDirection == HeroFlightDirection.push
                ? landingOvershootRadians
                : 0.0);
        final angle = rotationProgress * targetAngle * directionSign;

        // Provide the rotation via InheritedWidget so the 3D viewer
        // can apply it directly to the scene graph (model node).
        // This ensures environment lighting and reflections update
        // in real time, unlike a widget-level Transform which only
        // rotates the already-rendered 2D output.
        return FlightRotation(
          angle: angle,
          axis: axis,
          progress: rotationProgress,
          isPop: flightDirection == HeroFlightDirection.pop,
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
  List<Object?> get props => [
    axis,
    halfFlips,
    flipForward,
    perspective,
    rotationCurve,
    landingOvershootRadians,
    curve,
  ];
}
