import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:heroine/heroine.dart';

import 'core/theme/app_theme.dart';
import 'features/badges/views/badge_detail_screen.dart';
import 'features/badges/views/badge_grid_screen.dart';

/// Custom page route with HeroinePageRouteMixin for drag-dismiss support.
class _HeroineDetailPageRoute extends PageRoute<void>
    with HeroinePageRouteMixin<void> {
  _HeroineDetailPageRoute({
    required this.pageBuilder,
    required HeroineDetailPage page,
  }) : super(settings: page);

  final WidgetBuilder pageBuilder;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 400);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return pageBuilder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
      ),
      child: child,
    );
  }
}

/// Custom GoRouter page that uses HeroinePageRouteMixin.
class HeroineDetailPage extends CustomTransitionPage<void> {
  HeroineDetailPage({
    required super.child,
    super.key,
  }) : super(
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              child,
        );

  @override
  Route<void> createRoute(BuildContext context) {
    return _HeroineDetailPageRoute(
      pageBuilder: (_) => child,
      page: this,
    );
  }
}

/// Main GoRouter configuration.
final _router = GoRouter(
  observers: [HeroineController()],
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const BadgeGridScreen(),
    ),
    GoRoute(
      path: '/badge/:id',
      pageBuilder: (context, state) {
        final id = state.pathParameters['id']!;
        return HeroineDetailPage(
          key: state.pageKey,
          child: BadgeDetailScreen(badgeId: id),
        );
      },
    ),
  ],
);

/// Root application widget.
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Fitness Badges',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: _router,
    );
  }
}
