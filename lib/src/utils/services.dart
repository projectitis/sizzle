import 'dart:async';
import 'dart:convert';

import 'package:flame/components.dart';

import '../game/game.dart';
import './save_storage.dart';
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

  /// Where [save] and [load] keep their data. Defaults to
  /// [PlatformSaveStorage], which stores it on the device.
  ///
  /// Assign a different [SaveStorage] before the first [save] or [load] to put
  /// save data somewhere else - a cloud backend, or [MemorySaveStorage] in
  /// tests.
  static SaveStorage saveStorage = PlatformSaveStorage();

  /// The reserved key holding the [flags] list in the save document.
  static const String _flagsKey = '_flags';

  /// The reserved key holding the yarn variables in the save document.
  static const String _yarnKey = '_yarn';

  /// The suffix given to a save file that could not be loaded.
  static const String _corruptSuffix = '.corrupt';

  /// The save document currently held in memory.
  static Map<String, dynamic> _data = {};

  /// The name [_data] was read from or last written to. A document belongs to
  /// one save file, so an operation on a different name must start fresh
  /// rather than carry the previous file's custom keys across.
  static String? _dataName;

  /// Callback for customising data after loading
  static OnFileAccessCallback? _onLoad;

  /// Called immediately after a save document has been read and applied.
  /// Mutate the supplied map to read your own keys back out.
  ///
  /// It runs after flags and yarn variables have been restored, so it sees
  /// fully loaded engine state. An exception thrown from here is *not* caught -
  /// that is a bug in the callback, not a failed load. Do not call [save] or
  /// [load] from inside it; those calls are serialised and would deadlock.
  static set onLoad(OnFileAccessCallback callback) {
    _onLoad = callback;
  }

  /// Callback for customising data before saving
  static OnFileAccessCallback? _onSave;

  /// Called immediately before the save document is written. Mutate the
  /// supplied map to add your own keys.
  ///
  /// Everything added must be JSON-encodable - a `DateTime` or a custom class
  /// fails the save. An exception thrown from here is *not* caught - that is a
  /// bug in the callback, not a failed save. Do not call [save] or [load] from
  /// inside it; those calls are serialised and would deadlock.
  static set onSave(OnFileAccessCallback callback) {
    _onSave = callback;
  }

  /// Serialises [save], [load] and [deleteSave] so two calls never interleave
  /// their reads, writes and mutations of engine state.
  static Future<void> _queue = Future<void>.value();

  /// Whether a queued operation is running, used only to catch the reentrancy
  /// that would deadlock [_queue].
  static bool _busy = false;

  /// Whether a save document is being built, used only to catch a [save] made
  /// from inside an `onSave` callback, which would recurse.
  static bool _building = false;

  static Future<T> _serialised<T>(Future<T> Function() action) async {
    assert(
      !_busy,
      'Services.save, load and deleteSave are serialised, so calling one from '
      'inside an onLoad callback and awaiting it deadlocks.',
    );
    final previous = _queue;
    final done = Completer<void>();
    _queue = done.future;
    // `previous` is only ever completed from the `finally` below, never with an
    // error, so one failed operation cannot poison the queue.
    await previous;
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
      done.complete();
    }
  }

  /// The save file an operation acts on: [name] if given, otherwise [saveFile].
  static String _resolve(String? name) => name ?? _saveFile;

  /// Load saved data from [name], or from [saveFile] if [name] is omitted.
  ///
  /// This restores flags and yarn variables (the dialog system). Flags are
  /// replaced wholesale; yarn variables are appended or replaced. Clear the
  /// yarn variables with `Services.dialog.clear(variables: true)` first if that
  /// is not what you want. Use the [onLoad] callback to read your own keys back
  /// out afterwards.
  ///
  /// Returns `true` only if a save document was found, validated and applied.
  /// Returns `false` if there is nothing saved, or if the document could not be
  /// read or is not a usable save - in which case the reason is reported
  /// through [log] and no engine state has been touched. It never throws.
  ///
  /// A document that fails to load is moved aside to `<name>.corrupt` so the
  /// next [save] starts clean without destroying it. That means [hasSave] has
  /// to be checked *before* this call to tell "nothing saved" apart from "the
  /// save was damaged":
  ///
  /// ```dart
  /// final had = await Services.hasSave();
  /// if (await Services.load()) {
  ///   continueGame();
  /// } else if (had) {
  ///   showDamagedSaveDialog();
  /// } else {
  ///   newGame();
  /// }
  /// ```
  static Future<bool> load({String? name}) =>
      _serialised(() => _load(_resolve(name)));

  static Future<bool> _load(String name) async {
    final String? contents;
    try {
      contents = await saveStorage.read(name);
    } catch (e) {
      log.error('Save file "$name" could not be read ($e)');
      return false;
    }

    if (contents == null) {
      _data = {};
      _dataName = name;
      return false;
    }

    final dynamic decoded;
    try {
      decoded = json.decode(contents);
    } on FormatException catch (e) {
      return await _reject(name, 'it is not valid JSON: ${e.message}');
    }
    if (decoded is! Map) {
      return await _reject(
        name,
        'the document is a ${decoded.runtimeType}, not an object',
      );
    }

    return await _apply(name, Map<String, dynamic>.from(decoded));
  }

  /// Validate [doc] in full, then commit it to the engine.
  ///
  /// A wrong container shape means the document is not a Sizzle save at all, so
  /// it is rejected whole - restoring half of it would leave the game silently
  /// wrong. A single bad entry inside an otherwise coherent container is a much
  /// smaller failure, so it is dropped and reported rather than costing the
  /// player everything. Nothing is committed until every check has passed.
  static Future<bool> _apply(String name, Map<String, dynamic> doc) async {
    List<String>? newFlags;
    if (doc.containsKey(_flagsKey)) {
      final raw = doc[_flagsKey];
      if (raw is! List) {
        return await _reject(
          name,
          '$_flagsKey is a ${raw.runtimeType}, not a list',
        );
      }
      newFlags = [];
      for (final v in raw) {
        if (v is String) {
          newFlags.add(v);
        } else {
          log.warn(
            'Save file "$name" dropped a flag '
            '(${v.runtimeType} is not a string)',
          );
        }
      }
    }

    Map<String, dynamic>? newVars;
    if (doc.containsKey(_yarnKey)) {
      final raw = doc[_yarnKey];
      if (raw is! Map) {
        return await _reject(
          name,
          '$_yarnKey is a ${raw.runtimeType}, not an object',
        );
      }
      newVars = {};
      raw.forEach((k, v) {
        if (k is! String) {
          log.warn(
            'Save file "$name" dropped a yarn variable '
            '(the name is a ${k.runtimeType}, not a string)',
          );
        } else if (v is String || v is num || v is bool) {
          newVars![k] = v;
        } else {
          log.warn(
            'Save file "$name" dropped yarn variable "$k" '
            '(${v.runtimeType} is not a string, number or bool)',
          );
        }
      });
    }

    // Everything above this line is read-only. Commit from here.
    _data = doc;
    _dataName = name;
    if (newFlags != null) flags.flags = newFlags;
    if (newVars != null) {
      // Written straight into the map rather than through `setVariable`, which
      // additionally enforces type stability and would reject a save whose $x
      // is a number over a session where $x is currently a string. The save is
      // authoritative. The value-type check `setVariable` does that we do want
      // has already been applied above.
      dialog.yarn.variables.variables.addAll(newVars);
    }
    _onLoad?.call(_data);
    return true;
  }

  /// Report [name] as unusable, move it aside, and return `false`.
  ///
  /// Moving it aside rather than deleting it keeps a damaged save available for
  /// diagnosis - the engine never destroys player data on its own. The move is
  /// best effort: it is a write on the failure path, which may be failing
  /// precisely because writes do not work, so a failure here must not turn one
  /// problem into two.
  static Future<bool> _reject(String name, String reason) async {
    log.error('Save file "$name" was not loaded ($reason)');
    try {
      await saveStorage.rename(name, '$name$_corruptSuffix');
      _data = {};
      _dataName = name;
    } catch (e) {
      log.warn('Save file "$name" could not be moved aside ($e)');
    }
    return false;
  }

  /// Save the current session to [name], or to [saveFile] if [name] is omitted.
  ///
  /// This stores all flags and all current yarn variables. Use the [onSave]
  /// callback to add your own keys to the document first.
  ///
  /// Returns `true` if the document reached storage. Returns `false` if it
  /// could not be encoded or written - in which case the reason is reported
  /// through [log] and whatever was already saved is left intact. It never
  /// throws.
  ///
  /// The document is captured when this is called, not when the write happens,
  /// so it holds the state as of the call even if another save or load is
  /// still in flight ahead of it.
  static Future<bool> save({String? name}) {
    final resolved = _resolve(name);

    final Map<String, dynamic> doc;
    final String contents;
    try {
      doc = _document(resolved);
      // Encoded before writing, so data the game added that cannot be
      // represented as JSON fails without having touched the stored save.
      contents = json.encode(doc);
    } on JsonUnsupportedObjectError catch (e) {
      log.error(
        'Save file "$resolved" was not written '
        '(${e.unsupportedObject.runtimeType} cannot be encoded as JSON)',
      );
      return Future<bool>.value(false);
    }

    return _serialised(() => _write(resolved, doc, contents));
  }

  /// Build the document to write to [name].
  ///
  /// This runs synchronously from [save] rather than from the queued write, so
  /// a save records the state as of the call.
  static Map<String, dynamic> _document(String name) {
    assert(
      !_building,
      'Services.save cannot be called from inside an onSave callback.',
    );
    _building = true;
    try {
      // A copy. It only becomes the in-memory document once it has been
      // written, so a save that fails part way through cannot leave the engine
      // holding a document it would never be able to write again.
      final doc = Map<String, dynamic>.of(_dataName == name ? _data : const {});

      // Copies, not the live list and map - `onSave` receives this document,
      // and mutating it must not be able to corrupt the engine's own state.
      doc[_flagsKey] = List<String>.of(flags.flags);
      doc[_yarnKey] = Map<String, dynamic>.of(dialog.yarn.variables.variables);
      _onSave?.call(doc);
      return doc;
    } finally {
      _building = false;
    }
  }

  static Future<bool> _write(
    String name,
    Map<String, dynamic> doc,
    String contents,
  ) async {
    try {
      await saveStorage.write(name, contents);
    } catch (e) {
      log.error('Save file "$name" could not be written ($e)');
      return false;
    }

    _data = doc;
    _dataName = name;
    return true;
  }

  /// Whether saved data exists under [name], or under [saveFile] if [name] is
  /// omitted.
  ///
  /// This does not validate it - a damaged save still reports `true`. Use it to
  /// decide whether to offer a "continue" option, and see [load] for telling a
  /// damaged save apart from no save at all.
  ///
  /// Returns `false` if storage could not be queried, which is reported through
  /// [log].
  static Future<bool> hasSave({String? name}) async {
    final resolved = _resolve(name);
    try {
      return await saveStorage.exists(resolved);
    } catch (e) {
      log.error('Save file "$resolved" could not be checked ($e)');
      return false;
    }
  }

  /// Delete the saved data under [name], or under [saveFile] if [name] is
  /// omitted.
  ///
  /// Returns `true` if there is no longer a save there, including when there
  /// was none to begin with. Returns `false` only if the delete failed, which
  /// is reported through [log].
  ///
  /// This does not clear the running session - flags and yarn variables are
  /// untouched. It does discard the in-memory document, so a later [save]
  /// writes a fresh one rather than restoring the deleted keys.
  static Future<bool> deleteSave({String? name}) =>
      _serialised(() => _deleteSave(_resolve(name)));

  static Future<bool> _deleteSave(String name) async {
    try {
      await saveStorage.delete(name);
    } catch (e) {
      log.error('Save file "$name" could not be deleted ($e)');
      return false;
    }
    if (_dataName == name) {
      _data = {};
      _dataName = null;
    }
    return true;
  }
}
