# Changes

## Unreleased

- `Services.saveFile` sets the name used by `Services.save` / `Services.load`,
  which was previously hardcoded. Defaults to `Services.defaultSaveFile`
  (`sizzle.json`), so existing saves are unaffected. Change it between calls for
  multiple save slots
- Web support: Sizzle now compiles for web
  - `dart:io` and `path_provider` are no longer reachable from a web build.
    Every use moved behind a conditional-import shim in
    `lib/src/utils/platform/`
  - `Services.save` / `Services.load` persist to `localStorage` under the key
    `sizzle.json` on web, and to the documents-directory file of the same name
    everywhere else. Existing native save files are unaffected
  - `FileLogger` falls back to console output on web (no file system). The new
    `FileLogger.isWritingToFile` reports which sink is in use
  - `Device.isAndroid` and friends report the *native* platform, so all are
    `false` on web - use `Device.isWeb`. `Device.os` is `'web'` plus the browser
    user agent, and `Device.describe()` now names `Web` instead of `Unknown OS`
  - **Breaking:** the minimum Dart SDK is now 3.3.0, required by
    `dart:js_interop`. Adds a `web` package dependency
- Ambient (always-on) mode support
  - `AmbientState` and the `AmbientProvider` seam at `Device.ambientProvider`
  - `SizzleGame.ambient` for burn-in and low-bit constraints while rendering
  - `SizzleMessage.ambientChanged` and `ambientTick`; the tick carries real
    elapsed seconds so idle progress can be computed in closed form
  - Entering ambient stops the simulation and drops to one repaint per tick
- Battery saver support
  - `PowerProvider` seam at `Device.powerProvider`, `SizzleGame.isPowerSaveMode`
    and `SizzleMessage.powerSaveChanged`. The engine takes no action of its own
- Pause handling reworked around `PauseReason`, exposed as
  `SizzleGame.pauseReasons`
  - **Breaking:** `resumeEngine()` now clears only the caller's own reason. A
    game that is also backgrounded or in ambient mode stays paused until those
    clear, where previously the ticker would restart
  - **Fixed:** a title could not pause a `FrameRateMode.softwareHalfRate` game
    - the engine is always paused in that mode, so the step gate ignored
    `pauseEngine()` and the game kept simulating
- Frame rate fixes
  - **Fixed:** hardware rate verification measured the *previous* mode, so
    `softwareHalfRate` → `hardwareHalfRate` could "verify" a panel change that
    never happened
  - Verification is deferred while the game is paused rather than degrading on
    a 0fps reading, and the panel hint is re-applied after Surface recreation
  - `setFrameRateMode` now announces at most one `frameRateModeChanged` per call
- **Fixed:** the `AppLifecycleListener` created per game was never disposed

- Variable-width strokes (`VariableWidthStroke`)
  - Randomised calligraphic lines, quadratic curves, and multi-segment paths
  - Line-cap treatments (butt, round, square, blot)
  - Closed paths stroked as rings
  - Pixel-based segment length for consistent tessellation density


## 0.1.3

- Game improvements
  - Scaling
  - Dispose callback
- Object pooling support
- Physics mixins (Lifetime, Movement)
- Refactored services class
  - Logging (including to file)
- Vector math utils, Range class
- Device utility class
- [JX](https://pub.dev/packages/jx) support
- API docs (generated using dartdoc)
- Bugs
  - Fixed letterboxing


## 0.1.2

- Dialog
- NineGrid
  - Advanced NineGrid implementation
- PlySprite
  - Animation queue
  - Callback events


## 0.1.1

- SizzleGame
  - Add support for single scene


## 0.1.0

- Initial version
- SizzleGame
  - Target and max view window
  - Manage scaling and letterboxing
  - Scenes (based on Flame Routes)
- BitmapSpriteComponent
  - Snapping to pixels
- Services
  - Persist state (save/load to local device)
