import 'dart:typed_data';

import '../platform/platform.dart' as platform;
import '../platform/save_bytes_codec.dart';

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
  ///
  /// Throws a `FormatException` if what is stored there is binary rather than
  /// text. Reading binary data as text is a mistake worth reporting, not one to
  /// paper over with replacement characters.
  Future<String?> read(String name);

  /// The bytes stored under [name], or `null` if nothing is stored there.
  ///
  /// Reading something written by [write] returns its UTF-8 bytes, because that
  /// is what a text document is once it has been stored.
  Future<Uint8List?> readBytes(String name);

  /// Store [contents] under [name], replacing anything already there.
  ///
  /// Must be all-or-nothing: an interrupted or failed write has to leave the
  /// previous contents intact rather than a truncated document. A save file
  /// that was half written is exactly the corruption this API exists to avoid.
  Future<void> write(String name, String contents);

  /// Store [bytes] under [name], replacing anything already there.
  ///
  /// Carries the same all-or-nothing requirement as [write] - a half-written
  /// document is the corruption this API exists to avoid, and binary data is no
  /// more recoverable from a truncated write than text is.
  ///
  /// Backends that can only hold strings have to encode the bytes, which costs
  /// space. `PlatformSaveStorage` base64 encodes on web, where the per-origin
  /// quota is only a few megabytes, so keep binary save data small there.
  Future<void> writeBytes(String name, Uint8List bytes);

  /// The names currently stored, sorted, optionally limited to those starting
  /// with [prefix].
  ///
  /// This covers the whole storage space rather than only the documents Sizzle
  /// wrote - on native that is every file in the application documents
  /// directory, including a `FileLogger` log and any `<name>.corrupt` left by a
  /// rejected load, and on web it is every `localStorage` key on the origin.
  /// [prefix] is how a game narrows that to its own save slots.
  ///
  /// A backend that cannot enumerate its contents should throw.
  Future<List<String>> list({String? prefix});

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
  Future<Uint8List?> readBytes(String name) => platform.readSaveBytes(name);

  @override
  Future<void> write(String name, String contents) =>
      platform.writeSaveData(name, contents);

  @override
  Future<void> writeBytes(String name, Uint8List bytes) =>
      platform.writeSaveBytes(name, bytes);

  @override
  Future<List<String>> list({String? prefix}) =>
      platform.listSaveData(prefix: prefix);

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
  ///
  /// Binary entries are held in the same map, encoded the way a string-only
  /// backend has to encode them - see [saveBytesMarker]. That keeps a single
  /// namespace, so [list], [exists], [delete] and [rename] treat text and
  /// binary alike, and makes this class behave identically to the web side of
  /// `PlatformSaveStorage`.
  final Map<String, String> entries = {};

  @override
  Future<String?> read(String name) async {
    final stored = entries[name];
    return stored == null ? null : decodeSaveText(stored);
  }

  @override
  Future<Uint8List?> readBytes(String name) async {
    final stored = entries[name];
    return stored == null ? null : decodeSaveBytes(stored);
  }

  @override
  Future<void> write(String name, String contents) async =>
      entries[name] = contents;

  @override
  Future<void> writeBytes(String name, Uint8List bytes) async =>
      entries[name] = encodeSaveBytes(bytes);

  @override
  Future<List<String>> list({String? prefix}) async {
    final names = prefix == null
        ? entries.keys.toList()
        : entries.keys.where((name) => name.startsWith(prefix)).toList();
    names.sort();
    return names;
  }

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
