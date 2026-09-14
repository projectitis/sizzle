import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'log_sink.dart';
import 'save_bytes_codec.dart';

// --- Platform identity ------------------------------------------------------

/// Always `'web'`. The browser does not expose the host operating system
/// reliably, so use `Device.isWeb` rather than trying to infer the host.
String get operatingSystem => 'web';

/// The browser user agent string, which is the closest web equivalent to an OS
/// version.
String get operatingSystemVersion => web.window.navigator.userAgent;

// A browser is never one of the native platforms, even when the browser itself
// is running on that platform. `Device.isWeb` is the check to use on web.
bool get isAndroid => false;
bool get isIOS => false;
bool get isWindows => false;
bool get isMacOS => false;
bool get isLinux => false;
bool get isFuchsia => false;

// --- Save data --------------------------------------------------------------

/// Read the save data stored under [name], or `null` if none exists.
///
/// On web this reads the `localStorage` entry keyed by [name]. Storage is
/// per-origin and is cleared when the user clears site data.
///
/// Throws a `FormatException` if the entry holds binary data, matching the
/// native side, where `File.readAsString` rejects bytes that are not valid
/// UTF-8. See [saveBytesMarker].
Future<String?> readSaveData(String name) async {
  final stored = web.window.localStorage.getItem(name);
  return stored == null ? null : decodeSaveText(stored);
}

/// Read the save data stored under [name] as bytes, or `null` if none exists.
///
/// Reading a text entry this way returns its UTF-8 bytes, matching what the
/// native side gets from reading a text file as bytes.
Future<Uint8List?> readSaveBytes(String name) async {
  final stored = web.window.localStorage.getItem(name);
  return stored == null ? null : decodeSaveBytes(stored);
}

/// Write [contents] as the save data under [name], replacing anything already
/// stored there.
///
/// `localStorage` writes are atomic - the entry is replaced whole or not at all
/// - so there is no web equivalent of the temp-file dance the native side needs.
///
/// Throws if the browser denies `localStorage` access (private browsing with
/// site data blocked) or the origin's storage quota is exhausted. In both cases
/// the previous value is left intact.
Future<void> writeSaveData(String name, String contents) async =>
    web.window.localStorage.setItem(name, contents);

/// Write [bytes] as the save data under [name], replacing anything already
/// stored there.
///
/// `localStorage` holds strings only, so the bytes are base64 encoded and
/// tagged with [saveBytesMarker]. Base64 costs about a third more space again
/// against a per-origin quota of only a few megabytes, so keep binary save data
/// small on web.
///
/// Throws under the same conditions as [writeSaveData].
Future<void> writeSaveBytes(String name, Uint8List bytes) async =>
    web.window.localStorage.setItem(name, encodeSaveBytes(bytes));

/// The names of everything stored alongside the save data, sorted, optionally
/// limited to those starting with [prefix].
///
/// This lists every `localStorage` key on the origin, not only Sizzle's own
/// saves - keys written by Flutter or by any other library on the page show up
/// too. Use [prefix] to narrow it.
Future<List<String>> listSaveData({String? prefix}) async {
  final storage = web.window.localStorage;
  final names = <String>[];
  for (var i = 0; i < storage.length; i++) {
    final key = storage.key(i);
    if (key == null) continue;
    if (prefix != null && !key.startsWith(prefix)) continue;
    names.add(key);
  }
  names.sort();
  return names;
}

/// Whether save data is stored under [name].
Future<bool> saveDataExists(String name) async =>
    web.window.localStorage.getItem(name) != null;

/// Remove the save data stored under [name]. Does nothing if there is none.
Future<void> deleteSaveData(String name) async =>
    web.window.localStorage.removeItem(name);

/// Move the save data stored under [from] to [to], replacing anything already
/// stored at [to]. Does nothing if there is nothing stored at [from].
///
/// `localStorage` has no rename, so this copies and then removes. The copy
/// briefly doubles the space this entry uses, and throws if that exceeds the
/// origin's quota - in which case [from] is left untouched.
Future<void> renameSaveData(String from, String to) async {
  final value = web.window.localStorage.getItem(from);
  if (value == null) return;
  web.window.localStorage.setItem(to, value);
  web.window.localStorage.removeItem(from);
}

// --- Log sink ---------------------------------------------------------------

/// Always `null` - web has no writable file system, so `FileLogger` falls back
/// to console output.
Future<LogSink?> openLogSink(String path) async => null;
