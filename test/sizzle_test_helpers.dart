import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';

/// The path to the goldens directory
String goldens =
    '${Directory.current.path.replaceAll(r'\', '/')}/test/_goldens';

/// A simple implementation of [AssetBundle] that reads files from an asset dir.
///
/// This is meant to be similar to the default [rootBundle] for testing.
class DiskAssetBundle extends CachingAssetBundle {
  static const _assetManifestDotJson = 'AssetManifest.json';

  /// Creates a [DiskAssetBundle] by loading files from [path].
  static Future<AssetBundle> loadFromPath(
    String path, {
    String? from,
  }) async {
    path = path.replaceAll(r'\', '/');
    String pattern = path;
    if (!pattern.endsWith('/')) {
      pattern += '/';
    }
    pattern += '**';
    final cache = <String, ByteData>{};
    await for (final entity in Glob(pattern).list(root: from)) {
      print('  Found asset: ${entity.path}');
      if (entity is File) {
        final bytes = await (entity as File).readAsBytes();

        // Keep the path relative to the asset folder
        String filePath = entity.path.replaceAll(r'\', '/');
        filePath = filePath.substring(filePath.indexOf(path) + path.length);
        print('    Saving asset: $filePath');
        cache[filePath] = ByteData.view(bytes.buffer);
      }
    }
    final manifest = <String, List<String>>{};
    cache.forEach((key, _) {
      manifest[key] = [key];
    });

    cache[_assetManifestDotJson] = ByteData.view(
      Uint8List.fromList(jsonEncode(manifest).codeUnits).buffer,
    );

    return DiskAssetBundle._(cache);
  }

  final Map<String, ByteData> _cache;

  DiskAssetBundle._(this._cache);

  @override
  Future<ByteData> load(String key) async {
    return _cache[key]!;
  }
}
