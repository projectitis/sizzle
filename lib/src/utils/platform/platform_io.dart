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
Future<void> writeSaveData(String name, String contents) async {
  final file = File('${(await _documentsDir()).path}/$name');
  await file.writeAsString(contents);
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
