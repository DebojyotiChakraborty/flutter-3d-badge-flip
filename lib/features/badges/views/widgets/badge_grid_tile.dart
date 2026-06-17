import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:heroine/heroine.dart';

import '../../../../core/constants/animation_constants.dart';
import '../../../../core/utils/heroine_helpers.dart';
import '../../models/badge_model.dart';
import 'badge_3d_viewer.dart';

/// A single grid cell in the badge grid.
///
/// Displays the actual 3D badge model rendered via flutter_scene.
/// The heroine transition uses only the live 3D widget (no thumbnail fallback),
/// so the same visual element scales and flips into the detail screen.
///
/// The 3D viewer is wrapped in a [Heroine] widget for shared-element
/// transitions to the detail screen. Since flutter_scene renders on
/// Flutter's canvas (not a WebView), the actual 3D model participates
/// in the heroine flip transition.
class BadgeGridTile extends StatefulWidget {
  const BadgeGridTile({super.key, required this.badge});

  final AwardBadge badge;

  @override
  State<BadgeGridTile> createState() => _BadgeGridTileState();
}

class _BadgeGridTileState extends State<BadgeGridTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final badge = widget.badge;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.mediumImpact();
        context.push('/badge/${badge.id}');
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? AnimationConstants.pressScaleFactor : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Badge 3D model with heroine wrapper + optional glow
            Expanded(child: Center(child: _buildBadgeImage(badge))),
            const SizedBox(height: 6),

            // Badge name.
            // Reserve a fixed two-line band so every tile's badge area is the
            // same height — otherwise single- vs two-line labels would push the
            // badges to different vertical positions within a row. The label is
            // centered horizontally and truncated with an ellipsis past 2 lines.
            SizedBox(
              height: 30,
              width: double.infinity,
              child: Text(
                badge.name,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 11,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgeImage(AwardBadge badge) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileSize = constraints.maxWidth.clamp(0.0, constraints.maxHeight);

        // The fixed size lives OUTSIDE the Heroine so the flight shuttle can
        // re-size the viewer to the (growing) flight rect. The 3D viewer then
        // renders the scene at the flight's real resolution instead of being a
        // small grid-sized render that gets scaled up — which looked pixelated.
        //
        // The 3D viewer participates in the flip transition because
        // flutter_scene renders on Flutter's canvas.
        return RepaintBoundary(
          child: SizedBox(
            width: tileSize,
            height: tileSize,
            child: Heroine(
              tag: badge.heroTag,
              motion: badgeMotion(),
              flightShuttleBuilder: badgeShuttleBuilder,
              child: Badge3DViewer(
                modelAssetPath: badge.modelAssetPath,
                size: tileSize,
                onModelLoaded: () {},
                enableTouch: false, // No touch controls in grid
                continuousRendering: true,
              ),
            ),
          ),
        );
      },
    );
  }
}
