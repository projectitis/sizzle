import 'package:flame/components.dart';

import '../utils/services.dart';
import '../utils/services/image_service.dart';

/// Loads an SVG once and rasterizes it into a [Sprite] sized at the display
/// surface's physical-pixel resolution, then sizes the sprite in logical
/// pixels so it lands at the intended on-screen size. The DPR multiply keeps
/// icons crisp on high-DPI surfaces (e.g. Wear OS at DPR 2) without
/// over-rendering on DPR 1.
///
/// Two knobs:
///
/// - [displayScale] — the asset's intended on-screen scale at 100% camera
///   zoom. Default `1.0` for assets authored at their intended display size
///   (the convention used by hamster). Pass a smaller value to shrink or a
///   larger value to grow the asset on screen.
/// - [renderScale] — texture-density multiplier. `1.0` (default) gives 1:1
///   sampling at [displaySize]; `2.0` rasterises at twice the density so the
///   sprite can be scaled up to 2× without softening (useful for assets
///   inside a camera-zoom transform, or for sprites whose per-instance
///   render size exceeds [displaySize]). The returned [displaySize] is
///   unaffected by [renderScale] — only the texture density changes.
///
/// [contextScale] is the game's design→screen multiplier (e.g.
/// `screenSize / designSize`); [dpr] is the device pixel ratio. Both are
/// game-specific and supplied by the caller.
///
/// Rasterisation and caching are delegated to [Services.images], which
/// detects the `.svg` extension and bakes the supplied scale into the
/// output. The cache name is keyed by `path@pixelScale` so the same SVG
/// loaded at different scales gets distinct cached images.
class SvgImage {
  SvgImage._(this.sprite, this.displaySize);

  final Sprite sprite;

  /// The intended on-screen size (in canvas / logical pixels): the size the
  /// consuming component should set as its [PositionComponent.size].
  final Vector2 displaySize;

  /// Rasterises [assetPath] at
  /// `displayScale * contextScale * dpr * renderScale`. See class docs for
  /// what each knob does.
  static Future<SvgImage> load(
    String assetPath, {
    required double contextScale,
    required double dpr,
    double displayScale = 1.0,
    double renderScale = 1.0,
  }) async {
    final pixelScale = displayScale * contextScale * dpr * renderScale;
    final cacheName = '$assetPath@${pixelScale.toStringAsFixed(4)}';
    final image = await Services.images.load(
      properties: ImageProperties(
        assetPath,
        name: cacheName,
        scale: Vector2.all(pixelScale),
      ),
    );
    // Texture sits in physical pixels; sprite is sized in logical pixels so
    // Flutter's DPR scale lands it 1:1 on the display surface. renderScale
    // is divided out so the on-screen size doesn't change when callers ask
    // for a denser texture.
    final displaySize = Vector2(
      image.width / (dpr * renderScale),
      image.height / (dpr * renderScale),
    );
    return SvgImage._(Sprite(image), displaySize);
  }
}
