import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'log_sink.dart';

// --- Platform identity ------------------------------------------------------

String get operatingSystem => Platform.operatingSystem;
String get operatingSystemVersion => Platform.operatingSystemVersion;

bool get isAndroid => Platform.isAndroid;
bool get isIOS => Platform.isIOS;
bool get isWindows => Platform.isWindows;
bool get isMacOS => Platform.isMacOS;
bool get isLinux => Platform.isLinux;
bool get isFuchsia => Platform.isFuchsia;

// --- Save data --------------------------------------------------------------

/// Cached documents directory. Resolving it goes through a platform channel,
/// so it is only looked up once.
Directory? _documents;

Future<Directory> _documentsDir() async =>
    _documents ??= await getApplicationDocumentsDirectory();

/// Read the save data stored under [name], or `null` if none exists.
///
/// On native platforms this is the file `name` in the application documents
/// directory.
Future<String?> readSaveData(String name) async {
  final file = File('${(await _documentsDir()).path}/$name');
  if (!await file.exists()) return null;
  return file.readAsString();
}

/// Write [contents] as the save data under [name], replacing anything already
/// stored there.
///
/// The write goes to `<name>.tmp` first and is then renamed over the target, so
/// a crash or kill part-way through leaves the previous save intact. Writing the
/// target directly would truncate it before writing, which is how a corrupt save
/// file gets created in the first place.
Future<void> writeSaveData(String name, String contents) async {
  final dir = (await _documentsDir()).path;
  final temp = File('$dir/$name.tmp');
  try {
    // `flush: true` matters here - without it the bytes may not have reached
    // the device when the rename commits the directory entry.
    await temp.writeAsString(contents, flush: true);
    await temp.rename('$dir/$name');
  } catch (_) {
    // Do not leave a partial temp file behind in the player's documents folder.
    try {
      await temp.delete();
    } catch (_) {}
    rethrow;
  }
}

/// Whether save data is stored under [name].
Future<bool> saveDataExists(String name) async =>
    File('${(await _documentsDir()).path}/$name').exists();

/// Remove the save data stored under [name]. Does nothing if there is none.
Future<void> deleteSaveData(String name) async {
  final file = File('${(await _documentsDir()).path}/$name');
  if (await file.exists()) await file.delete();
}

/// Move the save data stored under [from] to [to], replacing anything already
/// stored at [to]. Does nothing if there is nothing stored at [from].
Future<void> renameSaveData(String from, String to) async {
  final dir = (await _documentsDir()).path;
  final file = File('$dir/$from');
  if (!await file.exists()) return;
  await file.rename('$dir/$to');
}

// --- Log sink ---------------------------------------------------------------

/// Open a log sink at [path], relative to the application documents directory.
///
/// Returns `null` if the documents directory cannot be resolved, in which case
/// the caller is expected to fall back to console output.
Future<LogSink?> openLogSink(String path) async {
  final Directory dir;
  try {
    dir = await _documentsDir();
  } catch (_) {
    return null;
  }
  final file = File('${dir.path}/$path');
  return _FileLogSink(file.openWrite(mode: FileMode.writeOnly));
}

class _FileLogSink implements LogSink {
  _FileLogSink(this._sink);

  final IOSink _sink;

  @override
  void write(String data) => _sink.write(data);

  @override
  Future<void> close() => _sink.close();
}
