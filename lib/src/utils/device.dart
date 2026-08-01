import 'dart:io';
import 'dart:ui';

import 'package:flame/extensions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../game/frame_rate_mode.dart';

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

  /// The display's reported refresh rate in Hz, or `60.0` when the engine
  /// does not know (older engines report `0` for an unknown display).
  ///
  /// This is what the panel *can* do, not what the app is achieving - use
  /// `SizzleGame.measuredRenderFps` for the latter.
  static double get refreshRate {
    final rate = view.display.refreshRate;
    return rate > 0 ? rate : 60.0;
  }

  /// Platform hook for changing the display refresh rate, used by
  /// [FrameRateMode.hardwareHalfRate].
  ///
  /// Sizzle ships no native implementation; assign one from a companion
  /// plugin to light up hardware frame-rate limiting. Games never call this
  /// directly - `SizzleGame.setFrameRateMode` drives it.
  static HwFrameRateProvider? hwFrameRateProvider;

  /// Whether a [hwFrameRateProvider] is registered *and* reports that this
  /// platform can accept refresh-rate requests.
  ///
  /// Even when `true` a request may be silently ignored by the panel, so
  /// `SizzleGame` verifies the result by measurement rather than trusting
  /// this flag.
  static bool get isHWFrameRateSupported =>
      hwFrameRateProvider?.isSupported ?? false;

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
