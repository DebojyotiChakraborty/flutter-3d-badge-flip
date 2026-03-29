import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:heroine/heroine.dart';

import '../../../../core/constants/animation_constants.dart';
import '../../../../core/theme/badge_colors.dart';
import '../../../../core/utils/heroine_helpers.dart';
import '../../models/badge_model.dart';
import 'badge_progress_bar.dart';
import 'badge_thumbnail.dart';

/// A single grid cell in the badge grid.
///
/// Displays a metallic thumbnail with the badge name below.
/// Earned badges are full-color with a subtle glow.
/// Unearned badges are greyscale at 40% opacity with a progress bar.
///
/// The thumbnail is wrapped in a [Heroine] widget for shared-element
/// transitions to the detail screen.
class BadgeGridTile extends StatefulWidget {
  const BadgeGridTile({
    super.key,
    required this.badge,
  });

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
            // Badge thumbnail with heroine wrapper + optional glow
            Expanded(
              child: Center(
                child: _buildBadgeImage(badge),
              ),
            ),
            const SizedBox(height: 6),

            // Badge name
            Text(
              badge.name,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: badge.isEarned
                        ? Colors.white.withValues(alpha: 0.9)
                        : Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            // Progress bar for unearned badges
            if (!badge.isEarned && badge.progress != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: BadgeProgressBar(
                  progress: badge.progress!,
                  color: badge.accentColor,
                  height: 3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBadgeImage(AwardBadge badge) {
    // Subtle radial glow behind earned badges
    Widget thumbnailWidget = BadgeThumbnail(
      accentColor: badge.accentColor,
      isEarned: badge.isEarned,
    );

    if (badge.isEarned) {
      thumbnailWidget = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: BadgeColors.glowFor(badge.accentColor),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: thumbnailWidget,
      );
    }

    // Wrap in Heroine for shared-element transition.
    // RepaintBoundary for grid rendering performance.
    return RepaintBoundary(
      child: Heroine(
        tag: badge.heroTag,
        motion: badgeMotion(),
        flightShuttleBuilder: badgeShuttleBuilder,
        child: thumbnailWidget,
      ),
    );
  }
}
