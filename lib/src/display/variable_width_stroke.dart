import 'dart:math';
import 'dart:ui';

/// How a stroke is finished off at an end that has non-zero thickness.
///
/// These mirror the usual line-cap semantics and double as the primitives for
/// chaining several strokes into a path: interior joins are [butt], while
/// [round] doubles as a simple round-join filler.
enum StrokeEndStyle {
  /// Flat cap flush with the endpoint.
  butt,

  /// Semicircular cap bulging one half-width past the endpoint.
  round,

  /// Rectangular cap extending one half-width past the endpoint.
  square,

  /// Like [round] — a semicircular dab at the requested thickness — but the
  /// stroke necks straight down to `minWidth` immediately after, mimicking the
  /// heavy ink blot a brush leaves when it first touches the page.
  blot,
}

/// An explicit end treatment: a fixed [width] (full thickness, clamped to the
/// stroke's `maxWidth`) finished with a [style].
///
/// Passing one of these to [VariableWidthStroke.generate] overrides the default
/// taper-to-a-point at that end. Leaving it null keeps the taper.
class StrokeEnd {
  const StrokeEnd(this.width, {this.style = StrokeEndStyle.butt});

  /// The full thickness at the end. Truncated to the stroke's `maxWidth`.
  final double width;

  /// The cap shape.
  final StrokeEndStyle style;
}

/// A builder for a multi-segment centreline made of straight and quadratic
/// Bézier pieces, to be stroked as a single continuous variable-width stroke by
/// [VariableWidthStroke.path].
///
/// Construct with the starting point, then chain [lineTo] / [curveTo]. Each
/// segment continues from the previous one's end. Set [close] to join the last
/// point back to the start and stroke the result as a closed ring.
///
/// ```dart
/// final spec = StrokePath(const Offset(0, 0))
///   ..lineTo(const Offset(100, 0))
///   ..curveTo(const Offset(150, 60), const Offset(200, 0));
/// ```
class StrokePath {
  StrokePath(this.start, {this.close = false});

  /// Where the centreline begins.
  final Offset start;

  /// When true, a closing line runs from the last segment's end back to [start]
  /// and the stroke is built as a ring (no end caps).
  final bool close;

  final List<_PathSegment> _segments = [];

  /// True until at least one segment has been added.
  bool get isEmpty => _segments.isEmpty;

  /// Appends a straight segment ending at [end]. Returns `this` for chaining.
  StrokePath lineTo(Offset end) {
    _segments.add(_LineSegment(end));
    return this;
  }

  /// Appends a quadratic Bézier segment with the given [control] point ending at
  /// [end]. Returns `this` for chaining.
  StrokePath curveTo(Offset control, Offset end) {
    _segments.add(_CurveSegment(control, end));
    return this;
  }
}

/// One piece of a [StrokePath]. Its start is implied by the previous piece's end
/// (or the path's start for the first piece).
sealed class _PathSegment {
  const _PathSegment();

  /// Where this piece ends.
  Offset get end;
}

class _LineSegment extends _PathSegment {
  const _LineSegment(this.end);
  @override
  final Offset end;
}

class _CurveSegment extends _PathSegment {
  const _CurveSegment(this.control, this.end);
  final Offset control;
  @override
  final Offset end;
}

/// The result of generating a stroke: the centreline it was grown from, the two
/// offset edges, and the fillable outline that wraps them.
///
/// Exposing [leftEdge] / [rightEdge] alongside the [spine] lets callers (and
/// tests) reason about the line the stroke rides — e.g. to check that each edge
/// stays on its own side of the centreline.
class GeneratedStroke {
  const GeneratedStroke({
    required this.spine,
    required this.leftEdge,
    required this.rightEdge,
    required this.outline,
  });

  /// The centreline the stroke was built around, from start to end.
  final List<Offset> spine;

  /// The spine offset to the left along each local perpendicular.
  final List<Offset> leftEdge;

  /// The spine offset to the right along each local perpendicular.
  final List<Offset> rightEdge;

  /// The fillable outline wrapping the [spine].
  final Path outline;
}

/// Generates a filled [Path] that outlines a stroke whose width varies along a
/// centreline (its "spine"). Filling this path — rather than stroking a line
/// with a fixed [Paint.strokeWidth] — is what lets the edge swell and taper the
/// way an ink-loaded nib does in calligraphy.
///
/// Each edge is the spine offset by a non-negative half-width along the local
/// perpendicular, so the two edges always stay on their own sides of the
/// centreline — the stroke rides the boundary rather than crossing it. (The one
/// way that can break is offset self-intersection on a curve tighter than the
/// half-width; irrelevant for gentle wobble, but worth knowing if sharp spines
/// are used.)
///
/// It is self-contained and depends only on `dart:ui`, so the generated [Path]
/// can be filled by any Flame component or `CustomPainter`. See
/// `docs/variable_width_stroke.md` for a walkthrough.
class VariableWidthStroke {
  const VariableWidthStroke._();

  /// Builds a fillable outline around [spine].
  ///
  /// [halfWidths] gives the half-thickness of the stroke at each spine point
  /// (so the full width there is `2 * halfWidths[i]`). It must have the same
  /// length as [spine].
  ///
  /// The outline walks up one side of the spine and back down the other,
  /// offsetting each point along the local perpendicular, then closes into a
  /// single fillable polygon.
  static Path outline({
    required List<Offset> spine,
    required List<double> halfWidths,
    StrokeEndStyle startStyle = StrokeEndStyle.butt,
    StrokeEndStyle endStyle = StrokeEndStyle.butt,
  }) {
    final (left, right) = _offsetEdges(spine, halfWidths);
    return _buildOutline(spine, left, right, startStyle, endStyle);
  }

  /// Offsets [spine] by `±halfWidths[i]` along each local perpendicular,
  /// returning the two edges. This is the single place the offset geometry is
  /// computed.
  static (List<Offset> left, List<Offset> right) _offsetEdges(
    List<Offset> spine,
    List<double> halfWidths, {
    bool closed = false,
  }) {
    assert(spine.length == halfWidths.length);
    assert(spine.length >= 2);

    final left = List<Offset>.filled(spine.length, Offset.zero);
    final right = List<Offset>.filled(spine.length, Offset.zero);
    for (var i = 0; i < spine.length; i++) {
      final offset = _normalAt(spine, i, closed: closed) * halfWidths[i];
      left[i] = spine[i] + offset;
      right[i] = spine[i] - offset;
    }
    return (left, right);
  }

  /// Closes the two edges into one fillable polygon: forward along [left], an
  /// end cap across to [right], back along [right], then a start cap back to the
  /// beginning. The caps carry the requested [startStyle] / [endStyle].
  static Path _buildOutline(
    List<Offset> spine,
    List<Offset> left,
    List<Offset> right,
    StrokeEndStyle startStyle,
    StrokeEndStyle endStyle,
  ) {
    final last = spine.length - 1;
    final path = Path()..moveTo(left.first.dx, left.first.dy);
    for (var i = 1; i <= last; i++) {
      path.lineTo(left[i].dx, left[i].dy);
    }

    // End cap: from the left edge across to the right edge, around spine.last,
    // opening outward along the end tangent.
    _appendCap(
      path,
      left[last],
      right[last],
      spine[last],
      _outwardDir(spine[last], spine[last - 1]),
      endStyle,
    );

    for (var i = last - 1; i >= 0; i--) {
      path.lineTo(right[i].dx, right[i].dy);
    }

    // Start cap: from the right edge back to the left edge, around spine.first.
    _appendCap(
      path,
      right.first,
      left.first,
      spine.first,
      _outwardDir(spine.first, spine[1]),
      startStyle,
    );

    path.close();
    return path;
  }

  /// Appends a cap to [path] (already at point [a]) running to [b], curving or
  /// squaring off around endpoint [p] and opening along outward unit tangent
  /// [out]. `a` and `b` are the two edge points at the end, each a half-width
  /// [h] from [p].
  static void _appendCap(
    Path path,
    Offset a,
    Offset b,
    Offset p,
    Offset out,
    StrokeEndStyle style,
  ) {
    final h = (a - p).distance;
    // A zero-width end (a taper) has nothing to cap.
    if (h == 0 || style == StrokeEndStyle.butt) {
      path.lineTo(b.dx, b.dy);
      return;
    }
    switch (style) {
      case StrokeEndStyle.square:
        path
          ..lineTo(a.dx + out.dx * h, a.dy + out.dy * h)
          ..lineTo(b.dx + out.dx * h, b.dy + out.dy * h)
          ..lineTo(b.dx, b.dy);
      case StrokeEndStyle.round || StrokeEndStyle.blot:
        // Semicircle of radius h around p, from a to b, bulging along [out].
        // For a blot, h is the dab radius; the width profile does the necking.
        final startAngle = atan2(a.dy - p.dy, a.dx - p.dx);
        final aDir = (a - p) / h;
        final rotated = Offset(-aDir.dy, aDir.dx); // aDir turned +90°
        final sweep =
            (rotated.dx * out.dx + rotated.dy * out.dy) >= 0 ? pi : -pi;
        path.arcTo(
          Rect.fromCircle(center: p, radius: h),
          startAngle,
          sweep,
          false,
        );
      case StrokeEndStyle.butt:
        break; // handled above
    }
  }

  /// Unit vector pointing from [inner] outward through the endpoint [tip].
  static Offset _outwardDir(Offset tip, Offset inner) {
    final v = tip - inner;
    final len = v.distance;
    return len == 0 ? const Offset(1, 0) : v / len;
  }

  /// Generates a randomised variable-width stroke running straight from [start]
  /// to [end], returning the centreline, the two offset edges, and the outline.
  ///
  /// The spine is tessellated into segments roughly [segmentLength] pixels long
  /// (so the count scales with the line's length and the density stays
  /// consistent across strokes). Each sample is nudged perpendicular by a small
  /// random "wobble" so the stroke isn't ruler-straight. The thickness follows a
  /// smoothed random walk between [minWidth] and [maxWidth]; [widthVariability]
  /// (0..1) compresses that swing toward the midpoint.
  ///
  /// By default both ends taper to a point. Pass a [StrokeEnd] as [startCap] or
  /// [endCap] to instead finish that end at a fixed thickness (truncated to
  /// [maxWidth]) with a butt / round / square / blot cap.
  static GeneratedStroke generate({
    required Offset start,
    required Offset end,
    required Random random,
    double segmentLength = _defaultSegmentLength,
    double minWidth = 3,
    double maxWidth = 26,
    double wobble = 10,
    double widthVariability = 1,
    StrokeEnd? startCap,
    StrokeEnd? endCap,
  }) {
    final count = _segmentCount((end - start).distance, segmentLength);
    return _strokeAlongSpine(
      spine: _applyWobble(_lineSamples(start, end, count), random, wobble),
      random: random,
      minWidth: minWidth,
      maxWidth: maxWidth,
      widthVariability: widthVariability,
      startCap: startCap,
      endCap: endCap,
    );
  }

  /// Like [generate], but the spine follows the quadratic Bézier curve defined
  /// by [start], [control] and [end]. Parameters and cap behaviour are identical
  /// to [generate]; the wobble is applied perpendicular to the curve's local
  /// tangent.
  static GeneratedStroke generateCurve({
    required Offset start,
    required Offset control,
    required Offset end,
    required Random random,
    double segmentLength = _defaultSegmentLength,
    double minWidth = 3,
    double maxWidth = 26,
    double wobble = 10,
    double widthVariability = 1,
    StrokeEnd? startCap,
    StrokeEnd? endCap,
  }) {
    final count = _segmentCount(
      _quadraticLength(start, control, end),
      segmentLength,
    );
    return _strokeAlongSpine(
      spine: _applyWobble(
        _quadraticSamples(start, control, end, count),
        random,
        wobble,
      ),
      random: random,
      minWidth: minWidth,
      maxWidth: maxWidth,
      widthVariability: widthVariability,
      startCap: startCap,
      endCap: endCap,
    );
  }

  /// The shared core: given a ready [spine] (already wobbled), builds the width
  /// profile, blot necks, caps and offset edges. Both the line/curve generators
  /// and the path stroker feed a spine through here.
  static GeneratedStroke _strokeAlongSpine({
    required List<Offset> spine,
    required Random random,
    required double minWidth,
    required double maxWidth,
    required double widthVariability,
    required StrokeEnd? startCap,
    required StrokeEnd? endCap,
  }) {
    final minHalf = minWidth / 2;

    // The half-width the *body* profile is pinned to at each end:
    //  - null cap => 0 (taper to a point);
    //  - blot     => minWidth, so the stroke runs thin right after the dab;
    //  - otherwise the requested thickness, truncated to maxWidth.
    double profilePin(StrokeEnd? cap) {
      if (cap == null) return 0;
      if (cap.style == StrokeEndStyle.blot) return minHalf;
      return cap.width.clamp(0.0, maxWidth) / 2;
    }

    // The dab radius for a blot end (null when the end isn't a blot). This is
    // stamped onto the very endpoint after the profile is built, so the cap is
    // wide while the adjacent stroke is already at minimum.
    double? blotRadius(StrokeEnd? cap) =>
        cap != null && cap.style == StrokeEndStyle.blot
            ? cap.width.clamp(0.0, maxWidth) / 2
            : null;

    final halfWidths = _smoothRandomHalfWidths(
      count: spine.length,
      random: random,
      minWidth: minWidth,
      maxWidth: maxWidth,
      variability: widthVariability,
      startHalf: profilePin(startCap),
      endHalf: profilePin(endCap),
    );

    // Ease the blot dab radius down to the (minimum) body over a few samples so
    // the neck is soft rather than a single hard step, while the endpoint itself
    // still carries the full dab.
    final startBlot = blotRadius(startCap);
    final endBlot = blotRadius(endCap);
    if (startBlot != null) {
      _applyBlotNeck(halfWidths, startBlot, fromStart: true);
    }
    if (endBlot != null) {
      _applyBlotNeck(halfWidths, endBlot, fromStart: false);
    }

    final (left, right) = _offsetEdges(spine, halfWidths);
    return GeneratedStroke(
      spine: spine,
      leftEdge: left,
      rightEdge: right,
      outline: _buildOutline(
        spine,
        left,
        right,
        startCap?.style ?? StrokeEndStyle.butt,
        endCap?.style ?? StrokeEndStyle.butt,
      ),
    );
  }

  /// Convenience wrapper around [generate] that returns just the fillable path.
  ///
  /// [random] is optional; when omitted a fresh [Random] is used, so each call
  /// produces a different stroke. Pass a seeded [Random] for a repeatable one.
  static Path line({
    required Offset start,
    required Offset end,
    Random? random,
    double segmentLength = _defaultSegmentLength,
    double minWidth = 3,
    double maxWidth = 26,
    double wobble = 10,
    double widthVariability = 1,
    StrokeEnd? startCap,
    StrokeEnd? endCap,
  }) {
    return generate(
      start: start,
      end: end,
      random: random ?? Random(),
      segmentLength: segmentLength,
      minWidth: minWidth,
      maxWidth: maxWidth,
      wobble: wobble,
      widthVariability: widthVariability,
      startCap: startCap,
      endCap: endCap,
    ).outline;
  }

  /// Convenience wrapper around [generateCurve] that returns just the fillable
  /// path: a variable-width stroke along the quadratic Bézier through [start],
  /// [control] and [end].
  ///
  /// [random] is optional; when omitted a fresh [Random] is used, so each call
  /// produces a different stroke. Pass a seeded [Random] for a repeatable one.
  static Path curve({
    required Offset start,
    required Offset control,
    required Offset end,
    Random? random,
    double segmentLength = _defaultSegmentLength,
    double minWidth = 3,
    double maxWidth = 26,
    double wobble = 10,
    double widthVariability = 1,
    StrokeEnd? startCap,
    StrokeEnd? endCap,
  }) {
    return generateCurve(
      start: start,
      control: control,
      end: end,
      random: random ?? Random(),
      segmentLength: segmentLength,
      minWidth: minWidth,
      maxWidth: maxWidth,
      wobble: wobble,
      widthVariability: widthVariability,
      startCap: startCap,
      endCap: endCap,
    ).outline;
  }

  /// Generates one continuous variable-width stroke along a multi-segment
  /// [StrokePath] (a chain of lines and curves), returning the centreline, the
  /// two offset edges, and the outline.
  ///
  /// Because the whole path is stroked as a single spine, the width flows
  /// smoothly across the joins with no pinch. [startCap] / [endCap] apply at the
  /// two open ends; for a closed path they are ignored and the stroke is built
  /// as a ring.
  static GeneratedStroke generatePath(
    StrokePath spec, {
    required Random random,
    double segmentLength = _defaultSegmentLength,
    double minWidth = 3,
    double maxWidth = 26,
    double wobble = 10,
    double widthVariability = 1,
    StrokeEnd? startCap,
    StrokeEnd? endCap,
  }) {
    if (spec.isEmpty) {
      throw ArgumentError('StrokePath needs at least one segment to stroke.');
    }
    final base = _pathSpine(spec, segmentLength);
    final spine = _applyWobble(base, random, wobble, closed: spec.close);
    return spec.close
        ? _strokeClosedLoop(
            spine: spine,
            random: random,
            minWidth: minWidth,
            maxWidth: maxWidth,
            widthVariability: widthVariability,
          )
        : _strokeAlongSpine(
            spine: spine,
            random: random,
            minWidth: minWidth,
            maxWidth: maxWidth,
            widthVariability: widthVariability,
            startCap: startCap,
            endCap: endCap,
          );
  }

  /// Convenience wrapper around [generatePath] that returns just the fillable
  /// path.
  ///
  /// [random] is optional; when omitted a fresh [Random] is used, so each call
  /// produces a different stroke. Pass a seeded [Random] for a repeatable one.
  static Path path(
    StrokePath spec, {
    Random? random,
    double segmentLength = _defaultSegmentLength,
    double minWidth = 3,
    double maxWidth = 26,
    double wobble = 10,
    double widthVariability = 1,
    StrokeEnd? startCap,
    StrokeEnd? endCap,
  }) {
    return generatePath(
      spec,
      random: random ?? Random(),
      segmentLength: segmentLength,
      minWidth: minWidth,
      maxWidth: maxWidth,
      wobble: wobble,
      widthVariability: widthVariability,
      startCap: startCap,
      endCap: endCap,
    ).outline;
  }

  /// Concatenates the samples of every segment in [spec] into one spine,
  /// dropping each segment's leading point (it duplicates the previous end). Each
  /// segment is tessellated to roughly [segmentLength]-pixel steps based on its
  /// own length, so density is consistent whatever the mix of long and short
  /// pieces. For a closed path a line back to the start is appended and the
  /// duplicated final point removed, leaving the distinct loop vertices.
  static List<Offset> _pathSpine(StrokePath spec, double segmentLength) {
    final points = <Offset>[];
    var from = spec.start;
    for (final seg in spec._segments) {
      final samples = switch (seg) {
        _LineSegment() => _lineSamples(
            from,
            seg.end,
            _segmentCount((seg.end - from).distance, segmentLength),
          ),
        _CurveSegment() => _quadraticSamples(
            from,
            seg.control,
            seg.end,
            _segmentCount(
              _quadraticLength(from, seg.control, seg.end),
              segmentLength,
            ),
          ),
      };
      points.addAll(points.isEmpty ? samples : samples.skip(1));
      from = seg.end;
    }
    if (spec.close) {
      // Only bridge back to the start if the last segment didn't already land
      // there; otherwise a zero-length closing line would inject a degenerate
      // corner at the seam.
      if ((from - spec.start).distanceSquared > 1e-9) {
        final count =
            _segmentCount((spec.start - from).distance, segmentLength);
        points.addAll(_lineSamples(from, spec.start, count).skip(1));
      }
      points.removeLast(); // drop the trailing start-duplicate; loop is implied
    }
    return points;
  }

  /// Strokes a closed [spine] as a ring: an outer and an inner offset contour,
  /// filled even-odd so the band between them is what shows. Width varies
  /// continuously with no end taper or caps.
  static GeneratedStroke _strokeClosedLoop({
    required List<Offset> spine,
    required Random random,
    required double minWidth,
    required double maxWidth,
    required double widthVariability,
  }) {
    final halfWidths = _loopHalfWidths(
      spine.length,
      random,
      minWidth,
      maxWidth,
      widthVariability,
    );
    final (left, right) = _offsetEdges(spine, halfWidths, closed: true);
    final outline = Path()
      ..addPolygon(left, true)
      ..addPolygon(right, true)
      ..fillType = PathFillType.evenOdd;
    return GeneratedStroke(
      spine: spine,
      leftEdge: left,
      rightEdge: right,
      outline: outline,
    );
  }

  /// Body-only half-widths for a closed loop: the smoothed random walk mapped to
  /// `[minWidth, maxWidth]` with no end taper, then eased at the seam so the
  /// loop's thickness meets itself without a step.
  static List<double> _loopHalfWidths(
    int count,
    Random random,
    double minWidth,
    double maxWidth,
    double variability,
  ) {
    final walk = _smoothRandomWalk(count: count, random: random, amplitude: 1);
    final halfWidths = <double>[];
    for (var i = 0; i < count; i++) {
      var unit = (walk[i] * 0.5 + 0.5).clamp(0.0, 1.0);
      unit = 0.5 + (unit - 0.5) * variability;
      halfWidths.add((minWidth + (maxWidth - minWidth) * unit) * 0.5);
    }
    _closeSeam(halfWidths);
    return halfWidths;
  }

  /// Eases the tail of [values] toward `values.first` over a few samples so a
  /// looping sequence joins itself smoothly at the seam.
  static void _closeSeam(List<double> values) {
    final n = values.length;
    final span = min(_blotNeckSamples, max(1, (n - 1) ~/ 4));
    final head = values.first;
    for (var j = 1; j <= span; j++) {
      final t = (j - 1) / span; // 0 at the seam edge, 1 where the ease ends
      final blend = 1 - _smoothstep(t);
      final i = n - j;
      values[i] += (head - values[i]) * blend;
    }
  }

  /// Number of samples over which a blot dab eases down to the body width.
  static const int _blotNeckSamples = 6;

  /// Blends [halfWidths] from the [dab] radius at the end sample down to the
  /// underlying (minimum) profile over a short run, smoothing the blot's neck.
  /// The endpoint keeps the full [dab]; each subsequent sample eases toward the
  /// value already there.
  static void _applyBlotNeck(
    List<double> halfWidths,
    double dab, {
    required bool fromStart,
  }) {
    final n = halfWidths.length;
    final span = min(_blotNeckSamples, max(1, (n - 1) ~/ 4));
    for (var k = 0; k <= span; k++) {
      final i = fromStart ? k : n - 1 - k;
      final t = k / span; // 0 at the dab, 1 where the neck rejoins the body
      final blend = 1 - _smoothstep(t); // 1 at the endpoint, 0 by the span end
      halfWidths[i] += (dab - halfWidths[i]) * blend;
    }
  }

  /// Classic smoothstep easing: 0 at 0, 1 at 1, flat at both ends.
  static double _smoothstep(double t) => t * t * (3 - 2 * t);

  /// Local outward normal at spine point [i], averaged with its neighbours so
  /// the offset direction turns smoothly along the path. When [closed] the
  /// neighbours wrap around, so the seam of a loop gets a proper two-sided
  /// tangent instead of a clamped one.
  static Offset _normalAt(List<Offset> spine, int i, {bool closed = false}) {
    final n = spine.length;
    final prev = closed ? spine[(i - 1 + n) % n] : spine[max(0, i - 1)];
    final next = closed ? spine[(i + 1) % n] : spine[min(n - 1, i + 1)];
    var tangent = next - prev;
    final len = tangent.distance;
    tangent = len == 0 ? const Offset(1, 0) : tangent / len;
    // Rotate the tangent 90°: (dx, dy) -> (-dy, dx).
    return Offset(-tangent.dy, tangent.dx);
  }

  /// Default target length, in pixels, of each tessellated segment.
  static const double _defaultSegmentLength = 10;

  /// Number of segments needed to cover [length] at roughly [segmentLength]
  /// pixels each, always at least one.
  static int _segmentCount(double length, double segmentLength) =>
      max(1, (length / segmentLength).round());

  /// Rough arc length of the quadratic Bézier through [p0], [p1], [p2] — the
  /// mean of its chord and its control-net length. Good enough to choose a
  /// segment count.
  static double _quadraticLength(Offset p0, Offset p1, Offset p2) {
    final chord = (p2 - p0).distance;
    final net = (p1 - p0).distance + (p2 - p1).distance;
    return (chord + net) / 2;
  }

  /// Samples the straight segment [start]..[end] into `segments + 1` points.
  static List<Offset> _lineSamples(Offset start, Offset end, int segments) {
    final axis = end - start;
    return [for (var i = 0; i <= segments; i++) start + axis * (i / segments)];
  }

  /// Samples the quadratic Bézier through [start] (P0), [control] (P1) and
  /// [end] (P2) into `segments + 1` points.
  static List<Offset> _quadraticSamples(
    Offset start,
    Offset control,
    Offset end,
    int segments,
  ) {
    final points = <Offset>[];
    for (var i = 0; i <= segments; i++) {
      final t = i / segments;
      final u = 1 - t;
      // B(t) = u^2 P0 + 2ut P1 + t^2 P2
      points.add(start * (u * u) + control * (2 * u * t) + end * (t * t));
    }
    return points;
  }

  /// Nudges each point of [base] perpendicular to its local tangent by a
  /// smoothed random walk. Works for any spine — straight or curved. On an open
  /// spine the wander tapers to zero at the ends so they stay pinned; on a
  /// [closed] loop there are no ends, so it runs full-amplitude and the seam is
  /// eased so the wander meets itself.
  static List<Offset> _applyWobble(
    List<Offset> base,
    Random random,
    double wobble, {
    bool closed = false,
  }) {
    final n = base.length;
    // Consume the same random draw either way so seeded output is stable
    // whether or not wobble is in play.
    final offsets =
        _smoothRandomWalk(count: n, random: random, amplitude: wobble);
    if (wobble == 0) return base;
    if (closed) _closeSeam(offsets);

    final points = <Offset>[];
    for (var i = 0; i < n; i++) {
      final taper = closed ? 1.0 : sin((i / (n - 1)) * pi); // 0 at open ends
      points.add(
        base[i] + _normalAt(base, i, closed: closed) * (offsets[i] * taper),
      );
    }
    return points;
  }

  static List<double> _smoothRandomHalfWidths({
    required int count,
    required Random random,
    required double minWidth,
    required double maxWidth,
    double variability = 1,
    double startHalf = 0,
    double endHalf = 0,
  }) {
    final walk = _smoothRandomWalk(
      count: count,
      random: random,
      amplitude: 1,
    );
    final halfWidths = <double>[];
    for (var i = 0; i < count; i++) {
      final t = i / (count - 1);

      // Split the classic centre taper into two separable half-humps: the left
      // rises 0->1 over the first half then holds, the right holds then falls
      // 1->0. Their product equals the original sin(pi*t) lens, but each end can
      // now be treated independently.
      final leftHump = sin(pi * min(t, 0.5));
      final rightHump = sin(pi * min(1 - t, 0.5));

      // Map the [-1, 1]-ish walk into [minWidth, maxWidth], then pull it back
      // toward the midpoint by (1 - variability) so the thickness swings less.
      var unit = (walk[i] * 0.5 + 0.5).clamp(0.0, 1.0);
      unit = 0.5 + (unit - 0.5) * variability;
      final body = (minWidth + (maxWidth - minWidth) * unit) * 0.5;

      // Body tapered by both humps, plus each end pinned to its requested
      // half-width where its hump has receded. In each half this is a convex
      // blend of `body` and the end half-width, so it never exceeds maxWidth/2
      // and reduces to the plain taper when both ends are 0.
      final hw = body * leftHump * rightHump +
          startHalf * (1 - leftHump) +
          endHalf * (1 - rightHump);
      halfWidths.add(hw);
    }
    return halfWidths;
  }

  /// Produces [count] values via a random walk that is then relaxed (smoothed)
  /// so neighbouring values stay close — giving organic, non-jittery variation
  /// roughly within `[-amplitude, amplitude]`.
  static List<double> _smoothRandomWalk({
    required int count,
    required Random random,
    required double amplitude,
  }) {
    final raw = <double>[];
    var value = 0.0;
    for (var i = 0; i < count; i++) {
      value += (random.nextDouble() * 2 - 1) * 0.35;
      value = value.clamp(-1.0, 1.0);
      raw.add(value);
    }

    // A couple of smoothing passes soften the walk into flowing curves.
    var smoothed = raw;
    for (var pass = 0; pass < 3; pass++) {
      final next = List<double>.from(smoothed);
      for (var i = 1; i < count - 1; i++) {
        next[i] = (smoothed[i - 1] + smoothed[i] * 2 + smoothed[i + 1]) / 4;
      }
      smoothed = next;
    }

    return [for (final v in smoothed) v * amplitude];
  }
}
