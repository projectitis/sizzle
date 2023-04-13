import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

typedef OnFileAccessCallback = void Function(Map<String, dynamic> data);

/// Global services class
class Services {
  static final _FILE_NAME = 'sizzle.json';

  static Map<String, dynamic> _data = {};
  static List<String> _flags = [];
  static Directory? _dir;

  static OnFileAccessCallback? _onLoad;
  static set onLoad(OnFileAccessCallback callback) {
    _onLoad = callback;
  }

  static OnFileAccessCallback? _onSave;
  static set onSave(OnFileAccessCallback callback) {
    _onSave = callback;
  }

  /// Initialise the context
  static Future<void> init() async {
    _dir ??= await getApplicationDocumentsDirectory();
    print('Services got dir:${_dir?.path}');
    load();
  }

  /// Load all data from the device
  ///
  /// Provide [onLoad] callback to customise data before the load operation
  static void load() async {
    if (_dir == null) return;
    print('Services load');

    final File file = File('${_dir!.path}/$_FILE_NAME');
    if (await file.exists()) {
      _data = json.decode(file.readAsStringSync());
      _flags = [];
      if (_data.containsKey('_flags')) {
        _data['_flags'].forEach((v) => _flags.add(v as String));
      }
      _onLoad?.call(_data);
    }
  }

  /// Save all data to the device
  ///
  /// Override [saveCustom] to customise data before the save operation
  static void save() async {
    if (_dir == null) return;

    _data['_flags'] = _flags;
    _onSave?.call(_data);

    final File file = File('${_dir!.path}/$_FILE_NAME');
    file.writeAsStringSync(json.encode(_data));
  }

  /// Set or unset a flag
  static bool flag(String f, [bool v = true]) {
    if (v) {
      if (_flags.contains(f)) return true;
      _flags.add(f);
    } else {
      return _flags.remove(f);
    }
    return false;
  }

  /// Check a flag
  static bool flagged(String f) {
    return _flags.contains(f);
  }

  /// Return full list of flags
  static List<String> get flags {
    return _flags;
  }
}
