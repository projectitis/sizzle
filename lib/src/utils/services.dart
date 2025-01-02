import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flame/components.dart';
import 'package:path_provider/path_provider.dart';

import '../game/game.dart';
import './services/dialog_service.dart';
import './services/file_service.dart';
import './services/flag_service.dart';
import './services/image_service.dart';
import './logger.dart';

typedef OnFileAccessCallback = void Function(Map<String, dynamic> data);

/// Global services class
class Services {
  Services() {
    assert(false, 'Use static methods only. Do not create an instance.');
  }

  /// The save file name used by [load] and [save] to
  /// persist player data between game sessions.
  static final _savefile = 'sizzle.json';

  /// The path to the root asset folder
  static final _assetFolder = 'assets/';

  /// Reference to the currently running game
  static final Component _gameRef = Component();
  static get game => _gameRef.findGame() as SizzleGame;

  /// Reference to the file service
  static final FileService files = FileService(_assetFolder);

  /// Reference to the image service
  static final ImageService images = ImageService(_assetFolder);

  /// Reference to the flag service
  static final FlagService flags = FlagService();

  /// Reference to the dialog service
  static final DialogService dialog = DialogService(files, flags);

  // Logger
  static Logger log = PrintLogger();

  /// The data loaded from the device
  static Map<String, dynamic> _data = {};

  /// Documents directory for device
  static Directory? _dir;

  /// Callback for customising data after loading
  static OnFileAccessCallback? _onLoad;
  static set onLoad(OnFileAccessCallback callback) {
    _onLoad = callback;
  }

  /// Callback for customising data before saving
  static OnFileAccessCallback? _onSave;
  static set onSave(OnFileAccessCallback callback) {
    _onSave = callback;
  }

  /// Load all data from the device. This includes flags
  /// and yarn variables (dialog system). Flags are appended
  /// or replaced. Clear the flags first if this is not desired.
  /// Yarn variables are appended or replaced. Clear the yarn
  /// variables using [clearDialog] if this is not desired.
  /// Use [onLoad] callback to customise data after the load operation.
  static FutureOr<void> load() async {
    _dir ??= await getApplicationDocumentsDirectory();
    if (_dir == null) return;

    final File file = File('${_dir!.path}/$_savefile');
    if (await file.exists()) {
      _data = json.decode(file.readAsStringSync());
      _onLoad?.call(_data);
      if (_data.containsKey('_flags')) {
        flags.clear();
        _data['_flags'].forEach((v) => flags[v as String] = true);
      }
      if (_data.containsKey('_yarn')) {
        dialog.yarn.variables.variables.addAll(_data['_yarn']);
      }
    }
  }

  /// Save all data to the device
  ///
  /// Override [saveCustom] to customise data before the save operation
  static FutureOr<void> save() async {
    _dir ??= await getApplicationDocumentsDirectory();
    if (_dir == null) return;

    _data['_flags'] = flags.flags;
    _data['_yarn'] = dialog.yarn.variables.variables;
    _onSave?.call(_data);

    final File file = File('${_dir!.path}/$_savefile');
    file.writeAsStringSync(json.encode(_data));
  }
}
