import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:jenny/jenny.dart';
import 'package:path_provider/path_provider.dart';

import 'package:sizzle/src/game/game.dart';

typedef OnFileAccessCallback = void Function(Map<String, dynamic> data);

/// Global services class
class Services {
  Services() {
    throw ('Do not create an instance of this class. Access static methods only.');
  }

  /// The save file name used by [load] and [save] to
  /// persist player data between game sessions.
  static final _savefile = 'sizzle.json';

  /// The path to the root asset folder
  static final _assetFolder = 'assets/';

  /// Reference to the currently running game
  static late final SizzleGame game;

  /// Reference to the yarn spinner project. In most
  /// cases this does not need to be directly accessed.
  /// Use [loadDialog] and [startDialog] with a
  /// [DialogComponent] view instead.
  static final YarnProject yarn = YarnProject();

  static Map<String, dynamic> _data = {};
  static final List<String> _flags = [];
  static Directory? _dir;
  static DialogueRunner? _runner;
  static Completer<void>? _dialogComplete;
  static final Map<String, Image> _cachedImages = {};
  static final Map<String, ByteData> _cachedFiles = {};

  static OnFileAccessCallback? _onLoad;
  static set onLoad(OnFileAccessCallback callback) {
    _onLoad = callback;
  }

  static OnFileAccessCallback? _onSave;
  static set onSave(OnFileAccessCallback callback) {
    _onSave = callback;
  }

  /// Initialise the services. SizzleGame does this
  /// automatically during constructor, and should not be
  /// called again.
  static void init(SizzleGame game) {
    Services.game = game;
    Services.yarn.functions.addFunction1('flagged', Services._checkFlagsFromYarn);
    Services.yarn.commands.addCommand1('flag', Services._setFlagsFromYarn);
  }

  /// Load all data from the device. This includes flags
  /// and yarn variables (dialog system). Flags are appended
  /// or replaced. Clear the flags first if this is not desired.
  /// Yarn variables are appended or replaced. Clear the yarn
  /// variables using [clearDialog] if this is not desired.
  /// Use [onLoad] callback to customise data after the load operation.
  static void load() async {
    _dir ??= await getApplicationDocumentsDirectory();
    if (_dir == null) return;

    final File file = File('${_dir!.path}/$_savefile');
    if (await file.exists()) {
      _data = json.decode(file.readAsStringSync());
      _onLoad?.call(_data);
      if (_data.containsKey('_flags')) {
        _data['_flags'].forEach((v) => _flags.add(v as String));
      }
      if (_data.containsKey('_yarn')) {
        yarn.variables.variables.addAll(_data['_yarn']);
      }
    }
  }

  /// Save all data to the device
  ///
  /// Override [saveCustom] to customise data before the save operation
  static void save() async {
    _dir ??= await getApplicationDocumentsDirectory();
    if (_dir == null) return;

    _data['_flags'] = _flags;
    _data['_yarn'] = yarn.variables.variables;
    _onSave?.call(_data);

    final File file = File('${_dir!.path}/$_savefile');
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

  /// Load and parse one or more yarn spinner dialog [files]
  /// ready for starting a dialog. If [replaceNodes] is true,
  /// the already loaded yarn nodes will be deleted first. Any
  /// characters, variables, functions are not affected.
  static FutureOr<void> loadDialog(List<String> files, {bool replaceNodes = false}) async {
    if (replaceNodes) {
      yarn.nodes.clear();
    }
    for (final file in files) {
      String data = await loadString(file, false);
      yarn.parse(data);
    }
  }

  /// Starts a dialog with the node given by [nodeName]. The
  /// dialog should have been loaded by [loadDialog] first.
  /// The [views] present the dialog to the user. At least
  /// one view must be provided.
  static Future<void> startDialog(String nodeName, List<DialogueView> views) {
    assert(_runner == null, 'Trying to start dialog $nodeName but dialog already started');
    assert(views.isNotEmpty, 'Trying to start dialog $nodeName but no dialog views provided');
    _runner = DialogueRunner(yarnProject: yarn, dialogueViews: views);
    _runner!.startDialogue(nodeName).whenComplete(_dialogEnded);
    _dialogComplete = Completer();
    return _dialogComplete!.future;
  }

  static void _dialogEnded() {
    _runner = null;
    _dialogComplete?.complete();
    _dialogComplete = null;
  }

  /// Clearing data can be useful when moving between different
  /// areas of the game. Be default it clears nodes only, but can
  /// be used to clear other data as well by setting [nodes],
  /// [characters], [variables], [functions] or [commands] to true
  /// or false. It will not clear node visit counts.
  static void clearDialog({
    bool nodes = true,
    bool characters = false,
    bool variables = false,
    bool commands = false,
    bool functions = false,
  }) {
    if (nodes) {
      yarn.nodes.clear();
    }
    if (characters) {
      //yarn.characters.clear();
    }
    if (variables) {
      //yarn.variables.clear(false);
    }
    if (commands) {
      //yarn.commands.clear();
    }
    if (functions) {
      //yarn.functions.clear();
    }
  }

  /// Used internally to set or unset flags from yarn.
  /// Accepts a single comma delimited string for flags. Flags
  /// may be prefixed with ! to unset them. e.g. "flag1,!flag2"
  static void _setFlagsFromYarn(String f) {
    for (String fl in f.split(',')) {
      fl = fl.trim();
      if (fl[0] == '!') {
        flag(fl.substring(1), false);
      } else {
        flag(fl, true);
      }
    }
  }

  /// Used internally to check flags are set from yarn.
  /// Accepts a single comma delimited string of flags. Flags
  /// may be prefixed with ! to check if they are unset. All
  /// conditions must be true to pass. e.g. "flag1,!flag2"
  static bool _checkFlagsFromYarn(String f) {
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

  /// Load an image from the asset bundle by [path]. If
  /// [cache] is true, the image will also be cached so that
  /// subsequent loads are faster. [path] is relative to the
  /// 'assets' folder. Use [clearCache] to later remove the
  /// image if it's nmo longer required.
  static Future<Image> loadImage(String path, [bool cache = true]) async {
    if (_cachedImages.containsKey(path)) {
      return _cachedImages[path]!;
    }
    final data = await rootBundle.load(_assetFolder + path);
    final bytes = Uint8List.view(data.buffer);
    final image = await decodeImageFromList(bytes);
    if (cache) {
      _cachedImages[path] = image;
    }
    return image;
  }

  /// Return an image previously loaded and cached with
  /// [loadImage]. The image must be fully loaded. This method
  /// is only recommended if it can be guaranteed the image
  /// has loaded, and async is not possible. Instead,
  /// consider calling and awaiting [loadImage] as a safer
  /// alternative.
  static Image loadedImage(String path) {
    return _cachedImages[path]!;
  }

  /// Load bytes from the asset bundle by [path]. If
  /// [cache] is true, the file will also be cached so that
  /// subsequent loads are faster. [path] is relative to the
  /// 'assets' folder. Use [clearCache] to later remove the
  /// image if it's nmo longer required.
  static Future<ByteData> loadFile(String path, [bool cache = true]) async {
    if (_cachedFiles.containsKey(path)) {
      return _cachedFiles[path]!;
    }
    final data = await rootBundle.load(_assetFolder + path);
    if (cache) {
      _cachedFiles[path] = data;
    }
    return data;
  }

  /// Return a file previously loaded and cached with
  /// [loadFile]. The file must be fully loaded. This method
  /// is only recommended if it can be guaranteed the image
  /// has loaded, and async is not possible. Instead,
  /// consider calling and awaiting [loadFile] as a safer
  /// alternative.
  static ByteData loadedFile(String path) {
    return _cachedFiles[path]!;
  }

  /// Load a string from the asset bundle by [path]. If
  /// [cache] is true, the file will also be cached so that
  /// subsequent loads are faster. [path] is relative to the
  /// 'assets' folder. Use [clearCache] to later remove the
  /// image if it's nmo longer required.
  static Future<String> loadString(String path, [bool cache = true]) async {
    final buffer = (await loadFile(path, cache)).buffer;
    return utf8.decode(buffer.asUint8List(0, buffer.lengthInBytes));
  }

  /// Return a string previously loaded and cached with
  /// [loadString]. The file must be fully loaded. This method
  /// is only recommended if it can be guaranteed the image
  /// has loaded, and async is not possible. Instead,
  /// consider calling and awaiting [loadString] as a safer
  /// alternative.
  static String loadedString(String path) {
    final buffer = _cachedFiles[path]!.buffer;
    return utf8.decode(buffer.asUint8List(0, buffer.lengthInBytes));
  }

  /// Load a JSON file from the asset bundle by [path]. If
  /// [cache] is true, the file will also be cached so that
  /// subsequent loads are faster. [path] is relative to the
  /// 'assets' folder. Use [clearCache] to later remove the
  /// image if it's nmo longer required.
  static Future<dynamic> loadJson(String path, [bool cache = true]) async {
    return jsonDecode(await loadString(path, cache));
  }

  /// Return a JSON file previously loaded and cached with
  /// [loadJson]. The file must be fully loaded. This method
  /// is only recommended if it can be guaranteed the image
  /// has loaded, and async is not possible. Instead,
  /// consider calling and awaiting [loadJson] as a safer
  /// alternative.
  static dynamic loadedJson(String path) {
    return jsonDecode(_cachedFiles[path].toString());
  }

  /// Will remove the file in [path] from the cache. If [path]
  /// is empty, the entire cache will be cleared. By default
  /// both the image and file cache will be affected. This can
  /// be changed by setting [images] and/or [files] to false.
  void clearCache({String path = '', bool images = true, bool files = true}) {
    if (images) {
      if (path == '') {
        _cachedImages.clear();
      } else {
        _cachedImages.remove(path);
      }
    }
    if (files) {
      if (path == '') {
        _cachedFiles.clear();
      } else {
        _cachedFiles.remove(path);
      }
    }
  }
}
