import 'package:flutter_test/flutter_test.dart';

import 'package:sizzle/sizzle.dart';

import '../sizzle_test_helpers.dart';

class _Probe extends EnvironmentComponent {}

Future<void> testWithEnv(
  String name,
  Future<void> Function(SizzleGame game) body,
) {
  return testWithGame<SizzleGame>(
    name,
    () => SizzleGame(scene: Scene.create),
    body,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Environment data API', () {
    test('starts empty and dirty', () {
      final env = Environment();
      expect(env.lights, isEmpty);
      expect(env.needsRedraw, isTrue);
    });

    test('initial lights populate without requiring a flag flip', () {
      final env = Environment(lights: [AmbientLight()]);
      expect(env.lights.length, 1);
      // Initial state is already dirty; the constructor doesn't need to
      // flip anything.
      expect(env.needsRedraw, isTrue);
    });

    test('addLight marks the environment as needing redraw', () {
      final env = Environment();
      env.clearLights(); // no-op, leaves dirty=true
      env.clearNeedsRedraw(); // clean for this test
      expect(env.needsRedraw, isFalse);

      env.addLight(AmbientLight());
      expect(env.needsRedraw, isTrue);
    });

    test('removeLight marks dirty only when light was present', () {
      final env = Environment();
      final a = AmbientLight();
      env.addLight(a);
      env.clearNeedsRedraw();

      env.removeLight(AmbientLight()); // not present
      expect(env.needsRedraw, isFalse);

      env.removeLight(a);
      expect(env.needsRedraw, isTrue);
      expect(env.lights, isEmpty);
    });

    test('clearLights marks dirty only when non-empty', () {
      final env = Environment();
      env.clearNeedsRedraw();
      env.clearLights();
      expect(env.needsRedraw, isFalse);

      env.addLight(AmbientLight());
      env.clearNeedsRedraw();
      env.clearLights();
      expect(env.needsRedraw, isTrue);
      expect(env.lights, isEmpty);
    });
  });

  group('Light defaults', () {
    test('AmbientLight defaults to opaque white, strength 1.0', () {
      final l = AmbientLight();
      expect(l.color.toARGB32(), 0xFFFFFFFF);
      expect(l.strength, 1.0);
    });

    test('DirectionalLight normalises direction at construction', () {
      final l = DirectionalLight(direction: Vector3(0, 0, 2));
      expect(l.direction.x, closeTo(0, 1e-6));
      expect(l.direction.y, closeTo(0, 1e-6));
      expect(l.direction.z, closeTo(1, 1e-6));
    });

    test('DirectionalLight re-normalises on assignment', () {
      final l = DirectionalLight(direction: Vector3(0, 0, 1));
      l.direction = Vector3(3, 0, 0);
      expect(l.direction.x, closeTo(1, 1e-6));
      expect(l.direction.y, closeTo(0, 1e-6));
      expect(l.direction.z, closeTo(0, 1e-6));
    });

    test('DirectionalLight zero vector is preserved (no NaN)', () {
      final l = DirectionalLight(direction: Vector3.zero());
      expect(l.direction.x, 0);
      expect(l.direction.y, 0);
      expect(l.direction.z, 0);
    });
  });

  group('Environment.of', () {
    test('throws StateError when component has no ancestor', () {
      final orphan = PositionComponent();
      expect(() => Environment.of(orphan), throwsStateError);
    });

    testWithEnv('returns the closest ancestor when nested',
        (game) async {
      final outer = Environment();
      final inner = Environment();
      final probe = PositionComponent();
      inner.add(probe);
      outer.add(inner);
      game.add(outer);
      await game.ready();

      expect(identical(Environment.of(probe), inner), isTrue);
    });
  });

  group('EnvironmentComponent', () {
    testWithEnv('caches the Environment ancestor on mount',
        (game) async {
      final env = Environment();
      final probe = _Probe();
      env.add(probe);
      game.add(env);
      await game.ready();

      expect(identical(probe.environment, env), isTrue);
    });

    testWithEnv('mounted child starts dirty', (game) async {
      final env = Environment();
      final probe = _Probe();
      env.add(probe);
      game.add(env);
      await game.ready();

      expect(probe.needsRedraw, isTrue);
    });

    testWithEnv('addLight cascades dirty to descendant', (game) async {
      final env = Environment();
      final probe = _Probe();
      env.add(probe);
      game.add(env);
      await game.ready();

      probe.clearNeedsRedraw();
      env.clearNeedsRedraw();

      env.addLight(AmbientLight());
      expect(env.needsRedraw, isTrue);
      expect(probe.needsRedraw, isTrue);
    });

    testWithEnv(
        'cascade descends through plain PositionComponent ancestors',
        (game) async {
      final env = Environment();
      final mid = PositionComponent();
      final probe = _Probe();
      mid.add(probe);
      env.add(mid);
      game.add(env);
      await game.ready();

      probe.clearNeedsRedraw();
      env.clearNeedsRedraw();

      env.addLight(AmbientLight());
      expect(probe.needsRedraw, isTrue);
    });

    testWithEnv('cascade stops descending past a marked descendant',
        (game) async {
      final env = Environment();
      final outerProbe = _Probe();
      final innerProbe = _Probe();
      outerProbe.add(innerProbe);
      env.add(outerProbe);
      game.add(env);
      await game.ready();

      // Both probes should already be dirty (mounted).
      expect(outerProbe.needsRedraw, isTrue);
      expect(innerProbe.needsRedraw, isTrue);

      // After cleaning, a new mark-cascade reaches both again.
      outerProbe.clearNeedsRedraw();
      innerProbe.clearNeedsRedraw();
      env.clearNeedsRedraw();

      env.addLight(AmbientLight());
      expect(outerProbe.needsRedraw, isTrue);
      expect(innerProbe.needsRedraw, isTrue);
    });

    testWithEnv('attaching a child to a dirty parent dirties it',
        (game) async {
      final env = Environment();
      game.add(env);
      await game.ready();

      // env is already dirty (just mounted).
      final probe = _Probe();
      env.add(probe);
      await game.ready();

      expect(probe.needsRedraw, isTrue);
    });

    testWithEnv('re-mount under a different Environment updates ref',
        (game) async {
      final envA = Environment();
      final envB = Environment();
      game.add(envA);
      game.add(envB);
      await game.ready();

      final probe = _Probe();
      envA.add(probe);
      await game.ready();
      expect(identical(probe.environment, envA), isTrue);

      probe.removeFromParent();
      await game.ready();

      envB.add(probe);
      await game.ready();
      expect(identical(probe.environment, envB), isTrue);
    });

    testWithEnv(
        'markNeedsRedraw cascades even when self is already dirty '
        '(descendants may have cleared independently)', (game) async {
      final env = Environment();
      final outerProbe = _Probe();
      final innerProbe = _Probe();
      outerProbe.add(innerProbe);
      env.add(outerProbe);
      game.add(env);
      await game.ready();

      // Inner cleared after a hypothetical render; outer still dirty.
      innerProbe.clearNeedsRedraw();
      outerProbe.markNeedsRedraw();
      // Inner should re-dirty even though outer was already marked.
      expect(innerProbe.needsRedraw, isTrue);
    });
  });
}

