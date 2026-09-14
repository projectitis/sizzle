@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sizzle/sizzle.dart';
// The marker is an internal detail of the string-only encoding, so it is not
// exported from `package:sizzle/sizzle.dart`. Reach for it directly, the same
// way `platform/save_data_io_test.dart` reaches for the native shim.
import 'package:sizzle/src/utils/platform/save_bytes_codec.dart';
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

  group('binary storage', () {
    // The encoding itself is covered on the VM by
    // `test/utils/services/save_storage_test.dart`, which drives the same codec
    // through `MemorySaveStorage`. What is only checkable here is that the
    // encoded value really lands in `localStorage`.
    final binary = Uint8List.fromList([0, 1, 2, 0xFF, 0xFE, 127]);
    final storage = PlatformSaveStorage();

    setUp(() {
      web.window.localStorage.removeItem('thumb.png');
    });

    test('writeBytes stores an encoded entry in localStorage', () async {
      await storage.writeBytes('thumb.png', binary);

      final raw = web.window.localStorage.getItem('thumb.png');
      expect(raw, isNotNull);
      expect(raw, startsWith(saveBytesMarker));
    });

    test('bytes round trip through localStorage', () async {
      await storage.writeBytes('thumb.png', binary);
      expect(await storage.readBytes('thumb.png'), binary);
    });

    test('list reports the localStorage keys', () async {
      await Services.save();
      await storage.writeBytes('thumb.png', binary);

      final names = await storage.list();
      expect(names, contains('sizzle.json'));
      expect(names, contains('thumb.png'));
    });
  });
}
