import 'package:flutter/widgets.dart';

/// Provides the current heroine flight rotation angle to descendants.
///
/// The shuttle builder places this above the hero child during flight,
/// allowing the 3D viewer to apply the rotation directly to the scene
/// graph (model node) instead of using a 2D widget-level Transform.
/// This ensures environment lighting and reflections update in real time.
class FlightRotation extends InheritedWidget {
  /// Current rotation angle in radians.
  final double angle;

  /// Which axis the rotation is around.
  final Axis axis;

  /// Normalized flight progress after the shuttle rotation curve is applied.
  final double progress;

  /// Whether this flight is returning to the source screen.
  final bool isPop;

  const FlightRotation({
    super.key,
    required this.angle,
    required this.axis,
    required this.progress,
    required this.isPop,
    required super.child,
  });

  /// Returns the flight rotation data if inside a heroine flight, or null.
  static FlightRotation? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<FlightRotation>();
  }

  @override
  bool updateShouldNotify(FlightRotation oldWidget) =>
      angle != oldWidget.angle ||
      axis != oldWidget.axis ||
      progress != oldWidget.progress ||
      isPop != oldWidget.isPop;
}
