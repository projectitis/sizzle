import 'dart:io';
import 'dart:ui';

import 'package:flame/extensions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class Device {
  static String get os =>
      '${Platform.operatingSystem.toLowerCase()} ${Platform.operatingSystemVersion.toLowerCase()}';

  static bool get isAndroid => Platform.isAndroid;
  static bool get isIOS => Platform.isIOS;
  static bool get isWindows => Platform.isWindows;
  static bool get isMacOS => Platform.isMacOS;
  static bool get isLinux => Platform.isLinux;
  static bool get isFuchsia => Platform.isFuchsia;

  static bool get isMobile => (isAndroid || isIOS) && !isWatch;
  static bool get isWeb => kIsWeb;
  static bool get isDesktop => isWindows || isLinux || isMacOS;
  static bool get isWatch {
    if (isIOS && os.contains('watch')) return true;
    if (isAndroid) {
      if (os.contains('wear')) return true;
      // Wear OS 4+ no longer surfaces "wear" in operatingSystemVersion
      // (e.g. TicWatch Pro 5 reports "tmdb.240925.002"). Fall back to a
      // shape heuristic: small + nearly-square is unique to watches.
      final size = screenSize;
      final logicalShort = (size.x < size.y ? size.x : size.y) / pixelRatio;
      final aspect = size.x / size.y;
      final nearlySquare = (aspect - 1.0).abs() < 0.1;
      final smallScreen = logicalShort <= 320;
      return nearlySquare && smallScreen;
    }
    return false;
  }

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

  static String describe() {
    String s = '';
    s += isAndroid
        ? 'Android'
        : isIOS
            ? 'iOS'
            : isWindows
                ? 'Windows'
                : isMacOS
                    ? 'macOS'
                    : isLinux
                        ? 'Linux'
                        : isFuchsia
                            ? 'Fuchsia'
                            : 'Unknown OS';
    s += ' ($os), ';
    s += isWatch
        ? 'Watch'
        : isMobile
            ? 'Mobile'
            : isDesktop
                ? 'Desktop'
                : isWeb
                    ? 'Web'
                    : 'Unknown type';
    s += ', $screenSize, pr=$pixelRatio';
    return s;
  }
}
