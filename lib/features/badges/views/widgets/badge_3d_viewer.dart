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
    this.enableTouch = false,
  });

  /// Path to the .model file (converted from GLB via flutter_scene_importer).
  final String modelAssetPath;
  final VoidCallback onModelLoaded;
  final double size;

  /// When true, the user can drag to rotate the badge along the Y axis.
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

  // Touch rotation state (Y-axis only)
  double _rotationY = 0;
  double _lastPanX = 0;

  @override
  void initState() {
    super.initState();
    _initScene();
    // Create a ticker for continuous repaint when touch is enabled.
    if (widget.enableTouch) {
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

      _retuneModelMaterials(node);

      // Create the scene graph ONCE and add the node.
      final scene = Scene();

      try {
        // Use the custom studio map to avoid real-world scene reflections.
        final studioEnv = await EnvironmentMap.fromAssets(
          radianceImagePath: 'assets/env/studio_radiance.png',
          irradianceImagePath: 'assets/env/studio_irradiance.png',
        );
        scene.environment.environmentMap = studioEnv;
        scene.environment.intensity = 0.78;
        scene.environment.exposure = 1.0;
      } catch (e) {
        // Keep badges visible even if custom env textures fail to load.
        debugPrint('Failed to load studio env map, using default IBL: $e');
        scene.environment.intensity = 0.65;
        scene.environment.exposure = 1.15;
      }

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

  void _retuneModelMaterials(Node root) {
    void visit(Node node) {
      final mesh = node.mesh;
      if (mesh != null) {
        for (final primitive in mesh.primitives) {
          final material = primitive.material;
          if (material is! PhysicallyBasedMaterial) {
            continue;
          }

          // The imported models currently rely on baseColorFactor values.
          // Boosting saturation/value keeps colors visible without textures.
          if (material.baseColorTexture == null) {
            material.baseColorFactor = _boostBaseColor(material.baseColorFactor);
          }

          material.metallicFactor = material.metallicFactor.clamp(0.55, 0.9);
          material.roughnessFactor = material.roughnessFactor.clamp(0.2, 0.72);
        }
      }

      for (final child in node.children) {
        visit(child);
      }
    }

    visit(root);
  }

  vm.Vector4 _boostBaseColor(vm.Vector4 linearColor) {
    final color = Color.fromRGBO(
      (linearColor.x.clamp(0.0, 1.0) * 255).round(),
      (linearColor.y.clamp(0.0, 1.0) * 255).round(),
      (linearColor.z.clamp(0.0, 1.0) * 255).round(),
      linearColor.w.clamp(0.0, 1.0),
    );

    final hsv = HSVColor.fromColor(color);
    final boosted = hsv
        .withSaturation((hsv.saturation * 1.6).clamp(0.45, 1.0))
        .withValue((hsv.value * 1.45).clamp(0.32, 1.0));

    final out = boosted.toColor();
    return vm.Vector4(
      out.r.clamp(0.0, 1.0),
      out.g.clamp(0.0, 1.0),
      out.b.clamp(0.0, 1.0),
      linearColor.w,
    );
  }

  void _onTick(Duration elapsed) {
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
              }
            : null,
        onPanUpdate: widget.enableTouch
            ? (details) {
                final dx = details.localPosition.dx - _lastPanX;
                _lastPanX = details.localPosition.dx;
                setState(() {
                  _rotationY += dx * 0.01;
                });
              }
            : null,
        child: _sceneReady
            ? ClipRect(
                child: CustomPaint(
                  painter: _ScenePainter(
                    scene: _scene!,
                    modelNode: _modelNode!,
                    rotationY: _rotationY,
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

  _ScenePainter({
    required this.scene,
    required this.modelNode,
    required this.rotationY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Update the node's transform for Y-axis rotation only.
    modelNode.localTransform = vm.Matrix4.identity()..rotateY(rotationY);

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
