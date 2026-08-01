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
  int clearCount = 0;

  @override
  bool get isSupported => true;

  @override
  Future<bool> setHardwareFrameRate(double fps) async {
    requestedFps = fps;
    return true;
  }

  @override
  Future<void> clear() async => clearCount++;
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
