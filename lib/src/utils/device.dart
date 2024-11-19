import 'dart:io';

import 'package:flutter/foundation.dart';

class Device {
  static String get os => Platform.operatingSystemVersion.toLowerCase();

  static bool get isAndroid => Platform.isAndroid;
  static bool get isIOS => Platform.isIOS;
  static bool get isWindows => Platform.isWindows;
  static bool get isMacOS => Platform.isMacOS;
  static bool get isLinux => Platform.isLinux;
  static bool get isFuchsia => Platform.isFuchsia;

  static bool get isMobile => (isAndroid || isIOS) && !isWatch;
  static bool get isWeb => kIsWeb;
  static bool get isDesktop => isWindows || isLinux || isMacOS;
  static bool get isWatch =>
      (isAndroid && os.contains('wear')) || (isIOS && os.contains('watch'));
}
