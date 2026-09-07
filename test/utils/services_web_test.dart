@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sizzle/sizzle.dart';
import 'package:web/web.dart' as web;

/// Web has no file system, so `Services.save`/`load` persist to
/// `localStorage` instead. This file is browser-only - run it with:
///
///     flutter test --platform chrome test/utils/services_web_test.dart
///
/// The rest of the suite imports `dart:io` (via the test helpers) and cannot
/// run under Chrome, so this file must be named explicitly.
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
    Services.flags.clear();
  });

  test('save writes the save data to localStorage', () async {
    Services.flags['castle_key'] = true;
    await Services.save();

    final raw = web.window.localStorage.getItem('sizzle.json');
    expect(raw, isNotNull);
    expect(raw, contains('castle_key'));
  });

  test('load restores flags written by a previous save', () async {
    Services.flags['castle_key'] = true;
    Services.flags['bridge_repaired'] = true;
    await Services.save();

    Services.flags.clear();
    expect(Services.flags['castle_key'], isFalse);

    await Services.load();
    expect(Services.flags['castle_key'], isTrue);
    expect(Services.flags['bridge_repaired'], isTrue);
  });

  test('load with nothing stored leaves state untouched', () async {
    Services.flags['transient'] = true;

    await Services.load();

    expect(Services.flags['transient'], isTrue);
  });

  test('onSave / onLoad round-trip custom data', () async {
    Services.onSave = (data) => data['hi_score'] = 4200;
    await Services.save();

    int? restored;
    Services.onLoad = (data) => restored = data['hi_score'] as int?;
    await Services.load();

    expect(restored, 4200);
  });
}
