import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sizzle/sizzle.dart';

/// Tests for `MemorySaveStorage`, which doubles as the coverage for the
/// string-only encoding `PlatformSaveStorage` uses on web. Both go through the
/// same codec, and this one runs on the VM - the browser suite cannot be
/// executed on the machine this was written on (see `services_web_test.dart`).
///
/// The behaviour being pinned down is that a storage backend which can only
/// hold strings still behaves like a file system: text and binary share one
/// namespace, and reading one as the other does what native does rather than
/// returning something subtly wrong.
void main() {
  late MemorySaveStorage storage;

  setUp(() => storage = MemorySaveStorage());

  // 0xFF 0xFE is not valid UTF-8, and 'abcd' is a length that base64 would
  // happily decode into garbage. Both are the cases a naive implementation
  // gets wrong.
  final binary = Uint8List.fromList([0, 1, 2, 0xFF, 0xFE, 127]);

  group('round trip', () {
    test('text written as text reads back as text', () async {
      await storage.write('game.json', '{"a":1}');
      expect(await storage.read('game.json'), '{"a":1}');
    });

    test('text written as text reads back as UTF-8 bytes', () async {
      await storage.write('game.json', '{"a":1}');
      expect(await storage.readBytes('game.json'), utf8.encode('{"a":1}'));
    });

    test('bytes written as bytes read back as bytes', () async {
      await storage.writeBytes('thumb.png', binary);
      expect(await storage.readBytes('thumb.png'), binary);
    });

    test('bytes read as text throw rather than return the encoding', () async {
      await storage.writeBytes('thumb.png', binary);
      expect(
        () => storage.read('thumb.png'),
        throwsA(isA<FormatException>()),
      );
    });

    test('a text length base64 would accept is still read as text', () async {
      // 'abcd' is valid base64. Without the marker this would silently decode
      // to three bytes of garbage instead of four bytes of text.
      await storage.write('note.txt', 'abcd');
      expect(await storage.readBytes('note.txt'), utf8.encode('abcd'));
    });

    test('empty bytes round trip', () async {
      await storage.writeBytes('empty.bin', Uint8List(0));
      expect(await storage.readBytes('empty.bin'), isEmpty);
    });

    test('reading something that is not there returns null', () async {
      expect(await storage.read('nothing.json'), isNull);
      expect(await storage.readBytes('nothing.png'), isNull);
    });

    test('a write replaces bytes and a byte write replaces text', () async {
      await storage.writeBytes('slot', binary);
      await storage.write('slot', 'now text');
      expect(await storage.read('slot'), 'now text');

      await storage.writeBytes('slot', binary);
      expect(await storage.readBytes('slot'), binary);
    });
  });

  group('list', () {
    test('returns the stored names sorted', () async {
      await storage.write('b.json', '{}');
      await storage.write('a.json', '{}');
      await storage.write('c.json', '{}');

      expect(await storage.list(), ['a.json', 'b.json', 'c.json']);
    });

    test('honours a prefix', () async {
      await storage.write('save_1.json', '{}');
      await storage.write('save_2.json', '{}');
      await storage.write('settings.json', '{}');

      expect(await storage.list(prefix: 'save_'), [
        'save_1.json',
        'save_2.json',
      ]);
    });

    test('covers binary and text alike', () async {
      await storage.write('game.json', '{}');
      await storage.writeBytes('thumb.png', binary);

      expect(await storage.list(), ['game.json', 'thumb.png']);
    });

    test('returns an empty list when nothing is stored', () async {
      expect(await storage.list(), isEmpty);
    });

    test('a prefix matching nothing returns an empty list', () async {
      await storage.write('game.json', '{}');
      expect(await storage.list(prefix: 'save_'), isEmpty);
    });

    test('reflects a delete', () async {
      await storage.write('game.json', '{}');
      await storage.delete('game.json');
      expect(await storage.list(), isEmpty);
    });
  });

  group('binary entries behave like text entries', () {
    test('exists reports a binary entry', () async {
      await storage.writeBytes('thumb.png', binary);
      expect(await storage.exists('thumb.png'), isTrue);
    });

    test('delete removes a binary entry', () async {
      await storage.writeBytes('thumb.png', binary);
      await storage.delete('thumb.png');
      expect(await storage.exists('thumb.png'), isFalse);
    });

    test('rename moves a binary entry without altering it', () async {
      await storage.writeBytes('thumb.png', binary);
      await storage.rename('thumb.png', 'thumb.png.old');

      expect(await storage.exists('thumb.png'), isFalse);
      expect(await storage.readBytes('thumb.png.old'), binary);
    });
  });

  test('entries stays inspectable for tests that seed it directly', () async {
    // `services_save_test.dart` and the documented example both reach into
    // `entries` to seed or assert a raw document, so text has to be stored
    // verbatim rather than wrapped.
    await storage.write('game.json', '{"a":1}');
    expect(storage.entries['game.json'], '{"a":1}');

    storage.entries['damaged.json'] = 'not json';
    expect(await storage.read('damaged.json'), 'not json');
  });
}
