import 'package:flutter/material.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';

/// Wrapper around Flutter3DViewer for displaying interactive 3D badge models.
///
/// Only instantiated on the detail screen after the heroine transition.
/// Uses orbit controls for touch-based rotation.
class Badge3DViewer extends StatefulWidget {
  const Badge3DViewer({
    super.key,
    required this.glbAssetPath,
    required this.onModelLoaded,
    this.size = 250,
  });

  final String glbAssetPath;
  final VoidCallback onModelLoaded;
  final double size;

  @override
  State<Badge3DViewer> createState() => _Badge3DViewerState();
}

class _Badge3DViewerState extends State<Badge3DViewer> {
  late Flutter3DController _controller;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _controller = Flutter3DController();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Flutter3DViewer(
        controller: _controller,
        src: widget.glbAssetPath,
        enableTouch: true,
        onLoad: (String modelAddress) {
          if (!_loaded) {
            _loaded = true;
            widget.onModelLoaded();
          }
        },
      ),
    );
  }
}
