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
  final String path;

  /// A friendly name. Use [path] if not provided.
  late final String name;

  /// Scale of the image along each axis.
  final Vector2? scale;

  /// The area of the image to crop. Default is the entire image.
  final Rect? crop;

  /// The angle to rotate the image in radians. Also see [fitCrop].
  final double? angle;

  /// Used if rotating. If set to true, the image will be scaled to fit the
  /// crop rectangle. Only the crop width and height will be used (position is
  /// ignored).
  final bool? fitCrop;

  /// Flip the image horizontally.
  final bool? flipX;

  /// Flip the image vertically.
  final bool? flipY;

  /// Use antialias when transforming the image.
  final bool? antiAlias;

  /// The blend mode to use when transforming the image.
  final BlendMode? blendMode;

  /// The quality used when transforming the image.
  final FilterQuality? filterQuality;

  /// If true, the default properties will be replaced by the provided. If false
  /// the provided properties will be merged with the default properties.
  late final bool ignoreDefaultProperties;

  ImageProperties(
    this.path, {
    String? name,
    this.scale,
    this.crop,
    this.angle,
    this.fitCrop,
    this.flipX,
    this.flipY,
    this.antiAlias,
    this.blendMode,
    this.filterQuality,
    bool? ignoreDefaultProperties,
  }) {
    this.name = name ?? path;
    this.ignoreDefaultProperties = ignoreDefaultProperties ?? false;
  }

  /// Create a copy of this object with the properties of another
  /// [ImageProperties] merged into it.
  ///
  /// [name], [path] and [ignoreDefaultProperties] aren't merged.
  ImageProperties copyMerged(ImageProperties other) {
    ImageProperties copy = ImageProperties(
      path,
      name: name,
      scale: other.scale ?? scale,
      crop: other.crop ?? crop,
      angle: other.angle ?? angle,
      fitCrop: other.fitCrop ?? fitCrop,
      flipX: other.flipX ?? flipX,
      flipY: other.flipY ?? flipY,
      antiAlias: other.antiAlias ?? antiAlias,
      blendMode: other.blendMode ?? blendMode,
      filterQuality: other.filterQuality ?? filterQuality,
      ignoreDefaultProperties: ignoreDefaultProperties,
    );
    return copy;
  }
}

/// A service for loading and caching image assets
class ImageService {
  final List<ImageProperties> _queued = [];
  final Map<String, Image> _cache = {};
  final String assetFolder;
  final AssetBundle assetBundle;
  ImageProperties? defaultProperties;

  /// Create a new image service with path to [assetFolder] for loading images.
  ImageService(this.assetFolder,
      {AssetBundle? assetBundle, this.defaultProperties})
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

  /// Process an image
  Future<Image> processImage(
    Image image,
    ImageProperties imageProperties,
  ) async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    double width = image.width.toDouble();
    double height = image.height.toDouble();
    bool requiresProcessing = false;

    // Prepare properties
    ImageProperties properties = imageProperties;
    if (defaultProperties != null && !imageProperties.ignoreDefaultProperties) {
      properties = defaultProperties!.copyMerged(imageProperties);
    }

    // Prepare crop
    Rect propertyCrop = properties.crop ?? Rect.zero;
    Rect c = propertyCrop;

    // Prepare scale
    Vector2 propertyScale = properties.scale ?? Vector2.all(1.0);
    if (propertyScale.x != 1.0 || propertyScale.y != 1.0) {
      width *= propertyScale.x;
      height *= propertyScale.y;
    }

    // Prepare rotation
    double propertyAngle = properties.angle ?? 0.0;
    if (propertyAngle != 0.0) {
      if ((properties.fitCrop ?? false) && !propertyCrop.isEmpty) {
        Rect b = propertyCrop.bounds(-propertyAngle);
        double scale = max(b.width / width, b.height / height);
        width *= scale;
        height *= scale;
        propertyScale.multiply(Vector2.all(scale));
        b = boundingBox(Size(width, height), propertyAngle);
        c = Rect.fromLTWH(
          (width - propertyCrop.width) / 2,
          (height - propertyCrop.height) / 2,
          propertyCrop.width,
          propertyCrop.height,
        );
      } else {
        c = boundingBox(Size(width, height), propertyAngle);
        if (!propertyCrop.isEmpty) {
          c = propertyCrop.translate(c.left, c.top);
        }
      }
      if (properties.flipX ?? false) {
        c = Rect.fromLTWH(-c.left, c.top, c.width, c.height);
      }
      if (properties.flipY ?? false) {
        c = Rect.fromLTWH(c.left, -c.top, c.width, c.height);
      }
    }

    // Flip X
    if (properties.flipX ?? false) {
      canvas.scale(-1.0, 1.0);
      canvas.translate(-width, 0.0);
      requiresProcessing = true;
    }

    // Flip Y
    if (properties.flipY ?? false) {
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
    if (propertyAngle != 0.0) {
      canvas.translate(width / 2, height / 2);
      canvas.rotate(-propertyAngle);
      canvas.translate(-width / 2, -height / 2);
      requiresProcessing = true;
    }

    // Scale
    if (propertyScale.x != 1.0 || propertyScale.y != 1.0) {
      canvas.scale(propertyScale.x, propertyScale.y);
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
        ..isAntiAlias = properties.antiAlias ?? true
        ..blendMode = properties.blendMode ?? BlendMode.srcOver
        ..filterQuality = properties.filterQuality ?? FilterQuality.low,
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
