/// Platform shims for the parts of Sizzle that cannot use `dart:io` directly.
///
/// `dart:io` does not exist on web, and importing it is a compile error there
/// rather than a runtime failure. Every `dart:io` and `path_provider` use in
/// Sizzle is therefore funnelled through this library, which resolves to
/// `platform_io.dart` when `dart:io` is available and `platform_web.dart`
/// otherwise. Both files declare the same top-level API.
library;

export 'platform_web.dart' if (dart.library.io) 'platform_io.dart';
