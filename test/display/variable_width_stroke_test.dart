import 'dart:math';
import 'dart:ui' show PathFillType;

import 'package:flutter_test/flutter_test.dart';

import 'package:sizzle/sizzle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A straight horizontal spine makes cap/width geometry predictable: normals
  // are vertical, so every edge x equals the spine x and caps extend purely in
  // x. A fixed segmentLength keeps the sample density deterministic.
  GeneratedStroke straight({
    StrokeEnd? startCap,
    StrokeEnd? endCap,
    double maxWidth = 40,
  }) {
    return VariableWidthStroke.generate(
      start: const Offset(100, 300),
      end: const Offset(400, 300),
      random: Random(1),
      segmentLength: 300 / 64,
      wobble: 0,
      minWidth: 6,
      maxWidth: maxWidth,
      startCap: startCap,
      endCap: endCap,
    );
  }

  double startHalfWidth(GeneratedStroke s) =>
      (s.leftEdge.first - s.spine.first).distance;
  double endHalfWidth(GeneratedStroke s) =>
      (s.leftEdge.last - s.spine.last).distance;

  group('edges stay on their own side of the spine', () {
    // Neither offset edge may cross the centreline; verified geometrically
    // across a sweep of seeds for both straight and curved spines.
    for (var seed = 0; seed < 20; seed++) {
      test('straight spine, seed $seed', () {
        final s = VariableWidthStroke.generate(
          start: const Offset(0, 385),
          end: const Offset(1000, 315),
          random: Random(seed),
          maxWidth: 42,
          minWidth: 6,
          wobble: 28,
          widthVariability: 0.5,
        );
        expect(_crossings(s.leftEdge, s.spine), 0);
        expect(_crossings(s.rightEdge, s.spine), 0);
      });

      test('curved spine, seed $seed', () {
        final s = VariableWidthStroke.generateCurve(
          start: const Offset(0, 350),
          control: const Offset(500, 100),
          end: const Offset(1000, 350),
          random: Random(seed),
          maxWidth: 42,
          minWidth: 6,
          wobble: 28,
          widthVariability: 0.5,
        );
        expect(_crossings(s.leftEdge, s.spine), 0);
        expect(_crossings(s.rightEdge, s.spine), 0);
      });
    }
  });

  group('end treatments', () {
    test('null caps taper both ends to a point', () {
      final s = straight();
      expect(startHalfWidth(s), closeTo(0, 1e-9));
      expect(endHalfWidth(s), closeTo(0, 1e-9));
    });

    test('a specified end is pinned to half its thickness', () {
      final s = straight(startCap: const StrokeEnd(30));
      expect(startHalfWidth(s), closeTo(15, 1e-9));
      expect(endHalfWidth(s), closeTo(0, 1e-9)); // other end still tapers
    });

    test('end thickness is truncated to maxWidth', () {
      final s = straight(startCap: const StrokeEnd(1000), maxWidth: 40);
      expect(startHalfWidth(s), closeTo(20, 1e-9)); // maxWidth / 2
    });

    test('butt cap stays flush with the endpoint', () {
      final s = straight(
        startCap: const StrokeEnd(40),
        maxWidth: 40,
      );
      expect(s.outline.getBounds().left, closeTo(100, 0.5));
      expect(s.outline.contains(const Offset(90, 300)), isFalse);
    });

    test('square cap extends a half-width and fills the corners', () {
      final s = straight(
        startCap: const StrokeEnd(40, style: StrokeEndStyle.square),
        maxWidth: 40,
      );
      expect(s.outline.getBounds().left, closeTo(80, 0.5)); // 100 - halfWidth
      expect(s.outline.contains(const Offset(81, 319)), isTrue);
    });

    test('round cap extends a half-width but rounds the corners off', () {
      final s = straight(
        startCap: const StrokeEnd(40, style: StrokeEndStyle.round),
        maxWidth: 40,
      );
      expect(s.outline.getBounds().left, closeTo(80, 0.5));
      expect(s.outline.contains(const Offset(85, 300)), isTrue);
      expect(s.outline.contains(const Offset(81, 319)), isFalse); // rounded off
    });

    test('blot dabs at the requested radius then necks softly to minimum', () {
      final s = straight(
        startCap: const StrokeEnd(40, style: StrokeEndStyle.blot),
        maxWidth: 40, // minWidth 6 -> half-width 3 at the base of the neck
      );
      expect(startHalfWidth(s), closeTo(20, 1e-9));
      expect(s.outline.getBounds().left, closeTo(80, 0.5));
      expect(s.outline.contains(const Offset(81, 319)), isFalse); // rounded dab

      // The neck eases down over several samples rather than stepping.
      double hw(int i) => (s.leftEdge[i] - s.spine[i]).distance;
      for (var i = 1; i <= 6; i++) {
        expect(
          hw(i),
          lessThan(hw(i - 1)),
          reason: 'sample $i should keep easing',
        );
      }
      expect(hw(3), greaterThan(8)); // mid-neck, nowhere near minimum yet
      expect(hw(6), lessThan(9)); // eased back down to ~minimum body width
    });
  });

  group('StrokePath', () {
    test('an open path chains its segments into one continuous spine', () {
      final spec = StrokePath(const Offset(0, 0))
        ..lineTo(const Offset(100, 0))
        ..curveTo(const Offset(150, 50), const Offset(200, 0));

      final s = VariableWidthStroke.generatePath(
        spec,
        random: Random(1),
        segmentLength: 10,
        wobble: 0,
      );

      expect(s.spine.first, const Offset(0, 0));
      expect(s.spine.last, const Offset(200, 0));
      // 100px line at 10px steps -> the join lands at index 10, exactly once.
      expect(s.spine[10], const Offset(100, 0));
      for (var i = 1; i < s.spine.length; i++) {
        expect(s.spine[i], isNot(s.spine[i - 1]));
      }
    });

    test('a closed path is stroked as a ring with a hollow centre', () {
      final spec = StrokePath(const Offset(100, 100), close: true)
        ..lineTo(const Offset(300, 100))
        ..lineTo(const Offset(300, 300))
        ..lineTo(const Offset(100, 300));

      final s = VariableWidthStroke.generatePath(
        spec,
        random: Random(1),
        segmentLength: 25,
        wobble: 0,
        minWidth: 12,
        maxWidth: 20,
      );

      expect(s.spine.first, const Offset(100, 100));
      expect(s.spine.last, isNot(const Offset(100, 100)));
      expect(s.outline.fillType, PathFillType.evenOdd);
      expect(s.outline.contains(const Offset(200, 200)), isFalse); // hollow
      expect(s.outline.contains(const Offset(200, 100)), isTrue); // on the band
    });

    test('an empty path throws', () {
      expect(
        () => VariableWidthStroke.generatePath(
          StrokePath(const Offset(0, 0)),
          random: Random(1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('segmentLength drives a consistent tessellation density', () {
    test('sample count scales with the line length', () {
      final short = VariableWidthStroke.generate(
        start: const Offset(0, 0),
        end: const Offset(100, 0),
        random: Random(1),
        segmentLength: 10,
        wobble: 0,
      );
      final long = VariableWidthStroke.generate(
        start: const Offset(0, 0),
        end: const Offset(300, 0),
        random: Random(1),
        segmentLength: 10,
        wobble: 0,
      );
      // ~length/segmentLength + 1 samples, so density is the same for both.
      expect(short.spine.length, 11);
      expect(long.spine.length, 31);
    });
  });
}

/// Counts proper (interior) intersections between the segments of [edge] and
/// those of [spine]. Shared or coincident endpoints — as happen where the
/// stroke tapers to zero and the edge meets the spine — are not crossings.
int _crossings(List<Offset> edge, List<Offset> spine) {
  var count = 0;
  for (var i = 0; i < edge.length - 1; i++) {
    for (var j = 0; j < spine.length - 1; j++) {
      if (_properlyIntersect(edge[i], edge[i + 1], spine[j], spine[j + 1])) {
        count++;
      }
    }
  }
  return count;
}

double _orient(Offset a, Offset b, Offset c) =>
    (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);

bool _properlyIntersect(Offset p1, Offset p2, Offset p3, Offset p4) {
  final d1 = _orient(p3, p4, p1);
  final d2 = _orient(p3, p4, p2);
  final d3 = _orient(p1, p2, p3);
  final d4 = _orient(p1, p2, p4);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}
