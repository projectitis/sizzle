import 'dart:ui' hide decodeImageFromList;

import 'package:flame/extensions.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// A class to store properties of an image, including manipulating the image
/// prior to caching.
class ImageProperties {
  // The path
  late final String path;
  late final String name;
  late final double scale;
  late final Vector2 size;
  late final double angle;
  late final bool flipX;
  late final bool flipY;
  late final bool antiAlias;
  late final BlendMode blendMode;
  late final BoxFit fit;

  ImageProperties(this.path,
      {String? name,
      double? scale,
      Vector2? size,
      double? angle,
      bool? flipX,
      bool? flipY,
      bool? antiAlias,
      BlendMode? blendMode,
      BoxFit? fit}) {
    this.name = name ?? path;
    this.scale = scale ?? 1.0;
    this.size = size ?? Vector2.zero();
    this.angle = angle ?? 0.0;
    this.flipX = flipX ?? false;
    this.flipY = flipY ?? false;
    this.antiAlias = antiAlias ?? true;
    this.blendMode = blendMode ?? BlendMode.srcOver;
    this.fit = fit ?? BoxFit.fill;
  }
}

/// A service for loading and caching image assets
class ImageService {
  final List<ImageProperties> _queued = [];
  final Map<String, Image> _cache = {};
  final String assetFolder;

  /// Create a new image service with path to [assetFolder] for loading images.
  ImageService(this.assetFolder);

  /// Add an image to the queue so that it is cached when [loadQueue] is called.
  /// Call [load] instead to load the image immediately, or [get] if it has
  /// been loaded previously. Only provide [properties] or [path], not both.
  void enqueue({ImageProperties? properties, String? path}) {
    assert(
      !(properties == null && path == null),
      'Provide either properties or path, not both',
    );
    assert(
      properties != null && path != null,
      'Provide either properties or path',
    );
    ImageProperties p = properties ?? ImageProperties(path!);
    _queued.add(p);
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
      !(properties == null && path == null),
      'Provide either properties or path, not both',
    );
    assert(
      properties != null && path != null,
      'Provide either properties or path',
    );
    String assetName = path ?? properties!.name;
    if (_cache.containsKey(assetName)) {
      return _cache[assetName]!;
    }
    String assetPath = path ?? properties!.path;
    final data = await rootBundle.load(assetFolder + assetPath);
    final bytes = Uint8List.view(data.buffer);
    final image = await decodeImageFromList(bytes);
    if (properties == null) {
      if (cache) {
        _cache[assetName] = image;
      }
      return image;
    }
    final processedImage = await processImage(image, properties);
    image.dispose();
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

  /// Helper method to process an image
  static Future<Image> processImage(
    Image image,
    ImageProperties properties,
  ) async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    int width = image.width;
    int height = image.height;
    bool requiresProcessing = false;

    // Scale
    if (properties.scale != 1.0) {
      canvas.scale(properties.scale);
      width = (width / properties.scale).toInt();
      height = (height / properties.scale).toInt();
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
        ..blendMode = properties.blendMode,
    );

    // Return image
    return recorder.endRecording().toImageSafe(width, height);
  }
}
