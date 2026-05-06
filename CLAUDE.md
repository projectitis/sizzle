# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Sizzle is a bitmap/pixel game engine for Flutter, built on top of Flame. It specializes in perfect pixel-art rendering with automatic scaling, letterboxing, and scene management. It can also be used to develop non-pixel-art projects. The project is in alpha stage.

## Development Commands

### Testing
The test suite depends on `flutter_test` (which needs `dart:ui`), so use the Flutter test runner — not `dart test`.

```bash
# Run all tests
flutter test

# Run a specific test file
flutter test test/utils/pool_test.dart

# Run tests in a directory
flutter test test/display/

# Update golden files (for visual regression tests)
flutter test --update-goldens
```

### Code Quality
```bash
# Run static analysis
dart analyze

# Format code (project uses require_trailing_commas lint)
dart format .
```

### Dependencies
```bash
# Install dependencies
flutter pub get

# Note: jenny dependency uses a local path (see pubspec.yaml).
# Flame may also switch to a local path during development - check the
# commented lines in pubspec.yaml.
```

### Documentation
Two documentation systems live in `docs/`:

- `docs/*.md` — hand-written guides (game structure, services, snap, pooling, etc.).
- `docs/api/` — generated dartdoc output.

```bash
# Generate API documentation (output: docs/api/)
# Comment out external exports in lib/sizzle.dart first - see docs/readme.md
dart doc --output=docs/api .

# Docs configuration in dartdoc_options.yaml
```

### Asset Workflows

**PlySprite Export from Aseprite**
- Sizzle uses a custom compact sprite format called PlySprite
- Lua exporter script: `scripts/aseprite/ply-sprite.lua`
- Installation:
  1. Open Aseprite → File → Scripts → Open scripts folder
  2. Copy `ply-sprite.lua` to the scripts folder
  3. File → Scripts → Rescan scripts folder
- Usage: File → Scripts → ply-sprite (exports current sprite to PlySprite format)

## Architecture

### Core Game Structure

**SizzleGame** (`lib/src/game/game.dart`)
- Extends `FlameGame` from Flame
- Manages scene routing via `RouterComponent`
- Handles pixel-perfect scaling and letterboxing
- Key concepts:
  - `targetSize`: Always-visible game area (e.g., 320×240)
  - `maxSize`: Maximum drawable area (can be larger than target)
  - `viewWindow`: Actual visible area on screen (between target and max)
  - `snapScale`: Pixel scaling factor for perfect pixel rendering
  - `scaleToWholePixels`: Ensures pixels are whole numbers of screen pixels

**Scene** (`lib/src/game/scene.dart`)
- Base class for all game screens/scenes
- Extends Flame `Component` with `HasGameReference<SizzleGame>`
- Each scene is mounted on-demand by the router
- The `scenes:` map (or `scene:`) takes a constructor reference, not an instance. Use `MyScene.new` for the simple case, or supply a closure (`() => MyScene(arg)`) when the scene needs constructor arguments.
- Use `changeScene(name)` to navigate between scenes

### Services Architecture

**Services** (`lib/src/utils/services.dart`)
- Static class providing global access to game services (no instantiation)
- Access pattern: `Services.images.load()`, `Services.flags['key']`, etc.
- `Services.save()` / `Services.load()` persist flags + dialog variables. Hook into `Services.onSave` / `Services.onLoad` to round-trip your own data.

**FileService** (`lib/src/utils/services/file_service.dart`)
- Asset loading and caching from the `assets/` folder
- Uses an enqueue/`loadQueue` pattern shared with the image and SVG services
- Methods: `enqueue`/`enqueueAll`, `loadQueue`, `load`, `loadString`, `loadJson`, `loadJX`, plus cached accessors `get`/`getString`/`getJson`/`getJX`, `contains`, `remove`, `clear`

**ImageService** (`lib/src/utils/services/image_service.dart`)
- Image loading, caching, and on-load transformations (scale, crop, rotate, flip, blend)
- `defaultProperties` applies a baseline transform to every load (per-image properties merge on top, or set `ignoreDefaultProperties` to bypass)
- Same enqueue/`loadQueue` flow as FileService

**SvgService** (`lib/src/utils/services/svg_service.dart`)
- Parses and caches `Svg` assets for `SvgComponent`
- Same enqueue/`loadQueue` flow as the file and image services

**FlagService** (`lib/src/utils/services/flag_service.dart`)
- Boolean game state tracking (flags either exist or don't)
- Pattern: `Services.flags['castle_key'] = true;` then check `Services.flags.flagged('castle_key')` or `Services.flags['castle_key']`
- Automatically persisted in save/load

**DialogService** (`lib/src/utils/services/dialog_service.dart`)
- Wraps Flame's jenny (Yarn Spinner) package
- API: `Services.dialog.load(files)`, `parse(data)`, `start(node, views)`, `clear(...)`
- Yarn scripts can read/write flags via the auto-registered `flag` command and `flagged()` function

**Logger** (`lib/src/utils/logger.dart`)
- Accessed via `Services.log`. Defaults to `PrintLogger`; `PrintJsonLogger` and `FileLogger` are also provided. Implement the `Logger` interface for custom sinks.

### Display Components

Located in `lib/src/display/`:
- **sprite.dart**: PlySprite and animated sprite components
- **snap.dart**: `Snap` mixin and components that auto-scale/pixel-snap (`SnapPositionComponent`, `SnapSpriteComponent`, plus the `AnchorWindow` enum)
- **shape.dart**: `SnapRectangleComponent`
- **dialog.dart**: Speech bubble dialog component (`DialogComponent`, `SnapDialogComponent`, plus `DialogStyle`/`DialogTextStyle`/`DialogOptions`)
- **ninegrid.dart**: Nine-slice scaling for UI elements
- **lightning.dart**: Lightning visual effect (uses object pooling)
- **tile.dart**: Tile/tilemap components
- **environment.dart**: `EnvironmentComponent`, `Environment`, and `AmbientLight`/`DirectionalLight` for lit rendering
- **svg.dart**: `Svg` parser for the project's narrow SVG subset (Paraplu namespace, line/move/close paths only)
- **svg_component.dart**: `SvgComponent` — renders a parsed `Svg` with cascading lighting from the nearest `Environment` ancestor. Recomposes lazily; rotating ancestors must extend `EnvironmentComponent` for the dirty cascade to work.

### Text

- `lib/src/text/text.dart`: `TextAreaComponent`, `SnapTextAreaComponent`, plus `TextAreaLine`/`CharCode` helpers used by the dialog system.

### Math, Physics & Utils

- `lib/src/math/`: Vector utilities and math helpers
- `lib/src/physics/`: `Lifetime` (TTL components) and `Movement` (mixin for moving components)
- `lib/src/utils/pool.dart`: `Pool<T>` and `Pooled` mixin for object pooling. See `docs/pool.md`.
- `lib/src/utils/device.dart`: platform/device helpers
- `lib/src/utils/logger.dart`: see Services Architecture above

## Testing Patterns

### Test Helpers (`test/sizzle_test_helpers.dart`)

**testWithSizzleGame()**
```dart
testWithSizzleGame(
  'Component can be added to game',
  (game) async {
    final component = MyComponent()..addToParent(game);
    await game.ready();
    expect(component.isMounted, true);
  },
);
```

**testWithGame<T>()**
For tests that need a custom-constructed game (e.g. with specific scenes or sizes):
```dart
testWithGame<SizzleGame>(
  'Custom factory passes constructor arguments to the scene',
  () => SizzleGame(
    scenes: {'level': () => LeveledScene(42)},
    targetSize: Vector2(150, 100),
  ),
  (game) async {
    await game.ready();
    expect((game.currentScene! as LeveledScene).level, 42);
  },
);
```

**testGolden()**
```dart
testGolden(
  'Renders correctly',
  (game) async {
    final scene = game.currentScene!;
    scene.add(MyComponent());
  },
  game: SizzleGame(scene: Scene.new, targetSize: Vector2(150, 100)),
  size: Vector2(300, 200),
  goldenFile: '$goldens/my-test.png',
);
```

**DiskAssetBundle**
- Use `DiskAssetBundle.loadFromPath('test/_resources/')` to load test assets
- Required for tests that need images or other asset files
- Example in `test/game/game_test.dart`

### Test Organization

- Tests mirror `lib/` structure under `test/`
- Golden files stored in `test/_goldens/`
- Test resources in `test/_resources/` (the SVG fixtures live in `test/_resources/svg/`)
- Each test file corresponds to a source file (e.g. `pool.dart` → `test/utils/pool_test.dart`)

## Code Patterns

### Creating a Scene
The simplest scene only needs to extend `Scene`:

```dart
class MyScene extends Scene {
  @override
  Future<void> onLoad() async {
    Services.images.enqueue(path: 'player.png');
    await Services.images.loadQueue();
    add(SpriteComponent.fromImage(Services.images['player.png']!));
  }
}

// In main()
SizzleGame(scenes: {'my': MyScene.new});
```

If the scene needs constructor arguments, swap `MyScene.new` for a closure:

```dart
SizzleGame(scenes: {'level': () => LevelScene(currentLevel)});
```

### Scene Navigation
```dart
// From within a Scene:
changeScene('menu');

// From anywhere with game reference:
Services.game.changeScene('game', replace: true);
```

### Using Services

**Image Loading Pattern (Recommended)**
```dart
// Workflow: Enqueue → LoadQueue → Use → Clear

// 1. Enqueue images (in constructors/setup)
Services.images.enqueue(path: 'images/ui/background.png');
Services.images.enqueue(properties: ImageProperties(
  'images/player.png',
  name: 'player-left',  // Optional shorter name
  scale: Vector2.all(0.5),
  flipX: true,
));

// 2. Load all queued images (in onLoad)
await Services.images.loadQueue();

// 3. Access cached images
final bg = Services.images['images/ui/background.png'];
final player = Services.images['player-left'];  // Using short name

// 4. Clear when done (optional)
Services.images.remove('images/ui/background.png');
Services.images.clear();  // Remove all

// Alternative: Load without queueing (must manually dispose)
final img = await Services.images.load(path: 'sprite.png', cache: false);
img.dispose();
```

The same enqueue/`loadQueue` pattern applies to `Services.files` and `Services.svg`.

**Flags and State**
```dart
// Set and check flags
Services.flags['level_complete'] = true;
if (Services.flags.flagged('level_complete')) { }

// Save/load game state (includes flags and dialog state by default)
await Services.save();
await Services.load();

// Persist your own data alongside flags + yarn variables
Services.onSave = (data) => data['hi_score'] = score;
Services.onLoad = (data) => score = data['hi_score'] as int? ?? 0;
```

### Pixel-Perfect Rendering

Components with the `Snap` mixin (or one of the `Snap*` components) automatically scale and pixel-snap:
- `SnapPositionComponent`
- `SnapSpriteComponent`
- `SnapRectangleComponent`
- `SnapTextAreaComponent`
- `SnapDialogComponent`

Access the current pixel scale via `game.snapScale` for custom positioning.

### Object Pooling

For frequently allocated short-lived objects (particles, projectiles, transient math), use the `Pool<T>` / `Pooled` API in `lib/src/utils/pool.dart`. See `docs/pool.md` for the full pattern.

## Important Notes

- The project uses local path dependencies for `jenny` - check pubspec.yaml if build fails
- Flame dependency may switch between pub and local path during development
- All public APIs are exported through `lib/sizzle.dart` - import only from there
- Flame APIs are re-exported, so games typically only need `import 'package:sizzle/sizzle.dart'`
- Code style enforces trailing commas (see `analysis_options.yaml`)
