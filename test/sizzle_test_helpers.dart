import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';

/// The path to the goldens directory
String goldens =
    '${Directory.current.path.replaceAll(r'\', '/')}/test/_goldens';

/// A custom [AssetBundle] that reads files from a directory.
///
/// This is meant to be used in place of [rootBundle] for testing
class DiskAssetBundle extends CachingAssetBundle {
  static const _assetManifestDotJson = 'AssetManifest.json';

  /// Creates a [DiskAssetBundle] by loading files from [path].
  static Future<AssetBundle> loadFromPath(
    String path, {
    String? from,
  }) async {
    // Prepare the file search pattern
    path = _formatPath(path);
    String pattern = path;
    if (!pattern.endsWith('/')) {
      pattern += '/';
    }
    pattern += '**';

    // Load the assets
    final cache = <String, ByteData>{};
    await for (final entity in Glob(pattern).list(root: from)) {
      if (entity is File) {
        final bytes = await (entity as File).readAsBytes();

        // Keep only the asset name relative to the folder
        String name = _formatPath(entity.path);
        name = name.substring(name.indexOf(path) + path.length);
        cache[name] = ByteData.view(bytes.buffer);
      }
    }

    // Create the asset manifest
    final manifest = <String, List<String>>{};
    cache.forEach((key, _) {
      manifest[key] = [key];
    });
    cache[_assetManifestDotJson] = ByteData.view(
      Uint8List.fromList(jsonEncode(manifest).codeUnits).buffer,
    );

    return DiskAssetBundle._(cache);
  }

  /// Format a file path to only forward slashes
  static String _formatPath(String path) {
    return path.replaceAll(r'\', '/');
  }

  /// The cache of assets
  final Map<String, ByteData> _cache;

  /// Private constructor
  DiskAssetBundle._(this._cache);

  /// Load an asset from the cache
  @override
  Future<ByteData> load(String key) async {
    return _cache[key]!;
  }
}
