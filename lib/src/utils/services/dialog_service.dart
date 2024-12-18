import 'dart:async';

import 'package:jenny/jenny.dart';

import './file_service.dart';
import './flag_service.dart';

class DialogService {
  /// Reference to the yarn spinner project. In most cases this does not need to
  /// be directly accessed. Use [load] and [start] with a [DialogComponent] view
  /// instead.
  final YarnProject yarn = YarnProject();

  /// The dialog runner
  DialogueRunner? _runner;

  /// Completer for dialog completion
  Completer<void>? _dialogComplete;

  /// Reference to the file service
  FileService files;

  /// Reference to the flag service
  FlagService flags;

  /// Create a new dialog service with a reference to the [files] and [flags]
  DialogService(this.files, this.flags) {
    yarn.functions.addFunction1('flagged', _checkFlagsFromYarn);
    yarn.commands.addCommand1('flag', _setFlagsFromYarn);
  }

  /// Load and parse one or more yarn spinner dialog [files]
  /// ready for starting a dialog. If [replaceNodes] is true,
  /// the already loaded yarn nodes will be deleted first. Any
  /// characters, variables, functions are not affected.
  Future<void> load(
    List<String> files, {
    bool replaceNodes = false,
  }) async {
    if (replaceNodes) {
      yarn.nodes.clear();
    }
    for (final file in files) {
      String data = await this.files.loadString(
            path: file,
            cache: false,
          );
      yarn.parse(data);
    }
  }

  /// Starts a dialog with the node given by [nodeName]. The
  /// dialog should have been loaded by [load] first.
  /// The [views] present the dialog to the user. At least
  /// one view must be provided.
  Future<void> start(String nodeName, List<DialogueView> views) {
    assert(
      _runner == null,
      'Trying to start dialog $nodeName but dialog already started',
    );
    assert(
      views.isNotEmpty,
      'Trying to start dialog $nodeName but no dialog views provided',
    );
    _runner = DialogueRunner(yarnProject: yarn, dialogueViews: views);
    _runner!.startDialogue(nodeName).whenComplete(_dialogEnded);
    _dialogComplete = Completer();
    return _dialogComplete!.future;
  }

  /// Called when the dialog has ended
  void _dialogEnded() {
    _runner = null;
    _dialogComplete?.complete();
    _dialogComplete = null;
  }

  /// Clearing data can be useful when moving between different
  /// areas of the game. Be default it clears nodes only, but can
  /// be used to clear other data as well by setting [nodes],
  /// [characters], [variables], [functions] or [commands] to true
  /// or false. It will not clear node visit counts.
  void clear({
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
  void _setFlagsFromYarn(String f) {
    for (String fl in f.split(',')) {
      fl = fl.trim();
      if (fl[0] == '!') {
        flags[fl.substring(1)] = false;
      } else {
        flags[fl] = true;
      }
    }
  }

  /// Used internally to check flags are set from yarn.
  /// Accepts a single comma delimited string of flags. Flags
  /// may be prefixed with ! to check if they are unset. All
  /// conditions must be true to pass. e.g. "flag1,!flag2"
  bool _checkFlagsFromYarn(String f) {
    for (String fl in f.split(',')) {
      fl = fl.trim();
      if (fl[0] == '!') {
        if (flags[fl.substring(1)]) {
          return false;
        }
      } else {
        if (!flags[fl]) {
          return false;
        }
      }
    }
    return true;
  }
}
