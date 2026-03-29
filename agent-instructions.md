# Agent Instructions: Apple Fitness Badge Viewer — Flutter

## READ FIRST

Read `context.md` before writing any code. It contains the architecture, the flutter_scene rationale, the RotatingBadgeShuttleBuilder design, the fallback strategy, and all data models.

**Key architectural principle**: The 3D badge model is a real `flutter_scene` 3D object the entire time — in the grid, during the hero transition, and in the detail view. We do NOT use flat thumbnails with `Matrix4.rotateY()`. The 3D geometry is visible at every angle during the flip.

---

## Pre-Build: flutter_scene Viability Check

Before scaffolding the app, verify that flutter_scene works in your environment.

### Step 0.1: Switch to Flutter Master Channel

```bash
flutter channel master
flutter upgrade
flutter --version  # Verify Dart >= 3.7
```

### Step 0.2: Create a Throwaway Test Project

```bash
flutter create scene_test && cd scene_test
flutter pub add flutter_scene
```

Follow the flutter_scene README setup:
- Install CMake (required for native assets build).
- Add a simple GLB file (download any free GLB from https://sketchfab.com or use a simple one).
- Try to render it with a `SceneWidget`.
- Verify it builds and renders on iOS simulator or Android device.

### Step 0.3: Decision Point

- **If flutter_scene works** → Proceed with the primary architecture below.
- **If flutter_scene fails to build or render** → Read the "Fallback Strategy" section in `context.md`. Implement Fallback B (flat flip + flutter_3d_controller post-landing). Adapt the phases below accordingly. Document what failed and why.

---

## Build Order (Primary: flutter_scene)

Each phase must compile and run before the next.

---

### Phase 0: Project Bootstrap

1. Create project: `flutter create --org com.example --project-name fitness_badges fitness_badges`
2. **Ensure Flutter master channel** (required for flutter_scene).
3. Install CMake if not present (flutter_scene uses Native Assets).
4. Add all dependencies from `context.md` to `pubspec.yaml`. Run `flutter pub get`.
5. Verify compilation with default counter app.
6. Delete default code. Create folder structure from `context.md`.
7. Set up `app.dart`:
   - `ProviderScope` at root.
   - `MaterialApp.router` with `GoRouter`.
   - **`observers: [HeroineController()]`** — mandatory for Heroine transitions.
   - Dark theme: `scaffoldBackgroundColor: Colors.black`.
   - Two routes: `/` (grid), `/badge/:id` (detail using `HeroinePageRoute`).

**Checkpoint**: Black screen app launches. No crashes.

---

### Phase 1: flutter_scene Hello World

Before building the full app, prove the 3D pipeline works.

1. **Obtain a test GLB file**: Create or download a simple metallic disc/coin shape. Place in `assets/badges/glb/test_badge.glb`. Declare in `pubspec.yaml` assets.

2. **Study flutter_scene examples**: Read the source at https://github.com/bdero/flutter_scene/tree/master/example. Understand:
   - How to load a Scene from a GLB asset.
   - How to render with `SceneWidget` or a custom `SceneNode` render widget.
   - How to set camera position.
   - How to rotate the model/node programmatically.
   - What the actual class names and method signatures are (the API in `context.md` is approximate — use the REAL API).

3. **Create a test screen** that:
   - Loads the GLB scene asynchronously.
   - Renders it centered on screen.
   - Auto-rotates it around the Y axis using a `Ticker` or `AnimationController`.
   - Shows the badge spinning continuously.

4. **Verify**: You see a 3D metallic object spinning smoothly with proper lighting, reflections, and depth. If not, debug flutter_scene setup before proceeding.

**Checkpoint**: A 3D badge spins on screen at 60fps. You can see edge thickness at 90° and 270°.

---

### Phase 2: Scene Cache + Data Layer

1. **`badge_model.dart`**: Implement the `Badge` class from `context.md`. Include `heroTag` getter.

2. **`sample_badges.dart`**: Create 7 sample badges matching Apple Fitness screenshots (see `context.md` for the list). Point `glbAssetPath` to real or placeholder GLB files.

3. **`badge_repository.dart`**: Returns sample badges. Wrap in Riverpod provider.

4. **`badge_scene_cache.dart`**: Riverpod `FutureProvider` that preloads all earned badge GLB files into a `Map<String, Scene>` on app start. This cache is the single source of truth for 3D scenes.

   ```dart
   @riverpod
   Future<Map<String, Scene>> badgeSceneCache(Ref ref) async {
     final badges = ref.read(badgeListProvider);
     final cache = <String, Scene>{};
     for (final badge in badges.where((b) => b.isEarned)) {
       cache[badge.id] = await Scene.fromGlb(badge.glbAssetPath);
       // ^ Use the REAL flutter_scene API to load. This is approximate.
     }
     return cache;
   }
   ```

5. **`badge_scene_widget.dart`**: Reusable widget that renders a badge's 3D scene.
   - Takes a `Scene` (from cache), a `camera` config, and an `interactive` flag.
   - When `interactive: false` (grid): static front-facing camera, no touch response.
   - When `interactive: true` (detail): touch-to-rotate via gesture detector updating camera position.
   - Handles the case where the scene is null (unearned badge) by showing a grey placeholder.

**Checkpoint**: All badge scenes preload on app start. `BadgeSceneWidget` renders a 3D badge from cache.

---

### Phase 3: Badge Grid

1. **`badge_grid_viewmodel.dart`**: Riverpod providers for badge list and badge-by-id lookup.

2. **`badge_grid_screen.dart`**:
   - Shows loading shimmer while scene cache loads.
   - Once loaded, displays `CustomScrollView` with:
     - `SliverToBoxAdapter`: "Close Your Rings" title + subtitle.
     - `SliverGrid`: 3 columns, 16px spacing, `BadgeGridTile` cells.

3. **`badge_grid_tile.dart`**:
   - Earned: `BadgeSceneWidget(interactive: false)` showing the 3D badge.
   - Unearned: Greyscale placeholder with progress bar.
   - Wrapped in `Heroine`:
     ```dart
     Heroine(
       tag: badge.heroTag,
       motion: Motion.bouncySpring(
         duration: const Duration(milliseconds: 800),
         extraBounce: 0.15,
       ),
       // flightShuttleBuilder will be added in Phase 5
       child: BadgeSceneWidget(
         scene: sceneCache[badge.id],
         interactive: false,
       ),
     )
     ```
   - `onTap`: `context.go('/badge/${badge.id}')`.

**Checkpoint**: Grid shows 3D rendered badges from fixed camera angles. Each badge is a real 3D object with metallic PBR materials. Tapping navigates with a default Heroine spring (no rotation yet).

---

### Phase 4: Detail Screen

1. **`badge_detail_viewmodel.dart`**: Provider for selected badge state.

2. **`badge_detail_screen.dart`**:
   - Badge `Heroine` with `BadgeSceneWidget(interactive: true)` in upper 60%.
   - `BadgeInfoCard` with name, description, date in lower 40%.
   - For unearned: locked state with progress bar.
   - Wrap Heroine in `DragDismissable(onDismiss: () => context.pop())`.
   - Wrap info card in `ReactToHeroineDismiss` to fade on drag.

3. **`scene_camera_controller.dart`**: Touch-to-rotate logic.
   - `GestureDetector` wrapping the `SceneWidget`.
   - `onPanUpdate`: map dx to Y-axis rotation, dy to X-axis tilt.
   - Optional: momentum / spring deceleration after pan ends.

4. **`badge_info_card.dart`** + **`badge_progress_bar.dart`**: As before.

**Checkpoint**: Tapping a grid badge navigates to detail with default Heroine spring. Detail shows interactive 3D badge you can rotate by dragging. Drag-dismiss returns to grid.

---

### Phase 5: RotatingBadgeShuttleBuilder — THE CORE

This is where the magic happens. The 3D model rotates in true 3D during the hero flight.

#### Step 5.1: Study Heroine Internals

Read the heroine source in pub cache (`~/.pub-cache/hosted/pub.dev/heroine-0.7.1/lib/src/`):

1. **`heroine_shuttle_builder.dart`**: Base class API. Understand `call()` signature.
2. **`simple_shuttle_builder.dart`**: How it maps animation.value → valueFromTo via curve. This is what we're BYPASSING.
3. **`flip_shuttle_builder.dart`**: How it extracts fromHero/toHero children. Copy this pattern.
4. **The heroine flight overlay**: Understand where the shuttle widget lives during flight (it's in an Overlay, not in the widget tree of either route). This matters for context-dependent lookups like Provider/Riverpod.

#### Step 5.2: Scene Access Strategy

The shuttle builder runs in an Overlay, outside both routes' widget trees. This means `ref.read()` from Riverpod may not work directly. Options:

**Option A**: Store the `Scene` reference directly on the shuttle builder (not const):
```dart
class RotatingBadgeShuttleBuilder extends HeroineShuttleBuilder {
  final Scene scene;
  // ...
}
```
Create the builder dynamically when constructing the Heroine widget, passing in the scene from cache.

**Option B**: Use a global/static scene cache that doesn't need Riverpod context:
```dart
class BadgeSceneCache {
  static final Map<String, Scene> _cache = {};
  static Scene? get(String badgeId) => _cache[badgeId];
  // populated during app init
}
```

**Option C**: Extract the `BadgeSceneWidget` from the Heroine's child in `fromHeroContext` / `toHeroContext` and get the scene from it.

Choose whichever works with heroine's architecture. Option A is simplest.

#### Step 5.3: Implement RotatingBadgeShuttleBuilder

```dart
class RotatingBadgeShuttleBuilder extends HeroineShuttleBuilder {
  final Scene scene;
  final int halfFlips;
  final bool flipForward;

  RotatingBadgeShuttleBuilder({
    required this.scene,
    this.halfFlips = 4,       // 2 full rotations
    this.flipForward = true,
    super.curve,
  });

  @override
  Widget call(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        // RAW value — DO NOT clamp. Spring overshoot creates the bounce.
        final rawValue = animation.value;
        final angle = rawValue * halfFlips * pi;
        final dirSign = (flipForward ? 1.0 : -1.0) *
            (flightDirection == HeroFlightDirection.pop ? -1.0 : 1.0);

        // Rotate the 3D model — use the REAL flutter_scene API
        scene.rootNode.localTransform = Matrix4.rotationY(angle * dirSign);

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
  List<Object?> get props => [scene, halfFlips, flipForward, curve];
}
```

**THIS IS A SKETCH.** You MUST:
1. Replace approximate flutter_scene API calls with real ones.
2. Handle scene node rotation vs camera rotation (study examples to determine which gives better visual results).
3. Test that `SceneWidget` renders correctly inside the Heroine overlay.
4. Handle the scene lifecycle — ensure the scene isn't disposed or corrupted during flight.

#### Step 5.4: Wire Up the Shuttle Builder

Update both grid tile and detail screen Heroine widgets:

```dart
// In BadgeGridTile
final scene = sceneCache[badge.id]!;
Heroine(
  tag: badge.heroTag,
  motion: Motion.bouncySpring(
    duration: const Duration(milliseconds: 800),
    extraBounce: 0.15,
  ),
  flightShuttleBuilder: RotatingBadgeShuttleBuilder(
    scene: scene,
    halfFlips: 4,
    flipForward: true,
  ),
  child: BadgeSceneWidget(scene: scene, interactive: false),
)
```

Same config on detail screen Heroine.

#### Step 5.5: Tune the Spring

Run the app and adjust:

| Parameter      | Start | Range     | Effect                            |
| -------------- | ----- | --------- | --------------------------------- |
| `extraBounce`  | 0.15  | 0.05–0.3  | Rotation overshoot amount         |
| `duration`     | 800ms | 600–1200  | Flight duration                   |
| `halfFlips`    | 4     | 2–6       | Rotation count                    |

The bounce should be visible as the badge rotating ~20° past 720° then springing back.

**Checkpoint**: Tapping a grid badge triggers the full transition: the REAL 3D model flies from grid to detail, performing 2 full Y-axis rotations where you can see the badge's edge, back, and depth at every angle. The rotation bounces at the end. Reverse on back.

---

### Phase 6: Polish

1. **Grid tile press effect**: Scale-down 0.95× on press.
2. **Badge glow**: Radial gradient shadow behind earned badges using accent color.
3. **Detail info entrance**: Stagger-animate info card sliding up after Heroine lands.
4. **Haptic feedback**: `HapticFeedback.mediumImpact()` on tap and bounce settle.
5. **Locked badges**: Unearned badges use greyscale placeholder, transition shows lock overlay.
6. **Scroll behavior**: `SliverAppBar` + `SliverGrid` for scrollable header.
7. **Safe area**: Respect notch/home indicator.
8. **Environment lighting**: Add an HDR environment map for realistic PBR reflections on the metallic badges.

**Checkpoint**: App feels polished and close to Apple Fitness.

---

### Phase 7: Optional Enhancements

- **Gyroscope tilt**: `sensors_plus` for accelerometer → subtle tilt on detail view badge.
- **Category filtering**: Tabs/chips.
- **Badge unlock animation**: Particle/shine effect.
- **Share**: Long-press → snapshot → share sheet.

---

## Key Gotchas

### flutter_scene
- **"Native Assets" build errors**: Ensure CMake is installed. On macOS: `brew install cmake`. On Linux: `apt-get install cmake`.
- **Doesn't render**: Verify Impeller is enabled. On iOS/Android it's the default. On desktop, pass `--enable-impeller`.
- **API mismatch**: The API in `context.md` is APPROXIMATE. Read the actual source/docs before implementing. Class names, method signatures, and widget names may differ.
- **Multiple SceneWidgets in grid**: If frame rate drops, consider rendering only visible tiles. Use `SliverGrid` with `AutomaticKeepAlive`.

### Heroine
- **No transition**: `HeroineController` not in `GoRouter.observers`. This is the #1 cause.
- **Blank shuttle during flight**: The shuttle builder's SceneWidget isn't rendering in the overlay. Try wrapping in `RepaintBoundary` or `Material(type: MaterialType.transparency)`.
- **Scene corrupted after flight**: The same `Scene` instance is shared between grid tile, shuttle builder, and detail view. Ensure only one is actively modifying `rootNode.localTransform` at a time. Reset the transform when the flight completes.
- **Clipping during rotation**: `clipBehavior: Clip.none` on parent widgets.

### Scene Cache / Memory
- **Loading time**: GLB loading is async. Show a shimmer grid until cache is populated.
- **Memory pressure**: Each Scene holds GPU buffers. With 7+ badges, monitor memory. Dispose scenes for off-screen badges if needed.
- **Scene mutation safety**: When the shuttle builder rotates the scene, the grid tile and detail view should NOT also be trying to render the same scene simultaneously. Heroine handles this via its placeholder mechanism (the source widget shows a placeholder during flight), but verify this.

## Testing Checklist

- [ ] Flutter master channel, CMake installed, flutter_scene builds.
- [ ] GLB loads and renders in flutter_scene with PBR materials.
- [ ] Scene cache preloads all earned badge scenes.
- [ ] Grid shows 3D badges (not flat images) from fixed camera angle.
- [ ] `HeroineController` registered in GoRouter observers.
- [ ] Tapping badge triggers Heroine + true 3D Y-rotation (visible depth at 90°/270°).
- [ ] Rotation bounces past 720° and springs back (not just position bounce).
- [ ] Reverse animation on back/dismiss is smooth.
- [ ] iOS back swipe doesn't double-animate (Heroine handles this).
- [ ] Detail view allows touch-to-rotate the 3D badge.
- [ ] DragDismissable works from detail view.
- [ ] No scene corruption after multiple transitions.
- [ ] Unearned badges show locked state.
- [ ] 60fps on real iOS and Android devices during grid scroll AND transition.
- [ ] Dark theme throughout, no white flashes.
