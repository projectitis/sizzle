import 'package:flame/components.dart';
import 'package:flame/extensions.dart';

import '../utils/services.dart';
import '../utils/services/file_service.dart';
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
///
/// ## Re-rendering
///
/// Pass an [onRender] callback to mutate the SVG source string before
/// rasterization (e.g. swap colors at runtime). Call [render] any number of
/// times after [load] to re-rasterize without re-reading the asset; the
/// callback always receives the **original** asset SVG (modifications are
/// not cumulative). The [Sprite] is mutated in place — consumers holding a
/// reference to [sprite] do not need to reassign it.
class SvgImage {
  SvgImage._(
    this.sprite,
    this.displaySize,
    this._svgString,
    this._properties,
    this._imageService,
    this.onRender,
  );

  final Sprite sprite;

  /// The intended on-screen size (in canvas / logical pixels): the size the
  /// consuming component should set as its [PositionComponent.size].
  final Vector2 displaySize;

  /// Optional callback invoked on every [load] and [render] with the original
  /// asset SVG string. Its return value is rasterized into the sprite. Set to
  /// `null` to render the original SVG unchanged.
  String Function(String svg)? onRender;

  final String _svgString;
  final ImageProperties _properties;
  final ImageService _imageService;

  /// Rasterises [assetPath] at
  /// `displayScale * contextScale * dpr * renderScale`. See class docs for
  /// what each knob does. If [onRender] is provided it is applied to the SVG
  /// source before the initial rasterization and stored on the instance for
  /// subsequent [render] calls.
  ///
  /// [fileService] and [imageService] default to [Services.files] and
  /// [Services.images]. Pass explicit instances to use custom services (e.g.
  /// in tests). The provided [imageService] is also used by subsequent
  /// [render] calls.
  static Future<SvgImage> load(
    String assetPath, {
    required double contextScale,
    required double dpr,
    double displayScale = 1.0,
    double renderScale = 1.0,
    String Function(String svg)? onRender,
    FileService? fileService,
    ImageService? imageService,
  }) async {
    final files = fileService ?? Services.files;
    final images = imageService ?? Services.images;
    final pixelScale = displayScale * contextScale * dpr * renderScale;
    final cacheName = '$assetPath@${pixelScale.toStringAsFixed(4)}';
    final svgString = await files.loadString(path: assetPath);
    final properties = ImageProperties(
      assetPath,
      name: cacheName,
      scale: Vector2.all(pixelScale),
    );
    final initialSvg = onRender != null ? onRender(svgString) : svgString;
    final image = await images.rasterizeSvgString(initialSvg, properties);
    // Texture sits in physical pixels; sprite is sized in logical pixels so
    // Flutter's DPR scale lands it 1:1 on the display surface. renderScale
    // is divided out so the on-screen size doesn't change when callers ask
    // for a denser texture.
    final displaySize = Vector2(
      image.width / (dpr * renderScale),
      image.height / (dpr * renderScale),
    );
    return SvgImage._(
      Sprite(image),
      displaySize,
      svgString,
      properties,
      images,
      onRender,
    );
  }

  /// Re-rasterise the SVG. Invokes [onRender] (the argument here if given,
  /// otherwise the instance field) with the original asset SVG string; the
  /// result is rasterized at the same pixel scale used at [load]. The sprite's
  /// image is swapped in place and the previous image is disposed.
  ///
  /// Concurrency: not protected. Overlapping [render] calls have undefined
  /// ordering — the caller is responsible for serializing if needed.
  ///
  /// If another [SvgImage] shares the same asset path and scale, both
  /// instances point at the same cached image; calling [render] here will
  /// replace the cache entry and dispose the image the other instance's
  /// sprite still references.
  Future<void> render({String Function(String svg)? onRender}) async {
    final callback = onRender ?? this.onRender;
    final svg = callback != null ? callback(_svgString) : _svgString;
    final oldImage = sprite.image;
    final newImage = await _imageService.rasterizeSvgString(
      svg,
      _properties,
    );
    sprite.image = newImage;
    sprite.srcSize = newImage.size;
    oldImage.dispose();
  }
}
