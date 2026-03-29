import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:heroine/heroine.dart';

import '../../../core/constants/animation_constants.dart';
import '../../../core/theme/badge_colors.dart';
import '../../../core/utils/heroine_helpers.dart';
import '../viewmodels/badge_grid_viewmodel.dart';
import 'widgets/badge_3d_viewer.dart';
import 'widgets/badge_info_card.dart';
import 'widgets/badge_thumbnail.dart';

/// Detail screen for a single badge.
///
/// Layout: Badge image in upper 60%, info card in lower 40%.
/// The badge thumbnail is wrapped in [Heroine] + [DragDismissable].
/// After the heroine transition lands, the 3D GLB viewer loads and
/// crossfades with the static thumbnail.
///
/// IMPORTANT: The 3D viewer (WebView) is placed OUTSIDE the Heroine child.
/// WebViews break when reparented into overlays during heroine flights.
class BadgeDetailScreen extends ConsumerStatefulWidget {
  const BadgeDetailScreen({
    super.key,
    required this.badgeId,
  });

  final String badgeId;

  @override
  ConsumerState<BadgeDetailScreen> createState() => _BadgeDetailScreenState();
}

class _BadgeDetailScreenState extends ConsumerState<BadgeDetailScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _infoCardController;
  late Animation<double> _infoCardOpacity;
  late Animation<Offset> _infoCardSlide;
  bool _glbLoaded = false;
  bool _showGlbViewer = false;

  @override
  void initState() {
    super.initState();

    // Stagger-animate the info card entrance.
    _infoCardController = AnimationController(
      vsync: this,
      duration: AnimationConstants.infoCardDuration,
    );
    _infoCardOpacity = CurvedAnimation(
      parent: _infoCardController,
      curve: AnimationConstants.infoCardCurve,
    );
    _infoCardSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _infoCardController,
      curve: AnimationConstants.infoCardCurve,
    ));

    // Delay the info card entrance to let the heroine transition land first.
    Future.delayed(
      AnimationConstants.heroFlightDuration + AnimationConstants.infoCardDelay,
      () {
        if (mounted) {
          _infoCardController.forward();
          // Start loading the 3D viewer AFTER heroine transition completes.
          // This prevents WebView from being reparented during flight.
          setState(() => _showGlbViewer = true);
        }
      },
    );
  }

  @override
  void dispose() {
    _infoCardController.dispose();
    super.dispose();
  }

  void _onGlbLoaded() {
    if (mounted) {
      setState(() => _glbLoaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final badge = ref.watch(badgeByIdProvider(widget.badgeId));
    if (badge == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'Badge not found',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    final badgeSize = MediaQuery.of(context).size.width * 0.65;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Upper 60% — badge image area
            Expanded(
              flex: 6,
              child: Center(
                child: SizedBox(
                  width: badgeSize,
                  height: badgeSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Layer 1: Heroine with thumbnail (participates in flight)
                      DragDismissable(
                        child: Heroine(
                          tag: badge.heroTag,
                          motion: badgeMotion(),
                          flightShuttleBuilder: badgeShuttleBuilder,
                          child: Container(
                            width: badgeSize,
                            height: badgeSize,
                            decoration: badge.isEarned
                                ? BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: BadgeColors.glowFor(
                                            badge.accentColor),
                                        blurRadius: 40,
                                        spreadRadius: 10,
                                      ),
                                    ],
                                  )
                                : null,
                            child: BadgeThumbnail(
                              accentColor: badge.accentColor,
                              isEarned: badge.isEarned,
                              size: badgeSize,
                            ),
                          ),
                        ),
                      ),

                      // Layer 2: 3D GLB viewer OUTSIDE Heroine
                      // Only instantiated after heroine flight completes
                      // to prevent WebView from breaking during reparenting.
                      if (_showGlbViewer && badge.isEarned)
                        AnimatedOpacity(
                          opacity: _glbLoaded ? 1.0 : 0.0,
                          duration: AnimationConstants.crossfadeDuration,
                          child: SizedBox(
                            width: badgeSize,
                            height: badgeSize,
                            child: Badge3DViewer(
                              glbAssetPath: badge.glbAssetPath,
                              size: badgeSize,
                              onModelLoaded: _onGlbLoaded,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // Lower 40% — info card with stagger animation
            Expanded(
              flex: 4,
              child: ReactToHeroineDismiss(
                builder: (context, progress, offset, child) {
                  return Opacity(
                    opacity: (1 - progress).clamp(0.0, 1.0),
                    child: child,
                  );
                },
                child: SlideTransition(
                  position: _infoCardSlide,
                  child: FadeTransition(
                    opacity: _infoCardOpacity,
                    child: SingleChildScrollView(
                      child: BadgeInfoCard(badge: badge),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
