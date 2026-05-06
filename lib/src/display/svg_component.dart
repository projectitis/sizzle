import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:meta/meta.dart';

import './environment.dart';
import './svg.dart';
import '../utils/services.dart';

/// Renders a parsed [Svg] with lighting from the nearest [Environment]
/// ancestor.
///
/// The component caches a `ui.Picture` of the lit SVG and recomposes only
/// when [needsRedraw] is set, which happens automatically when:
/// * the [Environment]'s lights change (cascades down through every
///   [EnvironmentComponent] descendant), or
/// * `this.angle` changes (the setter calls [markNeedsRedraw]).
///
/// **Important:** any rotating component sitting between the [Environment]
/// and this [SvgComponent] must itself extend [EnvironmentComponent] so
/// its rotation can cascade dirty state. Wrapping in a plain
/// [PositionComponent] breaks the cascade and lighting will appear stale.
///
/// Translation and scale are handled by the parent canvas transform and do
/// not trigger a recompose.
///
/// Construct with an asset [path]; the SVG is loaded via [Services.svg]
/// during [onLoad] and the component's [size] is set to the SVG's size.
/// If [anchor] is not provided it is derived from the SVG's `pp:origin`.
class SvgComponent extends EnvironmentComponent {
  SvgComponent({
    required String path,
    Anchor? anchor,
    super.position,
    super.scale,
    super.angle,
    super.priority,
    super.children,
    super.key,
  })  : _path = path,
        _preloadedSvg = null,
        _explicitAnchor = anchor,
        super(anchor: anchor ?? Anchor.topLeft);

  /// Build directly from an already-parsed [Svg]. Useful for tests or when
  /// the caller manages loading and caching themselves.
  SvgComponent.fromSvg(
    Svg svg, {
    Anchor? anchor,
    super.position,
    super.scale,
    super.angle,
    super.priority,
    super.children,
    super.key,
  })  : _path = '',
        _preloadedSvg = svg,
        _explicitAnchor = anchor,
        super(anchor: anchor ?? Anchor.topLeft);

  final String _path;
  final Svg? _preloadedSvg;
  final Anchor? _explicitAnchor;

  Svg? _svg;
  Svg? get svg => _svg;

  Picture? _picture;

  /// The cached lit [Picture]. Replaced on every recompose.
  @visibleForTesting
  Picture? get picture => _picture;

  @override
  Future<void> onLoad() async {
    final s = _preloadedSvg ?? await Services.svg.load(path: _path);
    _svg = s;
    size = s.size;
    if (_explicitAnchor == null && s.size.x > 0 && s.size.y > 0) {
      anchor = Anchor(s.origin.x / s.size.x, s.origin.y / s.size.y);
    }
  }

  @override
  void onMount() {
    super.onMount();
    if (environment == null) {
      throw StateError(
        '$runtimeType requires an Environment ancestor in the tree',
      );
    }
  }

  @override
  set angle(double v) {
    if (v == angle) return;
    super.angle = v;
    markNeedsRedraw();
  }

  @override
  void render(Canvas canvas) {
    final s = _svg;
    if (s == null) return;
    if (needsRedraw || _picture == null) {
      final relAngle = absoluteAngle - environment!.absoluteAngle;
      _compose(s, relAngle);
      clearNeedsRedraw();
    }
    canvas.drawPicture(_picture!);
  }

  @override
  void onRemove() {
    _picture?.dispose();
    _picture = null;
    super.onRemove();
  }

  void _compose(Svg s, double totalAngle) {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    final lights = environment!.lights;
    final paint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;

    for (final item in s.renderList) {
      canvas.save();
      canvas.transform(Float64List.fromList(item.transform.storage));
      for (final path in item.group.paths) {
        paint.color = resolvePathColor(
          path,
          item.group.material,
          totalAngle,
          lights,
        );
        canvas.drawPath(path.uiPath, paint);
      }
      canvas.restore();
    }

    _picture?.dispose();
    _picture = recorder.endRecording();
  }

  // --- Shading ---------------------------------------------------------------

  /// Specular hardness exponent. Higher = sharper highlight.
  @visibleForTesting
  static const double specularExponent = 16.0;

  /// Maximum lighten/darken amount (toward white/black) applied when light
  /// intensity falls outside `[0, 1]` in dual-colour mode.
  @visibleForTesting
  static const double outOfRangeFactor = 0.5;

  /// How strongly a light's colour pushes the surface toward that colour.
  /// Tinting is multiplicative: `c * (1 + tint * tintStrength)`.
  @visibleForTesting
  static const double tintStrength = 0.75;

  /// Per-sheen highlight strength in single-colour mode — controls how much
  /// the surface lightens above the shading midpoint. Specular bypasses this
  /// and modulates alpha instead.
  @visibleForTesting
  static const Map<SvgMaterialSheen, double> sheenFactor =
      <SvgMaterialSheen, double>{
    SvgMaterialSheen.dull: 0.2,
    SvgMaterialSheen.matte: 0.50,
    SvgMaterialSheen.gloss: 0.80,
    SvgMaterialSheen.specular: 0.0,
  };

  /// Sheen-independent shadow strength in single-colour mode. Below the
  /// shading midpoint, surfaces darken at this rate regardless of sheen,
  /// giving uniformly deep shadows where dull/matte/gloss read as similar.
  @visibleForTesting
  static const double shadowFactor = 0.6;

  /// How much sheen still flavours the shadow side, as a multiplier on
  /// [sheenFactor]. 0 = shadow depth is purely [shadowFactor]; 1 = shadow
  /// would scale with sheen as much as the highlight does. Small values
  /// keep gloss slightly deeper than dull while still reading as "dark".
  @visibleForTesting
  static const double shadowSheenWeight = 0.6;

  /// Resolve the final fill colour for [path] given its group [material], the
  /// accumulated rotation [totalAngle] from the [Environment], and the
  /// environment's [lights]. Pure function — exposed for testing.
  @visibleForTesting
  static Color resolvePathColor(
    SvgPath path,
    SvgMaterial material,
    double totalAngle,
    List<Light> lights,
  ) {
    // Rotate the normal in the XY plane by totalAngle. Z is unaffected.
    final cosA = cos(totalAngle);
    final sinA = sin(totalAngle);
    final wnx = cosA * path.normal.x - sinA * path.normal.y;
    final wny = sinA * path.normal.x + cosA * path.normal.y;
    final wnz = path.normal.z;

    // Two accumulators:
    //   `shadeI` is signed — back-facing directional contributions push it
    //   below 0 so surfaces facing away can darken below baseColor (single
    //   mode) or below the lerp floor (dual mode).
    //   `intensity` clamps directional contributions at 0 — represents the
    //   non-negative "incident light energy" used to normalise the tint hue.
    double shadeI = 0;
    double intensity = 0;
    double tintR = 0, tintG = 0, tintB = 0;
    double specPower = 0;
    final isSpec = material.sheen == SvgMaterialSheen.specular;

    for (final l in lights) {
      double signed;
      double clampedI;
      if (l is AmbientLight) {
        signed = l.strength;
        clampedI = l.strength;
      } else if (l is DirectionalLight) {
        // Surface faces the light when dot(N, -direction) > 0.
        final ndl =
            -(wnx * l.direction.x + wny * l.direction.y + wnz * l.direction.z);
        signed = ndl * l.strength;
        final clamped = ndl < 0 ? 0.0 : ndl;
        clampedI = clamped * l.strength;
        if (isSpec) {
          specPower += pow(clamped, specularExponent) * l.strength;
        }
      } else {
        continue;
      }
      shadeI += signed;
      intensity += clampedI;
      final argb = l.color.toARGB32();
      final lr = ((argb >> 16) & 0xFF) / 255.0;
      final lg = ((argb >> 8) & 0xFF) / 255.0;
      final lb = (argb & 0xFF) / 255.0;
      tintR += lr * clampedI;
      tintG += lg * clampedI;
      tintB += lb * clampedI;
    }

    final base = material.baseColor;
    final top = material.topColor;
    final dualMode = base.toARGB32() != top.toARGB32();

    // Average light hue, normalised to [0, 1] per channel. White light leaves
    // surfaces unchanged; coloured light pulls each channel toward
    // (channel * lightChannel) by [tintStrength]. Saturation is faded toward
    // neutral as total intensity approaches zero, otherwise the hue would
    // snap from "fully tinted" to "no tint" at the boundary where a
    // directional light's contribution clamps to 0, producing a visible edge.
    double avgR = 1, avgG = 1, avgB = 1;
    if (intensity > 0) {
      final inv = 1.0 / intensity;
      final hueR = (tintR * inv).clamp(0.0, 1.0);
      final hueG = (tintG * inv).clamp(0.0, 1.0);
      final hueB = (tintB * inv).clamp(0.0, 1.0);
      final w = intensity.clamp(0.0, 1.0);
      avgR = 1 + (hueR - 1) * w;
      avgG = 1 + (hueG - 1) * w;
      avgB = 1 + (hueB - 1) * w;
    }

    if (isSpec) {
      // Specular paths: nearly invisible except where light hits directly.
      // Colour is the (tinted) base; alpha is driven by the highlight power.
      final r = _tintChannel(_channelR(base), avgR);
      final g = _tintChannel(_channelG(base), avgG);
      final b = _tintChannel(_channelB(base), avgB);
      final a = _clamp255((255 * specPower).round());
      return Color.fromARGB(a, r, g, b);
    }

    int r, g, b;
    int alpha;
    if (dualMode) {
      final t = intensity.clamp(0.0, 1.0);
      r = _lerpInt(_channelR(base), _channelR(top), t);
      g = _lerpInt(_channelG(base), _channelG(top), t);
      b = _lerpInt(_channelB(base), _channelB(top), t);
      if (shadeI > 1) {
        final shift = (shadeI - 1) * outOfRangeFactor;
        r = _shift(r, shift);
        g = _shift(g, shift);
        b = _shift(b, shift);
      } else if (shadeI < 0) {
        final shift = shadeI * outOfRangeFactor;
        r = _shift(r, shift);
        g = _shift(g, shift);
        b = _shift(b, shift);
      }
      alpha = _channelA(base);
    } else {
      // Single-colour mode: asymmetric shading. Above the midpoint, sheen
      // drives the highlight (dull/matte/gloss read very differently). Below
      // it, a sheen-independent shadow factor dominates so all sheens darken
      // similarly — sheen still nudges the shadow depth via shadowSheenWeight,
      // just much less than it does on the lit side.
      final delta = shadeI - 0.5;
      final highlightScale = sheenFactor[material.sheen] ?? 0.0;
      final shift = delta >= 0
          ? delta * highlightScale
          : delta * (shadowFactor + highlightScale * shadowSheenWeight);
      r = _shift(_channelR(base), shift);
      g = _shift(_channelG(base), shift);
      b = _shift(_channelB(base), shift);
      alpha = _channelA(base);
    }

    r = _tintChannel(r, avgR);
    g = _tintChannel(g, avgG);
    b = _tintChannel(b, avgB);
    return Color.fromARGB(alpha, r, g, b);
  }

  static int _channelA(Color c) => (c.toARGB32() >> 24) & 0xFF;
  static int _channelR(Color c) => (c.toARGB32() >> 16) & 0xFF;
  static int _channelG(Color c) => (c.toARGB32() >> 8) & 0xFF;
  static int _channelB(Color c) => c.toARGB32() & 0xFF;

  static int _lerpInt(int a, int b, double t) =>
      (a + (b - a) * t).round().clamp(0, 255);

  /// Shift a channel toward white (positive) or black (negative).
  static int _shift(int c, double shift) {
    if (shift >= 0) return (c + (255 - c) * shift).round().clamp(0, 255);
    return (c + c * shift).round().clamp(0, 255);
  }

  /// Pull channel `c` toward `c * avgLight` by [tintStrength]. White light
  /// (avgLight = 1) leaves the channel unchanged; coloured light biases the
  /// channel toward whatever colour is hitting the surface.
  static int _tintChannel(int c, double avgLight) {
    final target = c * avgLight;
    return (c + (target - c) * tintStrength).round().clamp(0, 255);
  }

  static int _clamp255(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);
}
