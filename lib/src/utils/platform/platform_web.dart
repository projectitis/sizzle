import 'package:web/web.dart' as web;

import 'log_sink.dart';

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
Future<String?> readSaveData(String name) async =>
    web.window.localStorage.getItem(name);

/// Write [contents] as the save data under [name], replacing anything already
/// stored there.
///
/// Throws if the browser denies `localStorage` access (private browsing with
/// site data blocked) or the origin's storage quota is exhausted.
Future<void> writeSaveData(String name, String contents) async =>
    web.window.localStorage.setItem(name, contents);

// --- Log sink ---------------------------------------------------------------

/// Always `null` - web has no writable file system, so `FileLogger` falls back
/// to console output.
Future<LogSink?> openLogSink(String path) async => null;
