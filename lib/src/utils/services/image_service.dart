import 'dart:math';
import 'dart:ui' hide decodeImageFromList;

import 'package:flame/extensions.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import '../../math/math.dart';

/// A class to store properties of an image, including manipulating the image
/// prior to caching.
class ImageProperties {
  /// The path to the image asset.
  late final String path;

  /// A friendly name. Use [path] if not provided.
  late final String name;

  /// Scale of the image along each axis.
  late final Vector2 scale;

  /// The area of the image to crop. Default is the entire image.
  late final Rect crop;

  /// The angle to rotate the image in radians. Also see [fitCrop].
  late final double angle;

  /// Used if rotating. If set to true, the image will be scaled to fit the
  /// crop rectangle. Only the crop width and height will be used (position is
  /// ignored).
  late final bool fitCrop;

  /// Flip the image horizontally.
  late final bool flipX;

  /// Flip the image vertically.
  late final bool flipY;

  /// Use antialias when transforming the image.
  late final bool antiAlias;

  /// The blend mode to use when transforming the image.
  late final BlendMode blendMode;

  /// The quality used when transforming the image.
  late final FilterQuality filterQuality;

  ImageProperties(
    this.path, {
    String? name,
    Vector2? scale,
    Rect? crop,
    double? angle,
    bool? fitCrop,
    bool? flipX,
    bool? flipY,
    bool? antiAlias,
    BlendMode? blendMode,
    FilterQuality? filterQuality,
  }) {
    this.name = name ?? path;
    this.scale = scale ?? Vector2.all(1.0);
    this.crop = crop ?? Rect.zero;
    this.angle = angle ?? 0.0;
    this.flipX = flipX ?? false;
    this.flipY = flipY ?? false;
    this.antiAlias = antiAlias ?? true;
    this.blendMode = blendMode ?? BlendMode.srcOver;
    this.fitCrop = fitCrop ?? false;
    this.filterQuality = filterQuality ?? FilterQuality.low;
  }
}

/// A service for loading and caching image assets
class ImageService {
  final List<ImageProperties> _queued = [];
  final Map<String, Image> _cache = {};
  final String assetFolder;
  final AssetBundle assetBundle;

  /// Create a new image service with path to [assetFolder] for loading images.
  ImageService(this.assetFolder, {AssetBundle? assetBundle})
      : assetBundle = assetBundle ?? rootBundle;

  /// Add an image to the queue so that it is cached when [loadQueue] is called.
  /// Call [load] instead to load the image immediately, or [get] if it has
  /// been loaded previously. Only provide [properties] or [path], not both.
  void enqueue({ImageProperties? properties, String? path}) {
    assert(
      !(properties != null && path != null),
      'Provide either properties or path, not both',
    );
    assert(
      !(properties == null && path == null),
      'Provide either properties or path',
    );
    ImageProperties p = properties ?? ImageProperties(path!);
    _queued.add(p);
  }

  /// Add multiple images to the queue
  void enqueueAll({List<ImageProperties>? properties, List<String>? paths}) {
    if (properties != null) {
      _queued.addAll(properties);
    }
    if (paths != null) {
      for (String path in paths) {
        enqueue(path: path);
      }
    }
  }

  /// Load all images that have been added to the queue with [enqueue]
  Future<void> loadQueue() async {
    for (ImageProperties properties in _queued) {
      await load(properties: properties);
    }
    _queued.clear();
  }

  /// Load an image from a path and cache it. if [properties.name] is not
  /// provided, the path will be used as the name. Additional parameters can be
  /// provided to scale and resize the image. Only provide [properties] or
  /// [path], not both.
  Future<Image> load({
    ImageProperties? properties,
    String? path,
    bool cache = true,
  }) async {
    assert(
      !(properties != null && path != null),
      'Provide either properties or path, not both',
    );
    assert(
      !(properties == null && path == null),
      'Provide either properties or path',
    );
    String assetName = path ?? properties!.name;
    if (_cache.containsKey(assetName)) {
      return _cache[assetName]!;
    }
    String assetPath = path ?? properties!.path;
    final data = await assetBundle.load(assetFolder + assetPath);
    final bytes = Uint8List.view(data.buffer);
    final image = await decodeImageFromList(bytes);
    if (properties == null) {
      if (cache) {
        _cache[assetName] = image;
      }
      return image;
    }
    final processedImage = await processImage(image, properties);
    if (cache) {
      _cache[properties.name] = processedImage;
    }
    return processedImage;
  }

  /// Clear the entire cache and dispose of the images
  void clear() {
    for (Image image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
  }

  /// Remove and dispose an image from the cache by [name]
  void remove(String name) {
    if (_cache.containsKey(name)) {
      _cache[name]!.dispose();
      _cache.remove(name);
    }
  }

  /// Get an image from the cache by [name]
  Image? operator [](String name) => _cache[name];

  /// Get an image from the cache by [name]
  Image? get(String name) => _cache[name];

  /// Check if an image is in the cache by [name]
  bool contains(String name) => _cache.containsKey(name);

  /// The number of images in the cache
  int get length => _cache.length;

  /// Check if the cache is empty
  bool get isEmpty => _cache.isEmpty;

  /// Check if the cache is not empty
  bool get isNotEmpty => _cache.isNotEmpty;

  /// Helper method to process an image
  static Future<Image> processImage(
    Image image,
    ImageProperties properties,
  ) async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    double width = image.width.toDouble();
    double height = image.height.toDouble();
    bool requiresProcessing = false;

    // Prepare crop
    Rect c = properties.crop;

    // Prepare scale
    if (properties.scale.x != 1.0 || properties.scale.y != 1.0) {
      width *= properties.scale.x;
      height *= properties.scale.y;
    }

    // Prepare rotation
    if (properties.angle != 0.0) {
      if (properties.fitCrop && !properties.crop.isEmpty) {
        Rect b = properties.crop.bounds(-properties.angle);
        double scale = max(b.width / width, b.height / height);
        width *= scale;
        height *= scale;
        properties.scale.multiply(Vector2.all(scale));
        b = boundingBox(Size(width, height), properties.angle);
        c = Rect.fromLTWH(
          (width - properties.crop.width) / 2,
          (height - properties.crop.height) / 2,
          properties.crop.width,
          properties.crop.height,
        );
      } else {
        c = boundingBox(Size(width, height), properties.angle);
        if (!properties.crop.isEmpty) {
          c = properties.crop.translate(c.left, c.top);
        }
      }
      if (properties.flipX) {
        c = Rect.fromLTWH(-c.left, c.top, c.width, c.height);
      }
      if (properties.flipY) {
        c = Rect.fromLTWH(c.left, -c.top, c.width, c.height);
      }
    }

    // Flip X
    if (properties.flipX) {
      canvas.scale(-1.0, 1.0);
      canvas.translate(-width, 0.0);
      requiresProcessing = true;
    }

    // Flip Y
    if (properties.flipY) {
      canvas.scale(1.0, -1.0);
      canvas.translate(0.0, -height);
      requiresProcessing = true;
    }

    // Crop
    if (!c.isEmpty) {
      canvas.translate(-c.left, -c.top);
      requiresProcessing = true;
    }

    // Finish rotation
    if (properties.angle != 0.0) {
      canvas.translate(width / 2, height / 2);
      canvas.rotate(-properties.angle);
      canvas.translate(-width / 2, -height / 2);
      requiresProcessing = true;
    }

    // Scale
    if (properties.scale.x != 1.0 || properties.scale.y != 1.0) {
      canvas.scale(properties.scale.x, properties.scale.y);
      requiresProcessing = true;
    }

    // Quit early if no processing is required
    if (!requiresProcessing) {
      recorder.endRecording().dispose();
      return image;
    }

    // Draw the image
    canvas.drawImage(
      image,
      Offset.zero,
      Paint()
        ..isAntiAlias = properties.antiAlias
        ..blendMode = properties.blendMode
        ..filterQuality = properties.filterQuality,
    );

    // Crop?
    double cropWidth = c.width == 0.0 ? width : c.width;
    double cropHeight = c.height == 0.0 ? height : c.height;

    // Return image
    image.dispose();
    return await recorder.endRecording().toImageSafe(
          cropWidth.toInt(),
          cropHeight.toInt(),
        );
  }
}
