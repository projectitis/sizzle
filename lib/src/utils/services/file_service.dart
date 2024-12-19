import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:jx/jx.dart';

class FileProperties {
  final String path;
  late final String name;

  FileProperties(this.path, {String? name}) {
    this.name = name ?? path;
  }
}

class FileService {
  final List<FileProperties> _queued = [];
  final Map<String, ByteData> _cache = {};
  final String assetFolder;

  FileService(this.assetFolder);

  /// Add a file to the queue so that it is cached when [loadQueue] is called.
  /// Call [load] instead to load the file immediately, or [get] if it has
  /// been loaded previously. Only provide [properties] or [path], not both.
  void enqueue({FileProperties? properties, String? path}) {
    assert(
      !(properties != null && path != null),
      'Provide either properties or path, not both',
    );
    assert(
      !(properties == null && path == null),
      'Provide either properties or path',
    );
    FileProperties p = properties ?? FileProperties(path!);
    _queued.add(p);
  }

  /// Add multiple files to the queue
  void enqueueAll(List<FileProperties>? properties, List<String>? paths) {
    if (properties != null) {
      _queued.addAll(properties);
    }
    if (paths != null) {
      for (String path in paths) {
        enqueue(path: path);
      }
    }
  }

  /// Load all files that have been added to the queue with [enqueue]
  Future<void> loadQueue() async {
    for (FileProperties properties in _queued) {
      await load(properties: properties);
    }
    _queued.clear();
  }

  /// Load a file from a path and cache it. if [name] is not provided, the path
  /// will be used as the name.
  Future<ByteData> load({
    FileProperties? properties,
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
    final data = await rootBundle.load(assetFolder + assetPath);
    if (cache) {
      _cache[assetName] = data;
    }
    return data;
  }

  /// Load a file from a path, cache it and return it as a string. if [name] is
  /// not provided, the path will be used as the name.
  Future<String> loadString({
    FileProperties? properties,
    String? path,
    bool cache = true,
  }) async {
    final data = await load(properties: properties, path: path, cache: cache);
    final buffer = data.buffer;
    return utf8.decode(buffer.asUint8List(0, buffer.lengthInBytes));
  }

  /// Load a file from a path, cache it and return it as a json object. if
  /// [name] is not provided, the path will be used as the name.
  Future<dynamic> loadJson({
    FileProperties? properties,
    String? path,
    bool cache = true,
  }) async {
    return jsonDecode(
      await loadString(
        properties: properties,
        path: path,
        cache: cache,
      ),
    );
  }

  /// Load a file from a path, cache it and return it as a JX object. if
  /// [name] is not provided, the path will be used as the name.
  Future<dynamic> loadJX({
    FileProperties? properties,
    String? path,
    bool cache = true,
  }) async {
    JxParser jx = JxParser();
    return jx.parse(
      await loadString(
        properties: properties,
        path: path,
        cache: cache,
      ),
    );
  }

  /// Clear the entire cache
  void clear() {
    _cache.clear();
  }

  /// Remove a file from the cache by [name]
  void remove(String name) {
    _cache.remove(name);
  }

  /// Get a file from the cache by [name]
  ByteData? operator [](String name) => _cache[name];

  /// Get a file from the cache by [name]
  ByteData? get(String name) => _cache[name];

  /// Get a string from the cache by [name]
  String getString(String path) {
    final buffer = _cache[path]!.buffer;
    return utf8.decode(buffer.asUint8List(0, buffer.lengthInBytes));
  }

  /// Get a json object from the cache by [name]
  dynamic getJson(String path) {
    return jsonDecode(getString(path));
  }

  /// Get a JX object from the cache by [name]
  dynamic getJX(String path) {
    JxParser jx = JxParser();
    return jx.parse(getString(path));
  }

  /// Check if a file is in the cache by [name]
  bool contains(String name) => _cache.containsKey(name);
}
