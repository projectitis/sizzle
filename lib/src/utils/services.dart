import 'dart:async';
import 'dart:convert';

import 'package:flame/components.dart';

import '../game/game.dart';
import './platform/platform.dart';
import './services/dialog_service.dart';
import './services/file_service.dart';
import './services/flag_service.dart';
import './services/image_service.dart';
import './services/lit_svg_service.dart';
import './services/message_service.dart';
import './services/tween_service.dart';
import './logger.dart';

typedef OnFileAccessCallback = void Function(Map<String, dynamic> data);

/// Global services class
class Services {
  Services() {
    assert(false, 'Use static methods only. Do not create an instance.');
  }

  /// The default value of [saveFile].
  static const String defaultSaveFile = 'sizzle.json';

  static String _saveFile = defaultSaveFile;

  /// The save file name used by [load] and [save] to
  /// persist player data between game sessions.
  ///
  /// On native platforms this is a file in the application documents
  /// directory. On web it is the `localStorage` key, since web builds have no
  /// file system.
  ///
  /// Defaults to [defaultSaveFile]. Set it before the first [load] or [save]
  /// to use a different name, or change it between calls to keep several
  /// independent save slots:
  ///
  /// ```dart
  /// Services.saveFile = 'slot2.json';
  /// await Services.save();
  /// ```
  ///
  /// The name is used verbatim, so it must be valid for the platform: a file
  /// name on native, a `localStorage` key on web.
  static String get saveFile => _saveFile;

  static set saveFile(String value) {
    assert(value.isNotEmpty, 'The save file name cannot be empty');
    _saveFile = value;
  }

  /// The path to the root asset folder
  static final _assetFolder = 'assets/';

  /// Reference to the currently running game
  static final Component _gameRef = Component();
  static get game => _gameRef.findGame() as SizzleGame;

  /// Reference to the file service
  static final FileService files = FileService(_assetFolder);

  /// Reference to the image service
  static final ImageService images = ImageService(_assetFolder);

  /// Reference to the lit-SVG service
  static final LitSvgService litSvg = LitSvgService(_assetFolder);

  /// Reference to the flag service
  static final FlagService flags = FlagService();

  /// Reference to the dialog service
  static final DialogService dialog = DialogService(files, flags);

  /// Reference to the tween service. Ticked automatically by
  /// `SizzleGame.update`.
  static final TweenService tween = TweenService();

  /// Reference to the message service. Dispatch is synchronous, so this
  /// service is not ticked.
  static final MessageService messages = MessageService();

  // Logger
  static Logger log = PrintLogger();

  /// The data loaded from the device
  static Map<String, dynamic> _data = {};

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
  /// variables using `Services.dialog.clear(variables: true)` if this is not
  /// desired. Use [onLoad] callback to customise data after the load operation.
  static FutureOr<void> load() async {
    final contents = await readSaveData(_saveFile);
    if (contents == null) return;

    _data = json.decode(contents);
    _onLoad?.call(_data);
    if (_data.containsKey('_flags')) {
      flags.clear();
      _data['_flags'].forEach((v) => flags[v as String] = true);
    }
    if (_data.containsKey('_yarn')) {
      dialog.yarn.variables.variables.addAll(_data['_yarn']);
    }
  }

  /// Save all data to the device.
  ///
  /// Use the [onSave] callback to customise data before the save operation.
  static FutureOr<void> save() async {
    _data['_flags'] = flags.flags;
    _data['_yarn'] = dialog.yarn.variables.variables;
    _onSave?.call(_data);

    await writeSaveData(_saveFile, json.encode(_data));
  }
}
