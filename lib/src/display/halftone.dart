import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:meta/meta.dart';

/// How the gradient's [HalftoneStop.amount] maps to dot radius.
///
/// The mapping is applied when the amount lookup is baked (see [buildAmountLut]),
/// so the shader is identical for every mode — no branch, no GPU cost.
enum HalftoneGrowth {
  /// Dot radius grows linearly with amount.
  linear,

  /// Dot *area* (ink coverage) grows linearly with amount, i.e.
  /// radius ∝ √amount. Reads as a more perceptually even tone ramp.
  area,
}

/// A single stop on the halftone amount curve.
///
/// [position] is the fractional distance along the gradient axis (0..1) and
/// [amount] is the dot coverage at that point (0 = no dot / background,
/// 1 = fully solid foreground). Values between stops are linearly interpolated;
/// outside the first/last stop the curve is held flat.
///
/// See `docs/halftone.md`.
@immutable
class HalftoneStop {
  const HalftoneStop(this.position, this.amount);

  /// Fractional distance along the gradient axis (0..1).
  final double position;

  /// Dot coverage at [position] (0 = background, 1 = solid foreground).
  final double amount;

  @override
  bool operator ==(Object other) =>
      other is HalftoneStop &&
      other.position == position &&
      other.amount == amount;

  @override
  int get hashCode => Object.hash(position, amount);
}

/// Immutable description of a halftone gradient fill.
///
/// See `docs/halftone.md`.
@immutable
class HalftoneGradient {
  const HalftoneGradient({
    required this.axisStart,
    required this.axisEnd,
    required this.gridSize,
    required this.stops,
    this.offset = 0.0,
    this.screenAngle = 0.0,
    this.growth = HalftoneGrowth.linear,
    this.foreground = const Color(0xFF000000),
    this.background = const Color(0xFFFFFFFF),
  });

  /// Gradient axis start, in the fill's local pixel space.
  final Offset axisStart;

  /// Gradient axis end, in the fill's local pixel space.
  final Offset axisEnd;

  /// Lattice spacing in pixels.
  final double gridSize;

  /// Phase offset in pixels along the gradient normal. Used to align the
  /// lattices of two independently-drawn slices across a shared seam.
  final double offset;

  /// Lattice rotation ("screen angle") in radians.
  final double screenAngle;

  /// How amount maps to dot radius. Baked into the amount LUT, not the shader.
  final HalftoneGrowth growth;

  /// Dot colour.
  final Color foreground;

  /// Field colour.
  final Color background;

  /// Amount-vs-position curve. Should be sorted by [HalftoneStop.position].
  final List<HalftoneStop> stops;

  /// Convenience for a vertical gradient over a box of [size].
  factory HalftoneGradient.vertical({
    required Size size,
    required double gridSize,
    required List<HalftoneStop> stops,
    double offset = 0.0,
    double screenAngle = 0.0,
    HalftoneGrowth growth = HalftoneGrowth.linear,
    Color foreground = const Color(0xFF000000),
    Color background = const Color(0xFFFFFFFF),
  }) {
    return HalftoneGradient(
      axisStart: Offset(size.width / 2, 0),
      axisEnd: Offset(size.width / 2, size.height),
      gridSize: gridSize,
      stops: stops,
      offset: offset,
      screenAngle: screenAngle,
      growth: growth,
      foreground: foreground,
      background: background,
    );
  }
}

/// The result of a bake: the rendered [image] plus where it belongs.
///
/// [origin] is the coordinate, in the path's own space, of the image's
/// top-left pixel. When a bake auto-sizes to fit spilled dots, [origin] sits
/// above-left of the path bounds by the spill margin. Placement:
///
/// * to draw the shape exactly where its path is defined:
///   `canvas.drawImage(bake.image, bake.origin, paint)`;
/// * to put the path's own (0,0) at some target `t`:
///   `canvas.drawImage(bake.image, t + bake.origin, paint)`.
///
/// [origin] is [Offset.zero] whenever an explicit `size` was supplied.
///
/// See `docs/halftone.md`.
@immutable
class HalftoneBake {
  const HalftoneBake({required this.image, required this.origin});

  /// The rendered halftone image.
  final Image image;

  /// The coordinate of [image]'s top-left pixel in the path's own space.
  final Offset origin;
}

/// Loads the halftone [FragmentProgram]s once and produces configured shaders /
/// baked images from a [HalftoneGradient].
///
/// This is a pure `dart:ui` utility: build a shader with [shaderFor] /
/// [shaderForPathDots] and apply it as a [Paint.shader] inside your own
/// component's `render(canvas)`, or [bake] / [bakePathDots] to a cached [Image]
/// for the blit-while-scrolling path. See `docs/halftone.md`.
class HalftoneRenderer {
  HalftoneRenderer._(this._program, this._imageProgram, this._pathProgram);

  final FragmentProgram _program;
  final FragmentProgram _imageProgram;
  final FragmentProgram _pathProgram;

  /// Loads the shader programs. Call once at startup and reuse the result.
  ///
  /// The asset keys are prefixed with `packages/sizzle/` because the shaders
  /// ship inside this package; a package-relative `'shaders/...'` path fails to
  /// load at runtime.
  static Future<HalftoneRenderer> load() async {
    final program = await FragmentProgram.fromAsset(
      'packages/sizzle/shaders/halftone.frag',
    );
    final imageProgram = await FragmentProgram.fromAsset(
      'packages/sizzle/shaders/halftone_image.frag',
    );
    final pathProgram = await FragmentProgram.fromAsset(
      'packages/sizzle/shaders/halftone_path.frag',
    );
    return HalftoneRenderer._(program, imageProgram, pathProgram);
  }

  /// Default tone curve for [halftoneImage]: dark source (luminance 0) → full
  /// dot, light source (luminance 1) → no dot. Reproduces a photo as
  /// foreground ink on the background.
  static const List<HalftoneStop> defaultTone = [
    HalftoneStop(0.0, 1.0),
    HalftoneStop(1.0, 0.0),
  ];

  /// Builds a [FragmentShader] configured for [gradient] and [lut].
  ///
  /// [lut] is a 1D amount lookup produced by [buildAmountLut] (or [buildLut])
  /// for the gradient's stops. It is passed separately so callers can cache it
  /// and only rebuild when the stops change.
  FragmentShader shaderFor(HalftoneGradient gradient, Image lut) {
    final shader = _program.fragmentShader();
    var i = 0;
    // Uniform order must match the declaration order in halftone.frag.
    shader.setFloat(i++, gradient.axisStart.dx);
    shader.setFloat(i++, gradient.axisStart.dy);
    shader.setFloat(i++, gradient.axisEnd.dx);
    shader.setFloat(i++, gradient.axisEnd.dy);
    shader.setFloat(i++, gradient.gridSize);
    shader.setFloat(i++, gradient.offset);
    shader.setFloat(i++, gradient.screenAngle);
    _setColor(shader, () => i++, gradient.foreground);
    _setColor(shader, () => i++, gradient.background);
    shader.setImageSampler(0, lut);
    return shader;
  }

  /// Builds the amount LUT for [gradient] (its stops + growth mode). Callers
  /// that bake or paint many frames from the same stops can build this once and
  /// pass it back in via [shaderFor] / [bake] to avoid rebuilding it.
  Future<Image> buildLut(HalftoneGradient gradient) =>
      buildAmountLut(gradient.stops, growth: gradient.growth);

  /// Renders [gradient] into an offscreen image. This is the production path:
  /// bake a slice once, then blit the image while it scrolls.
  ///
  /// If [clip] is given, the halftone only fills that path (in the gradient's
  /// coordinate space) and everything outside it is left transparent. For a
  /// Sizzle `StrokePath`, pass its `toPath()`.
  ///
  /// [size] is optional: supply it for a fixed output rectangle, or omit it (a
  /// [clip] is then required) to auto-size the image tightly to the clip's
  /// bounds. The returned [HalftoneBake.origin] gives the placement offset.
  ///
  /// The amount LUT is built internally from the gradient. For hot loops that
  /// reuse the same stops across many bakes, pass a cached [lut] (from
  /// [buildLut]) to skip rebuilding it each time.
  Future<HalftoneBake> bake(
    HalftoneGradient gradient, {
    Size? size,
    Path? clip,
    Image? lut,
  }) async {
    if (size == null && clip == null) {
      throw ArgumentError('bake needs a size or a clip to size the output.');
    }
    final amountLut = lut ?? await buildLut(gradient);

    final bounds =
        size != null ? Offset.zero & size : _pixelBounds(clip!.getBounds());
    final origin = bounds.topLeft;
    final g =
        origin == Offset.zero ? gradient : _shiftGradient(gradient, -origin);
    final localClip =
        (clip != null && origin != Offset.zero) ? clip.shift(-origin) : clip;

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    if (localClip != null) canvas.clipPath(localClip);
    canvas.drawRect(
      Offset.zero & bounds.size,
      Paint()..shader = shaderFor(g, amountLut),
    );
    final image = await recorder
        .endRecording()
        .toImage(bounds.width.ceil(), bounds.height.ceil());
    return HalftoneBake(image: image, origin: origin);
  }

  /// Returns a halftone reproduction of [source] at the same pixel dimensions.
  ///
  /// Each lattice dot takes the tone of the source luminance at its centre, so
  /// the result reads as the image rendered in dots. All the usual controls
  /// apply: [gridSize] (dot spacing, px), [screenAngle] (lattice rotation,
  /// radians), [growth] (radius vs. area), [offset] (lattice phase in px, for
  /// tiling), and the two [foreground]/[background] colours.
  ///
  /// [tone] maps source luminance (0..1) to dot amount and doubles as a
  /// levels/contrast curve; the default ([defaultTone]) turns dark areas into
  /// full dots. [averageCells] (default true) pre-blurs the source by
  /// `gridSize * 0.5` so each centre sample reads as a cell average, giving
  /// smooth silhouettes; set false to point-sample. As with [bake], a cached
  /// [lut] (from [buildAmountLut] on the same [tone] + [growth]) can be supplied
  /// to skip rebuilding it.
  Future<Image> halftoneImage(
    Image source, {
    required double gridSize,
    double offset = 0.0,
    double screenAngle = 0.0,
    HalftoneGrowth growth = HalftoneGrowth.linear,
    List<HalftoneStop> tone = defaultTone,
    Color foreground = const Color(0xFF000000),
    Color background = const Color(0xFFFFFFFF),
    bool averageCells = true,
    Image? lut,
  }) async {
    final toneLut = lut ?? await buildAmountLut(tone, growth: growth);
    // Each dot samples the source at its cell centre. Point-sampling makes edges
    // and fine detail blocky (a boundary cell is all-or-nothing on its centre
    // pixel); pre-blurring by ~half a cell turns the centre sample into a local
    // average, so boundary dots take an intermediate size and the result reads
    // as proper halftone screening.
    final sampled = averageCells ? await _blur(source, gridSize * 0.5) : source;

    final shader = _imageProgram.fragmentShader();
    var i = 0;
    // Uniform order must match halftone_image.frag.
    shader.setFloat(i++, source.width.toDouble());
    shader.setFloat(i++, source.height.toDouble());
    shader.setFloat(i++, gridSize);
    shader.setFloat(i++, offset);
    shader.setFloat(i++, screenAngle);
    _setColor(shader, () => i++, foreground);
    _setColor(shader, () => i++, background);
    shader.setImageSampler(0, sampled);
    shader.setImageSampler(1, toneLut);

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(source.width.toDouble(), source.height.toDouble());
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    final picture = recorder.endRecording();
    return picture.toImage(source.width, source.height);
  }

  /// Returns [source] Gaussian-blurred by [sigma] px, at the same dimensions.
  Future<Image> _blur(Image source, double sigma) {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()
      ..imageFilter = ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: TileMode.clamp,
      );
    canvas.drawImage(source, Offset.zero, paint);
    return recorder.endRecording().toImage(source.width, source.height);
  }

  /// Rasterises [path] into a mask image of [size] (white inside, black out),
  /// used by the path-dots renderer to decide dot membership by centre.
  ///
  /// [feather] (blur sigma in px) softens the mask edge so edge dots shrink
  /// smoothly instead of popping off; 0 gives a crisp mask (hard cutoff).
  Future<Image> rasterizePathMask(
    Path path,
    Size size, {
    double feather = 0,
  }) {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF000000),
    );
    final paint = Paint()..color = const Color(0xFFFFFFFF);
    if (feather > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, feather);
    }
    canvas.drawPath(path, paint);
    return recorder
        .endRecording()
        .toImage(size.width.ceil(), size.height.ceil());
  }

  /// Configures a path-dots [FragmentShader]: like [shaderFor], but each dot is
  /// kept only if its cell centre lies inside [mask] (from [rasterizePathMask])
  /// and is then drawn whole (never clipped at the path boundary).
  FragmentShader shaderForPathDots(
    HalftoneGradient gradient,
    Image lut,
    Image mask,
    Size size,
  ) {
    final shader = _pathProgram.fragmentShader();
    var i = 0;
    // Uniform order must match halftone_path.frag.
    shader.setFloat(i++, gradient.axisStart.dx);
    shader.setFloat(i++, gradient.axisStart.dy);
    shader.setFloat(i++, gradient.axisEnd.dx);
    shader.setFloat(i++, gradient.axisEnd.dy);
    shader.setFloat(i++, gradient.gridSize);
    shader.setFloat(i++, gradient.offset);
    shader.setFloat(i++, gradient.screenAngle);
    _setColor(shader, () => i++, gradient.foreground);
    _setColor(shader, () => i++, gradient.background);
    shader.setFloat(i++, size.width);
    shader.setFloat(i++, size.height);
    shader.setImageSampler(0, lut);
    shader.setImageSampler(1, mask);
    return shader;
  }

  /// The largest distance (px) a whole/feathered dot can extend past the path
  /// edge, for a given [gridSize] and [feather] (defaults to `gridSize * 0.6`).
  /// This is the margin [bakePathDots] adds when auto-sizing; expose it if you
  /// want to size/offset a bake yourself.
  static double pathDotsSpill({required double gridSize, double? feather}) {
    final f = feather ?? gridSize * 0.6;
    return gridSize * 0.70710678 + 0.75 + 2 * f;
  }

  /// Like [bake] with a clip, but dots are included whole when their centre is
  /// inside [path] rather than being sliced at the boundary — circles spill
  /// past the edge. The background is still bounded by [path].
  ///
  /// [size] is optional: supply it for a fixed output rectangle, or omit it to
  /// auto-size the image to the path bounds inflated by [pathDotsSpill] so the
  /// spilled dots are fully captured. The returned [HalftoneBake.origin] is the
  /// placement offset (its inset from the path bounds is the spill margin).
  ///
  /// [feather] (blur sigma in px) antialiases the silhouette: edge dots shrink
  /// smoothly through the soft band outside the path instead of popping off.
  /// Defaults to `gridSize * 0.6`; pass 0 for a crisp cutoff.
  ///
  /// The amount LUT and the path mask are built internally; pass a cached [lut]
  /// (from [buildLut]) to skip rebuilding it in a hot loop.
  Future<HalftoneBake> bakePathDots(
    HalftoneGradient gradient,
    Path path, {
    Size? size,
    Image? lut,
    double? feather,
  }) async {
    final f = feather ?? gradient.gridSize * 0.6;
    final amountLut = lut ?? await buildLut(gradient);

    final bounds = size != null
        ? Offset.zero & size
        : pathDotsBakeBounds(
            path,
            pathDotsSpill(gridSize: gradient.gridSize, feather: f),
          );
    final origin = bounds.topLeft;
    final g =
        origin == Offset.zero ? gradient : _shiftGradient(gradient, -origin);
    final localPath = origin == Offset.zero ? path : path.shift(-origin);

    final mask = await rasterizePathMask(localPath, bounds.size, feather: f);

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Offset.zero & bounds.size,
      Paint()..shader = shaderForPathDots(g, amountLut, mask, bounds.size),
    );
    final image = await recorder
        .endRecording()
        .toImage(bounds.width.ceil(), bounds.height.ceil());
    return HalftoneBake(image: image, origin: origin);
  }
}

/// The pixel-snapped output rectangle [HalftoneRenderer.bakePathDots] uses when
/// auto-sizing: [path]'s bounds inflated by [spill] (from
/// [HalftoneRenderer.pathDotsSpill]) and rounded outward to whole pixels. Its
/// `topLeft` is the resulting [HalftoneBake.origin] and its `size` the image
/// dimensions.
Rect pathDotsBakeBounds(Path path, double spill) =>
    _pixelBounds(path.getBounds().inflate(spill));

/// Rounds [r] outward to whole pixels.
Rect _pixelBounds(Rect r) => Rect.fromLTRB(
      r.left.floorToDouble(),
      r.top.floorToDouble(),
      r.right.ceilToDouble(),
      r.bottom.ceilToDouble(),
    );

/// A copy of [g] with its gradient axis translated by [d].
HalftoneGradient _shiftGradient(HalftoneGradient g, Offset d) =>
    HalftoneGradient(
      axisStart: g.axisStart + d,
      axisEnd: g.axisEnd + d,
      gridSize: g.gridSize,
      stops: g.stops,
      offset: g.offset,
      screenAngle: g.screenAngle,
      growth: g.growth,
      foreground: g.foreground,
      background: g.background,
    );

void _setColor(FragmentShader shader, int Function() next, Color color) {
  shader.setFloat(next(), color.r);
  shader.setFloat(next(), color.g);
  shader.setFloat(next(), color.b);
  shader.setFloat(next(), color.a);
}

/// Builds a 256x1 RGBA lookup image encoding radius-fraction-vs-position for
/// [stops]. The value is stored in the red channel and sampled by the shader
/// (which multiplies it by the max radius). The [growth] mapping is applied
/// here, so the shader stays identical regardless of mode.
Future<Image> buildAmountLut(
  List<HalftoneStop> stops, {
  HalftoneGrowth growth = HalftoneGrowth.linear,
}) {
  const width = 256;
  final pixels = Uint8List(width * 4);
  final sorted = [...stops]..sort((a, b) => a.position.compareTo(b.position));

  for (var x = 0; x < width; x++) {
    final t = x / (width - 1);
    final amount = _amountAt(sorted, t);
    final mapped = switch (growth) {
      HalftoneGrowth.linear => amount,
      HalftoneGrowth.area => math.sqrt(amount),
    };
    final a = (mapped * 255.0).round().clamp(0, 255);
    final o = x * 4;
    pixels[o] = a; // R = radius fraction
    pixels[o + 1] = 0;
    pixels[o + 2] = 0;
    pixels[o + 3] = 255;
  }

  final completer = Completer<Image>();
  decodeImageFromPixels(
    pixels,
    width,
    1,
    PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

double _amountAt(List<HalftoneStop> stops, double t) {
  if (stops.isEmpty) return t;
  if (t <= stops.first.position) return stops.first.amount;
  if (t >= stops.last.position) return stops.last.amount;
  for (var i = 0; i < stops.length - 1; i++) {
    final a = stops[i];
    final b = stops[i + 1];
    if (t >= a.position && t <= b.position) {
      final span = b.position - a.position;
      if (span <= 0) return b.amount;
      final f = (t - a.position) / span;
      return a.amount + (b.amount - a.amount) * f;
    }
  }
  return stops.last.amount;
}
