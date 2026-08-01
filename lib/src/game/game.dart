import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart' hide Route;
// Flame re-exports its own frame-scoped `Timer` from the components barrel;
// hide it so `Timer` unambiguously means the `dart:async` one used to drive
// the fixed-timestep loop below.
import 'package:flame/components.dart' hide Timer;
import 'package:flame/events.dart';
import 'package:flame/extensions.dart';
import 'package:flame/game.dart';

import './frame_rate_mode.dart';
import './fps_meter.dart';
import './scene.dart';
import '../math/math.dart';
import '../utils/device.dart';
import '../utils/services.dart';
import '../utils/services/message_service.dart';

/// The root [FlameGame] for a Sizzle title.
///
/// `SizzleGame` adds three things on top of `FlameGame`:
///
/// 1. **A target/max sizing model with letterboxing.** Pass [targetSize]
///    (the always-visible game area) and optionally [maxSize] (the largest
///    drawable area). Sizzle picks a uniform scale that keeps the target
///    area fully on-screen, fills outwards up to the max, and draws a
///    letterbox in [letterBoxColor] for anything beyond. Set
///    [scaleToWholePixels] for crisp pixel-art rendering, or [scale] to
///    clamp the auto-fit factor.
/// 2. **Scene routing.** Provide either a single [scene] or a map of named
///    [scenes]; the first entry is the initial route. Each value is a
///    *constructor reference* (`MyScene.new` or a closure) that the
///    underlying [RouterComponent] invokes lazily on first visit. Switch
///    scenes with [changeScene] from anywhere with a game reference, or
///    `Scene.changeScene` from inside a scene.
/// 3. **Coordinate-transformed input** so taps, drags and hover hit the
///    same components they appear over once the letterbox translation has
///    been applied (see [componentsAtPoint]).
/// 4. **A simulation clock decoupled from the paint clock.** [fixedUpdate]
///    runs at [fixedUpdateFps] (60 by default) no matter how often the game
///    paints, and [frameRateMode] can halve the paint rate to save GPU or
///    display power without slowing gameplay down. See [setFrameRateMode].
///
/// Read-only views of the resulting layout are exposed via [viewWindow]
/// (the visible area inside the letterbox), [gameWindow] (the full max
/// area, which may extend past the screen), [safeWindow] (the slice that
/// is always visible regardless of aspect ratio), [gameWindowOffset] (the
/// max area's offset from the canvas), and [snapScale] (the current
/// pixel-to-screen ratio used by `Snap` components).
///
/// A typical entry point:
///
/// ```dart
/// void main() {
///   final game = SizzleGame(
///     scenes: {
///       'menu': MenuScene.new,
///       'game': GameScene.new,
///     },
///     targetSize: Vector2(240, 180),
///     maxSize: Vector2(360, 180),
///   );
///   runApp(GameWidget(game: game));
/// }
/// ```
class SizzleGame extends FlameGame
    with SingleGameInstance, TapCallbacks, KeyboardEvents {
  /// Router component that owns the navigation stack of scenes. Exposed
  /// publicly via [router].
  late RouterComponent _router;

  final Vector2 _targetSize = Vector2(320, 240);

  /// The always-visible game area, in unscaled game pixels. Common sizes
  /// are 320x240, 160x120 etc. Set via the `targetSize` constructor
  /// parameter; once the game is constructed this getter is read-only.
  Vector2 get targetGameSize => _targetSize;

  final Vector2 _maxSize = Vector2(320, 240);

  /// The maximum drawable area, in unscaled game pixels.
  ///
  /// May be larger than [targetGameSize] to extend the visible area beyond
  /// the guaranteed-on-screen target. Anything outside [targetGameSize] is
  /// not guaranteed to be displayed on every aspect ratio, so keep
  /// gameplay-critical content inside the target area.
  Vector2 get maxGameSize => _maxSize;

  /// The size of one game pixel in screen pixels after the view window has
  /// been scaled. Updated automatically by [onGameResize]; bitmap sprites
  /// and `Snap` components read this to render at the right scale and snap
  /// to whole pixels.
  final Vector2 snapScale = Vector2.all(1.0);

  /// When `true`, [snapScale] is rounded down to an integer so each game
  /// pixel covers a whole number of screen pixels. Recommended for
  /// pixel-art games.
  bool scaleToWholePixels = false;

  /// Optional clamp on the auto-fit scale factor. When non-zero the scale
  /// chosen by [onGameResize] is restricted to this `[min, max]` range.
  Range scale = Range.zero;

  /// The visible game area inside the letterbox, in screen pixels.
  /// Updated by [onGameResize].
  final MutableRectangle<double> viewWindow =
      MutableRectangle(0.0, 0.0, 320.0, 240.0);

  /// The full max-size game area in screen pixels. May extend past the
  /// visible canvas - see [viewWindow] for what the user actually sees.
  final MutableRectangle<double> gameWindow =
      MutableRectangle(0.0, 0.0, 320.0, 240.0);

  /// The slice of [gameWindow] that is guaranteed to be visible at every
  /// aspect ratio. May be smaller than [viewWindow]. UI and critical game
  /// elements should stay inside this rectangle.
  final MutableRectangle<double> safeWindow =
      MutableRectangle(0.0, 0.0, 320.0, 240.0);

  /// Offset of [gameWindow] from the top-left of the canvas, in screen
  /// pixels. Negative when the max area extends past the canvas edges.
  final Vector2 gameWindowOffset = Vector2.zero();

  /// Paint used to draw the letterbox bars. Only the colour is consulted.
  final Paint _letterBoxPaint = Paint();

  /// Optional cleanup callback. Invoked from [onDispose] before the
  /// superclass tears down, giving the game a chance to release resources
  /// (file handles, audio sinks, services) it owns.
  Function? onCleanup;

  /// Tracks whether [onDispose] has already run, since some platforms can
  /// fire multiple lifecycle events that each route through it.
  bool _isDisposed = false;

  /// The mode asked for by the constructor or [setFrameRateMode], before any
  /// hardware fallback is applied. See [effectiveFrameRateMode].
  FrameRateMode _requestedMode;

  /// The mode actually in force. Never [FrameRateMode.hardwareHalfRate]
  /// unless the platform was measured to honour the request.
  FrameRateMode _effectiveMode = FrameRateMode.native;

  /// Whether an unhonoured [FrameRateMode.hardwareHalfRate] request should
  /// degrade to [FrameRateMode.softwareHalfRate] rather than
  /// [FrameRateMode.native].
  bool _fallbackToSoftware;

  final int _fixedUpdateFps;

  /// Drives [fixedUpdate] in the half-rate modes, where the engine ticker
  /// either runs at a reduced rate or is paused entirely. A one-shot timer
  /// that reschedules itself so each delay can absorb the previous tick's
  /// own work time.
  Timer? _physicsTimer;

  /// Unspent simulation time, in seconds. Grows by the real elapsed time and
  /// is drained in whole [_fixedDt] steps.
  double _accumulator = 0.0;

  /// Measures the wall time between physics ticks, so a starved or early
  /// timer still advances the simulation by the right amount.
  final Stopwatch _physicsClock = Stopwatch();

  /// Measures the wall time between software-cadenced paints, so [update]
  /// (and anything driven from it, like tweens) receives a truthful `dt`.
  final Stopwatch _paintClock = Stopwatch();

  /// Counts physics ticks towards the next software-cadenced paint.
  int _paintTickCounter = 0;

  /// Set when [FrameRateMode.softwareHalfRate] paused the engine, so
  /// returning to [FrameRateMode.native] does not resume a game that the
  /// title itself had paused.
  bool _pausedByFrameRate = false;

  /// Set while the engine is being paused or resumed as an implementation
  /// detail of a frame rate mode, to suppress [SizzleMessage.gamePaused] /
  /// [SizzleMessage.gameResumed]. The title did not pause, so nothing
  /// should be told that it did.
  ///
  /// [_pausedByFrameRate] cannot serve this purpose: it is set *after*
  /// `pauseEngine` and cleared *before* `resumeEngine`, so it reads wrong
  /// at exactly the moment the notification would fire.
  bool _internalPauseChange = false;

  /// Whether a refresh-rate request is currently outstanding with the
  /// platform and needs clearing on teardown or mode change.
  bool _hardwareHintApplied = false;

  final FpsMeter _renderFpsMeter = FpsMeter();
  final RateCounter _fixedUpdateCounter = RateCounter();
  bool _measureFps;

  /// Most fixed steps run for a single frame. Once the backlog needs more
  /// than this the game is already too slow to catch up, and trying would
  /// only make the next frame slower still - so the backlog is dropped.
  static const int _maxSubSteps = 5;

  /// The exact timestep handed to every [fixedUpdate] call.
  double get _fixedDt => 1.0 / _fixedUpdateFps;

  /// Whether the current mode drives the simulation itself rather than
  /// letting the engine ticker drive it from [update].
  bool get _ownsLoop => _effectiveMode != FrameRateMode.native;

  /// Creates a new Sizzle game.
  ///
  /// Exactly one of [scene] (a single scene) or [scenes] (a named map)
  /// must be supplied. For [scenes], the first entry becomes the initial
  /// route. Each value is a constructor reference - typically `MyScene.new`,
  /// or `() => MyScene(arg)` if the scene needs constructor arguments.
  ///
  /// [targetSize] is the always-visible game area; [maxSize] (defaults to
  /// [targetSize]) lets you draw beyond it without the extra area becoming
  /// the new minimum visible area. [letterBoxColor] is painted around
  /// [maxSize] when the canvas is larger than the max area.
  /// [scaleToWholePixels] forces integer pixel scaling for crisp pixel-art.
  /// [scale] clamps the auto-fit scale factor.
  ///
  /// [frameRateMode] selects how often the game paints and
  /// [frameRateFallbackToSoftware] what happens when a hardware request is
  /// not honoured - both are applied on mount and can be changed later with
  /// [setFrameRateMode]. [fixedUpdateFps] is the simulation rate driving
  /// [fixedUpdate], independent of the paint rate. [measureFps] turns on the
  /// [measuredRenderFps] / [measuredFixedUpdateFps] meters; leave it off in
  /// production, where it costs nothing at all.
  SizzleGame({
    Map<String, Component Function()>? scenes,
    Component Function()? scene,
    Vector2? targetSize,
    Vector2? maxSize,
    Color letterBoxColor = const Color(0xff000000),
    this.scaleToWholePixels = false,
    Range? scale,
    FrameRateMode frameRateMode = FrameRateMode.native,
    bool frameRateFallbackToSoftware = true,
    int fixedUpdateFps = 60,
    bool measureFps = false,
  })  : _requestedMode = frameRateMode,
        _fallbackToSoftware = frameRateFallbackToSoftware,
        _fixedUpdateFps = fixedUpdateFps,
        _measureFps = measureFps,
        super() {
    assert(
      scene != null || scenes != null,
      'A scene or scenes must be provided',
    );
    assert(
      !(scene != null && scenes != null),
      'Provide either a scene or list of scenes, not both',
    );
    assert(
      fixedUpdateFps > 0,
      'fixedUpdateFps must be greater than zero',
    );

    if (targetSize != null) {
      _targetSize.setFrom(targetSize);
    }
    _maxSize.setFrom(maxSize ?? _targetSize);

    if (scale != null) {
      this.scale = scale;
    }

    _letterBoxPaint.color = letterBoxColor;

    final Map<String, Route> routes = {};
    if (scenes != null) {
      scenes.forEach((key, value) {
        routes[key] = Route(value);
      });
    } else if (scene != null) {
      routes['default'] = Route(scene);
    }
    add(
      _router =
          RouterComponent(initialRoute: routes.keys.first, routes: routes),
    );

    // Route lifecycle events through onDispose so platform-specific exit
    // paths (close button, OS shutdown) all converge on the same cleanup.
    AppLifecycleListener(
      onDetach: () {
        onDispose();
      },
      onExitRequested: () async {
        onDispose();
        return AppExitResponse.exit;
      },
    );
  }

  /// Recomputes [snapScale], [viewWindow], [gameWindow], [safeWindow] and
  /// [gameWindowOffset] for the new canvas size, then forwards to
  /// [FlameGame.onGameResize]. Honours [scale] and [scaleToWholePixels].
  @override
  void onGameResize(Vector2 canvasSize) {
    if (_targetSize.x != 0) {
      double s =
          min(canvasSize.x / _targetSize.x, canvasSize.y / _targetSize.y);
      if (scale.isNotZero) {
        s = scale.clamp(s);
      }
      if (scaleToWholePixels) s = max(s.floorToDouble(), 1.0);
      double xMax = _maxSize.x * s;
      double yMax = _maxSize.y * s;
      double xMin = _targetSize.x * s;
      double yMin = _targetSize.y * s;
      double w = min(canvasSize.x, xMax);
      double h = min(canvasSize.y, yMax);
      snapScale.setValues(s, s);
      viewWindow.setValues(
        (canvasSize.x - w) * 0.5,
        (canvasSize.y - h) * 0.5,
        w,
        h,
      );
      safeWindow.setValues(
        (xMax - xMin) * 0.5,
        (yMax - yMin) * 0.5,
        xMin,
        yMin,
      );
      gameWindow.setValues(
        (xMax - w) * 0.5,
        (yMax - h) * 0.5,
        xMax,
        yMax,
      );
      gameWindowOffset.setValues(
        (xMax - canvasSize.x) * 0.5,
        (yMax - canvasSize.y) * 0.5,
      );
    }
    super.onGameResize(canvasSize);
  }

  /// Advances the simulation, ticks Flame's component tree, then drives any
  /// global per-frame services (currently the tween service).
  ///
  /// This runs once per painted frame, so anything driven from here follows
  /// the paint rate. In [FrameRateMode.native] the fixed-timestep simulation
  /// is pumped from here too; in the half-rate modes the physics timer owns
  /// it instead, so it is deliberately not pumped twice.
  @override
  void update(double dt) {
    if (!_ownsLoop) {
      _advancePhysics(dt);
    }
    super.update(dt);
    Services.tween.update(dt);
  }

  /// Fixed-timestep update, called at [fixedUpdateFps] (60 by default)
  /// independently of how often the game paints.
  ///
  /// [fixedDt] is always exactly `1 / fixedUpdateFps`, so simulation stepped
  /// here is deterministic and frame-rate independent. Depending on how long
  /// the last frame took, this may be called zero, one, or several times per
  /// rendered frame.
  ///
  /// The default implementation does nothing. Override it for game-wide
  /// simulation; the active scene's [Scene.fixedUpdate] is called
  /// immediately afterwards for per-screen physics, mirroring the way
  /// [update] flows from the game into the scene.
  void fixedUpdate(double fixedDt) {}

  /// Drains [_accumulator] into whole fixed steps, driving [fixedUpdate] on
  /// the game and then on the current scene.
  ///
  /// [elapsed] is real time in seconds since the previous call, from
  /// whichever clock owns the loop in the current mode.
  void _advancePhysics(double elapsed) {
    final fixedDt = _fixedDt;
    _accumulator += elapsed;
    var steps = 0;
    while (_accumulator >= fixedDt && steps < _maxSubSteps) {
      fixedUpdate(fixedDt);
      final scene = currentScene;
      if (scene != null && !scene.paused) {
        scene.fixedUpdate(fixedDt);
      }
      _fixedUpdateCounter.increment();
      _accumulator -= fixedDt;
      steps++;
    }
    // Hitting the clamp means the simulation is falling behind wall time.
    // Drop the backlog rather than compounding it into the next frame.
    if (steps == _maxSubSteps) {
      _accumulator = 0.0;
    }
  }

  /// The frame-rate mode that was asked for, before any fallback.
  ///
  /// Compare with [effectiveFrameRateMode] to find out whether a hardware
  /// request actually took.
  FrameRateMode get frameRateMode => _requestedMode;

  /// The frame-rate mode currently in force.
  ///
  /// Differs from [frameRateMode] when [FrameRateMode.hardwareHalfRate] was
  /// requested but the platform could not, or would not, honour it.
  FrameRateMode get effectiveFrameRateMode => _effectiveMode;

  /// The rate at which [fixedUpdate] is driven, in calls per second. Fixed
  /// for the lifetime of the game; set it via the constructor.
  int get fixedUpdateFps => _fixedUpdateFps;

  /// Whether the frame-rate meters are running.
  ///
  /// While off, no timings callback is registered with the scheduler at all,
  /// so metering costs nothing. Turn it on from a debug overlay to read
  /// [measuredRenderFps] and [measuredFixedUpdateFps].
  bool get measureFps => _measureFps;

  set measureFps(bool value) {
    if (_measureFps == value) return;
    _measureFps = value;
    if (value) {
      _renderFpsMeter.start();
    } else {
      _renderFpsMeter.stop();
    }
    _fixedUpdateCounter.reset();
  }

  /// The rate at which frames are actually being presented, averaged over
  /// the last few frames.
  ///
  /// This is measured from the scheduler's frame timings rather than counted
  /// in [update], making it the ground truth for whether frame-rate limiting
  /// took effect. Returns `0` unless [measureFps] is on (or a hardware
  /// verification is in flight).
  double get measuredRenderFps =>
      _renderFpsMeter.isRunning ? _renderFpsMeter.fps : 0.0;

  /// The rate at which [fixedUpdate] is actually being called, averaged over
  /// roughly the last second.
  ///
  /// Should sit at [fixedUpdateFps]; a persistent sag means heavy frames are
  /// starving the physics timer. Returns `0` unless [measureFps] is on.
  double get measuredFixedUpdateFps =>
      _measureFps ? _fixedUpdateCounter.rate : 0.0;

  /// Switches to [mode], returning the mode that ended up in force.
  ///
  /// Asynchronous because [FrameRateMode.hardwareHalfRate] cannot be trusted
  /// on its word: the request is made, the real frame cadence is then
  /// measured for about half a second, and the mode is only kept if the
  /// display genuinely slowed down. If it did not - or if no
  /// `Device.hwFrameRateProvider` is registered, which is the case for a
  /// stock Sizzle build - the result degrades to
  /// [FrameRateMode.softwareHalfRate] when [fallbackToSoftware] is `true`,
  /// or to [FrameRateMode.native] with a logged warning when it is `false`.
  ///
  /// The other two modes resolve synchronously; the returned future is
  /// already complete by the time it is handed back.
  Future<FrameRateMode> setFrameRateMode(
    FrameRateMode mode, {
    bool fallbackToSoftware = true,
  }) async {
    _requestedMode = mode;
    _fallbackToSoftware = fallbackToSoftware;

    final resolved = _resolveModeSync(mode, fallbackToSoftware);
    if (resolved != null) {
      await _clearHardwareHint();
      _applyMode(resolved);
      return resolved;
    }

    final verified = await _resolveHardwareMode(fallbackToSoftware);
    // A second call may have overtaken us while the cadence was being
    // sampled; in that case the newer request wins.
    if (_requestedMode != mode) {
      return _effectiveMode;
    }
    _applyMode(verified);
    return verified;
  }

  /// Resolves [mode] without touching the platform, or returns `null` when
  /// the answer depends on measuring a hardware request.
  FrameRateMode? _resolveModeSync(FrameRateMode mode, bool fallback) {
    if (mode != FrameRateMode.hardwareHalfRate) {
      return mode;
    }
    if (!Device.isHWFrameRateSupported) {
      return _hardwareFallback(
        fallback,
        'no hardware frame rate provider is available on this platform',
      );
    }
    return null;
  }

  /// Requests the reduced panel rate and confirms it by measurement.
  Future<FrameRateMode> _resolveHardwareMode(bool fallback) async {
    final provider = Device.hwFrameRateProvider!;
    final target = _fixedUpdateFps / 2;

    final accepted = await provider.setHardwareFrameRate(target);
    if (!accepted) {
      return _hardwareFallback(
        fallback,
        'the platform rejected a ${target}fps request',
      );
    }
    _hardwareHintApplied = true;

    if (!await _isHardwareRateHonoured(target)) {
      await _clearHardwareHint();
      return _hardwareFallback(
        fallback,
        'the display kept presenting faster than the requested ${target}fps',
      );
    }
    return FrameRateMode.hardwareHalfRate;
  }

  /// Samples the real frame cadence for long enough to tell whether the
  /// panel actually slowed down.
  ///
  /// Runs the render meter transiently when [measureFps] is off, so
  /// verification works without leaving metering registered afterwards.
  Future<bool> _isHardwareRateHonoured(double target) async {
    final wasRunning = _renderFpsMeter.isRunning;
    if (wasRunning) {
      _renderFpsMeter.reset();
    } else {
      _renderFpsMeter.start();
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final measured = _renderFpsMeter.fps;
    if (!wasRunning) {
      _renderFpsMeter.stop();
    }
    // Allow generous headroom: the sample straddles the transition and a
    // honoured 30fps panel still reports the occasional short interval.
    return measured > 0 && measured <= target * 1.25;
  }

  /// Picks the degraded mode for an unhonoured hardware request and says why.
  FrameRateMode _hardwareFallback(bool fallback, String reason) {
    if (fallback) {
      Services.log.info(
        'FrameRateMode.hardwareHalfRate unavailable ($reason); '
        'using FrameRateMode.softwareHalfRate instead',
      );
      return FrameRateMode.softwareHalfRate;
    }
    Services.log.warn(
      'FrameRateMode.hardwareHalfRate unavailable ($reason) and '
      'fallbackToSoftware is false; rendering at the native frame rate',
    );
    return FrameRateMode.native;
  }

  Future<void> _clearHardwareHint() async {
    if (!_hardwareHintApplied) return;
    _hardwareHintApplied = false;
    await Device.hwFrameRateProvider?.clear();
  }

  /// Puts [mode] into force, reconfiguring the ticker and physics timer.
  ///
  /// Broadcasts [SizzleMessage.frameRateModeChanged] once the new mode is
  /// engaged, but only on an actual change - this is called repeatedly
  /// with the mode already in force.
  void _applyMode(FrameRateMode mode) {
    final bool changed = _effectiveMode != mode;
    _effectiveMode = mode;
    _engageMode();
    if (changed) {
      Services.messages.send(SizzleMessage.frameRateModeChanged, mode);
    }
  }

  /// (Re)configures the engine ticker and physics timer for
  /// [_effectiveMode]. Safe to call repeatedly - each call starts from a
  /// stopped timer.
  void _engageMode() {
    _stopPhysicsTimer();
    switch (_effectiveMode) {
      case FrameRateMode.native:
        _resumeIfPausedByFrameRate();
      case FrameRateMode.hardwareHalfRate:
        // The ticker keeps running: paints come from the (now slower) vsync,
        // and the timer only has to drive the simulation.
        _resumeIfPausedByFrameRate();
        _startPhysicsTimer();
      case FrameRateMode.softwareHalfRate:
        // The ticker is stopped and the timer drives both the simulation and,
        // every second tick, a paint via `stepEngine`.
        if (!paused) {
          _internalPauseChange = true;
          pauseEngine();
          _internalPauseChange = false;
          _pausedByFrameRate = true;
        }
        _startPhysicsTimer();
    }
  }

  void _resumeIfPausedByFrameRate() {
    if (_pausedByFrameRate) {
      _pausedByFrameRate = false;
      _internalPauseChange = true;
      resumeEngine();
      _internalPauseChange = false;
    }
  }

  void _startPhysicsTimer() {
    _accumulator = 0.0;
    _paintTickCounter = 0;
    _physicsClock
      ..reset()
      ..start();
    _paintClock
      ..reset()
      ..start();
    _schedulePhysicsTick(_fixedDt);
  }

  void _stopPhysicsTimer() {
    _physicsTimer?.cancel();
    _physicsTimer = null;
    _physicsClock.stop();
    _paintClock.stop();
  }

  void _schedulePhysicsTick(double delaySeconds) {
    final micros = (delaySeconds * 1e6).round();
    _physicsTimer = Timer(
      Duration(microseconds: micros < 0 ? 0 : micros),
      _onPhysicsTick,
    );
  }

  void _onPhysicsTick() {
    _physicsTimer = null;

    // Time since the previous tick started, not since it finished, so any
    // lateness is fed back into the accumulator instead of being lost.
    final elapsed = _physicsClock.elapsedMicroseconds / 1e6;
    _physicsClock
      ..reset()
      ..start();
    _advancePhysics(elapsed);

    if (_effectiveMode == FrameRateMode.softwareHalfRate) {
      _paintTickCounter++;
      if (_paintTickCounter >= 2) {
        _paintTickCounter = 0;
        // `stepEngine` only does anything while paused and attached; it runs
        // `update` and marks the render box dirty, so the paint itself still
        // lands on the next vsync and stays aligned with the display.
        if (paused && isMounted && isAttached) {
          final paintElapsed = _paintClock.elapsedMicroseconds / 1e6;
          _paintClock
            ..reset()
            ..start();
          stepEngine(stepTime: paintElapsed);
        }
      }
    }

    // Subtract this tick's own work so the cadence tracks `fixedUpdateFps`
    // instead of drifting out by the cost of every step.
    final work = _physicsClock.elapsedMicroseconds / 1e6;
    final delay = _fixedDt - work;
    // A mode change from inside `fixedUpdate` may have already stopped or
    // restarted the loop; don't fight it.
    if (_ownsLoop && _physicsTimer == null) {
      _schedulePhysicsTick(delay < 0 ? 0 : delay);
    }
  }

  /// Transforms event coordinates to account for the letterbox offset
  /// applied in [renderTree].
  ///
  /// Without this, hit testing would use raw screen coordinates while
  /// components are rendered with the letterbox translation, causing
  /// every tap/drag/hover event to miss its target.
  @override
  Iterable<Component> componentsAtPoint(
    Vector2 point, [
    List<Vector2>? nestedPoints,
  ]) {
    if (_targetSize.x != 0) {
      return super.componentsAtPoint(
        point -
            Vector2(
              viewWindow.left - gameWindow.left,
              viewWindow.top - gameWindow.top,
            ),
        nestedPoints,
      );
    }
    return super.componentsAtPoint(point, nestedPoints);
  }

  /// Translates the canvas to the [viewWindow] origin, renders the
  /// component tree, and fills any space outside [viewWindow] with the
  /// letterbox colour.
  @override
  void renderTree(Canvas c) {
    if (_targetSize.x != 0) {
      c.save();
      c.translate(
        viewWindow.left - gameWindow.left,
        viewWindow.top - gameWindow.top,
      );
      super.renderTree(c);
      c.restore();

      if (viewWindow.width < size.x) {
        // Left
        c.drawRect(
          Rect.fromLTWH(
            0.0,
            viewWindow.top.floorToDouble(),
            viewWindow.left,
            viewWindow.bottom.ceilToDouble(),
          ),
          _letterBoxPaint,
        );
        // Right
        c.drawRect(
          Rect.fromLTWH(
            viewWindow.right,
            viewWindow.top.floorToDouble(),
            viewWindow.left,
            viewWindow.bottom.ceilToDouble(),
          ),
          _letterBoxPaint,
        );
      }
      if (viewWindow.height < size.y) {
        // Top
        c.drawRect(
          Rect.fromLTWH(0.0, 0.0, size.x, viewWindow.top),
          _letterBoxPaint,
        );
        // Bottom
        c.drawRect(
          Rect.fromLTWH(0.0, viewWindow.bottom, size.x, viewWindow.top),
          _letterBoxPaint,
        );
      }
    } else {
      super.renderTree(c);
    }
  }

  /// Switches to the scene registered under [scene].
  ///
  /// Pushes the route to the top of the navigation stack. If the route is
  /// already in the stack it is moved to the top instead of being mounted
  /// twice. If it is already the top, this is a no-op. The scene's page
  /// is built lazily on first visit.
  ///
  /// When [replace] is `true` the current top route is removed first, so
  /// the new scene takes its place rather than stacking on top of it.
  ///
  /// The named route must exist in the `scenes:` map passed to the
  /// constructor or this will assert.
  void changeScene(String scene, {bool replace = false}) {
    assert(
      _router.routes.keys.contains(scene),
      'The scene \'$scene\' does not exist',
    );

    _router.pushNamed(scene, replace: replace);
  }

  /// The scene currently on top of the navigation stack, or `null` while
  /// the initial route is still mounting.
  ///
  /// The router only fills its route stack when it is itself mounted, which
  /// happens a frame after the game mounts - and later still in the modes
  /// that pause the ticker. [fixedUpdate] can therefore run before there is
  /// any scene to hand to, hence the mounted check.
  Scene? get currentScene {
    if (!_router.isMounted) return null;
    final route = _router.currentRoute;
    return route.hasChildren ? route.lastChild() as Scene : null;
  }

  /// The underlying Flame [RouterComponent] driving scene navigation.
  ///
  /// Exposed for advanced use cases - inspecting the navigation stack,
  /// driving custom transitions, or popping routes - that the convenience
  /// methods on [SizzleGame] and [Scene] don't cover.
  RouterComponent get router => _router;

  /// Starts the frame-rate meters and engages the requested
  /// [FrameRateMode].
  ///
  /// This happens on mount rather than in the constructor because the modes
  /// that pause the ticker need the render box to exist before `stepEngine`
  /// can produce anything.
  @override
  void onMount() {
    super.onMount();
    if (_measureFps) {
      _renderFpsMeter.start();
    }
    final resolved = _resolveModeSync(_requestedMode, _fallbackToSoftware);
    if (resolved != null) {
      _applyMode(resolved);
    } else {
      // Hardware verification takes half a second; run the game at the
      // native rate until it comes back with an answer, and let any
      // `setFrameRateMode` call made in the meantime win.
      _resolveHardwareMode(_fallbackToSoftware).then((mode) {
        if (_isDisposed) return;
        if (_requestedMode != FrameRateMode.hardwareHalfRate) return;
        _applyMode(mode);
      });
    }
  }

  /// Keeps the physics timer in step with the app being backgrounded, and
  /// broadcasts [SizzleMessage.appLifecycleChanged].
  ///
  /// Flame's own handling only covers the ticker, and in the half-rate modes
  /// Sizzle owns a timer that would otherwise keep simulating (and, in
  /// software mode, keep asking for paints) while the app is not visible.
  ///
  /// The message is sent before the early-out below so that it fires in
  /// every frame rate mode, not just the ones that own the loop.
  @override
  void lifecycleStateChange(AppLifecycleState state) {
    Services.messages.send(SizzleMessage.appLifecycleChanged, state);
    super.lifecycleStateChange(state);
    if (!_ownsLoop) return;
    switch (state) {
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        // `super` has already restarted the ticker if it paused it; re-engage
        // rebuilds our side of the loop with a fresh accumulator so the time
        // spent backgrounded is not simulated in one burst.
        if (isMounted) _engageMode();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _stopPhysicsTimer();
    }
  }

  /// Pauses the game loop, broadcasting [SizzleMessage.gamePaused].
  @override
  void pauseEngine() {
    final bool wasPaused = paused;
    super.pauseEngine();
    _notifyPauseChanged(wasPaused);
  }

  /// Resumes the game loop, broadcasting [SizzleMessage.gameResumed].
  @override
  void resumeEngine() {
    final bool wasPaused = paused;
    super.resumeEngine();
    _notifyPauseChanged(wasPaused);
  }

  /// Pauses or resumes the game loop, broadcasting
  /// [SizzleMessage.gamePaused] or [SizzleMessage.gameResumed].
  ///
  /// Overridden as well as [pauseEngine] / [resumeEngine] because Flame
  /// writes its backing field directly in those methods rather than
  /// routing through this setter, so all three are separate entry points.
  @override
  set paused(bool value) {
    final bool wasPaused = paused;
    super.paused = value;
    _notifyPauseChanged(wasPaused);
  }

  /// Broadcasts a pause transition, if one actually happened and it was
  /// not the engine pausing itself for [FrameRateMode.softwareHalfRate].
  void _notifyPauseChanged(bool wasPaused) {
    if (_internalPauseChange || paused == wasPaused) return;
    Services.messages.send(
      paused ? SizzleMessage.gamePaused : SizzleMessage.gameResumed,
    );
  }

  /// Runs [onCleanup] (if set) and tears down the game.
  ///
  /// Idempotent: subsequent calls are no-ops, which lets multiple
  /// platform lifecycle paths (`onDetach`, `onExitRequested`, manual
  /// disposal) safely converge here.
  @override
  void onDispose() {
    if (!_isDisposed) {
      _stopPhysicsTimer();
      _renderFpsMeter.stop();
      unawaited(_clearHardwareHint());
      onCleanup?.call();
      super.onDispose();
      _isDisposed = true;
    }
  }
}
