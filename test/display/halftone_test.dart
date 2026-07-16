import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:sizzle/sizzle.dart';

// These tests cover the pure `dart:ui` logic that runs without a GPU: value
// equality, the spill/auto-size formulas, and the amount LUT. A shader-backed
// smoke test is attempted at the end and skips itself if `FragmentProgram`
// can't load in the test environment (see its note) — the port is not blocked
// on goldens.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HalftoneStop', () {
    test('equality and hashCode compare position and amount', () {
      const a = HalftoneStop(0.25, 0.5);
      const b = HalftoneStop(0.25, 0.5);
      const c = HalftoneStop(0.25, 0.6);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('pathDotsSpill', () {
    test('default feather is gridSize * 0.6', () {
      // grid/√2 + 0.75 + 2*feather, feather = 20 * 0.6 = 12.
      expect(
        HalftoneRenderer.pathDotsSpill(gridSize: 20),
        closeTo(20 * 0.70710678 + 0.75 + 24, 1e-6),
      );
    });

    test('explicit feather overrides the default', () {
      expect(
        HalftoneRenderer.pathDotsSpill(gridSize: 20, feather: 0),
        closeTo(20 * 0.70710678 + 0.75, 1e-6),
      );
    });
  });

  group('pathDotsBakeBounds', () {
    test('inflates path bounds by spill and snaps outward to whole pixels', () {
      // A path whose bounds are (106,74)-(274,410), grid 20 → spill ≈ 38.892.
      // Inflating and rounding outward gives the experiment's 246×414 image at
      // origin (67,35).
      final path = Path()..addRect(const Rect.fromLTWH(106, 74, 168, 336));
      final spill = HalftoneRenderer.pathDotsSpill(gridSize: 20);

      final bounds = pathDotsBakeBounds(path, spill);

      expect(bounds.topLeft, const Offset(67, 35));
      expect(bounds.size, const Size(246, 414));
    });
  });

  group('buildAmountLut', () {
    // Reads the red channel (radius fraction) of the 256×1 LUT image.
    Future<List<double>> reds(Image lut) async {
      final data = (await lut.toByteData())!.buffer.asUint8List();
      return [for (var x = 0; x < lut.width; x++) data[x * 4] / 255.0];
    }

    test('endpoints match the first and last stop', () async {
      final lut = await buildAmountLut(const [
        HalftoneStop(0.0, 0.0),
        HalftoneStop(1.0, 1.0),
      ]);
      final r = await reds(lut);

      expect(r.length, 256);
      expect(r.first, closeTo(0.0, 0.01));
      expect(r.last, closeTo(1.0, 0.01));
    });

    test('linear growth is monotonically non-decreasing', () async {
      final lut = await buildAmountLut(const [
        HalftoneStop(0.0, 0.0),
        HalftoneStop(1.0, 1.0),
      ]);
      final r = await reds(lut);

      for (var i = 1; i < r.length; i++) {
        expect(r[i], greaterThanOrEqualTo(r[i - 1] - 1e-9));
      }
    });

    test('area growth is ≈ √ of linear at the midpoint', () async {
      const stops = [HalftoneStop(0.0, 0.0), HalftoneStop(1.0, 1.0)];
      final lin = await reds(await buildAmountLut(stops));
      final area = await reds(
        await buildAmountLut(stops, growth: HalftoneGrowth.area),
      );

      const mid = 128; // t ≈ 0.5
      expect(area[mid], closeTo(sqrt(lin[mid]), 0.02));
      // Area growth lifts the mid-tone (radius ∝ √amount reads darker sooner).
      expect(area[mid], greaterThan(lin[mid]));
    });
  });

  group('shader smoke test', () {
    test('load + bake a small gradient', () async {
      HalftoneRenderer renderer;
      try {
        renderer = await HalftoneRenderer.load();
      } catch (e) {
        // FragmentProgram.fromAsset may not resolve the packaged shader asset
        // under `flutter test`. The shaders avoid derivative functions, so this
        // is an environment limitation, not a shader problem — skip rather than
        // fail (see halftone-port-spec.md).
        markTestSkipped('FragmentProgram.fromAsset unavailable in tests: $e');
        return;
      }

      final gradient = HalftoneGradient.vertical(
        size: const Size(32, 32),
        gridSize: 8,
        stops: const [HalftoneStop(0.0, 0.0), HalftoneStop(1.0, 1.0)],
      );
      final rect = Path()..addRect(const Rect.fromLTWH(0, 0, 32, 32));

      final clipped = await renderer.bake(gradient, rect);
      expect(clipped.image.width, 32);
      expect(clipped.image.height, 32);
      expect(clipped.origin, Offset.zero);

      // Whole-dot mode auto-inflates by the spill margin.
      final dots = await renderer.bake(gradient, rect, clip: false);
      expect(dots.image.width, greaterThan(32));
      expect(dots.origin.dx, lessThan(0));
    });
  });
}
