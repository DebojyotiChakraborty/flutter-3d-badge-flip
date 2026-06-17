import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_scene/scene.dart' hide Animation;
import 'package:vector_math/vector_math.dart' as vm;

import '../../../../core/transitions/flight_rotation.dart';

/// A canvas-based 3D badge viewer using flutter_scene.
///
/// Unlike WebView-based viewers (flutter_3d_controller), this renders directly
/// on Flutter's canvas, so Matrix4 transforms (heroine flip) and widget
/// reparenting work correctly during shared-element transitions.
class Badge3DViewer extends StatefulWidget {
  const Badge3DViewer({
    super.key,
    required this.modelAssetPath,
    required this.onModelLoaded,
    this.size = 250,
    this.enableTouch = false,
    this.initialRotationY = 0,
    this.autoSnapToProfileOnLoad = false,
    this.initialSnapDelay = Duration.zero,
    this.initialSnapCurve = Curves.easeOutCubic,
    this.continuousRendering = false,
    this.rotationPersistKey,
  });

  /// Path to the GLB asset used for direct 3D rendering.
  final String modelAssetPath;
  final VoidCallback onModelLoaded;
  final double size;

  /// When true, the user can drag to rotate the badge along the Y axis.
  final bool enableTouch;

  /// Starting Y rotation for the badge model.
  final double initialRotationY;

  /// When true, snap to the nearest front/back face after the optional delay.
  final bool autoSnapToProfileOnLoad;

  /// Delay before the initial snap begins.
  final Duration initialSnapDelay;

  /// Curve used by the initial snap animation.
  final Curve initialSnapCurve;

  /// When true, keeps repainting the scene even without touch input.
  final bool continuousRendering;

  /// When set, the viewer remembers its current Y rotation under this key so a
  /// later heroine pop flight can continue the flip from wherever the user left
  /// the badge (e.g. resting on its back face) instead of jumping to the front.
  final String? rotationPersistKey;

  @override
  State<Badge3DViewer> createState() => _Badge3DViewerState();
}

class _Badge3DViewerState extends State<Badge3DViewer>
    with TickerProviderStateMixin {
  // These badge meshes are heavily metallic, so they depend on the
  // environment for most of their perceived brightness and specular pop.
  static const double _customEnvIntensity = 1.3;
  static const double _customEnvExposure = 2.0;
  static const double _fallbackEnvIntensity = 1.08;
  static const double _fallbackEnvExposure = 2.08;
  static Future<EnvironmentMap>? _studioEnvironmentFuture;

  /// Last Y rotation per [Badge3DViewer.rotationPersistKey]. A fresh viewer
  /// built for a heroine pop flight reads this so closing a flipped (back-
  /// facing) badge continues the flip instead of snapping to the front.
  static final Map<String, double> _persistedRotations = {};

  Scene? _scene;
  Node? _modelNode;
  bool _sceneReady = false;
  Ticker? _ticker;
  late final AnimationController _snapController;
  Animation<double>? _snapAnimation;
  bool _initialSnapArmed = false;
  bool _initialSnapCompleted = false;
  bool _popFlightActive = false;
  double? _popFlightBaseRotationY;

  // Touch rotation state (Y-axis only)
  late double _rotationY;
  double _lastPanX = 0;

  @override
  void initState() {
    super.initState();
    _rotationY = widget.initialRotationY;
    _snapController =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 260),
          )
          ..addListener(() {
            final animation = _snapAnimation;
            if (animation == null) {
              return;
            }
            setState(() {
              _applyRotation(animation.value);
            });
          })
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              _snapAnimation = null;
            }
          });

    _scheduleInitialSnap();
    _initScene();
    // Create a ticker for continuous repaint when touch is enabled.
    if (widget.enableTouch || widget.continuousRendering) {
      _ticker = createTicker(_onTick)..start();
    }
  }

  Future<EnvironmentMap> _loadSharedStudioEnvironment() {
    return _studioEnvironmentFuture ??= EnvironmentMap.fromAssets(
      radianceImagePath: 'assets/env/studio_radiance.png',
      irradianceImagePath: 'assets/env/studio_irradiance.png',
    );
  }

  void _scheduleInitialSnap() {
    if (!widget.autoSnapToProfileOnLoad ||
        widget.initialRotationY.abs() < 0.0001) {
      return;
    }

    Future.delayed(widget.initialSnapDelay, () {
      if (!mounted || _initialSnapCompleted) {
        return;
      }

      _initialSnapArmed = true;
      _maybeStartInitialSnap();
    });
  }

  void _maybeStartInitialSnap() {
    if (!_sceneReady || !_initialSnapArmed || _initialSnapCompleted) {
      return;
    }

    _initialSnapCompleted = true;
    _snapToNearestProfile(curve: widget.initialSnapCurve);
  }

  void _snapToNearestProfile({
    double extraRotation = 0,
    Curve curve = Curves.easeOutCubic,
  }) {
    final projectedRotation = _rotationY + extraRotation;
    final targetRotation =
        (projectedRotation / math.pi).roundToDouble() * math.pi;

    if ((targetRotation - _rotationY).abs() < 0.0001) {
      return;
    }

    _snapController.stop();
    _snapAnimation = Tween<double>(
      begin: _rotationY,
      end: targetRotation,
    ).chain(CurveTween(curve: curve)).animate(_snapController);

    _snapController
      ..value = 0
      ..forward();
  }

  Future<void> _initScene() async {
    try {
      // Initialize flutter_scene's static resources (shaders, IBL textures)
      await Scene.initializeStaticResources();

      // Load the 3D model
      final node = await Node.fromGlb(widget.modelAssetPath);
      if (!mounted) return;

      // Create the scene graph ONCE and add the node.
      final scene = Scene();

      try {
        // Reuse one studio environment across viewers so the grid and detail
        // badge scenes render with the same IBL setup.
        final studioEnv = await _loadSharedStudioEnvironment();
        scene.environment.environmentMap = studioEnv;
        scene.environment.intensity = _customEnvIntensity;
        scene.environment.exposure = _customEnvExposure;
      } catch (e) {
        // Keep badges visible even if custom env textures fail to load.
        debugPrint('Failed to load studio env map, using default IBL: $e');
        scene.environment.intensity = _fallbackEnvIntensity;
        scene.environment.exposure = _fallbackEnvExposure;
      }

      scene.add(node);

      setState(() {
        _scene = scene;
        _modelNode = node;
        _sceneReady = true;
      });
      _maybeStartInitialSnap();
      widget.onModelLoaded();
    } catch (e) {
      debugPrint('Failed to load 3D model ${widget.modelAssetPath}: $e');
    }
  }

  void _onTick(Duration elapsed) {
    if (_sceneReady) {
      setState(() {}); // Trigger repaint
    }
  }

  /// Sets the current Y rotation and, when a [Badge3DViewer.rotationPersistKey]
  /// is configured, remembers it so a later pop flight can resume from it.
  void _applyRotation(double value) {
    _rotationY = value;
    final key = widget.rotationPersistKey;
    if (key != null) {
      _persistedRotations[key] = value;
    }
  }

  /// Reduces an angle to the equivalent rotation in (-2*pi, 0]. The pop flight
  /// always turns the same (negative) way toward the front, so expressing the
  /// resting pose in this range makes the settle-back depend only on the visible
  /// face — not on which direction the user flipped. A back-facing badge always
  /// settles with a consistent half turn (both +pi and -pi map to -pi); a
  /// front-facing badge keeps its full turn. Mapping into (-pi, pi] instead would
  /// make a left-flip (-pi -> +pi) fight the flight and spin 1.5x.
  double _normalizeAngle(double radians) {
    const twoPi = 2 * math.pi;
    final wrapped = radians % twoPi; // Dart's % yields [0, twoPi)
    return wrapped > 0 ? wrapped - twoPi : wrapped;
  }

  void _syncFlightState(FlightRotation? flight) {
    final isPopFlight = flight?.isPop ?? false;
    if (isPopFlight && !_popFlightActive) {
      _popFlightActive = true;
      // The shuttle builds a fresh viewer for the flight, so this instance's
      // own _rotationY is just the initial pose. Resume from the rotation the
      // interactive detail viewer last persisted (e.g. the back face) so a
      // flipped badge continues its flip into the grid instead of jumping.
      final key = widget.rotationPersistKey;
      final restingRotation =
          (key != null ? _persistedRotations[key] : null) ?? _rotationY;
      _popFlightBaseRotationY = _normalizeAngle(restingRotation);
      _initialSnapArmed = false;
      _initialSnapCompleted = true;
      _snapController.stop();
      _snapAnimation = null;
      return;
    }

    if (!isPopFlight && _popFlightActive) {
      _popFlightActive = false;
      _popFlightBaseRotationY = null;
    }
  }

  double _effectiveRotationY(FlightRotation? flight) {
    if (flight == null || !flight.isPop) {
      return _rotationY;
    }

    final baseRotation = _popFlightBaseRotationY ?? _rotationY;
    final remaining = (1.0 - flight.progress).clamp(0.0, 1.0);
    return baseRotation * remaining;
  }

  @override
  void dispose() {
    _snapController.dispose();
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget viewer = GestureDetector(
      onPanStart: widget.enableTouch
          ? (details) {
              _initialSnapArmed = false;
              _initialSnapCompleted = true;
              _snapController.stop();
              _snapAnimation = null;
              _lastPanX = details.localPosition.dx;
            }
          : null,
      onPanUpdate: widget.enableTouch
          ? (details) {
              final dx = details.localPosition.dx - _lastPanX;
              _lastPanX = details.localPosition.dx;
              setState(() {
                _applyRotation(_rotationY + dx * 0.01);
              });
            }
          : null,
      onPanEnd: widget.enableTouch
          ? (details) {
              // A small fling projection makes quick swipes feel natural
              // before snapping to front/back profiles.
              final projectedFlingRotation =
                  details.velocity.pixelsPerSecond.dx * 0.0015;
              _snapToNearestProfile(extraRotation: projectedFlingRotation);
            }
          : null,
      onPanCancel: widget.enableTouch
          ? () {
              _snapToNearestProfile();
            }
          : null,
      child: _sceneReady
          ? Builder(
              builder: (context) {
                final flight = FlightRotation.maybeOf(context);
                _syncFlightState(flight);
                return ClipRect(
                  child: CustomPaint(
                    painter: _ScenePainter(
                      scene: _scene!,
                      modelNode: _modelNode!,
                      rotationY: _effectiveRotationY(flight),
                      flightRotation: flight,
                      devicePixelRatio:
                          MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0,
                    ),
                  ),
                );
              },
            )
          : const SizedBox.shrink(),
    );

    // Render at the size we're actually given so the 3D scene rasterizes at
    // display resolution. During a heroine flight the incoming constraints grow
    // with the flight rect, keeping the badge crisp instead of being a small
    // render that the shuttle scales up. Falls back to [widget.size] only when
    // the incoming constraints are unbounded.
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxSide = constraints.biggest.shortestSide;
        final side = maxSide.isFinite ? maxSide : widget.size;
        return SizedBox(width: side, height: side, child: viewer);
      },
    );
  }
}

class _ScenePainter extends CustomPainter {
  final Scene scene;
  final Node modelNode;
  final double rotationY;
  final FlightRotation? flightRotation;

  /// Logical→device pixel ratio of the surrounding view, used to oversample
  /// the 3D render so the badge is rasterized at full device resolution.
  final double devicePixelRatio;

  _ScenePainter({
    required this.scene,
    required this.modelNode,
    required this.rotationY,
    required this.devicePixelRatio,
    this.flightRotation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Combine touch rotation with any in-flight heroine rotation.
    final flight = flightRotation;
    final transform = vm.Matrix4.identity();
    if (flight != null) {
      if (flight.axis == Axis.vertical) {
        transform.rotateY(flight.angle);
      } else {
        transform.rotateX(flight.angle);
      }
    }
    transform.rotateY(rotationY);
    modelNode.localTransform = transform;

    // Camera positioned to frame the full badge model.
    // Badge models are ~40 units diameter with translations up to 54 units.
    final camera = PerspectiveCamera(
      position: vm.Vector3(0, 10, 60),
      target: vm.Vector3(0, 0, 0),
    );

    // flutter_scene allocates its render-target texture at the viewport size in
    // LOGICAL pixels and composites it 1:1 (see Surface.getNextRenderTarget),
    // so on a 3x screen the badge would be rasterized at 1/3 resolution and
    // upscaled — soft/pixelated in every state. Oversample by the device pixel
    // ratio: work in device pixels (scale by 1/dpr) and render into a viewport
    // of size*dpr, so the texture is created at full device resolution, then
    // drawn 1:1.
    final dev = size * devicePixelRatio;
    canvas.save();
    canvas.scale(1 / devicePixelRatio);
    // flutter_scene's camera basis renders our badges mirrored on X; correct it
    // so embossed text reads properly. Width is in device pixels here because of
    // the 1/dpr scale above.
    canvas.translate(dev.width, 0);
    canvas.scale(-1, 1);
    scene.render(camera, canvas, viewport: Offset.zero & dev);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ScenePainter oldDelegate) => true;
}
