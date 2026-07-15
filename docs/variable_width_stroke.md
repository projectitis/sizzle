# Variable-width strokes (calligraphy)

[:arrow_left: Back to documentation](index.md)

- [What it is](#what-it-is)
- [Drawing a stroke](#drawing-a-stroke)
- [Lines, curves and paths](#lines-curves-and-paths)
- [End treatments](#end-treatments)
- [Closed paths (rings)](#closed-paths-rings)
- [Tuning the look](#tuning-the-look)
- [Randomness and determinism](#randomness-and-determinism)
- [Limitations](#limitations)


## What it is

[`VariableWidthStroke`](../lib/src/display/variable_width_stroke.dart#:~:text=class+VariableWidthStroke)
generates a filled `Path` whose thickness swells and tapers along its length,
the way an ink-loaded nib or brush does — hand-drawn, "calligraphic" strokes for
comic-book-style art rather than uniform vector lines.

It works by treating the line you give it as a *centreline* ("spine"), then
offsetting a randomised, smoothly-varying half-width to each side and filling the
resulting outline. Because it produces a plain `dart:ui` `Path`, you fill it with
any `Paint` in a Flame component's `render` or a `CustomPainter` — Sizzle adds no
component of its own.


## Drawing a stroke

The quickest entry points return a fillable `Path` directly:

```dart
import 'package:sizzle/sizzle.dart';

final path = VariableWidthStroke.line(
  start: const Offset(20, 100),
  end: const Offset(300, 90),
);
```

Fill it wherever you render:

```dart
class InkStroke extends PositionComponent {
  InkStroke(this._path);

  final Path _path;
  final Paint _ink = Paint()..color = const Color(0xFF101010);

  @override
  void render(Canvas canvas) => canvas.drawPath(_path, _ink);
}
```

The stroke is randomised, so every call produces a slightly different line. Pass
a seeded `Random` to make it repeatable — see
[Randomness and determinism](#randomness-and-determinism).


## Lines, curves and paths

Three shapes are available, each with a `Path`-returning convenience method and a
`generate…` counterpart that also exposes the centreline and edges (a
[`GeneratedStroke`](../lib/src/display/variable_width_stroke.dart#:~:text=class+GeneratedStroke)):

- **Line** — [`line`](../lib/src/display/variable_width_stroke.dart#:~:text=Path+line) /
  `generate`, a straight run between two points.
- **Curve** — [`curve`](../lib/src/display/variable_width_stroke.dart#:~:text=Path+curve) /
  `generateCurve`, a quadratic Bézier through `start`, a `control` point, and
  `end`.
- **Path** — [`path`](../lib/src/display/variable_width_stroke.dart#:~:text=Path+path) /
  `generatePath`, a chain of lines and curves stroked as one.

For a multi-segment stroke, build a
[`StrokePath`](../lib/src/display/variable_width_stroke.dart#:~:text=class+StrokePath)
from a start point and chain `lineTo` / `curveTo`:

```dart
final spec = StrokePath(const Offset(20, 200))
  ..lineTo(const Offset(120, 160))
  ..curveTo(const Offset(220, 60), const Offset(320, 180))
  ..lineTo(const Offset(420, 150));

final path = VariableWidthStroke.path(spec);
```

The whole path is stroked as a single spine, so the width flows smoothly across
each join with no pinch — this is why you build one `StrokePath` rather than
drawing several separate strokes.


## End treatments

By default each end tapers to a fine point. To finish an end at a fixed
thickness, pass a
[`StrokeEnd`](../lib/src/display/variable_width_stroke.dart#:~:text=class+StrokeEnd)
as `startCap` / `endCap`. Its `width` is the full thickness (truncated to
`maxWidth`), and its `style` is one of
[`StrokeEndStyle`](../lib/src/display/variable_width_stroke.dart#:~:text=enum+StrokeEndStyle):

- **`butt`** — flat, flush with the endpoint.
- **`round`** — a semicircular cap bulging one half-width past the endpoint.
- **`square`** — a rectangular cap extending one half-width past the endpoint.
- **`blot`** — a round dab that immediately necks down to `minWidth`, mimicking
  the heavy ink a brush deposits when it first touches the page.

```dart
final path = VariableWidthStroke.line(
  start: const Offset(20, 100),
  end: const Offset(300, 100),
  startCap: const StrokeEnd(24, style: StrokeEndStyle.blot),
  endCap: const StrokeEnd(10, style: StrokeEndStyle.round),
);
```


## Closed paths (rings)

Set `close: true` on a `StrokePath` to join the last segment back to the start
and stroke the result as a ring — a hollow band with continuous width and no end
caps (caps are ignored for closed paths):

```dart
final ring = StrokePath(const Offset(150, 40), close: true)
  ..curveTo(const Offset(260, 40), const Offset(260, 150))
  ..curveTo(const Offset(260, 260), const Offset(150, 260))
  ..curveTo(const Offset(40, 260), const Offset(40, 150))
  ..curveTo(const Offset(40, 40), const Offset(150, 40));

final path = VariableWidthStroke.path(ring); // fillType is evenOdd
```

If your last segment already returns to the start point (as above), the closing
line is skipped so a fully-curved loop stays smooth all the way around. The
returned `Path` uses `PathFillType.evenOdd`, so the interior is left hollow.


## Tuning the look

All methods share the same shaping parameters:

- **`minWidth` / `maxWidth`** — the thickness range the body varies between.
- **`widthVariability`** (0..1) — compresses the thickness swing toward its
  midpoint. `1` uses the full range; lower values are calmer. `0` is near-uniform
  width.
- **`wobble`** — how far the centreline wanders off the ideal line/curve. `0`
  keeps it exact.
- **`segmentLength`** — the target length, in pixels, of each tessellated
  segment. The number of samples is derived from the shape's length, so the same
  `segmentLength` gives a consistent density (and consistent wobble/width
  feature size) regardless of how long the stroke is.

Because the thickness variation is generated per sample, `widthVariability` and
`segmentLength` interact: a given `widthVariability` reads smoother at a larger
`segmentLength` (fewer, wider features) and busier at a smaller one. Pick a
`segmentLength` for your art scale first, then tune `widthVariability`.


## Randomness and determinism

The `Path`-returning methods (`line`, `curve`, `path`) take an optional
`random`. Omit it and a fresh `Random` is used, so every call differs. Pass a
seeded `Random` for a repeatable stroke — useful for caching, or for art that
must look identical every run:

```dart
final path = VariableWidthStroke.line(
  start: a,
  end: b,
  random: Random(1234),
);
```

The `generate…` methods require the `Random` explicitly. Generating the `Path`
is not free, so cache it and only rebuild when its inputs change rather than
regenerating every frame.


## Limitations

- **Sharp corners / tight curves.** The offset edges can self-intersect where the
  centreline turns tighter than the half-width (a sharp join, or a curve whose
  radius is smaller than the stroke is thick). Gentle geometry is unaffected;
  keep joins soft, or reduce the width, if you see a knot at a corner.
- **Quadratic only.** Curves are quadratic Béziers (single control point). Chain
  several `curveTo`s to approximate longer or cubic-like curves.
- **Closing is a line.** A closed path bridges back to the start with a straight
  segment; end the last `curveTo` at the start point for a fully-curved loop.
