# Context: Apple Fitness Achievement Badge Viewer — Flutter

## Overview

Recreate the Apple Fitness "Close Your Rings" achievement badge experience in Flutter. Badges are **real 3D objects the entire time** — in the grid, during the hero transition, and in the detail view — just like Apple does with SceneKit.

Tapping a badge triggers a shared-element transition where the **actual 3D model** flies from grid to detail, scaling up and performing 2 full Y-axis rotations (720°) with a spring bounce at the end. The 3D geometry is visible at every angle during the flip — you see the edge thickness, metallic reflections, and back face — not a paper-thin flat image.

## How Apple Does It (from analysis)

Apple uses **SceneKit** scenes embedded in UIKit/SwiftUI collection view cells. Each grid cell contains a live SceneKit scene with the 3D badge model rendered from a fixed camera angle. Tapping opens a full-screen SceneKit scene with the same model, with a custom shared-element transition. The detail view enables touch-controlled rotation.

Key insight: the 3D model is what transitions. It's not a flat thumbnail that gets swapped for a 3D model later. The depth, edge, and reflections are visible throughout the animation.

## Flutter Equivalent: flutter_scene

**`flutter_scene`** (https://pub.dev/packages/flutter_scene) is the Flutter equivalent of SceneKit for our purposes. It's a pure Dart 3D rendering library that paints directly to the Flutter canvas via Flutter GPU / Impeller.

### Why flutter_scene (and NOT flutter_3d_controller or model_viewer_plus)

| Package                | Rendering          | Inside Heroine? | Grid Performance |
|------------------------|--------------------|-----------------|------------------|
| `flutter_3d_controller`| Platform WebView   | ❌ No — opaque platform view, blank during flight | ❌ 6+ WebViews = unusable |
| `model_viewer_plus`    | Platform WebView   | ❌ Same problem  | ❌ Same problem   |
| `flutter_scene`        | Native Flutter canvas (Impeller) | ✅ Yes — normal widget, composites like any other | ✅ Native rendering, no WebView overhead |

`flutter_scene` renders like a `CustomPainter`. It's a regular Flutter widget that participates in the normal render tree. This means:
- It CAN be placed inside a `Heroine` widget.
- It CAN be placed inside a shuttle builder during hero flight.
- Multiple instances CAN exist in a grid without WebView overhead.
- Camera/model rotation CAN be controlled programmatically per frame.

### flutter_scene Status & Risks

- **Latest version**: 0.9.2-0 (prerelease), published ~June 2025.
- **Dart SDK**: Requires 3.7 (dev). May need Flutter master/beta channel.
- **Impeller**: Required. Default on iOS and Android since Flutter 3.22+. Must be explicitly enabled on macOS/Windows/Linux.
- **Features**: GLB/glTF import, PBR materials, environment maps/IBL, blended animations.
- **Risk**: Prerelease. API may change. Not battle-tested in production. The experimental Dart "Native Assets" feature is required for asset import.
- **Mitigation**: If flutter_scene proves unusable, fall back to Option B (pre-rendered sprite sequence) or Option D (flat flip during flight + flutter_3d_controller for post-landing interaction). See Fallback Strategy section.

### flutter_scene Key API

```dart
import 'package:flutter_scene/flutter_scene.dart';
import 'package:vector_math/vector_math.dart';

// Load a GLB model
final scene = await Scene.fromGlb('assets/badges/glb/move_record.glb');

// Render in a widget
SceneWidget(
  scene: scene,
  camera: PerspectiveCamera(
    position: Vector3(0, 0, 5),
    target: Vector3.zero(),
  ),
)

// Programmatic rotation: rotate the root node
scene.rootNode.localTransform = Matrix4.rotationY(angleInRadians);
// OR rotate the camera position around Y axis:
camera = PerspectiveCamera(
  position: Vector3(sin(angle) * 5, 0, cos(angle) * 5),
  target: Vector3.zero(),
);
```

> **IMPORTANT**: The exact API above is approximate. The agent MUST read the actual flutter_scene source/docs/examples before implementing. The `Scene`, `SceneWidget`, `Camera`, and `Node` APIs may have different names or signatures. Check:
> - https://github.com/bdero/flutter_scene/tree/master/example
> - https://pub.dev/documentation/flutter_scene/latest/

---

## Tech Stack

| Layer              | Choice                                                                   |
| ------------------ | ------------------------------------------------------------------------ |
| Framework          | Flutter (beta or master channel — required for flutter_scene)            |
| State Management   | Riverpod (flutter_riverpod + riverpod_annotation)                        |
| Architecture       | MVVM                                                                     |
| 3D Rendering       | `flutter_scene` ^0.9.2-0 (native canvas 3D)                             |
| Hero Transitions   | `heroine` ^0.7.1                                                         |
| Animation/Motion   | `motor` ^1.1.0 (transitive via heroine)                                  |
| Navigation         | GoRouter                                                                 |
| Platform targets   | iOS & Android (Impeller default). macOS/Linux/Windows with --enable-impeller. |

---

## Architecture: How the 3D Badge Lives Through the Transition

### Grid View
Each grid cell contains a `flutter_scene` `SceneWidget` rendering the badge GLB from a fixed front-facing camera angle. No touch interaction — static render. The widget is wrapped in a `Heroine`.

```
GridTile
  └── Heroine(tag: badge.heroTag, motion: ..., flightShuttleBuilder: ...)
        └── BadgeSceneWidget(badge: badge, interactive: false)
              └── SceneWidget(scene: preloadedScene, camera: fixedFrontCamera)
```

### During Heroine Flight (The Shuttle Builder)
The custom `RotatingBadgeShuttleBuilder` takes the 3D scene widget and, on each animation frame, updates the model's Y-rotation to match `animation.value * 4 * π` (= 720° over the full animation). The 3D model rotates in true 3D with visible edges, depth, and reflections at every angle.

The spring overshoot from `Motion.bouncySpring()` causes the animation value to exceed 1.0 temporarily, which makes the rotation overshoot past 720° before settling back — the bounce effect.

### Detail View
Same `flutter_scene` widget but larger and with touch interaction enabled (drag to rotate). Wrapped in `Heroine` with same tag.

```
DetailScreen
  └── DragDismissable
        └── Heroine(tag: badge.heroTag, motion: ..., flightShuttleBuilder: ...)
              └── BadgeSceneWidget(badge: badge, interactive: true)
                    └── SceneWidget(scene: preloadedScene, camera: userControlledCamera)
  └── ReactToHeroineDismiss
        └── BadgeInfoCard(badge: badge)
```

### Scene Preloading Strategy
Loading GLB models has a cost. Strategy:
1. **On app start**: Preload all earned badge GLB scenes into a cache (`Map<String, Scene>`).
2. **Grid rendering**: Each grid tile reads from the cache. No per-tile load.
3. **During flight**: The shuttle builder reuses the cached scene. No loading during transition.
4. **Detail view**: Same cached scene, just with interactive camera controls.
5. **Unearned badges**: Don't preload GLBs. Show a greyscale placeholder (flat image or a simple grey disc scene).

```dart
// Scene cache provider (Riverpod)
@riverpod
Future<Map<String, Scene>> badgeSceneCache(Ref ref) async {
  final badges = ref.read(badgeListProvider);
  final cache = <String, Scene>{};
  for (final badge in badges.where((b) => b.isEarned)) {
    cache[badge.id] = await Scene.fromGlb(badge.glbAssetPath);
  }
  return cache;
}
```

---

## The Custom Shuttle Builder: RotatingBadgeShuttleBuilder

This is the core of the project. It replaces the `FlipShuttleBuilder` with true 3D rotation.

### Why Not Use FlipShuttleBuilder

`FlipShuttleBuilder` applies `Matrix4.rotateY()` to a flat 2D widget. This gives a "card flip" effect — at 90° and 270°, the widget is edge-on and paper-thin. There's no depth, no edge thickness, no back face.

With `flutter_scene`, we instead rotate the **3D model's transform** (or the camera), and the renderer draws the model from the new angle with full 3D fidelity.

### Implementation Sketch

```dart
class RotatingBadgeShuttleBuilder extends HeroineShuttleBuilder {
  final int halfFlips;        // 4 = 720°
  final bool flipForward;
  final Scene Function(BuildContext) sceneResolver; // Gets the cached Scene

  const RotatingBadgeShuttleBuilder({
    this.halfFlips = 4,
    this.flipForward = true,
    required this.sceneResolver,
    super.curve,
  });

  @override
  Widget call(
    BuildContext flightContext,
    Animation<double> animation,   // Raw spring value, CAN overshoot past 1.0
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    // Use animation.value DIRECTLY — no Curve.transform() clamping
    // This preserves spring overshoot for rotation bounce
    final scene = sceneResolver(flightContext);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final rawValue = animation.value;
        final angle = rawValue * halfFlips * pi;
        final direction = (flipForward ? 1.0 : -1.0) *
            (flightDirection == HeroFlightDirection.pop ? -1.0 : 1.0);

        // Update the 3D model's rotation
        scene.rootNode.localTransform = Matrix4.rotationY(angle * direction);

        return SceneWidget(
          scene: scene,
          camera: PerspectiveCamera(
            position: Vector3(0, 0, 5),
            target: Vector3.zero(),
          ),
        );
      },
    );
  }

  @override
  List<Object?> get props => [halfFlips, flipForward, curve];
}
```

**CRITICAL IMPLEMENTATION NOTES:**

1. **Scene mutation during flight**: We're mutating `scene.rootNode.localTransform` on every frame. Verify that flutter_scene supports this — the scene/node transform might need to be set differently. Study the flutter_scene examples for animation patterns.

2. **Scene resolution in shuttle builder**: The `sceneResolver` callback needs access to the preloaded scene cache. Since the shuttle builder is called with a `BuildContext`, you can potentially use `Provider.of<>()` or the Riverpod `ProviderContainer` to resolve the cached scene. Alternatively, store the scene reference directly in the shuttle builder if it's not const.

3. **Non-const shuttle builder**: Because `sceneResolver` is a function, this builder can't be `const`. This differs from `FlipShuttleBuilder`. Ensure heroine doesn't require const shuttle builders.

4. **The shuttle builder may not be the right place**: If accessing the scene from the shuttle builder's `call()` is architecturally awkward, an alternative is to use heroine's default shuttle behavior (which animates the actual Heroine child widget) and have the `BadgeSceneWidget` itself listen to the heroine's animation progress to update its rotation. Study whether the `Heroine` widget exposes its animation to children.

5. **Fallback if scene-in-shuttle fails**: If putting a `SceneWidget` inside the shuttle builder causes rendering issues (e.g., flutter_scene doesn't render correctly in the overlay layer that heroine uses for flights), fall back to: let heroine do its default position/scale animation on the `BadgeSceneWidget`, and separately drive the 3D rotation from within the widget itself using `animation.addListener()`.

---

## Heroine Configuration

### Motion
```dart
Motion.bouncySpring(
  duration: const Duration(milliseconds: 800),
  extraBounce: 0.15,  // Tune: 0.1=subtle, 0.2=dramatic overshoot
)
```

### GoRouter + HeroineController
```dart
GoRouter(
  observers: [HeroineController()],
  routes: [
    GoRoute(path: '/', builder: (_, __) => const BadgeGridScreen()),
    GoRoute(
      path: '/badge/:id',
      pageBuilder: (context, state) {
        final id = state.pathParameters['id']!;
        return HeroinePageRoute(
          builder: (context) => BadgeDetailScreen(badgeId: id),
        );
      },
    ),
  ],
)
```

### DragDismissable + ReactToHeroineDismiss
```dart
// Detail screen body
DragDismissable(
  onDismiss: () => context.pop(),
  child: Heroine(tag: badge.heroTag, ..., child: BadgeSceneWidget(badge: badge)),
)

// Fade out info card during drag dismiss
ReactToHeroineDismiss(
  builder: (context, progress, offset, child) =>
      Opacity(opacity: 1 - progress, child: child),
  child: BadgeInfoCard(badge: badge),
)
```

---

## Data Model

```dart
class Badge {
  final String id;
  final String name;
  final String description;
  final String glbAssetPath;
  final String? thumbnailAssetPath;  // Optional fallback
  final BadgeCategory category;
  final bool isEarned;
  final DateTime? dateEarned;
  final double? progress;
  final String? progressLabel;
  final Color accentColor;
  final Map<String, dynamic>? metadata;

  String get heroTag => 'badge_hero_$id';
}

enum BadgeCategory { closeYourRings, workouts, milestones, limitedEdition }
```

## Folder Structure

```
lib/
├── main.dart
├── app.dart
├── core/
│   ├── theme/
│   │   ├── app_theme.dart
│   │   └── badge_colors.dart
│   ├── constants/
│   │   └── animation_constants.dart
│   ├── scene/
│   │   ├── badge_scene_widget.dart         # Wrapper around SceneWidget
│   │   ├── badge_scene_cache.dart          # Riverpod provider for preloaded scenes
│   │   └── scene_camera_controller.dart    # Touch-to-rotate camera logic
│   └── transitions/
│       └── rotating_badge_shuttle_builder.dart  # THE CORE
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
│       │       ├── badge_info_card.dart
│       │       └── badge_progress_bar.dart
│       └── data/
│           ├── badge_repository.dart
│           └── sample_badges.dart
assets/
├── badges/
│   ├── glb/           # 3D model files
│   ├── thumbnails/    # Fallback PNGs (for unearned badges, loading states)
│   └── environment/   # HDR environment map for PBR lighting (optional)
```

## Dependencies (pubspec.yaml)

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.6.1
  riverpod_annotation: ^2.6.1
  go_router: ^14.0.0
  heroine: ^0.7.1
  flutter_scene: ^0.9.2-0          # Native 3D rendering
  vector_math: ^2.1.4              # 3D math (transitive via flutter_scene)
  shimmer: ^3.0.0

dev_dependencies:
  riverpod_generator: ^2.6.2
  build_runner: ^2.4.13
  riverpod_lint: ^2.6.2
```

> **Channel requirement**: `flutter_scene` requires Flutter master or beta channel due to experimental Dart Native Assets. Run `flutter channel master && flutter upgrade` before starting. On iOS/Android Impeller is already the default renderer — no extra flags needed.

---

## Fallback Strategy

If `flutter_scene` proves unusable (build failures, rendering bugs, API instability), fall back in this order:

### Fallback A: Pre-rendered Sprite Rotation
Render each GLB at 36 angles (every 10°) as PNGs using Blender/offline tooling. During the heroine flight, swap the displayed image based on `floor(animationValue * halfFlips * 180 / 10) % 36` to index into the sprite sheet. Gives 3D depth appearance without runtime 3D rendering.

### Fallback B: Flat Flip + Post-Landing 3D (Option D from earlier)
Use `FlipShuttleBuilder(halfFlips: 4)` with flat thumbnails during heroine flight. After landing, swap to `flutter_3d_controller` (WebView-based) for interactive 3D in the detail view. Optionally trigger a programmatic spin animation on the 3D model after it loads.

### Fallback C: CustomPainter 3D Coin
For simple badge shapes (disc/coin), implement a `CustomPainter` that draws an ellipse with gradient fills that simulate 3D rotation (width scales with cos(angle), shading shifts). Lightweight, no dependencies, works in heroine shuttle builder. Limited to simple geometry.

---

## Visual Design Notes

- Background: Pure black (#000000).
- Lighting: Single directional light from upper-left + ambient. Optional HDR environment map for PBR reflections.
- Badge shadows: Subtle radial glow beneath grid badges using accent color at ~15% opacity.
- Typography: System font. White primary, grey (#8E8E93) secondary.
- Grid: 16px gaps, 16px horizontal padding. 3 columns.
- Detail: Badge centered in upper 60%, info card in lower 40%.
- Earned badges: Full PBR render. Unearned: grey material or greyscale filter + 40% opacity.

## Performance Considerations

- **Scene preloading**: Load all earned badge GLBs on app start, async. Show shimmer loading state until cache is ready.
- **Grid rendering**: Each `SceneWidget` renders one badge. For 7 badges, that's 7 concurrent GPU scenes. Monitor frame rate — if problematic, render only visible tiles using `SliverGrid` + `AutomaticKeepAlive`.
- **Transition rendering**: During flight, only ONE scene is actively rotating (the shuttle builder's). Grid cells are hidden by Heroine's placeholder mechanism.
- **Memory**: Each loaded Scene holds GPU buffers. Dispose scenes for badges that scroll off screen if memory is tight.
- **Profile on real devices**: Flutter GPU / flutter_scene performance varies by device GPU. Always profile on real hardware, not emulators.
