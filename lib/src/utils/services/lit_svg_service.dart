import 'dart:convert';

import 'package:flutter/services.dart';

import '../../display/lit_svg_data.dart';

/// A service for loading and caching parsed [LitSvgData] assets.
///
/// Mirrors the queue/load/cache shape of [ImageService] and [FileService].
/// Each parsed [LitSvgData] is keyed in the cache by its asset path.
class LitSvgService {
  final List<String> _queued = <String>[];
  final Map<String, LitSvgData> _cache = <String, LitSvgData>{};
  final String assetFolder;
  final AssetBundle assetBundle;

  /// Create a new lit-SVG service with path to [assetFolder] for loading SVGs.
  LitSvgService(this.assetFolder, {AssetBundle? assetBundle})
      : assetBundle = assetBundle ?? rootBundle;

  /// Add an SVG to the queue so that it is parsed and cached when [loadQueue]
  /// is called. Call [load] instead to load immediately, or [get]/[] if it has
  /// been loaded previously.
  void enqueue({required String path}) {
    _queued.add(path);
  }

  /// Add multiple SVGs to the queue.
  void enqueueAll({required List<String> paths}) {
    _queued.addAll(paths);
  }

  /// Load every queued SVG and clear the queue.
  Future<void> loadQueue() async {
    for (final path in _queued) {
      await load(path: path);
    }
    _queued.clear();
  }

  /// Load and parse an SVG from [path], caching the result by [path]. If the
  /// SVG is already cached the cached instance is returned.
  Future<LitSvgData> load({required String path, bool cache = true}) async {
    if (_cache.containsKey(path)) {
      return _cache[path]!;
    }
    final data = await assetBundle.load(assetFolder + path);
    final source = utf8.decode(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    final svg = LitSvgData(source);
    if (cache) {
      _cache[path] = svg;
    }
    return svg;
  }

  /// Clear the entire cache.
  void clear() => _cache.clear();

  /// Remove a parsed SVG from the cache by [path].
  void remove(String path) => _cache.remove(path);

  /// Get a parsed SVG from the cache by [path].
  LitSvgData? operator [](String path) => _cache[path];

  /// Get a parsed SVG from the cache by [path].
  LitSvgData? get(String path) => _cache[path];

  /// Check if a parsed SVG is cached under [path].
  bool contains(String path) => _cache.containsKey(path);

  /// The number of cached SVGs.
  int get length => _cache.length;

  /// Whether the cache is empty.
  bool get isEmpty => _cache.isEmpty;

  /// Whether the cache is non-empty.
  bool get isNotEmpty => _cache.isNotEmpty;
}
