import 'dart:io';
import 'dart:ui';

import 'package:flame/extensions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

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

  static FlutterView? _view;
  static FlutterView get view {
    if (_view == null) {
      WidgetsFlutterBinding.ensureInitialized();
      _view = WidgetsBinding.instance.platformDispatcher.views.first;
    }
    return _view!;
  }

  static Vector2 get screenSize => view.physicalSize.toVector2();

  static double get pixelRatio => view.devicePixelRatio;
}
