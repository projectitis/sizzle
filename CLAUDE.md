# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Sizzle is a bitmap/pixel game engine for Flutter, built on top of Flame. It specializes in perfect pixel-art rendering with automatic scaling, letterboxing, and scene management. It can also be used to develop non-pixel-art projects. The project is in alpha stage.

## Development Commands

### Testing
```bash
# Run all tests
dart test

# Run a specific test file
dart test test/utils/pool_test.dart

# Run tests in a directory
dart test test/display/

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
dart pub get

# Note: jenny dependency uses local path. Check pubspec.yaml if it fails.
# Flame may also use local path during development (check commented lines in pubspec.yaml)
```

### Documentation
```bash
# Generate API documentation (output: docs/api/)
dart doc

# Docs configuration in dartdoc_options.yaml
# Generated docs exclude external packages (flame, flutter, etc.)
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
- Extends Flame `Component` with `HasGameRef<SizzleGame>`
- Must implement static `create()` factory method
- Each scene is mounted on-demand by the router
- Use `changeScene(name)` to navigate between scenes

### Services Architecture

**Services** (`lib/src/utils/services.dart`)
- Static class providing global access to game services (no instantiation)
- Access pattern: `Services.images.load()`, `Services.flags['key']`, etc.

**FileService** (`lib/src/utils/services/file_service.dart`)
- Asset loading and caching from the `assets/` folder
- Methods: `loadFile()`, `loadString()`, `loadJson()`, `clearCache()`

**ImageService** (`lib/src/utils/services/image_service.dart`)
- Image loading, caching, and property management
- Handles Sizzle's custom PlySprite format (Aseprite export)
- Supports global default properties for images

**FlagService** (`lib/src/utils/services/flag_service.dart`)
- Boolean game state tracking (flags either exist or don't)
- Pattern: `Services.flags['castle_key'] = true;` then check `Services.flags.flagged('castle_key')`
- Automatically persisted in save/load

**DialogService** (`lib/src/utils/services/dialog_service.dart`)
- Wraps Flame's jenny (Yarn Spinner) package
- Provides dialog/narrative system integration
- Flags are accessible from Yarn scripts

### Display Components

Located in `lib/src/display/`:
- **sprite.dart**: PlySprite and animated sprite components
- **snap.dart**: Pixel-snapped positioning components (SnapPositionComponent, SnapRectangleComponent, etc.)
- **dialog.dart**: Speech bubble dialog component
- **ninegrid.dart**: Nine-slice scaling for UI elements
- **shape.dart**: Basic shape rendering
- **lightning.dart**: Lightning visual effects
- **tile.dart**: Tile/tilemap components

### Math & Physics

- `lib/src/math/`: Vector utilities and math helpers
- `lib/src/physics/`: Movement and lifetime components for game entities

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

**testGolden()**
```dart
testGolden(
  'Renders correctly',
  (game) async {
    final scene = game.currentScene!;
    scene.add(MyComponent());
  },
  game: SizzleGame(scene: Scene.create, targetSize: Vector2(150, 100)),
  size: Vector2(300, 200),
  goldenFile: '$goldens/my-test.png',
);
```

**DiskAssetBundle**
- Use `DiskAssetBundle.loadFromPath('test/_resources/')` to load test assets
- Required for tests that need images or other asset files
- Example in `test/game/game_test.dart`

### Test Organization

- Tests mirror `lib/` structure in `test/`
- Golden files stored in `test/_goldens/`
- Test resources in `test/_resources/`
- Each test file corresponds to a source file (e.g., `pool.dart` → `pool_test.dart`)

## Code Patterns

### Creating a Scene
```dart
class MyScene extends Scene {
  static Component create() => MyScene();

  @override
  Future<void> onLoad() async {
    // Load assets, add components
    final sprite = await Services.images.load(path: 'player.png');
    add(SpriteComponent.fromImage(sprite));
  }
}
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
img.dispose();  // Remember to dispose!
```

**Flags and State**
```dart
// Set and check flags
Services.flags['level_complete'] = true;
if (Services.flags.flagged('level_complete')) { }

// Save/load game state (includes flags and dialog state)
await Services.save();
await Services.load();
```

### Pixel-Perfect Rendering

Components with "Snap" prefix automatically snap to pixel boundaries:
- `SnapPositionComponent`
- `SnapRectangleComponent`

Access current pixel scale via `game.snapScale` for custom positioning.

## Important Notes

- The project uses local path dependencies for `jenny` - check pubspec.yaml if build fails
- Flame dependency may switch between pub and local path during development
- All public APIs are exported through `lib/sizzle.dart` - import only from there
- Flame APIs are re-exported, so games typically only need `import 'package:sizzle/sizzle.dart'`
- Code style enforces trailing commas (see `analysis_options.yaml`)
