import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jenny/jenny.dart';
import 'package:sizzle/sizzle.dart';

String testCharacters = """
<<character Olive>>
<<character Morris>>
""";

String testDialog = """
title: test
---
<<if flagged("visitedRuins")>>
   <<if flagged("ruinsDisturbed")>>
      Morris: Keep it down this time! #whisper
   <<else>>
      Morris: Let's keep quiet... #whisper
   <<endif>>
<<else>>
   <<flag visitedRuins>>
   Olive: What is this place? Pretty #thinking
   Olive: It's so peaceful
   Morris: Quiet... #whisper
   -> Olive: What is it? #whisper
      Morris: I'm not sure #whisper
      Morris: I think I heard something #whisper
      <<if flagged("flag1,flag2,!flag3,!flag4")>>
         <<flag flag3,flag4,!flag1>>
      <<endif>>
   -> Olive: Yodelayihoo! Yodelayihoo! #loud
      Morris: BE QUIET! #angry
      Olive: Calm down, Mor...
      Olive: argh!
      <<flag ruinsDisturbed>>
<<endif>>
===
""";

class MockFileService extends FileService {
  MockFileService() : super('');

  @override
  Future<String> loadString({
    FileProperties? properties,
    String? path,
    bool cache = true,
  }) async {
    return testDialog;
  }
}

class MockDialogView extends DialogueView {
  bool started = false;
  bool choiceStarted = false;
  int respondToChoiceWith = 0;
  String? line;
  String? character;

  @override
  FutureOr<void> onDialogueStart() {
    started = true;
  }

  @override
  FutureOr<bool> onLineStart(DialogueLine dialogueLine) {
    if (line == null) {
      line = dialogueLine.text;
      character = dialogueLine.character?.name ?? 'Unknown';
    }
    return true;
  }

  @override
  FutureOr<int?> onChoiceStart(DialogueChoice choice) {
    choiceStarted = true;
    return respondToChoiceWith;
  }
}

void main() async {
  group('DialogService', () {
    FileService fileService = MockFileService();
    FlagService flagService = FlagService();
    DialogService dialogService = DialogService(fileService, flagService);

    tearDown(() {
      dialogService.clear(characters: true, nodes: true, variables: true);
      flagService.clear();
    });

    test('Registers functions and commands', () {
      expect(dialogService.yarn.functions.hasFunction('flagged'), true);
      expect(dialogService.yarn.functions.hasFunction('test'), false);
      expect(dialogService.yarn.commands.hasCommand('flag'), true);
      expect(dialogService.yarn.commands.hasCommand('test'), false);
    });

    test('Parses characters', () {
      dialogService.parse(testCharacters);

      expect(dialogService.yarn.characters.contains('Olive'), true);
      expect(dialogService.yarn.characters.contains('Morris'), true);
      expect(dialogService.yarn.characters.contains('James'), false);
    });

    test('Parses dialog', () {
      dialogService.parse(testCharacters);
      dialogService.parse(testDialog);

      expect(dialogService.yarn.nodes.length, 1);
      expect(dialogService.yarn.nodes['test'], isNotNull);
      expect(dialogService.yarn.nodes['fail'], isNull);
    });

    test('Loads dialog', () async {
      dialogService.parse(testCharacters);
      await dialogService.load(['test']);

      expect(dialogService.yarn.nodes.length, 1);
      expect(dialogService.yarn.nodes['test'], isNotNull);
      expect(dialogService.yarn.nodes['fail'], isNull);
    });

    test('Starts dialog', () async {
      MockDialogView view = MockDialogView();
      dialogService.parse(testCharacters);
      dialogService.parse(testDialog);
      expect(view.started, false);

      await dialogService.start('test', [view]);
      expect(view.started, true);
      expect(view.line, 'What is this place? Pretty');
      expect(view.character, 'Olive');
    });

    test('Correctly processes flags', () async {
      MockDialogView view = MockDialogView();
      dialogService.parse(testCharacters);
      dialogService.parse(testDialog);
      dialogService.flags.flag('visitedRuins');

      await dialogService.start('test', [view]);
      expect(view.line, 'Let\'s keep quiet...');
      expect(view.character, 'Morris');
    });
  });
}
