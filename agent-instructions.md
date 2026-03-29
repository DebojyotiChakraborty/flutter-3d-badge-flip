# Agent Instructions: Apple Fitness Badge Viewer — Flutter

## READ FIRST

Read `context.md` before writing any code. It contains the full technical context, the heroine package architecture analysis, the bounce gap explanation, the BouncyFlipShuttleBuilder design, and all data models. Do not deviate from the architecture unless you hit a concrete blocker — document the blocker and your alternative.

---

## Build Order

Each phase must compile and run before moving to the next. Build incrementally.

---

### Phase 0: Project Bootstrap

1. Create a new Flutter project: `flutter create --org com.example --project-name fitness_badges fitness_badges`
2. Add dependencies from `context.md` to `pubspec.yaml`. Run `flutter pub get`.
3. Verify the project compiles and runs with the default counter app.
4. Delete the default counter code. Create all directories from the folder structure in `context.md`.
5. Set up `app.dart`:
   - `ProviderScope` at the root.
   - `MaterialApp.router` with `GoRouter`.
   - **Register `HeroineController` in GoRouter's `observers`** — this is mandatory for heroine to work.
   - Dark theme: `ThemeData.dark()` with `scaffoldBackgroundColor: Colors.black`.
   - Two routes: `/` (grid) and `/badge/:id` (detail).
   - The detail route should use `HeroinePageRoute` as its page builder for dismiss support.

**Checkpoint**: App launches to a black screen. No crashes. `HeroineController` is registered.

---

### Phase 1: Data Layer + Badge Grid (Static)

1. **`badge_model.dart`**: Implement the `Badge` class from `context.md`. Include a `heroTag` getter returning `'badge_hero_${id}'`.

2. **`sample_badges.dart`**: Create 7 sample badges matching the Apple Fitness awards from the reference screenshots:
   - New Move Record (earned, 343 kcal, pink accent)
   - Move Goal 200% (earned, orange accent)
   - New Move Goal (earned, 120 kcal, silver accent)
   - 100 Move Goals (unearned, 8/100 progress, green accent)
   - Move Goal 300% (unearned, 1/360 kcal, orange accent)
   - Move Goal 400% (unearned, 1/480 kcal, green accent)
   - Longest Move Streak (unearned, 0/8 days, green accent)

   Use placeholder `thumbnailAssetPath` and `glbAssetPath` values for now.

3. **`badge_repository.dart`**: Returns the sample badges list. Wrap in a Riverpod provider.

4. **`badge_grid_viewmodel.dart`**: Riverpod providers:
   - `badgeListProvider`: Returns all badges.
   - `badgeByIdProvider(String id)`: Returns single badge by ID.

5. **`badge_grid_screen.dart`**: Grid UI.
   - `GridView.builder` with `SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3)`.
   - 16px padding and spacing.
   - Each cell is a `BadgeGridTile`.
   - Black background, white title "Close Your Rings" at top with subtitle.

6. **`badge_grid_tile.dart`**: Single grid cell.
   - Display a placeholder colored circle (badge accent color) since no thumbnails yet.
   - Badge name and subtitle below the circle.
   - Earned: full opacity. Unearned: 40% opacity + greyscale via `ColorFiltered`.
   - **Wrap the image area in a `Heroine` widget** (NOT Flutter's `Hero`):
     ```dart
     Heroine(
       tag: badge.heroTag,
       // motion and flightShuttleBuilder will be added in Phase 3
       child: CircleAvatar(...), // placeholder
     )
     ```
   - `onTap`: Navigate to `/badge/${badge.id}` using `context.go(...)`.
   - Show a small progress bar below unearned badges.

**Checkpoint**: Grid of colored circles with labels. Tapping one navigates to detail page. Heroine performs a basic default spring transition (no flip yet). Back button returns with reverse spring.

---

### Phase 2: Detail Screen (Static, No 3D Yet)

1. **`badge_detail_viewmodel.dart`**: Provider that takes badge ID and returns badge data + a `glbLoadedState` (starts false).

2. **`badge_detail_screen.dart`**:
   - Receives badge ID from route params.
   - Layout: Badge image centered in upper 60%, info below.
   - **Wrap badge image in `Heroine` widget with same `tag` as grid tile**:
     ```dart
     Heroine(
       tag: badge.heroTag,
       child: CircleAvatar(...), // larger placeholder, ~250×250
     )
     ```
   - Below: `BadgeInfoCard` with name, description, date earned.
   - For unearned: `BadgeProgressBar` instead of date.
   - Back button or swipe-to-go-back dismisses.

3. **`badge_info_card.dart`**: Badge metadata display. White on dark, centered text.

4. **`badge_progress_bar.dart`**: Linear progress indicator with label. Badge accent color.

**Checkpoint**: Tapping grid tile navigates to detail with default Heroine spring animation (position + scale spring, no flip). Detail shows larger circle + info. Back returns with reverse spring.

---

### Phase 3: BouncyFlipShuttleBuilder — THE CORE FEATURE

This is the hardest and most critical phase. Read the "Bounce Gap" section in `context.md` thoroughly before starting.

#### Step 3.1: Study Heroine Source

Before writing the custom builder, read the heroine package source code:

1. Open `packages/heroine/lib/src/shuttle_builders/flip_shuttle_builder.dart` in the pub cache (`~/.pub-cache/hosted/pub.dev/heroine-0.7.1/`).
2. Study how `FlipShuttleBuilder.buildHero()` calculates rotation from `valueFromTo`.
3. Open `simple_shuttle_builder.dart` and study how `call()` maps `animation.value` through `curve.transform(t)` — this is the clamping point.
4. Open `heroine_shuttle_builder.dart` for the base class API.
5. Note how the `call()` method receives `fromHeroContext` and `toHeroContext` — understand how to extract the child widgets.

#### Step 3.2: Implement BouncyFlipShuttleBuilder

Create `lib/core/transitions/bouncy_flip_shuttle_builder.dart`.

The key difference from `FlipShuttleBuilder`: extend `HeroineShuttleBuilder` directly (NOT `SimpleShuttleBuilder`) and use `animation.value` raw, without clamping through `Curve.transform()`.

```dart
import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:heroine/heroine.dart';

class BouncyFlipShuttleBuilder extends HeroineShuttleBuilder {
  final Axis axis;
  final int halfFlips;
  final bool flipForward;
  final double perspective;

  const BouncyFlipShuttleBuilder({
    this.axis = Axis.vertical,
    this.halfFlips = 4,
    this.flipForward = true,
    this.perspective = 0.001,
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
    // CRITICAL: Use animation.value DIRECTLY
    // Do NOT map through curve.transform() — that clamps to [0,1] and kills the bounce
    // The Motion.bouncySpring() on the Heroine drives this value past 1.0 during overshoot
    // e.g., with extraBounce: 0.15, it might reach ~1.1 before settling to 1.0

    // --- STUDY THE HEROINE SOURCE to determine:
    // 1. How to correctly extract fromHero/toHero child widgets
    // 2. Whether AnimatedBuilder is needed or if call() is already invoked per frame
    // 3. How FlipShuttleBuilder handles the from/to crossfade (if any)
    // --- Then implement accordingly. The code below is the rotation logic:

    final rawValue = animation.value;
    final angle = rawValue * halfFlips * pi;

    final dirSign = (flipForward ? 1.0 : -1.0) *
        (flightDirection == HeroFlightDirection.pop ? -1.0 : 1.0);

    // TODO: Extract child correctly (see heroine source for pattern)
    // TODO: Handle from/to widget crossfade if children differ

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, perspective)
        ..rotateY(axis == Axis.vertical ? angle * dirSign : 0)
        ..rotateX(axis == Axis.horizontal ? angle * dirSign : 0),
      child: /* resolved child */,
    );
  }

  @override
  List<Object?> get props => [axis, halfFlips, flipForward, perspective, curve];
}
```

**IMPORTANT**: The `TODO` comments are real — you MUST study the heroine source to fill these in. Do not guess. The child extraction pattern may involve `context.widget`, element tree walking, or a dedicated API. Get this wrong and you'll get blank frames during flight.

#### Step 3.3: Possible Alternative — Subclass SimpleShuttleBuilder with Override

If extending `HeroineShuttleBuilder` directly proves too complex (too much internals to reimplement), try an alternative: extend `SimpleShuttleBuilder` but **override `call()`** to bypass the clamping:

```dart
class BouncyFlipShuttleBuilder extends SimpleShuttleBuilder {
  // ...

  @override
  Widget call(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    // Call buildHero with the RAW unclamped value instead of curve.transform(value)
    final rawValue = animation.value;

    // Manually extract fromHero and toHero the same way SimpleShuttleBuilder does
    final fromHero = fromHeroContext.widget as Heroine;
    final toHero = toHeroContext.widget as Heroine;

    return buildHero(
      flightContext: flightContext,
      fromHero: fromHero.child,
      toHero: toHero.child,
      valueFromTo: rawValue,  // UNCLAMPED — this is the key change
      flightDirection: flightDirection,
    );
  }

  @override
  Widget buildHero({
    required BuildContext flightContext,
    required Widget fromHero,
    required Widget toHero,
    required double valueFromTo,  // Now receives unclamped spring value
    required HeroFlightDirection flightDirection,
  }) {
    final angle = valueFromTo * halfFlips * pi;
    // ... rotation transform ...
  }
}
```

This is cleaner because `buildHero()` gets the from/to child widgets pre-resolved by the parent. But verify `SimpleShuttleBuilder.call()` actually passes `fromHeroine.child` — check the source.

#### Step 3.4: Apply the Builder

Update both `Heroine` widgets (grid tile + detail screen):

```dart
Heroine(
  tag: badge.heroTag,
  motion: Motion.bouncySpring(
    duration: const Duration(milliseconds: 800),
    extraBounce: 0.15,
  ),
  flightShuttleBuilder: const BouncyFlipShuttleBuilder(
    axis: Axis.vertical,
    halfFlips: 4,
    flipForward: true,
  ),
  child: badgeWidget,
)
```

#### Step 3.5: Create animation_constants.dart

```dart
abstract class AnimationConstants {
  static const heroFlightDuration = Duration(milliseconds: 800);
  static const springExtraBounce = 0.15;
  static const flipHalfFlips = 4;
  static const flipPerspective = 0.001;
}
```

#### Step 3.6: Create heroine_helpers.dart

Factory for consistent Heroine configuration:

```dart
import 'package:heroine/heroine.dart';
import '../constants/animation_constants.dart';
import '../transitions/bouncy_flip_shuttle_builder.dart';

Motion badgeMotion() => Motion.bouncySpring(
  duration: AnimationConstants.heroFlightDuration,
  extraBounce: AnimationConstants.springExtraBounce,
);

const badgeShuttleBuilder = BouncyFlipShuttleBuilder(
  axis: Axis.vertical,
  halfFlips: AnimationConstants.flipHalfFlips,
  flipForward: true,
  perspective: AnimationConstants.flipPerspective,
);
```

Then in both grid tile and detail screen:
```dart
Heroine(
  tag: badge.heroTag,
  motion: badgeMotion(),
  flightShuttleBuilder: badgeShuttleBuilder,
  child: widget,
)
```

#### Step 3.7: Tune the Spring

Run the app and iterate on these values:

| Parameter      | Start Value | Range to Test | Effect                                   |
| -------------- | ----------- | ------------- | ---------------------------------------- |
| `extraBounce`  | 0.15        | 0.05 – 0.3   | More = bigger rotation overshoot         |
| `duration`     | 800ms       | 600 – 1200ms  | Total flight time                        |
| `halfFlips`    | 4           | 2 – 6         | Number of half-rotations                 |
| `perspective`  | 0.001       | 0.0005–0.003  | 3D depth exaggeration                    |

The bounce should feel natural — about 10-20° of overshoot past 720° then settle.

**If `Motion.bouncySpring` overshoot is too symmetrical** (i.e., bounce at the start AND end): try `Motion.customSpring(SpringDescription(mass: 1, stiffness: 180, damping: 15))` and tune the damping ratio for an underdamped spring that only visibly overshoots at the end.

**Checkpoint**: Tapping a badge triggers the full cinematic transition: fly + scale + 2× Y-axis flip + bounce settle on the rotation. Reverse on back. This should look impressive even with placeholder circles.

---

### Phase 4: Real Thumbnails

1. Create or obtain badge thumbnail images. Options:
   - `CustomPainter` concentric circles/gradients matching Apple badge style.
   - Real screenshots processed into PNGs.
   - If GLBs are available, render thumbnails from them.

2. Place in `assets/badges/thumbnails/`, declare in `pubspec.yaml`.

3. Update `sample_badges.dart` with real asset paths.

4. Update `BadgeGridTile` to use `Image.asset()` with circular clip + optional glow shadow.

5. Update `BadgeDetailScreen` heroine child to use same image (larger).

**Checkpoint**: Grid shows realistic badge thumbnails. Heroine flips a real image.

---

### Phase 5: 3D GLB Viewer in Detail

1. Add GLB files to `assets/badges/glb/`. Simple metallic disc/sphere if real badges unavailable.

2. **`badge_3d_viewer.dart`**: Wrapper around `Flutter3DController`.
   - Initialize controller in `initState`.
   - Front-facing camera position.
   - Enable touch rotation (orbit controls).
   - `onModelLoaded` callback.
   - Dispose controller in `dispose`.

3. **Integrate into detail screen** with crossfade pattern:
   - Initially show the static thumbnail (this is what Heroine animates).
   - After heroine transition completes, start loading GLB.
   - When GLB loads, crossfade from thumbnail to live 3D viewer (300ms opacity).

4. **State management**: `badge_detail_viewmodel` exposes `glbLoaded` state. `Badge3DViewer.onModelLoaded` updates it.

**Checkpoint**: After flip-transition completes, static badge seamlessly morphs into interactive 3D model.

---

### Phase 6: Polish & Micro-interactions

1. **Grid tile press effect**: Subtle scale-down on press (0.95×) using `GestureDetector` + `AnimatedScale`.

2. **Badge glow**: Radial gradient behind each earned badge using accent color at ~15% opacity.

3. **Detail view entrance**: Stagger-animate info card sliding up from below (200ms delay, 400ms duration).

4. **Haptic feedback**: `HapticFeedback.mediumImpact()` on badge tap.

5. **DragDismissable**: Wrap the detail Heroine in `DragDismissable(onDismiss: () => context.pop())`. Add `ReactToHeroineDismiss` to fade out the info card during drag.

6. **Locked badge tap**: Unearned badge still does heroine transition but shows lock icon + progress requirements (no 3D model).

7. **Scroll behavior**: `CustomScrollView` + `SliverToBoxAdapter` (header) + `SliverGrid` (badges).

8. **Safe area**: Respect notch and home indicator insets.

**Checkpoint**: Polished, close to Apple Fitness reference.

---

### Phase 7: Optional Enhancements

Only after Phases 0-6 are stable.

- **Gyroscope tilt**: `sensors_plus` for accelerometer → subtle 3D badge tilt (±15°).
- **Category filtering**: Chips/tabs to filter by badge category.
- **Badge unlock animation**: Particle/shine effect when badge transitions earned → unearned.
- **Share sheet**: Long-press badge → share rendered image + text.

---

## Key Gotchas & Debugging Tips

### Heroine Issues

- **No transition at all**: Did you register `HeroineController` in `GoRouter.observers`? This is the #1 cause.
- **"No Heroine found" / silent failure**: Both source and destination must have `Heroine` widgets with the exact same `tag` string and both must be in the widget tree when transition starts.
- **Clipping during rotation**: The 3D-rotated badge can get clipped by parent containers. Set `clipBehavior: Clip.none` on parent `Container`, `Card`, `SizedBox` etc.
- **Black flash on push**: The detail page scaffold renders before Heroine arrives. Use `FadeTransition` for the page transition background, or ensure scaffold background is pure black.
- **Double animation on iOS back swipe**: Heroine handles this automatically — it skips its animation when pop is triggered by a user gesture. No special handling needed.
- **GoRouter compatibility**: `HeroinePageRoute` may or may not integrate cleanly with GoRouter's `pageBuilder`. If issues arise, use `CustomTransitionPage` with `FadeTransition` and let the Heroine handle the hero animation independently.

### BouncyFlipShuttleBuilder Issues

- **Blank frame during flight**: You're extracting the child widget incorrectly. Study heroine source to see how `SimpleShuttleBuilder.call()` resolves `fromHero`/`toHero`.
- **Rotation not bouncing**: You're still clamping through `Curve.transform()`. Ensure you're reading `animation.value` directly.
- **Rotation bounces too much**: Reduce `extraBounce` on `Motion.bouncySpring()`. Or switch to `Motion.snappySpring()`.
- **Rotation direction wrong on pop**: Check the `directionSign` calculation — flip the sign for `HeroFlightDirection.pop`.
- **Widget shows back-face at end**: With `halfFlips: 4` (even number), the widget should end in its original orientation. If it doesn't, check that your angle calculation uses `halfFlips * pi` (not `2 * pi`).

### flutter_3d_controller

- Uses platform views (WebView). Noticeable load time — always show thumbnail first.
- Android emulator performance is poor. Test on real device.
- Only one model viewer active at a time to avoid memory issues.
- Alternative: `model_viewer_plus` has similar API.

### Performance

- Profile with `flutter run --profile`. Watch for jank during heroine transition.
- Use `RepaintBoundary` around grid tiles.
- Thumbnail images: ≤200×200 logical pixels for grid.

## Testing Checklist

- [ ] `HeroineController` registered in GoRouter observers.
- [ ] Grid displays all badges (earned = color, unearned = grey).
- [ ] Tapping earned badge triggers Heroine + 2× Y-flip + bounce settle on rotation.
- [ ] Rotation BOUNCES past 720° and springs back (not just position bounce).
- [ ] Tapping unearned badge shows locked state with progress.
- [ ] Back navigation plays reverse animation smoothly.
- [ ] iOS back swipe does NOT double-animate.
- [ ] 3D GLB viewer loads and is interactive in detail view.
- [ ] Crossfade from thumbnail to 3D is seamless.
- [ ] No memory leaks (3D controller disposed on pop).
- [ ] Works on both iOS and Android real devices.
- [ ] No clipping artifacts during rotation.
- [ ] Info card stagger animation plays after Heroine lands.
- [ ] DragDismissable works (drag badge down → dismiss + reverse fly).
- [ ] Grid scrolls smoothly with 7+ badges.
- [ ] Dark theme throughout, no white flashes.
