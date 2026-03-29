import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

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
    this.autoRotate = false,
    this.enableTouch = true,
  });

  /// Path to the .model file (converted from GLB via flutter_scene_importer).
  final String modelAssetPath;
  final VoidCallback onModelLoaded;
  final double size;
  final bool autoRotate;
  final bool enableTouch;

  @override
  State<Badge3DViewer> createState() => _Badge3DViewerState();
}

class _Badge3DViewerState extends State<Badge3DViewer>
    with SingleTickerProviderStateMixin {
  Scene? _scene;
  Node? _modelNode;
  bool _sceneReady = false;
  Ticker? _ticker;
  double _elapsedSeconds = 0;

  // Touch rotation state
  double _rotationY = 0;
  double _rotationX = 0;
  double _lastPanX = 0;
  double _lastPanY = 0;

  @override
  void initState() {
    super.initState();
    _initScene();
    // Only create a ticker if we need continuous updates (auto-rotate or touch)
    if (widget.autoRotate || widget.enableTouch) {
      _ticker = createTicker(_onTick)..start();
    }
  }

  Future<void> _initScene() async {
    try {
      // Initialize flutter_scene's static resources (shaders, IBL textures)
      await Scene.initializeStaticResources();

      // Load the 3D model
      final node = await Node.fromAsset(widget.modelAssetPath);
      if (!mounted) return;

      // Create the scene graph ONCE and add the node.
      final scene = Scene();

      // Use the default environment map (Royal Esplanade) which provides
      // colorful HDR lighting for proper PBR metallic colors.
      // Lower the intensity so the landscape features aren't recognizable
      // but the color variation still illuminates the badges correctly.
      scene.environment.intensity = 0.6;
      scene.environment.exposure = 1.8;

      scene.add(node);

      setState(() {
        _scene = scene;
        _modelNode = node;
        _sceneReady = true;
      });
      widget.onModelLoaded();
    } catch (e) {
      debugPrint('Failed to load 3D model ${widget.modelAssetPath}: $e');
    }
  }

  void _onTick(Duration elapsed) {
    _elapsedSeconds = elapsed.inMilliseconds / 1000.0;
    if (_sceneReady) {
      setState(() {}); // Trigger repaint
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: GestureDetector(
        onPanStart: widget.enableTouch
            ? (details) {
                _lastPanX = details.localPosition.dx;
                _lastPanY = details.localPosition.dy;
              }
            : null,
        onPanUpdate: widget.enableTouch
            ? (details) {
                final dx = details.localPosition.dx - _lastPanX;
                final dy = details.localPosition.dy - _lastPanY;
                _lastPanX = details.localPosition.dx;
                _lastPanY = details.localPosition.dy;
                setState(() {
                  _rotationY += dx * 0.01;
                  _rotationX += dy * 0.01;
                  _rotationX = _rotationX.clamp(-pi / 4, pi / 4);
                });
              }
            : null,
        child: _sceneReady
            ? ClipRect(
                child: CustomPaint(
                  painter: _ScenePainter(
                    scene: _scene!,
                    modelNode: _modelNode!,
                    rotationY: widget.autoRotate
                        ? _elapsedSeconds * 0.5 + _rotationY
                        : _rotationY,
                    rotationX: _rotationX,
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

class _ScenePainter extends CustomPainter {
  final Scene scene;
  final Node modelNode;
  final double rotationY;
  final double rotationX;

  _ScenePainter({
    required this.scene,
    required this.modelNode,
    required this.rotationY,
    required this.rotationX,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Update the node's transform for rotation.
    modelNode.localTransform = vm.Matrix4.identity()
      ..rotateY(rotationY)
      ..rotateX(rotationX);

    // Camera positioned to frame the full badge model.
    // Badge models are ~40 units diameter with translations up to 54 units.
    final camera = PerspectiveCamera(
      position: vm.Vector3(0, 10, 60),
      target: vm.Vector3(0, 0, 0),
    );

    scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant _ScenePainter oldDelegate) => true;
}
