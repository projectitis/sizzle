import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:sizzle/sizzle.dart';

import '../sizzle_test_helpers.dart';

const double _eps = 1e-3;

const String _miniSvg = '''
<svg xmlns="http://www.w3.org/2000/svg"
     xmlns:xlink="http://www.w3.org/1999/xlink"
     xmlns:pp="http://paraplu.io/svg"
     width="20" height="20" viewBox="0 0 20 20" pp:origin="10 10">
  <defs>
    <g id="g" pp:material="#808080 matte">
      <path fill="#8080ff" d="M0 0 L20 0 L20 20 L0 20 Z"/>
    </g>
  </defs>
  <use xlink:href="#g"/>
</svg>''';

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

/// Test fixture: an [EnvironmentComponent] that cascades dirty when its
/// angle changes, demonstrating the contract for custom rotating
/// intermediaries between an [Environment] and an [SvgComponent].
class _RotatingMid extends EnvironmentComponent {
  @override
  set angle(double v) {
    if (v == angle) return;
    super.angle = v;
    markNeedsRedraw();
  }
}

SvgPath _pathWithFill(String fill) {
  // Build a unit-square path with normal decoded from `fill`.
  final src = '''
<svg xmlns="http://www.w3.org/2000/svg" xmlns:pp="http://paraplu.io/svg"
     width="1" height="1">
  <defs><g id="g"><path fill="$fill" d="M0 0 L1 0 L1 1 L0 1 Z"/></g></defs>
  <use href="#g"/>
</svg>''';
  return Svg(src).groups.single.paths.single;
}

SvgMaterial _material({
  required Color base,
  Color? top,
  SvgMaterialSheen sheen = SvgMaterialSheen.matte,
}) {
  return SvgMaterial()
    ..baseColor = base
    ..topColor = top ?? base
    ..sheen = sheen;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // --------------------------------------------------------------------------
  // Shading model — pure function tests
  // --------------------------------------------------------------------------

  group('SvgComponent.resolvePathColor (single-colour, matte)', () {
    final path = _pathWithFill('#8080ff'); // normal facing camera (0,0,1)

    test('no lights → darkened by the shadow factor', () {
      final mat = _material(base: const Color(0xFF808080));
      final c = SvgComponent.resolvePathColor(path, mat, 0, []);
      // shadeI = 0, delta = -0.5. Shadow side uses
      //   shadowFactor + matte * shadowSheenWeight = 1.0 + 0.5*0.3 = 1.15.
      // shift = -0.5 * 1.15 = -0.575. 0x80 -> 128 * (1 - 0.575) ≈ 54.
      expect((c.toARGB32() >> 16) & 0xFF, closeTo(54, 1));
      expect((c.toARGB32() >> 8) & 0xFF, closeTo(54, 1));
      expect(c.toARGB32() & 0xFF, closeTo(54, 1));
      expect((c.toARGB32() >> 24) & 0xFF, 0xFF);
    });

    test('directional light aligned, strength 1 → lightened', () {
      final mat = _material(base: const Color(0xFF808080));
      final lights = [
        DirectionalLight(
          color: const Color(0xFFFFFFFF),
          strength: 1,
          direction: Vector3(0, 0, -1),
        ),
      ];
      final c = SvgComponent.resolvePathColor(path, mat, 0, lights);
      // intensity = 1, shift = (1 - 0.5) * 0.5 = +0.25.
      // 0x80 -> 128 + (255 - 128) * 0.25 = 159.75 ≈ 160.
      // White light → no hue tint, channels stay at the lightened value.
      expect((c.toARGB32() >> 16) & 0xFF, closeTo(160, 2));
      expect((c.toARGB32() >> 8) & 0xFF, closeTo(160, 2));
      expect(c.toARGB32() & 0xFF, closeTo(160, 2));
    });

    test('back-facing light pushes surface to (near-)black', () {
      final mat = _material(base: const Color(0xFF808080));
      final lights = [
        DirectionalLight(
          color: const Color(0xFFFFFFFF),
          strength: 1,
          direction: Vector3(0, 0, 1), // pointing toward +Z, away from surface
        ),
      ];
      final c = SvgComponent.resolvePathColor(path, mat, 0, lights);
      // shadeI = -1, delta = -1.5. shift = -1.5 * 1.15 = -1.725, clamps to 0.
      expect((c.toARGB32() >> 16) & 0xFF, 0);
    });

    test('rotation moves the lit side', () {
      // Path normal points at +X (after decoding #ff8080).
      final p = _pathWithFill('#ff8080');
      final mat = _material(base: const Color(0xFF808080));
      final lightLeft = [
        DirectionalLight(
          color: const Color(0xFFFFFFFF),
          strength: 1,
          direction: Vector3(1, 0, 0), // travelling +X (light from -X)
        ),
      ];
      // With totalAngle=0, normal is +X, light direction is +X, so
      // -dot(N, dir) = -1 → clamped to 0. Surface back-lit.
      final lit0 = SvgComponent.resolvePathColor(p, mat, 0, lightLeft);
      // With totalAngle=π, normal rotates to -X. -dot(N, dir) = +1 → fully lit.
      final litPi = SvgComponent.resolvePathColor(p, mat, pi, lightLeft);
      expect(
        (lit0.toARGB32() >> 16) & 0xFF,
        lessThan((litPi.toARGB32() >> 16) & 0xFF),
      );
    });
  });

  group('SvgComponent.resolvePathColor (specular)', () {
    final path = _pathWithFill('#8080ff');

    test('no aligned light → alpha ≈ 0', () {
      final mat = _material(
        base: const Color(0xFFFFFFFF),
        sheen: SvgMaterialSheen.specular,
      );
      final c = SvgComponent.resolvePathColor(path, mat, 0, []);
      expect((c.toARGB32() >> 24) & 0xFF, 0);
    });

    test('aligned directional light, strength 1 → alpha ≈ 255', () {
      final mat = _material(
        base: const Color(0xFFFFFFFF),
        sheen: SvgMaterialSheen.specular,
      );
      final lights = [
        DirectionalLight(
          color: const Color(0xFFFFFFFF),
          strength: 1,
          direction: Vector3(0, 0, -1),
        ),
      ];
      final c = SvgComponent.resolvePathColor(path, mat, 0, lights);
      expect((c.toARGB32() >> 24) & 0xFF, closeTo(255, 1));
    });

    test('aligned light at half strength → partial alpha', () {
      final mat = _material(
        base: const Color(0xFFFFFFFF),
        sheen: SvgMaterialSheen.specular,
      );
      final lights = [
        DirectionalLight(
          color: const Color(0xFFFFFFFF),
          strength: 0.5,
          direction: Vector3(0, 0, -1),
        ),
      ];
      final c = SvgComponent.resolvePathColor(path, mat, 0, lights);
      // specPower = pow(1, 16) * 0.5 = 0.5 → alpha = 127 or 128.
      expect((c.toARGB32() >> 24) & 0xFF, closeTo(128, 2));
    });
  });

  group('SvgComponent.resolvePathColor (dual-colour)', () {
    final path = _pathWithFill('#8080ff');
    final mat = _material(
      base: const Color(0xFF000000),
      top: const Color(0xFFFFFFFF),
    );

    test('intensity 0 → exactly base', () {
      final c = SvgComponent.resolvePathColor(path, mat, 0, []);
      expect((c.toARGB32() >> 16) & 0xFF, 0);
      expect((c.toARGB32() >> 8) & 0xFF, 0);
      expect(c.toARGB32() & 0xFF, 0);
    });

    test('intensity 1 → exactly top under white light', () {
      final lights = [
        DirectionalLight(
          color: const Color(0xFFFFFFFF),
          strength: 1,
          direction: Vector3(0, 0, -1),
        ),
      ];
      final c = SvgComponent.resolvePathColor(path, mat, 0, lights);
      // top is white; white light leaves it untinted.
      expect((c.toARGB32() >> 16) & 0xFF, 255);
      expect((c.toARGB32() >> 8) & 0xFF, 255);
      expect(c.toARGB32() & 0xFF, 255);
    });

    test('intensity 0.5 → midpoint between base and top (white light)', () {
      final lights = [
        DirectionalLight(
          color: const Color(0xFFFFFFFF),
          strength: 0.5,
          direction: Vector3(0, 0, -1),
        ),
      ];
      final c = SvgComponent.resolvePathColor(path, mat, 0, lights);
      // intensity = 1.0 * 0.5 = 0.5; lerp(0, 255, 0.5) = 128.
      // White light → no hue tint.
      expect((c.toARGB32() >> 16) & 0xFF, closeTo(128, 1));
    });
  });

  group('SvgComponent.resolvePathColor (light tint)', () {
    final path = _pathWithFill('#8080ff');

    test('red light shifts grey surface toward red', () {
      final mat = _material(
        base: const Color(0xFF808080),
        sheen: SvgMaterialSheen.dull,
      );
      final lights = [
        DirectionalLight(
          color: const Color(0xFFFF0000),
          strength: 1,
          direction: Vector3(0, 0, -1),
        ),
      ];
      final c = SvgComponent.resolvePathColor(path, mat, 0, lights);
      final r = (c.toARGB32() >> 16) & 0xFF;
      final g = (c.toARGB32() >> 8) & 0xFF;
      final b = c.toARGB32() & 0xFF;
      expect(r, greaterThan(g));
      expect(g, equals(b));
    });
  });

  group('SvgComponent.resolvePathColor (multi-light stacking)', () {
    final path = _pathWithFill('#8080ff');
    final mat = _material(
      base: const Color(0xFF000000),
      top: const Color(0xFFFFFFFF),
    );

    test('two directional lights at strength 0.5 each ≈ one at strength 1',
        () {
      final twoHalf = [
        DirectionalLight(
          color: const Color(0xFF000000),
          strength: 0.5,
          direction: Vector3(0, 0, -1),
        ),
        DirectionalLight(
          color: const Color(0xFF000000),
          strength: 0.5,
          direction: Vector3(0, 0, -1),
        ),
      ];
      final oneFull = [
        DirectionalLight(
          color: const Color(0xFF000000),
          strength: 1,
          direction: Vector3(0, 0, -1),
        ),
      ];
      final a = SvgComponent.resolvePathColor(path, mat, 0, twoHalf);
      final b = SvgComponent.resolvePathColor(path, mat, 0, oneFull);
      expect(
        (a.toARGB32() >> 16) & 0xFF,
        closeTo((b.toARGB32() >> 16) & 0xFF, 1),
      );
    });
  });

  // --------------------------------------------------------------------------
  // Component behaviour
  // --------------------------------------------------------------------------

  group('SvgComponent', () {
    Svg buildMini() => Svg(_miniSvg);

    testWithEnv('loads, sizes, and anchors from pp:origin', (game) async {
      final env = Environment(
        lights: [AmbientLight(color: const Color(0xFFFFFFFF))],
      );
      final svg = SvgComponent.fromSvg(buildMini());
      env.add(svg);
      game.add(env);
      await game.ready();

      expect(svg.size, Vector2(20, 20));
      expect(svg.anchor.x, closeTo(0.5, _eps));
      expect(svg.anchor.y, closeTo(0.5, _eps));
    });

    testWithEnv('respects an explicit anchor override', (game) async {
      final env = Environment(
        lights: [AmbientLight(color: const Color(0xFFFFFFFF))],
      );
      final svg =
          SvgComponent.fromSvg(buildMini(), anchor: Anchor.topLeft);
      env.add(svg);
      game.add(env);
      await game.ready();

      expect(svg.anchor, Anchor.topLeft);
    });

    testWithEnv('first render composes a Picture', (game) async {
      final env = Environment(
        lights: [AmbientLight(color: const Color(0xFFFFFFFF))],
      );
      final svg = SvgComponent.fromSvg(buildMini());
      env.add(svg);
      game.add(env);
      await game.ready();

      expect(svg.picture, isNull);
      svg.render(_dummyCanvas());
      expect(svg.picture, isNotNull);
    });

    testWithEnv('translation/scale do not recompose', (game) async {
      final env = Environment(
        lights: [AmbientLight(color: const Color(0xFFFFFFFF))],
      );
      final svg = SvgComponent.fromSvg(buildMini());
      env.add(svg);
      game.add(env);
      await game.ready();

      svg.render(_dummyCanvas());
      final first = svg.picture!;

      svg.position = Vector2(50, 60);
      svg.scale = Vector2.all(2);
      svg.render(_dummyCanvas());
      expect(identical(svg.picture, first), isTrue);
    });

    testWithEnv('rotating the component recomposes', (game) async {
      final env = Environment(
        lights: [AmbientLight(color: const Color(0xFFFFFFFF))],
      );
      final svg = SvgComponent.fromSvg(buildMini());
      env.add(svg);
      game.add(env);
      await game.ready();

      svg.render(_dummyCanvas());
      final first = svg.picture!;

      svg.angle = 1.0;
      svg.render(_dummyCanvas());
      expect(identical(svg.picture, first), isFalse);
    });

    testWithEnv(
        'rotating an EnvironmentComponent ancestor cascades and recomposes',
        (game) async {
      final env = Environment(
        lights: [AmbientLight(color: const Color(0xFFFFFFFF))],
      );
      final mid = _RotatingMid();
      final svg = SvgComponent.fromSvg(buildMini());
      mid.add(svg);
      env.add(mid);
      game.add(env);
      await game.ready();

      svg.render(_dummyCanvas());
      final first = svg.picture!;

      mid.angle = pi / 4;
      svg.render(_dummyCanvas());
      expect(identical(svg.picture, first), isFalse);
    });

    testWithEnv('addLight cascades to descendant SvgComponent',
        (game) async {
      final env = Environment(
        lights: [AmbientLight(color: const Color(0xFFFFFFFF))],
      );
      final svg = SvgComponent.fromSvg(buildMini());
      env.add(svg);
      game.add(env);
      await game.ready();

      svg.render(_dummyCanvas());
      final first = svg.picture!;

      env.addLight(AmbientLight(color: const Color(0xFFFF0000)));
      svg.render(_dummyCanvas());
      expect(identical(svg.picture, first), isFalse);
    });

    testWithEnv(
        'angle vs environment: angle=0 and angle=π render differently '
        'when the SVG has side-facing normals',
        (game) async {
      // A side-facing path (normal +X via #FF8080) lit by a single
      // directional light from -X (rays travel +X). At angle=0, the
      // surface faces away from the light (back-lit). At angle=π the
      // normal rotates to -X — surface faces the light (fully lit).
      // The cached pictures must differ.
      const sideFacingSvg = '''
<svg xmlns="http://www.w3.org/2000/svg"
     xmlns:xlink="http://www.w3.org/1999/xlink"
     xmlns:pp="http://paraplu.io/svg"
     width="20" height="20" viewBox="0 0 20 20" pp:origin="10 10">
  <defs>
    <g id="g" pp:material="#808080 matte">
      <path fill="#FF8080" d="M0 0 L20 0 L20 20 L0 20 Z"/>
    </g>
  </defs>
  <use xlink:href="#g"/>
</svg>''';
      final env = Environment(
        lights: [
          DirectionalLight(
            color: const Color(0xFFFFFFFF),
            strength: 1,
            direction: Vector3(1, 0, 0),
          ),
        ],
      );
      final svg = SvgComponent.fromSvg(Svg(sideFacingSvg));
      env.add(svg);
      game.add(env);
      await game.ready();

      svg.render(_dummyCanvas());
      final unrotated = svg.picture!;

      svg.angle = pi;
      svg.render(_dummyCanvas());
      expect(identical(svg.picture, unrotated), isFalse);
    });

    testWithEnv('throws when no Environment ancestor', (game) async {
      final svg = SvgComponent.fromSvg(buildMini());
      await expectLater(
        () async {
          game.add(svg);
          await game.ready();
        }(),
        throwsA(isA<StateError>()),
      );
    });
  });

  // --------------------------------------------------------------------------
  // Goldens
  // --------------------------------------------------------------------------

  group('SvgComponent goldens', () {
    Svg loadFixture(String name) =>
        Svg(File('test/_resources/svg/$name').readAsStringSync());

    Environment buildLightingEnvironment({double sunYaw = 0.3}) {
      // Lighting setup:
      //  * Slightly golden ambient (low strength, warm-white tint).
      //  * "Sunlight" — bright directional, slight yaw to come from
      //    upper-right of the scene in a top-down view.
      //  * Lower-strength purple side light, also from upper-right but
      //    more lateral than the sun.
      //
      // Light direction is the direction the rays travel, so a light
      // "from above-right" travels (-x, +y, -z).
      final sunDir = Vector3(-sunYaw, sunYaw, -1)..normalize();
      final sideDir = Vector3(-1, 1, -0.5)..normalize();
      return Environment(
        lights: [
          AmbientLight(color: const Color(0xFFFFF1D6), strength: 0.25),
          DirectionalLight(
            color: const Color(0xFFFFFAF0),
            strength: 0.8,
            direction: sunDir,
          ),
          DirectionalLight(
            color: const Color(0xFFB060E0),
            strength: 0.4,
            direction: sideDir,
          ),
        ],
      );
    }

    Future<void> Function(SizzleGame) preparer(Svg svg) {
      return (SizzleGame game) async {
        final scene = game.currentScene!;
        final env = buildLightingEnvironment();
        env.add(
          SvgComponent.fromSvg(
            svg,
            position: Vector2(110, 110),
          ),
        );
        scene.add(env);
      };
    }

    testGolden(
      'normal-map matte',
      preparer(loadFixture('normal-map-matte.svg')),
      game: SizzleGame(scene: Scene.create, targetSize: Vector2(220, 220)),
      size: Vector2(220, 220),
      goldenFile: '$goldens/svg-normal-map-matte.png',
    );

    testGolden(
      'normal-map dull',
      preparer(loadFixture('normal-map-dull.svg')),
      game: SizzleGame(scene: Scene.create, targetSize: Vector2(220, 220)),
      size: Vector2(220, 220),
      goldenFile: '$goldens/svg-normal-map-dull.png',
    );

    testGolden(
      'normal-map gloss',
      preparer(loadFixture('normal-map-gloss.svg')),
      game: SizzleGame(scene: Scene.create, targetSize: Vector2(220, 220)),
      size: Vector2(220, 220),
      goldenFile: '$goldens/svg-normal-map-gloss.png',
    );

    testGolden(
      'normal-map specular',
      preparer(loadFixture('normal-map-specular.svg')),
      game: SizzleGame(scene: Scene.create, targetSize: Vector2(220, 220)),
      size: Vector2(220, 220),
      goldenFile: '$goldens/svg-normal-map-specular.png',
    );

    testGolden(
      'normal-map matte rotated 45°',
      (game) async {
        final scene = game.currentScene!;
        final env = buildLightingEnvironment();
        env.add(
          SvgComponent.fromSvg(
            loadFixture('normal-map-matte.svg'),
            position: Vector2(110, 110),
            angle: pi / 4,
          ),
        );
        scene.add(env);
      },
      game: SizzleGame(scene: Scene.create, targetSize: Vector2(220, 220)),
      size: Vector2(220, 220),
      goldenFile: '$goldens/svg-normal-map-matte-rotated.png',
    );
  });
}

Canvas _dummyCanvas() {
  final recorder = PictureRecorder();
  return Canvas(recorder);
}
