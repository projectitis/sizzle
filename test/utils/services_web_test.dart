@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sizzle/sizzle.dart';
import 'package:web/web.dart' as web;

/// Web has no file system, so `PlatformSaveStorage` persists to `localStorage`
/// instead. This file is browser-only - run it with:
///
///     flutter test --platform chrome test/utils/services_web_test.dart
///
/// The rest of the suite imports `dart:io` (via the test helpers) and cannot
/// run under Chrome, so this file must be named explicitly.
///
/// Scope: only that the storage really reaches `localStorage`. The save and
/// load logic itself - validation, corrupt files, serialisation - is covered by
/// `services_save_test.dart`, which runs on the VM through a `MemorySaveStorage`
/// and so runs everywhere.
///
/// NOTE: these assertions have never actually been executed. On the machine
/// they were written on, `flutter test --platform chrome` hangs forever at
/// "loading ..." - Chrome starts and loads the harness page but never connects
/// back to the runner. The same hang occurs for a test importing no sizzle
/// code, so it is a harness problem rather than an engine one. Web save/load
/// was verified instead by shipping a real Sizzle game to itch.io. Treat these
/// tests as unproven until they go green somewhere.
void main() {
  setUp(() {
    web.window.localStorage.removeItem('sizzle.json');
    web.window.localStorage.removeItem('slot2.json');
    Services.saveFile = Services.defaultSaveFile;
    Services.flags.clear();
  });

  test('save writes the save data to localStorage', () async {
    Services.flags['castle_key'] = true;

    expect(await Services.save(), isTrue);

    final raw = web.window.localStorage.getItem('sizzle.json');
    expect(raw, isNotNull);
    expect(raw, contains('castle_key'));
  });

  test('load reads the save data back from localStorage', () async {
    Services.flags['castle_key'] = true;
    await Services.save();
    Services.flags.clear();

    expect(await Services.load(), isTrue);
    expect(Services.flags['castle_key'], isTrue);
  });

  test('the save file name selects the localStorage key', () async {
    Services.flags['castle_key'] = true;

    expect(await Services.save(name: 'slot2.json'), isTrue);

    expect(
      web.window.localStorage.getItem('slot2.json'),
      contains('castle_key'),
    );
    expect(web.window.localStorage.getItem('sizzle.json'), isNull);
  });

  test('hasSave and deleteSave reach localStorage', () async {
    await Services.save();
    expect(await Services.hasSave(), isTrue);

    expect(await Services.deleteSave(), isTrue);
    expect(await Services.hasSave(), isFalse);
    expect(web.window.localStorage.getItem('sizzle.json'), isNull);
  });
}
