import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sizzle/sizzle.dart';

import '../sizzle_test_helpers.dart';

/// A [MemorySaveStorage] with the hooks a test needs to provoke failures and
/// observe ordering. Kept here rather than on the shipped class - games have no
/// use for it.
class _TestStorage extends MemorySaveStorage {
  Object? throwOnRead;
  Object? throwOnWrite;
  Object? throwOnExists;
  Object? throwOnDelete;
  Object? throwOnRename;

  int writeCount = 0;

  /// Set while a write is in flight. If a second write ever starts while this
  /// is set, the operations were not serialised.
  bool writing = false;
  bool overlapped = false;

  @override
  Future<String?> read(String name) async {
    if (throwOnRead != null) throw throwOnRead!;
    return super.read(name);
  }

  @override
  Future<void> write(String name, String contents) async {
    if (throwOnWrite != null) throw throwOnWrite!;
    if (writing) overlapped = true;
    writing = true;
    writeCount++;
    // Yield, so an unserialised second write has a chance to interleave.
    await Future<void>.delayed(Duration.zero);
    await super.write(name, contents);
    writing = false;
  }

  @override
  Future<bool> exists(String name) async {
    if (throwOnExists != null) throw throwOnExists!;
    return super.exists(name);
  }

  @override
  Future<void> delete(String name) async {
    if (throwOnDelete != null) throw throwOnDelete!;
    return super.delete(name);
  }

  @override
  Future<void> rename(String from, String to) async {
    if (throwOnRename != null) throw throwOnRename!;
    return super.rename(from, to);
  }
}

void main() {
  const defaultFile = Services.defaultSaveFile;
  const corrupt = '$defaultFile.corrupt';

  late _TestStorage storage;
  late RecordingLogger logger;

  /// The document stored under [name], decoded.
  Map<String, dynamic> stored([String name = defaultFile]) =>
      json.decode(storage.entries[name]!) as Map<String, dynamic>;

  setUp(() {
    storage = _TestStorage();
    logger = RecordingLogger();
    Services.saveStorage = storage;
    Services.log = logger;
    Services.saveFile = Services.defaultSaveFile;
    Services.flags.clear();
    Services.dialog.yarn.variables.clear(clearNodeVisits: true);
    Services.onSave = (data) {};
    Services.onLoad = (data) {};
  });

  tearDown(() {
    Services.saveStorage = PlatformSaveStorage();
    Services.log = PrintLogger();
    Services.saveFile = Services.defaultSaveFile;
  });

  group('round trip', () {
    test('flags and yarn variables survive a save and load', () async {
      Services.flags['castle_key'] = true;
      Services.flags['bridge_repaired'] = true;
      Services.dialog.yarn.variables.setVariable(r'$gold', 42);
      Services.dialog.yarn.variables.setVariable(r'$name', 'Ada');
      Services.dialog.yarn.variables.setVariable(r'$met_king', true);

      expect(await Services.save(), isTrue);

      Services.flags.clear();
      Services.dialog.yarn.variables.clear(clearNodeVisits: true);

      expect(await Services.load(), isTrue);
      expect(Services.flags['castle_key'], isTrue);
      expect(Services.flags['bridge_repaired'], isTrue);
      final vars = Services.dialog.yarn.variables;
      expect(vars.getNumericValue(r'$gold'), 42);
      expect(vars.getStringValue(r'$name'), 'Ada');
      expect(vars.getBooleanValue(r'$met_king'), isTrue);
      expect(logger.errors, isEmpty);
      expect(logger.warnings, isEmpty);
    });

    test('node visit counts survive a round trip', () async {
      // Jenny prefixes node visit counts with @, and they are numbers.
      Services.dialog.yarn.variables.setVariable('@intro', 3);

      expect(await Services.save(), isTrue);
      Services.dialog.yarn.variables.clear(clearNodeVisits: true);
      expect(await Services.load(), isTrue);

      expect(Services.dialog.yarn.variables.getNumericValue('@intro'), 3);
    });

    test('load leaves flags alone when nothing is saved', () async {
      Services.flags['transient'] = true;

      expect(await Services.load(), isFalse);

      expect(Services.flags['transient'], isTrue);
      expect(logger.errors, isEmpty);
    });
  });

  group('damaged documents', () {
    test('invalid JSON is reported, not thrown', () async {
      storage.entries[defaultFile] = '{not json';
      Services.flags['existing'] = true;

      expect(await Services.load(), isFalse);

      expect(Services.flags['existing'], isTrue);
      expect(logger.errors, hasLength(1));
      expect(logger.errors.single, contains('not valid JSON'));
    });

    for (final document in ['[1,2]', '"x"', 'null', '5']) {
      test('a root that is $document is rejected', () async {
        storage.entries[defaultFile] = document;
        Services.flags['existing'] = true;

        expect(await Services.load(), isFalse);

        expect(Services.flags['existing'], isTrue);
        expect(logger.errors.single, contains('not an object'));
      });
    }

    test('a _flags that is not a list leaves existing flags intact', () async {
      // The regression test for the old behaviour: flags were cleared before
      // the list was read, so a bad document destroyed the running session.
      storage.entries[defaultFile] = '{"_flags":5}';
      Services.flags['existing'] = true;

      expect(await Services.load(), isFalse);

      expect(Services.flags['existing'], isTrue);
      expect(logger.errors.single, contains('not a list'));
    });

    test('a non-string flag is dropped, the rest load', () async {
      storage.entries[defaultFile] = '{"_flags":["good",7,"also_good"]}';

      expect(await Services.load(), isTrue);

      expect(Services.flags['good'], isTrue);
      expect(Services.flags['also_good'], isTrue);
      expect(Services.flags.flags, hasLength(2));
      expect(logger.warnings.single, contains('dropped a flag'));
    });

    test('a bad _yarn rejects the whole document, flags included', () async {
      // Proves validation completes before anything is committed.
      storage.entries[defaultFile] = '{"_flags":["a"],"_yarn":[1,2]}';

      expect(await Services.load(), isFalse);

      expect(Services.flags['a'], isFalse);
      expect(logger.errors.single, contains('not an object'));
    });

    test('yarn values of an unsupported type are dropped', () async {
      storage.entries[defaultFile] = json.encode({
        '_yarn': {
          r'$ok': 'fine',
          r'$nothing': null,
          r'$list': [1, 2],
          r'$map': {'a': 1},
        },
      });

      expect(await Services.load(), isTrue);

      final vars = Services.dialog.yarn.variables;
      expect(vars.getStringValue(r'$ok'), 'fine');
      expect(vars.hasVariable(r'$nothing'), isFalse);
      expect(vars.hasVariable(r'$list'), isFalse);
      expect(vars.hasVariable(r'$map'), isFalse);
      expect(logger.warnings, hasLength(3));

      // Fault 4: an unsupported value used to be accepted here and then throw
      // later, inside dialogue. Everything that survived must be usable.
      for (final name in vars.variables.keys) {
        expect(() => vars.getVariableAsExpression(name), returnsNormally);
      }
    });

    test('a rejected document is moved aside to .corrupt', () async {
      storage.entries[defaultFile] = '{not json';

      expect(await Services.load(), isFalse);

      expect(storage.entries.containsKey(defaultFile), isFalse);
      expect(storage.entries[corrupt], '{not json');
    });

    test('each save file gets its own .corrupt sibling', () async {
      storage.entries['slot2.json'] = '{not json';

      expect(await Services.load(name: 'slot2.json'), isFalse);

      expect(storage.entries['slot2.json.corrupt'], '{not json');
      expect(storage.entries.containsKey(corrupt), isFalse);
    });

    test('a failed move-aside leaves the file and does not throw', () async {
      storage.entries[defaultFile] = '{not json';
      storage.throwOnRename = StateError('read only');

      expect(await Services.load(), isFalse);

      expect(storage.entries[defaultFile], '{not json');
      expect(logger.errors, hasLength(1));
      expect(logger.warnings.single, contains('could not be moved aside'));
    });
  });

  group('storage failures', () {
    test('a read failure is reported, not thrown', () async {
      storage.throwOnRead = StateError('permission denied');

      expect(await Services.load(), isFalse);

      expect(logger.errors.single, contains('could not be read'));
    });

    test('a write failure is reported, not thrown', () async {
      storage.throwOnWrite = StateError('disk full');

      expect(await Services.save(), isFalse);

      expect(logger.errors.single, contains('could not be written'));
    });

    test('data that cannot be encoded fails without writing', () async {
      Services.flags['before'] = true;
      expect(await Services.save(), isTrue);
      final good = storage.entries[defaultFile];

      Services.onSave = (data) => data['stamp'] = Object();

      expect(await Services.save(), isFalse);

      // The previous good save must survive an encode failure untouched.
      expect(storage.entries[defaultFile], good);
      expect(logger.errors.single, contains('cannot be encoded as JSON'));
    });

    test('a failed save does not poison later ones', () async {
      // The document that failed to encode must not be kept in memory, or
      // every later save of this file would fail the same way.
      Services.onSave = (data) => data['stamp'] = Object();
      expect(await Services.save(), isFalse);

      Services.onSave = (data) {};
      Services.flags['after'] = true;
      expect(await Services.save(), isTrue);

      expect(stored()['_flags'], ['after']);
      expect(stored().containsKey('stamp'), isFalse);
    });

    test('a failed exists check reports false', () async {
      storage.throwOnExists = StateError('nope');

      expect(await Services.hasSave(), isFalse);

      expect(logger.errors.single, contains('could not be checked'));
    });
  });

  group('callbacks', () {
    test('onSave and onLoad round-trip custom data', () async {
      Services.onSave = (data) => data['hi_score'] = 4200;
      expect(await Services.save(), isTrue);

      int? restored;
      Services.onLoad = (data) => restored = data['hi_score'] as int?;
      expect(await Services.load(), isTrue);

      expect(restored, 4200);
    });

    test('onLoad runs after flags have been restored', () async {
      Services.flags['castle_key'] = true;
      await Services.save();
      Services.flags.clear();

      bool? sawFlag;
      Services.onLoad = (_) => sawFlag = Services.flags['castle_key'];
      await Services.load();

      expect(sawFlag, isTrue);
    });

    test('onSave cannot corrupt the flag list', () async {
      Services.flags['real'] = true;
      Services.onSave = (data) => (data['_flags'] as List).add('injected');

      expect(await Services.save(), isTrue);

      expect(Services.flags['injected'], isFalse);
      expect(Services.flags.flags, ['real']);
    });

    test('the flag list itself cannot be mutated', () {
      Services.flags['real'] = true;
      final flags = Services.flags.flags;
      expect(() => flags.add('injected'), throwsUnsupportedError);
    });
  });

  group('save files', () {
    test('name overrides saveFile without changing it', () async {
      Services.flags['castle_key'] = true;

      expect(await Services.save(name: 'slot2.json'), isTrue);

      expect(Services.saveFile, defaultFile);
      expect(storage.entries.containsKey(defaultFile), isFalse);
      expect(storage.entries['slot2.json'], contains('castle_key'));

      Services.flags.clear();
      expect(await Services.load(), isFalse);
      expect(Services.flags['castle_key'], isFalse);

      expect(await Services.load(name: 'slot2.json'), isTrue);
      expect(Services.flags['castle_key'], isTrue);
    });

    test('an omitted name uses saveFile', () async {
      Services.saveFile = 'slot3.json';
      expect(await Services.save(), isTrue);

      expect(storage.entries.containsKey('slot3.json'), isTrue);
      expect(storage.entries.containsKey(defaultFile), isFalse);
    });

    test('custom keys do not leak across files via saveFile', () async {
      Services.onSave = (data) => data.putIfAbsent('slot1_only', () => true);
      await Services.save();

      Services.onSave = (data) {};
      Services.saveFile = 'slot2.json';
      await Services.save();

      expect(stored('slot2.json').containsKey('slot1_only'), isFalse);
      expect(stored().containsKey('slot1_only'), isTrue);
    });

    test('custom keys do not leak across files via name', () async {
      Services.onSave = (data) => data.putIfAbsent('slot1_only', () => true);
      await Services.save();

      Services.onSave = (data) {};
      await Services.save(name: 'slot2.json');

      expect(stored('slot2.json').containsKey('slot1_only'), isFalse);
      expect(stored().containsKey('slot1_only'), isTrue);
    });

    test('unknown keys survive a load and re-save of the same file', () async {
      // Forward compatibility: a document written by a newer version of the
      // game must not lose its keys when an older version re-saves.
      storage.entries[defaultFile] = json.encode({
        '_flags': ['a'],
        'from_the_future': 99,
      });

      expect(await Services.load(), isTrue);
      expect(await Services.save(), isTrue);

      expect(stored()['from_the_future'], 99);
    });
  });

  group('hasSave and deleteSave', () {
    test('hasSave reports whether a document is stored', () async {
      expect(await Services.hasSave(), isFalse);
      await Services.save();
      expect(await Services.hasSave(), isTrue);
      expect(await Services.hasSave(name: 'slot2.json'), isFalse);
    });

    test('hasSave is true for a damaged document', () async {
      storage.entries[defaultFile] = '{not json';
      expect(await Services.hasSave(), isTrue);
    });

    test('deleteSave removes the document', () async {
      await Services.save();
      expect(await Services.deleteSave(), isTrue);
      expect(await Services.hasSave(), isFalse);
    });

    test('deleteSave succeeds when there is nothing to delete', () async {
      expect(await Services.deleteSave(), isTrue);
    });

    test('a save after deleteSave does not restore the old keys', () async {
      Services.onSave = (data) => data.putIfAbsent('old', () => true);
      await Services.save();

      Services.onSave = (data) {};
      await Services.deleteSave();
      await Services.save();

      expect(stored().containsKey('old'), isFalse);
    });

    test('a delete failure is reported, not thrown', () async {
      storage.throwOnDelete = StateError('nope');

      expect(await Services.deleteSave(), isFalse);

      expect(logger.errors.single, contains('could not be deleted'));
    });
  });

  group('serialisation', () {
    test('overlapping saves do not interleave', () async {
      Services.flags['first'] = true;
      final a = Services.save();
      Services.flags['second'] = true;
      final b = Services.save();

      expect(await Future.wait([a, b]), [true, true]);

      expect(storage.overlapped, isFalse);
      expect(storage.writeCount, 2);
      // Both writes happened, and the last one wins.
      expect(stored()['_flags'], containsAll(['first', 'second']));
    });

    test('a save records the state as of the call, not of the write', () async {
      // The write is queued, but the document is captured synchronously, so
      // changing state after calling save does not change what gets written.
      Services.flags['castle_key'] = true;
      final saving = Services.save();
      Services.flags.clear();

      expect(await saving, isTrue);
      expect(stored()['_flags'], ['castle_key']);
    });

    test('a load queued behind a save sees the saved document', () async {
      Services.flags['castle_key'] = true;
      final saving = Services.save();
      final loading = Services.load();
      Services.flags.clear();

      expect(await saving, isTrue);
      expect(await loading, isTrue);
      expect(Services.flags['castle_key'], isTrue);
    });

    test('a failed save does not block the next one', () async {
      storage.throwOnWrite = StateError('disk full');
      expect(await Services.save(), isFalse);

      storage.throwOnWrite = null;
      expect(await Services.save(), isTrue);
    });
  });
}
