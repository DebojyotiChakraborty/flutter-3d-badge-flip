import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:heroine/heroine.dart';

import '../../../core/constants/animation_constants.dart';
import '../../../core/utils/heroine_helpers.dart';
import '../viewmodels/badge_grid_viewmodel.dart';
import 'widgets/badge_3d_viewer.dart';
import 'widgets/badge_info_card.dart';

/// Detail screen for a single badge.
///
/// Layout: Badge image in upper 60%, info card in lower 40%.
/// The badge 3D viewer is wrapped in [Heroine] + [DragDismissable].
///
/// Because flutter_scene renders directly on Flutter's canvas (not a WebView),
/// the 3D model CAN participate in heroine flights and Matrix4 transforms.
/// This means the actual 3D badge flips during the shared-element transition.
class BadgeDetailScreen extends ConsumerStatefulWidget {
  const BadgeDetailScreen({super.key, required this.badgeId});

  final String badgeId;

  @override
  ConsumerState<BadgeDetailScreen> createState() => _BadgeDetailScreenState();
}

class _BadgeDetailScreenState extends ConsumerState<BadgeDetailScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _infoCardController;
  late Animation<double> _infoCardOpacity;
  late Animation<Offset> _infoCardSlide;

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
    _infoCardSlide =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _infoCardController,
            curve: AnimationConstants.infoCardCurve,
          ),
        );

    // Delay the info card entrance to let the heroine transition land first.
    Future.delayed(
      AnimationConstants.heroFlightDuration + AnimationConstants.infoCardDelay,
      () {
        if (mounted) _infoCardController.forward();
      },
    );
  }

  @override
  void dispose() {
    _infoCardController.dispose();
    super.dispose();
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
            // Upper 60% — badge 3D model
            Expanded(
              flex: 6,
              child: Center(
                child: DragDismissable(
                  child: Heroine(
                    tag: badge.heroTag,
                    motion: badgeMotion(),
                    flightShuttleBuilder: badgeShuttleBuilder,
                    // The 3D viewer is INSIDE the Heroine child.
                    // flutter_scene renders on Flutter's canvas,
                    // so Matrix4 transforms during flight work correctly.
                    child: SizedBox(
                      width: badgeSize,
                      height: badgeSize,
                      child: Badge3DViewer(
                        modelAssetPath: badge.modelAssetPath,
                        size: badgeSize,
                        onModelLoaded: () {},
                        enableTouch: true,
                        initialRotationY:
                            AnimationConstants.flipOvershootRadians,
                        autoSnapToProfileOnLoad: true,
                        initialSnapDelay: AnimationConstants.heroFlightDuration,
                        initialSnapCurve: AnimationConstants.heroFlightCurve,
                      ),
                    ),
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
