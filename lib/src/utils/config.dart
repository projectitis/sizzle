import 'dart:math';

import 'package:flame/extensions.dart';
import 'package:jx/jx.dart';

import '../game/game.dart';
import '../utils/services.dart';

/// Runtime configuration loaded from a `.jx` file.
///
/// A `.jx` config file is structured as top-level sections each containing
/// properties and optional `#`-prefixed modifier blocks. Modifier blocks may
/// be nested (meaning logical AND). At load time the tree is flattened to a
/// single `section → property → value` snapshot using the supplied
/// capabilities map to decide which modifier blocks apply.
///
/// Capabilities are an arbitrary `Map<String, bool>` keyed by modifier name
/// (without the `#` prefix). A modifier block applies when its name is mapped
/// to `true`; a missing key or a key mapped to `false` skips the block.
///
/// Walk order is document order: every matching write overwrites the previous
/// value. Property values are taken literally (a value that is itself an
/// object or array is not entered when resolving modifiers).
///
/// Example:
/// ```dart
/// final config = await Config.load('game.config.jx', {
///   'mobile': true,
///   'landscape': true,
///   'touch': true,
/// });
/// final title = config.asStr('ui.title');
/// final scale = config.asDouble('view.scale', defaultValue: 1.0);
/// ```
///
/// To re-flatten after e.g. an orientation change, assign new capabilities:
/// ```dart
/// config.onChange = () => refreshDerivedValues();
/// config.capabilities = {'mobile': true, 'portrait': true};
/// ```
class Config {
  final Map<String, dynamic> _tree;
  Map<String, bool> _capabilities;
  final Map<String, Map<String, dynamic>> _flat = {};

  /// Called after the [capabilities] setter rebuilds the snapshot. Not called
  /// when the new capabilities are equivalent to the old ones (treating any
  /// missing key as `false`). Assign directly:
  /// `config.onChange = () => ...;`
  void Function()? onChange;

  Config._(this._tree, this._capabilities) {
    _flatten();
  }

  /// Load and parse a JX config file from the asset bundle via
  /// [Services.files]. The file is not added to the file cache.
  ///
  /// [capabilities] is a map keyed by modifier name (no `#` prefix). Any
  /// modifier whose name is not present, or whose value is `false`, is
  /// treated as inactive.
  static Future<Config> load(
    String path, [
    Map<String, bool> capabilities = const {},
  ]) async {
    final src = await Services.files.loadString(path: path, cache: false);
    return Config.parse(src, capabilities);
  }

  /// Parse a JX config from a string. Useful for tests and inline configs.
  ///
  /// [capabilities] is a map keyed by modifier name (no `#` prefix).
  static Config parse(
    String jxSource, [
    Map<String, bool> capabilities = const {},
  ]) {
    final tree = _asMap(JxParser().parse(jxSource));
    if (tree == null) {
      throw const FormatException('Config root must be a JX object');
    }
    return Config._(tree, capabilities);
  }

  /// The capabilities used to flatten the current snapshot. Assigning a new
  /// value re-flattens in place and fires [onChange]. Assigning a value that
  /// is equivalent to the current one (treating missing keys as `false`) is a
  /// no-op.
  Map<String, bool> get capabilities => _capabilities;
  set capabilities(Map<String, bool> value) {
    if (_capsEqual(_capabilities, value)) return;
    _capabilities = value;
    _flatten();
    onChange?.call();
  }

  void _flatten() {
    _flat.clear();
    _tree.forEach((key, value) {
      if (key.startsWith('#')) {
        throw FormatException(
          'Modifier "$key" is not allowed at the root of a config file',
        );
      }
      final section = _asMap(value);
      if (section == null) {
        throw FormatException(
          'Property "$key" is not allowed at the root of a config file '
          '(only sections are allowed)',
        );
      }
      final target = <String, dynamic>{};
      _walk(section, target);
      _flat[key] = target;
    });
  }

  void _walk(Map<String, dynamic> source, Map<String, dynamic> target) {
    source.forEach((key, value) {
      if (key.startsWith('#')) {
        final modifierName = key.substring(1);
        if (!(_capabilities[modifierName] ?? false)) return;
        final nested = _asMap(value);
        if (nested != null) _walk(nested, target);
      } else {
        target[key] = value;
      }
    });
  }

  /// Unwrap a JxParser `ObjectType` or a plain Map into `Map<String, dynamic>`.
  /// Returns `null` for any other value (including arrays and primitives).
  static Map<String, dynamic>? _asMap(dynamic v) {
    if (v is ObjectType) return v.items;
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.cast<String, dynamic>();
    return null;
  }

  /// Two capability maps are equal when, for every key in either map, the
  /// effective value matches (a missing key counts as `false`).
  static bool _capsEqual(Map<String, bool> a, Map<String, bool> b) {
    if (identical(a, b)) return true;
    for (final k in {...a.keys, ...b.keys}) {
      if ((a[k] ?? false) != (b[k] ?? false)) return false;
    }
    return true;
  }

  /// Raw indexed access. Path must be exactly `"section.property"` — a single
  /// dot separating two non-empty parts. Returns `null` if the key is missing.
  /// Throws [ArgumentError] for any other path shape.
  dynamic operator [](String path) {
    final dot = path.indexOf('.');
    if (dot <= 0 || dot != path.lastIndexOf('.') || dot == path.length - 1) {
      throw ArgumentError.value(
        path,
        'path',
        'Config path must be "section.property"',
      );
    }
    return _flat[path.substring(0, dot)]?[path.substring(dot + 1)];
  }

  /// Read a string value at `"section.property"`. Returns [defaultValue] (or
  /// `null`) if the key is missing. Throws [ArgumentError] if the value is
  /// present but not a string.
  String? asStr(String path, {String? defaultValue}) {
    final v = this[path];
    if (v == null) return defaultValue;
    if (v is String) return v;
    throw ArgumentError(
      'Expected String at "$path" but got ${v.runtimeType}',
    );
  }

  /// Read an int value at `"section.property"`. Accepts `int` as-is and
  /// truncates `double` via `toInt()`. Returns [defaultValue] (or `null`) if
  /// the key is missing. Throws [ArgumentError] for non-numeric values.
  int? asInt(String path, {int? defaultValue}) {
    final v = this[path];
    if (v == null) return defaultValue;
    if (v is int) return v;
    if (v is double) return v.toInt();
    throw ArgumentError(
      'Expected int at "$path" but got ${v.runtimeType}',
    );
  }

  /// Read a double value at `"section.property"`. Accepts `double` as-is and
  /// widens `int` via `toDouble()`. Returns [defaultValue] (or `null`) if the
  /// key is missing. Throws [ArgumentError] for non-numeric values.
  double? asDouble(String path, {double? defaultValue}) {
    final v = this[path];
    if (v == null) return defaultValue;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    throw ArgumentError(
      'Expected double at "$path" but got ${v.runtimeType}',
    );
  }

  /// Read a numeric value at `"section.property"` and interpret it as an
  /// offset between [min] and [max]:
  ///
  /// - In `[0, 1]`: lerp from [min] to [max] (`0` → [min], `1` → [max]).
  /// - In `[-1, 0)`: lerp from [max] back toward [min]
  ///   (e.g. `min=100, max=200, value=-0.2` → `180`).
  /// - Greater than `1`: returns `min + value`.
  /// - Less than `-1`: returns `max + value`.
  ///
  /// Accepts the same numeric inputs as [asDouble] (int widens to double).
  /// Returns [defaultValue] (or `null`) if the key is missing. Throws
  /// [ArgumentError] for non-numeric values.
  double? asOffset(
    String path,
    double min,
    double max, {
    double? defaultValue,
  }) {
    final v = asDouble(path);
    if (v == null) return defaultValue;
    return _offset(v, min, max);
  }

  static double _offset(double v, double min, double max) {
    if (v > 1) return min + v;
    if (v < -1) return max + v;
    if (v >= 0) return min + v * (max - min);
    return max + v * (max - min);
  }

  /// Read an object value at `"section.property"` and interpret it as a
  /// position in screen pixels, relative to a window on the current
  /// [SizzleGame]. The object can carry:
  ///
  /// - `x` / `y`: numeric values interpreted by the same rules as [asOffset].
  ///   A missing axis defaults to `0` (i.e. the window's min on that axis).
  /// - `window`: optional string selecting which window to resolve against.
  ///   `'target'` uses `SizzleGame.safeWindow` (the always-visible area),
  ///   `'max'` uses `SizzleGame.gameWindow` (the full max-size area), and
  ///   anything else — including a missing property — uses the default
  ///   `SizzleGame.viewWindow` (the visible letterbox area).
  ///
  /// Returns [defaultValue] (or `null`) if the key is missing. Throws
  /// [ArgumentError] if the value is present but is not an object, or if `x`
  /// or `y` are present but non-numeric.
  Vector2? asPos(String path, {Vector2? defaultValue}) {
    final raw = this[path];
    if (raw == null) return defaultValue;
    final obj = _asMap(raw);
    if (obj == null) {
      throw ArgumentError(
        'Expected object at "$path" but got ${raw.runtimeType}',
      );
    }
    final game = Services.game as SizzleGame;
    final MutableRectangle<double> window;
    switch (obj['window']) {
      case 'target':
        window = game.safeWindow;
        break;
      case 'max':
        window = game.gameWindow;
        break;
      default:
        window = game.viewWindow;
    }
    return Vector2(
      _offset(_axis(obj['x'], path, 'x'), window.left, window.right),
      _offset(_axis(obj['y'], path, 'y'), window.top, window.bottom),
    );
  }

  static double _axis(dynamic v, String path, String axis) {
    if (v == null) return 0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    throw ArgumentError(
      'Expected numeric "$axis" at "$path" but got ${v.runtimeType}',
    );
  }

  /// Read a bool value at `"section.property"`. Strict: the value must already
  /// be a bool — strings like `'true'` are not coerced. Returns [defaultValue]
  /// (or `null`) if the key is missing. Throws [ArgumentError] for any other
  /// type.
  bool? asBool(String path, {bool? defaultValue}) {
    final v = this[path];
    if (v == null) return defaultValue;
    if (v is bool) return v;
    throw ArgumentError(
      'Expected bool at "$path" but got ${v.runtimeType}',
    );
  }
}
