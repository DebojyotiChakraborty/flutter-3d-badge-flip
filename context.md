# Context: Apple Fitness Achievement Badge Viewer — Flutter

## Overview

Recreate the Apple Fitness "Close Your Rings" achievement badge experience in Flutter. The app displays a grid of 3D metallic achievement badges. Tapping a badge triggers a cinematic shared-element transition: the badge flies from its grid position to a detail view, simultaneously scaling up and performing **two full Y-axis rotations (720°)** with a **spring/bounce ease-back** at the end before settling.

## Reference Behavior (Apple Fitness)

- **Grid view**: Dark background, badges in a 3-column grid. Earned badges are full-color metallic 3D; unearned badges are greyed-out silhouettes.
- **Tap → Detail view**: The tapped badge performs a shared element transition:
  1. Badge lifts from grid position.
  2. Simultaneously scales up to ~70% of screen width.
  3. During flight, performs 2 complete Y-axis flips (0° → 720°).
  4. Lands at center of detail screen with a bouncy overshoot settle (~10-20° past 720° then springs back).
- **Detail view**: Full-size 3D badge (interactive via drag/gyroscope), badge name, description, date earned, progress info.
- **Dismiss**: Reverse animation back to grid.

## Tech Stack

| Layer              | Choice                                                                   |
| ------------------ | ------------------------------------------------------------------------ |
| Framework          | Flutter (latest stable)                                                  |
| State Management   | Riverpod (flutter_riverpod + riverpod_annotation for codegen)            |
| Architecture       | MVVM (Model → ViewModel/Provider → View)                                |
| 3D Rendering       | GLB files via `flutter_3d_controller` (or `model_viewer_plus`)           |
| Hero Transitions   | `heroine` ^0.7.1 (https://pub.dev/packages/heroine)                     |
| Animation/Motion   | `motor` ^1.1.0 (transitive dependency of heroine)                       |
| Navigation         | GoRouter                                                                 |
| Platform targets   | iOS & Android                                                            |

---

## Heroine Package — Architecture Deep Dive

The `heroine` package replaces Flutter's `Hero` widget with spring-based hero transitions. Understanding its layered architecture is critical.

### Core Concepts

**`Heroine` widget** — Drop-in `Hero` replacement. Takes a `tag`, `child`, optional `motion` (controls flight spring), and optional `flightShuttleBuilder` (controls visual transforms during flight).

**`HeroineController`** — Must be registered as a `NavigatorObserver`. Without this, heroine transitions silently fail.

```dart
GoRouter(
  observers: [HeroineController()],
  routes: [...],
)
```

**`Motion`** — Controls the physics of the overall flight animation (position interpolation from source rect → destination rect). Drives `animation.value` from 0.0 → 1.0, with possible overshoot for bouncy springs.

Available presets:
- `Motion.bouncySpring({duration, extraBounce, snapToEnd})` — Spring with overshoot.
- `Motion.smoothSpring({duration, extraBounce, snapToEnd})` — No overshoot.
- `Motion.snappySpring({duration, extraBounce, snapToEnd})` — Small overshoot, faster settle.
- `Motion.customSpring(SpringDescription)` — Fully custom flutter SpringDescription.
- `CupertinoMotion.smooth()` — Default iOS feel. This is the default if no motion specified.
- `Motion.curved(Duration, Curve)` — Duration-based, not spring-based.

**`HeroineShuttleBuilder`** — Abstract class. Defines how the widget looks *during* flight. This is where visual transforms (flip, fade, scale) are applied.

**`SimpleShuttleBuilder`** — Abstract subclass of `HeroineShuttleBuilder`. Provides a simpler API: override `buildHero({fromHero, toHero, valueFromTo, flightDirection})` where `valueFromTo` is a 0.0→1.0 value mapped through the builder's `curve`.

**`FlipShuttleBuilder`** — Concrete `SimpleShuttleBuilder` that applies Y or X axis rotation.

### FlipShuttleBuilder API

```dart
const FlipShuttleBuilder({
  Axis axis = Axis.vertical,          // Axis.vertical = Y-axis flip
  bool flipForward = true,            // Direction of rotation
  bool invertFlipOnReturn = false,    // Reverse direction on pop
  int halfFlips = 1,                  // 1 = 180°, 2 = 360°, 4 = 720°
  Curve curve = Curves.fastOutSlowIn, // Applied to valueFromTo before rotation calc
})
```

**`halfFlips: 4`** gives us the 2 full rotations (720°) we need.

### The Bounce Gap — Why We Need a Custom Shuttle Builder

This is the single most important architectural detail in the project:

1. `Motion.bouncySpring()` drives the Heroine's overall `animation.value`. This value **CAN overshoot past 1.0** with a bouncy spring (e.g., it might hit ~1.1 before settling to 1.0). This overshoot is what makes position and scale bounce.

2. **BUT** `SimpleShuttleBuilder.call()` (the base class of `FlipShuttleBuilder`) maps `animation.value` through its `curve` property using `Curve.transform(t)`. Flutter's `Curve.transform()` **asserts that t is in [0.0, 1.0]** and clamps the input.

3. **Result**: Position/scale bounce ✅ (driven directly by Motion spring overshoot). Flip rotation bounce ❌ (clamped by Curve.transform inside SimpleShuttleBuilder).

The flip animation reaches exactly 720° and stops dead. No overshoot, no spring-back on the rotation. This is the gap.

### Solution: BouncyFlipShuttleBuilder

Create a custom shuttle builder that extends `HeroineShuttleBuilder` **directly** (bypassing `SimpleShuttleBuilder`) so we can access the raw `animation.value` without clamping:

```dart
class BouncyFlipShuttleBuilder extends HeroineShuttleBuilder {
  final Axis axis;
  final int halfFlips;
  final bool flipForward;
  final double perspective;

  const BouncyFlipShuttleBuilder({
    this.axis = Axis.vertical,
    this.halfFlips = 4,         // 2 full rotations = 720°
    this.flipForward = true,
    this.perspective = 0.001,
    super.curve,
  });

  @override
  Widget call(
    BuildContext flightContext,
    Animation<double> animation,  // RAW spring value — CAN overshoot past 1.0
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    // DO NOT clamp through Curve.transform() — use raw animation.value
    final rawValue = animation.value;

    // Rotation in radians: halfFlips * π * rawValue
    // When spring overshoots to 1.1 with halfFlips=4: 4 * π * 1.1 = ~792° (72° overshoot)
    final rotationAngle = rawValue * halfFlips * pi;

    final directionSign = (flipForward ? 1.0 : -1.0) *
        (flightDirection == HeroFlightDirection.pop ? -1.0 : 1.0);

    // Determine which child to show
    // For even halfFlips (2, 4, 6...) the widget ends facing forward
    // For odd halfFlips (1, 3, 5...) it ends showing the back
    final fromHeroine = fromHeroContext.widget as Heroine;
    final toHeroine = toHeroContext.widget as Heroine;
    final child = flightDirection == HeroFlightDirection.push
        ? toHeroine.child
        : fromHeroine.child;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, perspective)
            ..rotateY(axis == Axis.vertical ? rotationAngle * directionSign : 0)
            ..rotateX(axis == Axis.horizontal ? rotationAngle * directionSign : 0),
          child: child,
        );
      },
    );
  }

  @override
  List<Object?> get props => [axis, halfFlips, flipForward, perspective, curve];
}
```

**Critical implementation notes:**
- This is a SKETCH. The actual child extraction from heroine contexts may differ — study the heroine source code's `SimpleShuttleBuilder.call()` to see exactly how it resolves `fromHero`/`toHero` widgets. The `Heroine` widget's `child` property may not be directly accessible via `context.widget as Heroine` — you may need to walk the element tree.
- If even halfFlips, the widget ends in its original orientation (720° = 0° visually). If odd, it ends flipped. We want even (4).
- The `AnimatedBuilder` might be redundant if heroine already rebuilds on animation tick — check the call site.
- `perspective: 0.001` is a good starting value. Smaller = less dramatic 3D effect. Larger = more dramatic but can distort.

### Recommended Heroine Configuration

```dart
// Both grid tile AND detail screen must use matching config:
Heroine(
  tag: 'badge_${badge.id}',
  motion: Motion.bouncySpring(
    duration: const Duration(milliseconds: 800),
    extraBounce: 0.15,  // Tune: 0.1 = subtle, 0.2 = dramatic
  ),
  flightShuttleBuilder: const BouncyFlipShuttleBuilder(
    axis: Axis.vertical,
    halfFlips: 4,       // 4 half-flips = 2 full rotations = 720°
    flipForward: true,
  ),
  child: MyBadgeWidget(),
)
```

### GoRouter + Heroine Integration

```dart
GoRouter(
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
        // Option A: Use HeroinePageRoute for drag-dismiss support
        return HeroinePageRoute(
          builder: (context) => BadgeDetailScreen(badgeId: id),
        );
        // Option B: CustomTransitionPage for manual control
        // return CustomTransitionPage(
        //   child: BadgeDetailScreen(badgeId: id),
        //   transitionsBuilder: (ctx, anim, secAnim, child) =>
        //       FadeTransition(opacity: anim, child: child),
        // );
      },
    ),
  ],
)
```

### DragDismissable (Optional Enhancement)

Heroine supports drag-to-dismiss out of the box:

```dart
// In detail screen, wrap the Heroine:
DragDismissable(
  onDismiss: () => context.pop(),
  child: Heroine(
    tag: 'badge_${badge.id}',
    flightShuttleBuilder: const BouncyFlipShuttleBuilder(...),
    motion: Motion.bouncySpring(...),
    child: BadgeDetailImage(badge: badge),
  ),
)

// Fade out background content during drag:
ReactToHeroineDismiss(
  builder: (context, progress, offset, child) {
    return Opacity(opacity: 1 - progress, child: child);
  },
  child: BadgeInfoCard(badge: badge),
)
```

### User Gesture Pop Behavior

When a route is popped via a user gesture (iOS back swipe), Heroine automatically skips its transition animation. This prevents jarring double-animations. No special handling needed.

---

## Grid Thumbnails vs. Live 3D

Rendering 6-9 simultaneous GLB WebViews in a grid is too expensive. Use **pre-rendered PNG/WebP thumbnails** in the grid. Only instantiate the 3D model viewer in the detail view after the heroine transition completes.

Crossfade from thumbnail to live 3D after transition:
```dart
Stack(
  children: [
    AnimatedOpacity(
      opacity: glbLoaded ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: thumbnailImage,
    ),
    AnimatedOpacity(
      opacity: glbLoaded ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Flutter3DViewer(src: badge.glbPath),
    ),
  ],
)
```

## Data Model

```dart
class Badge {
  final String id;
  final String name;
  final String description;
  final String glbAssetPath;
  final String thumbnailAssetPath;
  final BadgeCategory category;
  final bool isEarned;
  final DateTime? dateEarned;
  final double? progress;         // 0.0-1.0
  final String? progressLabel;    // e.g., '8 of 100'
  final Map<String, dynamic>? metadata;

  String get heroTag => 'badge_hero_$id';
}

enum BadgeCategory { closeYourRings, workouts, milestones, limitedEdition }
```

## Folder Structure

```
lib/
├── main.dart
├── app.dart                          # MaterialApp.router + GoRouter + ProviderScope
├── core/
│   ├── theme/
│   │   ├── app_theme.dart
│   │   └── badge_colors.dart
│   ├── constants/
│   │   └── animation_constants.dart  # Spring configs, flip counts
│   ├── transitions/
│   │   └── bouncy_flip_shuttle_builder.dart  # THE CORE — custom shuttle builder
│   └── utils/
│       └── heroine_helpers.dart      # Shared Heroine config factory
├── features/
│   └── badges/
│       ├── models/
│       │   └── badge_model.dart
│       ├── viewmodels/
│       │   ├── badge_grid_viewmodel.dart
│       │   └── badge_detail_viewmodel.dart
│       ├── views/
│       │   ├── badge_grid_screen.dart
│       │   ├── badge_detail_screen.dart
│       │   └── widgets/
│       │       ├── badge_grid_tile.dart
│       │       ├── badge_3d_viewer.dart
│       │       ├── badge_info_card.dart
│       │       └── badge_progress_bar.dart
│       └── data/
│           ├── badge_repository.dart
│           └── sample_badges.dart
assets/
├── badges/
│   ├── glb/
│   └── thumbnails/
```

## Dependencies (pubspec.yaml)

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.6.1
  riverpod_annotation: ^2.6.1
  go_router: ^14.0.0
  heroine: ^0.7.1                 # Spring-based hero transitions (brings motor transitively)
  flutter_3d_controller: ^2.0.0   # GLB rendering
  shimmer: ^3.0.0                 # Loading placeholders

dev_dependencies:
  riverpod_generator: ^2.6.2
  build_runner: ^2.4.13
  riverpod_lint: ^2.6.2
```

> Verify latest compatible versions at build time. `heroine` is actively developed — check for API changes.

## Visual Design Notes

- Background: Pure black (`#000000`).
- Badge shadows: Subtle radial glow using badge accent color at ~15% opacity.
- Typography: System font. White primary text, grey (`#8E8E93`) secondary.
- Grid: 16px gaps, 16px horizontal padding. 3 columns.
- Detail: Badge centered in upper 60%, info card in lower 40%.
- Earned badges: Full color. Unearned: greyscale + 40% opacity + `ColorFiltered`.
