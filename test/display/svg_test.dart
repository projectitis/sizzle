import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:sizzle/sizzle.dart';

// Vector/Matrix storage in vector_math is Float32, so values like 72.65
// round-trip with up to ~2e-6 of error. Keep this loose enough to absorb that.
const double _eps = 1e-4;

Matcher _closeTo(double v) => closeTo(v, _eps);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Svg.parseColor', () {
    test('parses #RRGGBB as opaque', () {
      final c = Svg.parseColor('#FF8000');
      expect(c.toARGB32(), 0xFFFF8000);
    });

    test('parses #AARRGGBB literally', () {
      final c = Svg.parseColor('#80FF8000');
      expect(c.toARGB32(), 0x80FF8000);
    });

    test('parses #RGB by doubling each digit, opaque', () {
      expect(Svg.parseColor('#abc').toARGB32(), 0xFFAABBCC);
      expect(Svg.parseColor('#000').toARGB32(), 0xFF000000);
      expect(Svg.parseColor('#fff').toARGB32(), 0xFFFFFFFF);
    });

    test('throws without leading #', () {
      expect(() => Svg.parseColor('FF8000'), throwsFormatException);
    });

    test('throws on wrong length', () {
      expect(() => Svg.parseColor('#ab'), throwsFormatException);
      expect(() => Svg.parseColor('#abcd'), throwsFormatException);
      expect(() => Svg.parseColor('#abcde'), throwsFormatException);
    });
  });

  group('Svg.parseMaterial', () {
    test('1 token: base = top, sheen = matte', () {
      final m = Svg.parseMaterial('#ffffff');
      expect(m.baseColor.toARGB32(), 0xFFFFFFFF);
      expect(m.topColor.toARGB32(), 0xFFFFFFFF);
      expect(m.sheen, SvgMaterialSheen.matte);
    });

    test('2 tokens: base = top, sheen parsed', () {
      final m = Svg.parseMaterial('#ffffff gloss');
      expect(m.baseColor.toARGB32(), 0xFFFFFFFF);
      expect(m.topColor.toARGB32(), 0xFFFFFFFF);
      expect(m.sheen, SvgMaterialSheen.gloss);
    });

    test('3 tokens: base, top, sheen', () {
      final m = Svg.parseMaterial('#ffffff #000000 specular');
      expect(m.baseColor.toARGB32(), 0xFFFFFFFF);
      expect(m.topColor.toARGB32(), 0xFF000000);
      expect(m.sheen, SvgMaterialSheen.specular);
    });

    test('all sheen keywords parse', () {
      expect(
        Svg.parseMaterial('#000000 dull').sheen,
        SvgMaterialSheen.dull,
      );
      expect(
        Svg.parseMaterial('#000000 matte').sheen,
        SvgMaterialSheen.matte,
      );
      expect(
        Svg.parseMaterial('#000000 gloss').sheen,
        SvgMaterialSheen.gloss,
      );
      expect(
        Svg.parseMaterial('#000000 specular').sheen,
        SvgMaterialSheen.specular,
      );
    });

    test('single-letter sheen shorthand', () {
      expect(Svg.parseMaterial('#000 d').sheen, SvgMaterialSheen.dull);
      expect(Svg.parseMaterial('#000 m').sheen, SvgMaterialSheen.matte);
      expect(Svg.parseMaterial('#000 g').sheen, SvgMaterialSheen.gloss);
      expect(Svg.parseMaterial('#000 s').sheen, SvgMaterialSheen.specular);
    });

    test('mixes 3-digit hex with shorthand sheen', () {
      final m = Svg.parseMaterial('#abc #def s');
      expect(m.baseColor.toARGB32(), 0xFFAABBCC);
      expect(m.topColor.toARGB32(), 0xFFDDEEFF);
      expect(m.sheen, SvgMaterialSheen.specular);
    });

    test('throws on unknown sheen', () {
      expect(
        () => Svg.parseMaterial('#ffffff bogus'),
        throwsFormatException,
      );
    });

    test('throws when more than 3 tokens', () {
      expect(
        () => Svg.parseMaterial('#fff #fff #fff matte'),
        throwsFormatException,
      );
    });
  });

  group('Svg.normalFromColor', () {
    test('white #ffffff normalizes to (1,-1,1)/sqrt(3) (G inverted)', () {
      // The G channel is inverted at decode time so a high-G colour
      // represents a surface facing screen-up (-Y in screen Y-down).
      final n = Svg.normalFromColor(const Color(0xFFFFFFFF));
      final s = 1 / sqrt(3);
      expect(n.x, _closeTo(s));
      expect(n.y, _closeTo(-s));
      expect(n.z, _closeTo(s));
    });

    test('#80ff80 decodes to ≈ (0, -1, 0) (screen-up)', () {
      final n = Svg.normalFromColor(const Color(0xFF80FF80));
      // G=255 → tangent-up → screen-up = -Y in screen Y-down.
      expect(n.y, lessThan(-0.99));
      expect(n.x.abs(), lessThan(0.01));
      expect(n.z.abs(), lessThan(0.01));
    });

    test('alpha is ignored', () {
      final a = Svg.normalFromColor(const Color(0xFFFFFFFF));
      final b = Svg.normalFromColor(const Color(0x00FFFFFF));
      expect(a.x, _closeTo(b.x));
      expect(a.y, _closeTo(b.y));
      expect(a.z, _closeTo(b.z));
    });
  });

  group('Svg.parseTransform', () {
    test('null/empty returns identity', () {
      expect(Svg.parseTransform(null), Matrix4.identity());
      expect(Svg.parseTransform(''), Matrix4.identity());
      expect(Svg.parseTransform('   '), Matrix4.identity());
    });

    test('translate with 1 and 2 args', () {
      final m1 = Svg.parseTransform('translate(10)');
      expect(m1.getTranslation(), Vector3(10, 0, 0));

      final m2 = Svg.parseTransform('translate(10, 20)');
      expect(m2.getTranslation(), Vector3(10, 20, 0));

      final m3 = Svg.parseTransform('translate(10 20)');
      expect(m3.getTranslation(), Vector3(10, 20, 0));
    });

    test('scale uniform and non-uniform', () {
      final m1 = Svg.parseTransform('scale(2)');
      final p1 = m1.transform3(Vector3(3, 4, 0));
      expect(p1, Vector3(6, 8, 0));

      final m2 = Svg.parseTransform('scale(2, 3)');
      final p2 = m2.transform3(Vector3(3, 4, 0));
      expect(p2.x, _closeTo(6));
      expect(p2.y, _closeTo(12));
    });

    test('rotate(90) maps (1,0) to (0,1)', () {
      final m = Svg.parseTransform('rotate(90)');
      final p = m.transform3(Vector3(1, 0, 0));
      expect(p.x, _closeTo(0));
      expect(p.y, _closeTo(1));
    });

    test('rotate around pivot', () {
      // 180° around (10, 0): (20, 0) -> (0, 0)
      final m = Svg.parseTransform('rotate(180 10 0)');
      final p = m.transform3(Vector3(20, 0, 0));
      expect(p.x, _closeTo(0));
      expect(p.y, _closeTo(0));
    });

    test('matrix(1,0,0,1,10,20) equals translate(10,20)', () {
      final m1 = Svg.parseTransform('matrix(1,0,0,1,10,20)');
      final m2 = Svg.parseTransform('translate(10,20)');
      for (int i = 0; i < 16; i++) {
        expect(m1.storage[i], _closeTo(m2.storage[i]));
      }
    });

    test('matrix(0,1,-1,0,0,0) is 90° rotation', () {
      final m = Svg.parseTransform('matrix(0,1,-1,0,0,0)');
      final p = m.transform3(Vector3(1, 0, 0));
      expect(p.x, _closeTo(0));
      expect(p.y, _closeTo(1));
    });

    test('skewX(45) shears x by y', () {
      final m = Svg.parseTransform('skewX(45)');
      final p = m.transform3(Vector3(0, 1, 0));
      expect(p.x, _closeTo(1));
      expect(p.y, _closeTo(1));
    });

    test('skewY(45) shears y by x', () {
      final m = Svg.parseTransform('skewY(45)');
      final p = m.transform3(Vector3(1, 0, 0));
      expect(p.x, _closeTo(1));
      expect(p.y, _closeTo(1));
    });

    test('composes left-to-right', () {
      // translate(10) then rotate(90) — applied to (1,0):
      // translate first changes the coord system, so a point at (1,0)
      // ends up at translate·rotate·(1,0) = translate·(0,1) = (10, 1).
      final m = Svg.parseTransform('translate(10) rotate(90)');
      final p = m.transform3(Vector3(1, 0, 0));
      expect(p.x, _closeTo(10));
      expect(p.y, _closeTo(1));
    });

    test('throws on unknown function', () {
      expect(
        () => Svg.parseTransform('warp(10)'),
        throwsFormatException,
      );
    });

    test('throws when nothing parses', () {
      expect(
        () => Svg.parseTransform('not a transform'),
        throwsFormatException,
      );
    });
  });

  group('Svg path d parsing', () {
    Svg buildOnePathSvg(String d) {
      final src = '''
<svg xmlns="http://www.w3.org/2000/svg" xmlns:pp="http://paraplu.io/svg" width="10" height="10">
  <defs><g id="x"><path fill="#808080" d="$d"/></g></defs>
  <use href="#x"/>
</svg>''';
      return Svg(src);
    }

    void expectBounds(SvgPath p, double l, double t, double r, double b) {
      final rect = p.uiPath.getBounds();
      expect(rect.left, _closeTo(l));
      expect(rect.top, _closeTo(t));
      expect(rect.right, _closeTo(r));
      expect(rect.bottom, _closeTo(b));
    }

    test('absolute square via M/L/Z', () {
      final svg = buildOnePathSvg('M0 0 L10 0 L10 10 L0 10 Z');
      final path = svg.groups[0].paths.single;
      expectBounds(path, 0, 0, 10, 10);
      expect(path.uiPath.contains(const Offset(5, 5)), isTrue);
      expect(path.uiPath.contains(const Offset(20, 20)), isFalse);
    });

    test('relative move + implicit l continuation', () {
      final svg = buildOnePathSvg('m5 5 l10 0 10 10');
      // Vertices were (5,5), (15,5), (25,15).
      expectBounds(svg.groups[0].paths.single, 5, 5, 25, 15);
    });

    test('H/V shorthands', () {
      final svg = buildOnePathSvg('M0 0 H10 V10 H0 Z');
      final path = svg.groups[0].paths.single;
      expectBounds(path, 0, 0, 10, 10);
      expect(path.uiPath.contains(const Offset(5, 5)), isTrue);
    });

    test('adjacent negative numbers without separator', () {
      // From example.svg group "a" first path:
      // m-6.4-7.3 1.65 16.25H4.7L6.35-7.3z
      // vertices: (-6.4,-7.3), (-4.75,8.95), (4.7,8.95), (6.35,-7.3)
      final svg = buildOnePathSvg('m-6.4-7.3 1.65 16.25H4.7L6.35-7.3z');
      expectBounds(svg.groups[0].paths.single, -6.4, -7.3, 6.35, 8.95);
    });

    test('Z resets current point; subsequent m is relative to subpath start',
        () {
      final svg = buildOnePathSvg('M0 0 L10 0 Z m5 5 l10 0');
      final paths = svg.groups[0].paths;
      expect(paths.length, 2);
      // Path 1: vertices (0,0), (10,0). Degenerate line.
      expectBounds(paths[0], 0, 0, 10, 0);
      // After Z, current resets to (0, 0); m5 5 → (5, 5); l10 0 → (15, 5).
      expectBounds(paths[1], 5, 5, 15, 5);
    });

    test('multiple subpaths in one d become multiple SvgPaths', () {
      final svg = buildOnePathSvg('M0 0 L10 0 ZM20 0 L30 0 Z');
      final paths = svg.groups[0].paths;
      expect(paths.length, 2);
      expectBounds(paths[0], 0, 0, 10, 0);
      expectBounds(paths[1], 20, 0, 30, 0);
    });
  });

  group('Svg parses example.svg', () {
    late Svg svg;

    setUpAll(() {
      final source =
          File('test/_resources/svg/example.svg').readAsStringSync();
      svg = Svg(source);
    });

    test('size and origin', () {
      expect(svg.size, Vector2(200, 150));
      expect(svg.origin, Vector2(100, 68));
    });

    test('groups by id and order', () {
      expect(svg.groups.map((g) => g.id).toList(), ['a', 'b', 'c', 'd']);
    });

    test('group "a" material is white/specular', () {
      final a = svg.groups[0];
      expect(a.material.baseColor.toARGB32(), 0xFFFFFFFF);
      expect(a.material.topColor.toARGB32(), 0xFFFFFFFF);
      expect(a.material.sheen, SvgMaterialSheen.specular);
    });

    test('group "c" has 6 paths (3 sources, each splits at z/m)', () {
      final c = svg.groups.firstWhere((g) => g.id == 'c');
      expect(c.paths.length, 6);
    });

    test('group "a" splits the multi-subpath fill into 19 paths', () {
      // 18 <path> elements; one (#8009af) has two subpaths -> 19 SvgPaths.
      final a = svg.groups[0];
      expect(a.paths.length, 19);
    });

    test('group "a" first path has the expected normal', () {
      // fill="#80f6af"
      final a = svg.groups[0];
      final expected = Svg.normalFromColor(const Color(0xFF80F6AF));
      final actual = a.paths.first.normal;
      expect(actual.x, _closeTo(expected.x));
      expect(actual.y, _closeTo(expected.y));
      expect(actual.z, _closeTo(expected.z));
    });

    test('renderList resolves groups and transforms', () {
      expect(svg.renderList.length, 4);
      // Each render item references one of the four groups in order.
      expect(svg.renderList[0].group.id, 'a');
      expect(svg.renderList[1].group.id, 'b');
      expect(svg.renderList[2].group.id, 'c');
      expect(svg.renderList[3].group.id, 'd');

      // Last item has transform="translate(100 72.65)".
      final t = svg.renderList[3].transform.getTranslation();
      expect(t.x, _closeTo(100));
      expect(t.y, _closeTo(72.65));
    });
  });

  group('pp:expand', () {
    Svg buildSquare({double? groupExpand, double? pathExpand}) {
      final groupAttr = groupExpand == null
          ? ''
          : ' pp:expand="$groupExpand"';
      final pathAttr =
          pathExpand == null ? '' : ' pp:expand="$pathExpand"';
      final src = '''
<svg xmlns="http://www.w3.org/2000/svg" xmlns:pp="http://paraplu.io/svg" width="20" height="20">
  <defs>
    <g id="g"$groupAttr>
      <path fill="#808080"$pathAttr d="M0 0 L10 0 L10 10 L0 10 Z"/>
    </g>
  </defs>
  <use href="#g"/>
</svg>''';
      return Svg(src);
    }

    void expectBounds(SvgPath p, double l, double t, double r, double b) {
      final rect = p.uiPath.getBounds();
      expect(rect.left, _closeTo(l));
      expect(rect.top, _closeTo(t));
      expect(rect.right, _closeTo(r));
      expect(rect.bottom, _closeTo(b));
    }

    test('default expand is zero on group and path', () {
      final svg = buildSquare();
      expect(svg.groups[0].expand, 0);
      expect(svg.groups[0].paths.single.expand, 0);
      expectBounds(svg.groups[0].paths.single, 0, 0, 10, 10);
    });

    test('group expand grows the path outward', () {
      final svg = buildSquare(groupExpand: 1);
      expect(svg.groups[0].expand, 1);
      // Square 0..10 expanded by 1 per edge → -1..11.
      expectBounds(svg.groups[0].paths.single, -1, -1, 11, 11);
    });

    test('path expand grows the path outward', () {
      final svg = buildSquare(pathExpand: 2);
      expect(svg.groups[0].paths.single.expand, 2);
      expectBounds(svg.groups[0].paths.single, -2, -2, 12, 12);
    });

    test('group + path expand stack additively', () {
      final svg = buildSquare(groupExpand: 1.5, pathExpand: 0.5);
      // Total = 2 → -2..12.
      expectBounds(svg.groups[0].paths.single, -2, -2, 12, 12);
      expect(svg.groups[0].expand, 1.5);
      expect(svg.groups[0].paths.single.expand, 0.5);
    });

    test('opposite expand on group and path cancels', () {
      final svg = buildSquare(groupExpand: 1, pathExpand: -1);
      // Total = 0 → bounds unchanged.
      expectBounds(svg.groups[0].paths.single, 0, 0, 10, 10);
    });

    test('negative expand shrinks the path', () {
      final svg = buildSquare(pathExpand: -2);
      expectBounds(svg.groups[0].paths.single, 2, 2, 8, 8);
    });

    test('Svg.expandPolygon offsets a unit square outward by 1', () {
      final out = Svg.expandPolygon(
        [Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)],
        1,
      );
      expect(out[0].x, _closeTo(-1));
      expect(out[0].y, _closeTo(-1));
      expect(out[1].x, _closeTo(11));
      expect(out[1].y, _closeTo(-1));
      expect(out[2].x, _closeTo(11));
      expect(out[2].y, _closeTo(11));
      expect(out[3].x, _closeTo(-1));
      expect(out[3].y, _closeTo(11));
    });

    test('Svg.expandPolygon returns input unchanged when amount is 0', () {
      final input = [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)];
      final out = Svg.expandPolygon(input, 0);
      expect(identical(out, input), isTrue);
    });
  });

  group('Svg error cases', () {
    test('throws when use references unknown id', () {
      const src = '''
<svg xmlns="http://www.w3.org/2000/svg" xmlns:pp="http://paraplu.io/svg" width="10" height="10">
  <defs></defs>
  <use href="#missing"/>
</svg>''';
      expect(() => Svg(src), throwsFormatException);
    });

    test('throws when use has no href', () {
      const src = '''
<svg xmlns="http://www.w3.org/2000/svg" xmlns:pp="http://paraplu.io/svg" width="10" height="10">
  <use/>
</svg>''';
      expect(() => Svg(src), throwsFormatException);
    });

    test('throws when root is not <svg>', () {
      const src = '<not-svg/>';
      expect(() => Svg(src), throwsFormatException);
    });

    test('throws when xmlns:pp is missing', () {
      const src = '''
<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"></svg>''';
      expect(() => Svg(src), throwsFormatException);
    });

    test('throws when xmlns:pp has the wrong URI', () {
      const src = '''
<svg xmlns="http://www.w3.org/2000/svg" xmlns:pp="http://other/" width="10" height="10"></svg>''';
      expect(() => Svg(src), throwsFormatException);
    });
  });
}
