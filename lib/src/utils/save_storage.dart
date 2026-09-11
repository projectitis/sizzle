import './platform/platform.dart' as platform;

/// Where `Services.save` and `Services.load` keep their data.
///
/// Sizzle ships [PlatformSaveStorage], which writes a file in the application
/// documents directory on native platforms and a `localStorage` entry on web.
/// Assign your own implementation to `Services.saveStorage` to put save data
/// somewhere else - a cloud backend, an encrypted container, or
/// [MemorySaveStorage] in tests.
///
/// Implementations signal failure by throwing. `Services.save` and
/// `Services.load` catch, log and report the failure as `false`, so a backend
/// does not need an error contract of its own.
abstract class SaveStorage {
  /// The contents stored under [name], or `null` if nothing is stored there.
  Future<String?> read(String name);

  /// Store [contents] under [name], replacing anything already there.
  ///
  /// Must be all-or-nothing: an interrupted or failed write has to leave the
  /// previous contents intact rather than a truncated document. A save file
  /// that was half written is exactly the corruption this API exists to avoid.
  Future<void> write(String name, String contents);

  /// Whether anything is stored under [name].
  ///
  /// This is separate from [read] so backends that can answer it cheaply (a
  /// `HEAD` rather than a `GET`) are able to.
  Future<bool> exists(String name);

  /// Remove whatever is stored under [name]. Succeeds if nothing was there.
  Future<void> delete(String name);

  /// Move the contents of [from] to [to], replacing anything at [to]. Does
  /// nothing if there is nothing stored at [from].
  Future<void> rename(String from, String to);
}

/// The default [SaveStorage]. Stores save data on the device: a file in the
/// application documents directory on native platforms, a `localStorage` entry
/// on web.
class PlatformSaveStorage implements SaveStorage {
  @override
  Future<String?> read(String name) => platform.readSaveData(name);

  @override
  Future<void> write(String name, String contents) =>
      platform.writeSaveData(name, contents);

  @override
  Future<bool> exists(String name) => platform.saveDataExists(name);

  @override
  Future<void> delete(String name) => platform.deleteSaveData(name);

  @override
  Future<void> rename(String from, String to) =>
      platform.renameSaveData(from, to);
}

/// A [SaveStorage] that keeps everything in memory. Nothing is persisted, so
/// the contents are gone when the process ends.
///
/// Intended for tests - assign it to `Services.saveStorage` to exercise save
/// and load without touching the file system or `localStorage`:
///
/// ```dart
/// final storage = MemorySaveStorage();
/// Services.saveStorage = storage;
/// await Services.save();
/// expect(storage.entries[Services.saveFile], contains('castle_key'));
/// ```
class MemorySaveStorage implements SaveStorage {
  /// The stored documents, keyed by name. Readable and writable directly so a
  /// test can seed a deliberately damaged document.
  final Map<String, String> entries = {};

  @override
  Future<String?> read(String name) async => entries[name];

  @override
  Future<void> write(String name, String contents) async =>
      entries[name] = contents;

  @override
  Future<bool> exists(String name) async => entries.containsKey(name);

  @override
  Future<void> delete(String name) async => entries.remove(name);

  @override
  Future<void> rename(String from, String to) async {
    final value = entries.remove(from);
    if (value != null) entries[to] = value;
  }
}
