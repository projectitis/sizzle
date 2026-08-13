import 'dart:async' as async;

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:sizzle/sizzle.dart';

import '../sizzle_test_helpers.dart';

/// Scene that records how often each of the two clocks reaches it.
class CountingScene extends Scene {
  int updates = 0;
  int fixedUpdates = 0;

  @override
  void update(double dt) {
    updates++;
    super.update(dt);
  }

  @override
  void fixedUpdate(double fixedDt) {
    fixedUpdates++;
  }
}

/// Game that records its own [SizzleGame.fixedUpdate] calls.
class CountingGame extends SizzleGame {
  CountingGame({
    super.scenes,
    super.frameRateMode,
    super.frameRateFallbackToSoftware,
    super.fixedUpdateFps,
  });

  int fixedUpdates = 0;
  double lastFixedDt = 0.0;

  @override
  void fixedUpdate(double fixedDt) {
    fixedUpdates++;
    lastFixedDt = fixedDt;
  }
}

/// Provider that refuses the request outright.
class RejectingProvider implements HwFrameRateProvider {
  int clearCount = 0;

  @override
  bool get isSupported => true;

  @override
  Future<bool> setHardwareFrameRate(double fps) async => false;

  @override
  Future<void> clear() async => clearCount++;
}

/// Provider that accepts the request but whose panel never slows down - the
/// common case on real hardware, and the reason honour is measured.
class IgnoringProvider implements HwFrameRateProvider {
  double? requestedFps;
  int requestCount = 0;
  int clearCount = 0;

  @override
  bool get isSupported => true;

  @override
  Future<bool> setHardwareFrameRate(double fps) async {
    requestedFps = fps;
    requestCount++;
    return true;
  }

  @override
  Future<void> clear() async => clearCount++;
}

/// Ambient provider driven by the test rather than by hardware.
class FakeAmbientProvider implements AmbientProvider {
  void Function(bool isAmbient)? _onChanged;
  bool cancelled = false;

  @override
  bool get isSupported => true;

  @override
  void listen({required void Function(bool isAmbient) onChanged}) {
    _onChanged = onChanged;
  }

  @override
  void cancel() {
    cancelled = true;
    _onChanged = null;
  }

  void enter() => _onChanged?.call(true);

  void exit() => _onChanged?.call(false);
}

/// Power provider driven by the test rather than by the platform.
class FakePowerProvider implements PowerProvider {
  FakePowerProvider({bool initial = false}) : _isPowerSaveMode = initial;

  bool _isPowerSaveMode;
  void Function(bool)? _onChanged;
  bool cancelled = false;

  @override
  bool get isSupported => true;

  @override
  bool get isPowerSaveMode => _isPowerSaveMode;

  @override
  void listen({required void Function(bool isPowerSaveMode) onChanged}) {
    _onChanged = onChanged;
  }

  @override
  void cancel() {
    cancelled = true;
    _onChanged = null;
  }

  void set(bool value) {
    _isPowerSaveMode = value;
    _onChanged?.call(value);
  }
}

Future<CountingGame> startGame(CountingGame game) async {
  await initializeGame<CountingGame>(() => game);
  await game.ready();
  return game;
}

/// Cancels the physics timer and releases the singleton game slot, so the
/// next test can construct a game of its own.
void stopGame(SizzleGame game) {
  game.onDispose();
  game.onRemove();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The hardware-honour probe waits for real `FrameTiming` callbacks, which
  // never fire under `flutter test`. Shrink it so the no-frames fallback the
  // honour tests exercise resolves in ~100ms instead of the ~3s production cap.
  SizzleGame.honourSampleStep = const Duration(milliseconds: 5);
  SizzleGame.honourMaxSamples = 40;

  group('Frame rate mode resolution', () {
    tearDown(() {
      Device.hwFrameRateProvider = null;
    });

    test('is native by default', () async {
      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}),
      );

      expect(game.frameRateMode, FrameRateMode.native);
      expect(game.effectiveFrameRateMode, FrameRateMode.native);
      expect(game.paused, isFalse);

      stopGame(game);
    });

    test('hardwareHalfRate falls back to software with no provider', () async {
      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}),
      );

      final resolved =
          await game.setFrameRateMode(FrameRateMode.hardwareHalfRate);

      expect(resolved, FrameRateMode.softwareHalfRate);
      expect(game.frameRateMode, FrameRateMode.hardwareHalfRate);
      expect(game.effectiveFrameRateMode, FrameRateMode.softwareHalfRate);

      stopGame(game);
    });

    test(
        'hardwareHalfRate falls back to native when told not to use '
        'software', () async {
      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}),
      );

      final resolved = await game.setFrameRateMode(
        FrameRateMode.hardwareHalfRate,
        fallbackToSoftware: false,
      );

      expect(resolved, FrameRateMode.native);
      expect(game.effectiveFrameRateMode, FrameRateMode.native);
      expect(game.paused, isFalse);

      stopGame(game);
    });

    test('a rejected hardware request falls back without measuring', () async {
      final provider = RejectingProvider();
      Device.hwFrameRateProvider = provider;
      expect(Device.isHWFrameRateSupported, isTrue);

      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}),
      );

      final resolved =
          await game.setFrameRateMode(FrameRateMode.hardwareHalfRate);

      expect(resolved, FrameRateMode.softwareHalfRate);
      // Nothing was applied, so nothing needed clearing.
      expect(provider.clearCount, 0);

      stopGame(game);
    });

    test(
        'an accepted but unhonoured hardware request falls back and '
        'releases the hint', () async {
      final provider = IgnoringProvider();
      Device.hwFrameRateProvider = provider;

      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}, fixedUpdateFps: 60),
      );

      final resolved =
          await game.setFrameRateMode(FrameRateMode.hardwareHalfRate);

      // The request targets half the simulation rate...
      expect(provider.requestedFps, 30.0);
      // ...but no frames are presented in this environment, so honour cannot
      // be confirmed and the mode degrades.
      expect(resolved, FrameRateMode.softwareHalfRate);
      expect(provider.clearCount, 1);

      stopGame(game);
    });

    test(
        'an accepted request whose panel slows is kept, even when the first '
        'frame timing arrives late', () async {
      final provider = IgnoringProvider();
      Device.hwFrameRateProvider = provider;

      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}, fixedUpdateFps: 60),
      );

      // Stand in for a Pixel Watch 3: the Surface reconfiguration stalls
      // presentation, so the first frame timings arrive late; once they do,
      // the panel is at the requested 30fps. Feeding starts only after a delay
      // longer than the old fixed 500ms snapshot to prove the probe waits for
      // real samples rather than reading 0fps and giving up.
      const halfRateInterval = 1000000 ~/ 30; // 30fps in microseconds
      async.Timer? feeder;
      final lateStart = async.Timer(const Duration(milliseconds: 40), () {
        feeder = async.Timer.periodic(
          const Duration(milliseconds: 1),
          (_) => game.debugAddRenderFrameInterval(halfRateInterval),
        );
      });

      final resolved =
          await game.setFrameRateMode(FrameRateMode.hardwareHalfRate);

      lateStart.cancel();
      feeder?.cancel();

      // The panel genuinely slowed, so the mode is kept rather than degraded.
      expect(resolved, FrameRateMode.hardwareHalfRate);
      expect(game.effectiveFrameRateMode, FrameRateMode.hardwareHalfRate);

      stopGame(game);
    });
  });

  group('Frame rate mode engagement', () {
    test('softwareHalfRate pauses the ticker and native resumes it', () async {
      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}),
      );

      expect(game.paused, isFalse);

      await game.setFrameRateMode(FrameRateMode.softwareHalfRate);
      expect(game.paused, isTrue);

      await game.setFrameRateMode(FrameRateMode.native);
      expect(game.paused, isFalse);

      stopGame(game);
    });

    test('returning to native leaves a game the title paused alone', () async {
      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}),
      );

      // The title pauses for its own reasons (a pause menu, say) before the
      // frame rate mode changes.
      game.pauseEngine();
      await game.setFrameRateMode(FrameRateMode.softwareHalfRate);
      await game.setFrameRateMode(FrameRateMode.native);

      expect(game.paused, isTrue);

      stopGame(game);
    });

    test('the requested mode is engaged on mount', () async {
      final game = await startGame(
        CountingGame(
          scenes: {'a': CountingScene.new},
          frameRateMode: FrameRateMode.softwareHalfRate,
        ),
      );

      expect(game.effectiveFrameRateMode, FrameRateMode.softwareHalfRate);
      expect(game.paused, isTrue);

      stopGame(game);
    });
  });

  group('Power save', () {
    tearDown(() {
      Device.powerProvider = null;
      Services.messages.clear();
    });

    test('is off by default, on every platform', () async {
      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}),
      );

      expect(game.isPowerSaveMode, isFalse);
      expect(Device.isPowerSaveSupported, isFalse);

      stopGame(game);
    });

    test('adopts the platform state on mount and announces changes', () async {
      final power = FakePowerProvider(initial: true);
      Device.powerProvider = power;

      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}),
      );

      // Already on before the game started - the game must not have to wait
      // for a transition to learn the truth.
      expect(game.isPowerSaveMode, isTrue);

      final changes = <bool>[];
      Services.messages.add(SizzleMessage.powerSaveChanged, (_, args) {
        changes.add(args as bool);
        return true;
      });

      power.set(false);
      power.set(false); // not a transition
      power.set(true);

      expect(changes, [false, true]);
      expect(game.isPowerSaveMode, isTrue);

      stopGame(game);
      expect(power.cancelled, isTrue);
    });

    test('the engine takes no action of its own', () async {
      final power = FakePowerProvider();
      Device.powerProvider = power;

      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}),
      );

      power.set(true);

      // Trading quality for endurance is the game's call, not the engine's.
      expect(game.effectiveFrameRateMode, FrameRateMode.native);
      expect(game.paused, isFalse);

      stopGame(game);
    });
  });

  group('Ambient mode', () {
    late FakeAmbientProvider ambient;

    setUp(() {
      ambient = FakeAmbientProvider();
      Device.ambientProvider = ambient;
    });

    tearDown(() {
      Device.ambientProvider = null;
      Services.messages.clear();
    });

    test('is unsupported without a provider', () async {
      Device.ambientProvider = null;
      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}),
      );

      expect(Device.isAmbientSupported, isFalse);
      expect(game.pauseReasons, isEmpty);

      stopGame(game);
    });

    test('entering ambient pauses the game and leaving resumes it', () async {
      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}),
      );

      ambient.enter();
      expect(game.paused, isTrue);
      expect(game.pauseReasons, {PauseReason.ambient});

      ambient.exit();
      expect(game.paused, isFalse);
      expect(game.pauseReasons, isEmpty);

      stopGame(game);
    });

    test('the simulation stops while ambient', () async {
      final game = await startGame(
        CountingGame(
          scenes: {'a': CountingScene.new},
          frameRateMode: FrameRateMode.softwareHalfRate,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(game.fixedUpdates, greaterThan(0));

      ambient.enter();
      final atEnter = game.fixedUpdates;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(game.fixedUpdates, atEnter);

      ambient.exit();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(game.fixedUpdates, greaterThan(atEnter));

      stopGame(game);
    });

    test('a repeated transition is not double-counted', () async {
      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}),
      );

      var paused = 0;
      Services.messages.add(SizzleMessage.gamePaused, (_, __) {
        paused++;
        return true;
      });

      ambient.enter();
      ambient.enter();
      expect(paused, 1);

      stopGame(game);
    });

    test('a backgrounded ambient game stays paused on ambient exit', () async {
      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}),
      );

      game.lifecycleStateChange(AppLifecycleState.paused);
      ambient.enter();
      expect(
        game.pauseReasons,
        containsAll(
          <PauseReason>[PauseReason.backgrounded, PauseReason.ambient],
        ),
      );

      ambient.exit();
      expect(game.paused, isTrue);
      expect(game.pauseReasons, {PauseReason.backgrounded});

      stopGame(game);
    });

    test('teardown stops listening to the provider', () async {
      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}),
      );

      stopGame(game);
      expect(ambient.cancelled, isTrue);
      expect(Device.ambientProvider, same(ambient));
    });
  });

  group('Hardware frame rate', () {
    tearDown(() {
      Device.hwFrameRateProvider = null;
      Services.messages.clear();
    });

    test(
        'announces one mode change per call, even when the probe rolls '
        'back', () async {
      Device.hwFrameRateProvider = IgnoringProvider();
      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}),
      );

      final changes = <FrameRateMode>[];
      Services.messages.add(SizzleMessage.frameRateModeChanged, (_, args) {
        changes.add(args as FrameRateMode);
        return true;
      });

      await game.setFrameRateMode(FrameRateMode.hardwareHalfRate);

      // The mode is engaged provisionally so the meter samples the mode under
      // test, then rolled back when the panel turns out not to have slowed.
      // The caller should hear about the destination only.
      expect(game.effectiveFrameRateMode, FrameRateMode.softwareHalfRate);
      expect(changes, [FrameRateMode.softwareHalfRate]);

      stopGame(game);
    });

    test('defers verification while paused, then settles on resume', () async {
      Device.hwFrameRateProvider = IgnoringProvider();
      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}),
      );

      game.pauseEngine();
      final resolved =
          await game.setFrameRateMode(FrameRateMode.hardwareHalfRate);

      // A paused game presents no frames, so there is nothing to measure -
      // degrading here would condemn a mode that might be perfectly fine.
      expect(resolved, FrameRateMode.hardwareHalfRate);

      game.resumeEngine();
      await Future<void>.delayed(const Duration(milliseconds: 700));

      // Now it has been measured, and this environment presents nothing.
      expect(game.effectiveFrameRateMode, FrameRateMode.softwareHalfRate);

      stopGame(game);
    });

    test(
        'releases the panel hint while paused and re-applies on '
        'resume', () async {
      final provider = IgnoringProvider();
      Device.hwFrameRateProvider = provider;
      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}),
      );

      // Pause first so verification defers and the mode stays hardware.
      game.pauseEngine();
      await game.setFrameRateMode(FrameRateMode.hardwareHalfRate);
      expect(game.effectiveFrameRateMode, FrameRateMode.hardwareHalfRate);

      // A paused game has no Surface worth holding a panel hint against.
      expect(provider.clearCount, greaterThan(0));

      final requestsBefore = provider.requestCount;
      game.resumeEngine();
      await Future<void>.delayed(Duration.zero);

      // Re-requested rather than assumed to have survived - Android destroys
      // the Surface the hint was attached to across these transitions.
      expect(provider.requestCount, greaterThan(requestsBefore));

      stopGame(game);
    });
  });

  group('Pause reasons', () {
    test('the title can pause a softwareHalfRate game', () async {
      // Regression: the engine is always paused in this mode, so gating the
      // step on `paused` alone stepped straight through a pause menu and the
      // game kept simulating at full rate.
      final game = await startGame(
        CountingGame(
          scenes: {'a': CountingScene.new},
          frameRateMode: FrameRateMode.softwareHalfRate,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(game.fixedUpdates, greaterThan(0));

      game.pauseEngine();
      expect(game.pauseReasons, contains(PauseReason.user));
      final atPause = game.fixedUpdates;

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(game.fixedUpdates, atPause);

      game.resumeEngine();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(game.fixedUpdates, greaterThan(atPause));

      stopGame(game);
    });

    test('softwareHalfRate is not itself a pause reason', () async {
      final game = await startGame(
        CountingGame(
          scenes: {'a': CountingScene.new},
          frameRateMode: FrameRateMode.softwareHalfRate,
        ),
      );

      // The ticker is stopped so paints can be cadenced, but nothing wants
      // the game stopped - which is exactly the distinction the reason set
      // exists to make.
      expect(game.paused, isTrue);
      expect(game.pauseReasons, isEmpty);

      stopGame(game);
    });

    test('the game resumes only once the last reason clears', () async {
      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}),
      );

      game.pauseEngine();
      game.lifecycleStateChange(AppLifecycleState.paused);
      expect(
        game.pauseReasons,
        containsAll(<PauseReason>[PauseReason.user, PauseReason.backgrounded]),
      );

      // Clearing one reason must not undo the other.
      game.resumeEngine();
      expect(game.paused, isTrue);
      expect(game.pauseReasons, {PauseReason.backgrounded});

      game.lifecycleStateChange(AppLifecycleState.resumed);
      expect(game.paused, isFalse);
      expect(game.pauseReasons, isEmpty);

      stopGame(game);
    });

    test('backgrounding stops the physics timer', () async {
      final game = await startGame(
        CountingGame(
          scenes: {'a': CountingScene.new},
          frameRateMode: FrameRateMode.softwareHalfRate,
        ),
      );

      game.lifecycleStateChange(AppLifecycleState.paused);
      final atBackground = game.fixedUpdates;

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(game.fixedUpdates, atBackground);

      game.lifecycleStateChange(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(game.fixedUpdates, greaterThan(atBackground));

      stopGame(game);
    });

    test('pause messages fire once per transition, not per reason', () async {
      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}),
      );

      var paused = 0;
      var resumed = 0;
      Services.messages.add(SizzleMessage.gamePaused, (_, __) {
        paused++;
        return true;
      });
      Services.messages.add(SizzleMessage.gameResumed, (_, __) {
        resumed++;
        return true;
      });

      game.pauseEngine();
      game.lifecycleStateChange(AppLifecycleState.paused);
      // Two reasons, but only one transition out of "running".
      expect(paused, 1);
      expect(resumed, 0);

      game.resumeEngine();
      expect(resumed, 0);
      game.lifecycleStateChange(AppLifecycleState.resumed);
      expect(resumed, 1);

      Services.messages.clear();
      stopGame(game);
    });

    test('a frame rate mode change announces no pause', () async {
      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}),
      );

      var announcements = 0;
      Services.messages.add(SizzleMessage.gamePaused, (_, __) {
        announcements++;
        return true;
      });

      // softwareHalfRate stops the ticker, but the title did not pause.
      await game.setFrameRateMode(FrameRateMode.softwareHalfRate);
      expect(game.paused, isTrue);
      expect(announcements, 0);

      Services.messages.clear();
      stopGame(game);
    });
  });

  group('Fixed timestep', () {
    test(
        'native mode steps the simulation from update, in whole '
        'timesteps', () async {
      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}, fixedUpdateFps: 60),
      );
      final scene = game.currentScene! as CountingScene;
      game.fixedUpdates = 0;
      scene.fixedUpdates = 0;

      // Half a timestep is not enough to step anything.
      game.update(1 / 120);
      expect(game.fixedUpdates, 0);

      // The remainder is carried over, so the next half completes a step.
      game.update(1 / 120);
      expect(game.fixedUpdates, 1);
      expect(scene.fixedUpdates, 1);
      expect(game.lastFixedDt, closeTo(1 / 60, 1e-9));

      // A long frame catches up with several steps at once.
      game.update(0.055);
      expect(game.fixedUpdates, 4);
      expect(scene.fixedUpdates, 4);

      stopGame(game);
    });

    test('a huge frame is clamped rather than simulated in full', () async {
      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}, fixedUpdateFps: 60),
      );
      game.fixedUpdates = 0;

      // A full second of backlog would be 60 steps; the clamp keeps the
      // catch-up from making the next frame even slower.
      game.update(1.0);
      expect(game.fixedUpdates, 5);

      // The dropped backlog must not resurface on the following frame.
      game.update(1 / 60);
      expect(game.fixedUpdates, 6);

      stopGame(game);
    });

    test('a paused scene is not simulated, but the game still is', () async {
      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}, fixedUpdateFps: 60),
      );
      final scene = game.currentScene! as CountingScene;
      game.fixedUpdates = 0;
      scene.fixedUpdates = 0;

      scene.paused = true;
      game.update(1 / 60);

      expect(game.fixedUpdates, 1);
      expect(scene.fixedUpdates, 0);

      stopGame(game);
    });

    test('honours a non-default fixedUpdateFps', () async {
      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}, fixedUpdateFps: 120),
      );
      game.fixedUpdates = 0;

      expect(game.fixedUpdateFps, 120);
      game.update(1 / 60);
      expect(game.fixedUpdates, 2);
      expect(game.lastFixedDt, closeTo(1 / 120, 1e-9));

      stopGame(game);
    });

    test(
        'softwareHalfRate simulates on its own timer, with no frames '
        'painted', () async {
      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}, fixedUpdateFps: 60),
      );
      final scene = game.currentScene! as CountingScene;

      await game.setFrameRateMode(FrameRateMode.softwareHalfRate);
      game.fixedUpdates = 0;
      scene.fixedUpdates = 0;
      scene.updates = 0;

      await Future<void>.delayed(const Duration(milliseconds: 400));

      // Roughly 24 ticks at 60fps. Timer granularity varies wildly between
      // machines, so only assert the simulation is clearly running.
      expect(game.fixedUpdates, greaterThan(10));
      expect(scene.fixedUpdates, game.fixedUpdates);
      // Nothing is attached to paint into, so the render clock produced no
      // frames at all - proof the simulation is not driven by it.
      expect(scene.updates, 0);

      stopGame(game);
    });

    test('simulates before the router has mounted a scene', () async {
      // In softwareHalfRate the game is paused before the widget's first
      // `update(0)`, so the router - and with it `currentScene` - is still
      // empty when the physics timer first fires.
      final game = CountingGame(
        scenes: {'a': CountingScene.new},
        frameRateMode: FrameRateMode.softwareHalfRate,
      );
      // ignore: invalid_use_of_internal_member
      await game.load();
      // ignore: invalid_use_of_internal_member
      game.mount();
      expect(game.currentScene, isNull);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(game.fixedUpdates, greaterThan(0));

      stopGame(game);
    });

    test('disposing stops the physics timer', () async {
      final game = await startGame(
        CountingGame(
          scenes: {'a': CountingScene.new},
          frameRateMode: FrameRateMode.softwareHalfRate,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(game.fixedUpdates, greaterThan(0));

      stopGame(game);
      final settled = game.fixedUpdates;

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(game.fixedUpdates, settled);
    });
  });

  group('FPS metering', () {
    test('is off by default and reports nothing', () async {
      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}),
      );

      expect(game.measureFps, isFalse);
      expect(game.measuredRenderFps, 0.0);
      expect(game.measuredFixedUpdateFps, 0.0);

      stopGame(game);
    });

    test('can be toggled at runtime', () async {
      final game = await startGame(
        CountingGame(scenes: {'a': CountingScene.new}),
      );

      game.measureFps = true;
      expect(game.measureFps, isTrue);

      game.measureFps = false;
      expect(game.measureFps, isFalse);
      expect(game.measuredRenderFps, 0.0);

      stopGame(game);
    });
  });
}
