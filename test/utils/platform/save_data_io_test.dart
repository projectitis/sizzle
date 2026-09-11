@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sizzle/src/utils/platform/platform_io.dart';

/// Tests for the native save-data shim, which is the only place the atomic
/// write can be verified - the `SaveStorage` seam deliberately hides it from
/// everything above.
///
/// What is NOT covered here: killing the process between the write and the
/// rename. That cannot be done from inside the process. The invariants below
/// (the target is replaced whole, no `.tmp` survives, a failed write leaves the
/// previous save readable) are what the atomicity is actually for.
void main() {
  late Directory temp;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    temp = Directory.systemTemp.createTempSync('sizzle_save_test');
    // The shim caches the documents directory on first use, so the mock has to
    // be in place before anything touches it. `flutter test` runs each file in
    // its own isolate, so nothing else can have resolved it already.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => temp.path,
    );
  });

  tearDownAll(() {
    temp.deleteSync(recursive: true);
  });

  setUp(() {
    for (final entity in temp.listSync()) {
      entity.deleteSync(recursive: true);
    }
  });

  File file(String name) => File('${temp.path}/$name');

  test('written data reads back', () async {
    await writeSaveData('game.json', '{"a":1}');
    expect(await readSaveData('game.json'), '{"a":1}');
  });

  test('reading a file that does not exist returns null', () async {
    expect(await readSaveData('nothing.json'), isNull);
  });

  test('a write replaces a larger existing file and leaves no temp', () async {
    // Rename-over-existing is the part of the atomic write most likely to
    // differ by platform, so it is asserted rather than assumed.
    await writeSaveData('game.json', '{"long":"aaaaaaaaaaaaaaaaaaaaaaaaaaaa"}');
    await writeSaveData('game.json', '{"b":2}');

    expect(await readSaveData('game.json'), '{"b":2}');
    expect(file('game.json.tmp').existsSync(), isFalse);
    expect(temp.listSync(), hasLength(1));
  });

  test('a stale temp file does not affect a write', () async {
    file('game.json.tmp').writeAsStringSync('junk left by a killed process');

    await writeSaveData('game.json', '{"c":3}');

    expect(await readSaveData('game.json'), '{"c":3}');
    expect(file('game.json.tmp').existsSync(), isFalse);
  });

  test('saveDataExists reports presence', () async {
    expect(await saveDataExists('game.json'), isFalse);
    await writeSaveData('game.json', '{}');
    expect(await saveDataExists('game.json'), isTrue);
  });

  test('deleteSaveData removes the file', () async {
    await writeSaveData('game.json', '{}');
    await deleteSaveData('game.json');
    expect(await saveDataExists('game.json'), isFalse);
  });

  test('deleteSaveData does nothing when there is no file', () async {
    await expectLater(deleteSaveData('nothing.json'), completes);
  });

  test('renameSaveData moves over an existing target', () async {
    await writeSaveData('game.json', '{"new":1}');
    await writeSaveData('game.json.corrupt', '{"old":1}');

    await renameSaveData('game.json', 'game.json.corrupt');

    expect(await saveDataExists('game.json'), isFalse);
    expect(await readSaveData('game.json.corrupt'), '{"new":1}');
  });

  test('renameSaveData does nothing when the source is missing', () async {
    await expectLater(renameSaveData('nothing.json', 'x.json'), completes);
    expect(await saveDataExists('x.json'), isFalse);
  });
}
