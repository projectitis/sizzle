import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:jenny/jenny.dart';
import 'package:path_provider/path_provider.dart';

import 'package:sizzle/src/game/game.dart';

typedef OnFileAccessCallback = void Function(Map<String, dynamic> data);

/// Global services class
class Services {
  static final _fileName = 'sizzle.json';

  static late final SizzleGame game;
  static Map<String, dynamic> _data = {};
  static List<String> _flags = [];
  static Directory? _dir;
  static final YarnProject yarn = YarnProject();
  static DialogueRunner? _runner;

  static OnFileAccessCallback? _onLoad;
  static set onLoad(OnFileAccessCallback callback) {
    _onLoad = callback;
  }

  static OnFileAccessCallback? _onSave;
  static set onSave(OnFileAccessCallback callback) {
    _onSave = callback;
  }

  /// Initialise the context
  static Future<void> init(SizzleGame game) async {
    Services.game = game;
    Services.yarn.functions.addFunction1('flag', Services.checkFlagsFromYarn);
    Services.yarn.commands.addCommand1('flag', Services.setFlagsFromYarn);

    _dir ??= await getApplicationDocumentsDirectory();
    load();
  }

  /// Load all data from the device
  ///
  /// Provide [onLoad] callback to customise data before the load operation
  static void load() async {
    if (_dir == null) return;

    final File file = File('${_dir!.path}/$_fileName');
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

    final File file = File('${_dir!.path}/$_fileName');
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

  static void startDialog(String nodeName, List<DialogueView> views) {
    assert(_runner == null, 'Trying to start dialog $nodeName but dialog already started');
    assert(views.isNotEmpty, 'Trying to start dialog $nodeName but no dialog views provided');
    _runner = DialogueRunner(yarnProject: yarn, dialogueViews: views);
    _runner!.startDialogue(nodeName).whenComplete(_dialogEnded);
  }

  static void _dialogEnded() {
    _runner = null;
  }

  static FutureOr<void> loadDialog(List<String> files, {bool replaceNodes = false}) async {
    if (replaceNodes) {
      yarn.nodes.clear();
    }
    for (final file in files) {
      String data = await rootBundle.loadString(file);
      yarn.parse(data);
    }
  }

  /// Set or unset flags from yarn
  ///
  /// Accepts a single comma delimited string for flags. Flags
  /// may be prefixed with ! to unset them. e.g. "flag1,!flag2"
  static void setFlagsFromYarn(String f) {
    for (String fl in f.split(',')) {
      fl = fl.trim();
      if (fl[0] == '!') {
        flag(fl.substring(1), false);
      } else {
        flag(fl, true);
      }
    }
  }

  /// Check flags are set from yarn
  ///
  /// Accepts a single comma delimited string of flags. Flags
  /// may be prefixed with ! to check if they are unset. All
  /// conditions must be true to pass. e.g. "flag1,!flag2"
  static bool checkFlagsFromYarn(String f) {
    for (String fl in f.split(',')) {
      fl = fl.trim();
      if (fl[0] == '!') {
        if (flagged(fl.substring(1))) {
          return false;
        }
      } else {
        if (!flagged(fl)) {
          return false;
        }
      }
    }
    return true;
  }
}
