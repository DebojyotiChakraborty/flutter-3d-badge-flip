import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../viewmodels/badge_grid_viewmodel.dart';
import 'widgets/badge_grid_tile.dart';

/// The main grid screen showing all achievement badges.
///
/// Uses a [CustomScrollView] with a header ("Awards") and a
/// 3-column grid of [BadgeGridTile] widgets.
class BadgeGridScreen extends ConsumerWidget {
  const BadgeGridScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badges = ref.watch(badgeListProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Awards',
                      style:
                          Theme.of(context).textTheme.headlineLarge?.copyWith(
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Close Your Rings',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 15,
                          ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // Badge grid
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.75,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => BadgeGridTile(badge: badges[index]),
                  childCount: badges.length,
                ),
              ),
            ),

            // Bottom padding
            const SliverToBoxAdapter(
              child: SizedBox(height: 40),
            ),
          ],
        ),
      ),
    );
  }
}
