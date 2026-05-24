import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sizzle/sizzle.dart';

import '../sizzle_test_helpers.dart';

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final AssetBundle assets =
      await DiskAssetBundle.loadFromPath('test/_resources/');
  final FileService files = FileService('', assetBundle: assets);
  final String configSource =
      await files.loadString(path: 'test.config.jx', cache: false);

  group('Config flattening (test.config.jx)', () {
    test('Empty capabilities returns the section defaults', () {
      final config = Config.parse(configSource);
      expect(config.asStr('section1Name.property1Name'), 'default');
      expect(config.asStr('section1Name.property2Name'), 'default');
      expect(config.asStr('section1Name.property3Name'), 'default');
      expect(config.asStr('section2Name.property1Name'), 'default');
    });

    test('A single matching modifier overrides matching keys only', () {
      final config = Config.parse(configSource, const {'mobile': true});
      // #mobile overrides property1Name; property3Name has no override
      expect(config.asStr('section1Name.property1Name'), 'mobile');
      expect(config.asStr('section1Name.property3Name'), 'default');
    });

    test('Mobile + landscape: nested #landscape inside #mobile wins over '
        'the top-level #landscape (last-write document order)', () {
      final config = Config.parse(
        configSource,
        const {'mobile': true, 'landscape': true},
      );
      expect(config.asStr('section1Name.property2Name'), 'landscape');
      expect(config.asStr('section1Name.property1Name'), 'mobile');
    });

    test('Tablet + portrait: only matching nested block applies', () {
      final config = Config.parse(
        configSource,
        const {'tablet': true, 'portrait': true},
      );
      expect(config.asStr('section1Name.property1Name'), 'mobile');
      expect(config.asStr('section1Name.property2Name'), 'portrait');
    });

    test('Watch overrides property1Name but not property2Name', () {
      final config = Config.parse(configSource, const {'watch': true});
      expect(config.asStr('section1Name.property1Name'), 'watch');
      expect(config.asStr('section1Name.property2Name'), 'default');
    });

    test('Raw object value is returned literally (not entered for modifiers)',
        () {
      final config = Config.parse(configSource, const {'mobile': true});
      final raw = config['section2Name.rawPropertyExample'];
      expect(raw, isNotNull);
      // #mobile overrides the whole object
      expect(raw['value'], 0.25);
      expect(raw['ref'], 'viewBL');
    });

    test('Modifier name with value false is treated as inactive', () {
      final config = Config.parse(
        configSource,
        const {'mobile': false, 'watch': true},
      );
      expect(config.asStr('section1Name.property1Name'), 'watch');
    });

    test('Unknown modifier names in capabilities are simply ignored', () {
      final config = Config.parse(
        configSource,
        const {'flibbertigibbet': true, 'mobile': true},
      );
      expect(config.asStr('section1Name.property1Name'), 'mobile');
    });
  });

  group('Capabilities setter / onChange', () {
    test('Assigning new capabilities re-flattens and fires onChange once', () {
      final config = Config.parse(configSource);
      expect(config.asStr('section1Name.property1Name'), 'default');

      var calls = 0;
      config.onChange = () => calls++;
      config.capabilities = const {'mobile': true};

      expect(config.asStr('section1Name.property1Name'), 'mobile');
      expect(calls, 1);
    });

    test('Assigning equivalent capabilities is a no-op (onChange not fired)',
        () {
      final config = Config.parse(configSource, const {'mobile': true});
      var calls = 0;
      config.onChange = () => calls++;
      // Same effective state — explicit false matches missing key.
      config.capabilities = const {'mobile': true, 'landscape': false};
      expect(calls, 0);
    });

    test('capabilities getter returns the current value', () {
      final config = Config.parse(configSource);
      expect(config.capabilities, isEmpty);
      config.capabilities = const {'landscape': true};
      expect(config.capabilities, const {'landscape': true});
    });
  });

  group('Typed accessors', () {
    final src = '''
      {
        nums: {
          i: 5;
          d: 5.5;
          iAsDouble: 5.0;
        };
        bools: {
          t: true;
          f: false;
        };
        strs: {
          s: 'hello';
        };
      }
    ''';

    test('asInt accepts int and truncates double', () {
      final config = Config.parse(src);
      expect(config.asInt('nums.i'), 5);
      expect(config.asInt('nums.d'), 5);
      expect(config.asInt('nums.iAsDouble'), 5);
    });

    test('asDouble accepts double and widens int', () {
      final config = Config.parse(src);
      expect(config.asDouble('nums.d'), 5.5);
      expect(config.asDouble('nums.i'), 5.0);
    });

    test('asBool is strict and only accepts bool', () {
      final config = Config.parse(src);
      expect(config.asBool('bools.t'), isTrue);
      expect(config.asBool('bools.f'), isFalse);
      expect(
        () => config.asBool('strs.s'),
        throwsArgumentError,
      );
    });

    test('asStr is strict and only accepts String', () {
      final config = Config.parse(src);
      expect(config.asStr('strs.s'), 'hello');
      expect(
        () => config.asStr('nums.i'),
        throwsArgumentError,
      );
    });

    test('Missing key returns defaultValue (or null)', () {
      final config = Config.parse(src);
      expect(config.asStr('strs.missing'), isNull);
      expect(
        config.asStr('strs.missing', defaultValue: 'fallback'),
        'fallback',
      );
      expect(config.asInt('nums.missing', defaultValue: 42), 42);
      expect(config.asDouble('nums.missing', defaultValue: 1.5), 1.5);
      expect(config.asBool('bools.missing', defaultValue: true), isTrue);
      expect(config['missingSection.missingProp'], isNull);
    });

    test('Missing section also returns defaultValue', () {
      final config = Config.parse(src);
      expect(config.asInt('noSuchSection.anything'), isNull);
      expect(
        config.asInt('noSuchSection.anything', defaultValue: 9),
        9,
      );
    });
  });

  group('asOffset', () {
    final src = '''
      {
        offsets: {
          zero: 0.0;
          one: 1.0;
          negOne: -1.0;
          half: 0.5;
          userExample: -0.2;
          aboveOne: 2.0;
          belowNegOne: -2.0;
          asInt: 5;
        };
        bad: {
          notNum: 'oops';
        };
      }
    ''';

    test('Value 0 returns min, 1 returns max', () {
      final config = Config.parse(src);
      expect(config.asOffset('offsets.zero', 100, 200), 100);
      expect(config.asOffset('offsets.one', 100, 200), 200);
    });

    test('Value 0.5 lerps to the midpoint', () {
      final config = Config.parse(src);
      expect(config.asOffset('offsets.half', 100, 200), 150);
    });

    test('User example: -0.2 with min=100, max=200 returns 180', () {
      final config = Config.parse(src);
      expect(config.asOffset('offsets.userExample', 100, 200), 180);
    });

    test('Value -1 returns min (lerp from max all the way back)', () {
      final config = Config.parse(src);
      expect(config.asOffset('offsets.negOne', 100, 200), 100);
    });

    test('Value > 1 returns min + value', () {
      final config = Config.parse(src);
      expect(config.asOffset('offsets.aboveOne', 100, 200), 102);
    });

    test('Value < -1 returns max + value', () {
      final config = Config.parse(src);
      expect(config.asOffset('offsets.belowNegOne', 100, 200), 198);
    });

    test('Accepts int via asDouble widening', () {
      final config = Config.parse(src);
      // value=5 > 1 → min + 5
      expect(config.asOffset('offsets.asInt', 100, 200), 105);
    });

    test('Missing key returns defaultValue (or null)', () {
      final config = Config.parse(src);
      expect(config.asOffset('offsets.missing', 100, 200), isNull);
      expect(
        config.asOffset('offsets.missing', 100, 200, defaultValue: 42),
        42,
      );
    });

    test('Non-numeric value throws ArgumentError', () {
      final config = Config.parse(src);
      expect(
        () => config.asOffset('bad.notNum', 0, 1),
        throwsArgumentError,
      );
    });
  });

  group('operator[] path validation', () {
    final config = Config.parse('{ a: { b: 1; }; }');

    test('accepts exactly one dot', () {
      expect(config['a.b'], 1);
    });

    test('rejects no-dot path', () {
      expect(() => config['a'], throwsArgumentError);
    });

    test('rejects multi-dot path', () {
      expect(() => config['a.b.c'], throwsArgumentError);
    });

    test('rejects empty parts', () {
      expect(() => config['.b'], throwsArgumentError);
      expect(() => config['a.'], throwsArgumentError);
      expect(() => config['.'], throwsArgumentError);
      expect(() => config[''], throwsArgumentError);
    });
  });

  group('Structural violations', () {
    test('Property at root throws FormatException', () {
      expect(
        () => Config.parse('{ rootProp: "oops"; section: { a: 1; }; }'),
        throwsA(isA<FormatException>()),
      );
    });

    test('Modifier at root throws FormatException', () {
      expect(
        () => Config.parse('{ #mobile: { section: { a: 1; }; }; }'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Unknown modifier', () {
    test('Silently skipped (block does not apply, no throw)', () {
      final config = Config.parse('''
        {
          section: {
            prop: 'default';
            #foobar: { prop: 'unknown-modifier'; };
          };
        }
      ''');
      expect(config.asStr('section.prop'), 'default');
    });
  });

  group('asPos', () {
    // Game configured so the three windows have distinct bounds. With
    // canvas 800x600, targetSize 160x120, maxSize 320x240 the auto-fit
    // scale is 5, producing (left, top, right, bottom):
    //   viewWindow  = (   0,   0,  800,  600)  width  800, height 600
    //   safeWindow  = ( 400, 300, 1200,  900)  width  800, height 600
    //   gameWindow  = ( 400, 300, 2000, 1500)  width 1600, height 1200
    SizzleGame buildGame() => SizzleGame(
          scene: Scene.new,
          targetSize: Vector2(160, 120),
          maxSize: Vector2(320, 240),
        );

    final src = '''
      {
        positions: {
          centerView:   { x:  0.5; y:  0.5; };
          centerTarget: { x:  0.5; y:  0.5; window: 'target'; };
          centerMax:    { x:  0.5; y:  0.5; window: 'max'; };
          bogusWindow:  { x:  0.5; y:  0.5; window: 'nope'; };
          missingXY:    { };
          partial:      { x: 0.5; };
          offsets:      { x:  2.0; y: -2.0; };
          asInt:        { x:  1; y:  0; };
          notObject:    'hi';
          badX:         { x: 'oops'; y: 0.5; };
        };
      }
    ''';

    testWithGame<SizzleGame>(
      'Default window (view): { x: 0.5, y: 0.5 } returns the view centre',
      buildGame,
      (game) async {
        final config = Config.parse(src);
        expect(config.asPos('positions.centerView'), Vector2(400, 300));
      },
    );

    testWithGame<SizzleGame>(
      "window: 'target' resolves against safeWindow",
      buildGame,
      (game) async {
        final config = Config.parse(src);
        expect(config.asPos('positions.centerTarget'), Vector2(800, 600));
      },
    );

    testWithGame<SizzleGame>(
      "window: 'max' resolves against gameWindow",
      buildGame,
      (game) async {
        final config = Config.parse(src);
        expect(config.asPos('positions.centerMax'), Vector2(1200, 900));
      },
    );

    testWithGame<SizzleGame>(
      'Unrecognised window string falls back to viewWindow',
      buildGame,
      (game) async {
        final config = Config.parse(src);
        expect(config.asPos('positions.bogusWindow'), Vector2(400, 300));
      },
    );

    testWithGame<SizzleGame>(
      'Missing x and y both default to 0 (window min)',
      buildGame,
      (game) async {
        final config = Config.parse(src);
        // viewWindow.left = 0, viewWindow.top = 0
        expect(config.asPos('positions.missingXY'), Vector2(0, 0));
      },
    );

    testWithGame<SizzleGame>(
      'Missing one axis defaults that axis to 0',
      buildGame,
      (game) async {
        final config = Config.parse(src);
        // x=0.5 -> 400, y missing -> 0
        expect(config.asPos('positions.partial'), Vector2(400, 0));
      },
    );

    testWithGame<SizzleGame>(
      'Values outside [-1, 1] use the asOffset min+v / max+v rules',
      buildGame,
      (game) async {
        final config = Config.parse(src);
        // x = 2.0 (>1) -> viewWindow.left + 2 = 2
        // y = -2.0 (<-1) -> viewWindow.bottom - 2 = 598
        expect(config.asPos('positions.offsets'), Vector2(2, 598));
      },
    );

    testWithGame<SizzleGame>(
      'Int x/y widen to double',
      buildGame,
      (game) async {
        final config = Config.parse(src);
        // x = 1 (in [0,1]) -> viewWindow.right = 800
        // y = 0 -> viewWindow.top = 0
        expect(config.asPos('positions.asInt'), Vector2(800, 0));
      },
    );

    testWithGame<SizzleGame>(
      'Missing key returns defaultValue (or null)',
      buildGame,
      (game) async {
        final config = Config.parse(src);
        expect(config.asPos('positions.missing'), isNull);
        expect(
          config.asPos('positions.missing', defaultValue: Vector2.zero()),
          Vector2.zero(),
        );
      },
    );

    testWithGame<SizzleGame>(
      'Non-object value throws ArgumentError',
      buildGame,
      (game) async {
        final config = Config.parse(src);
        expect(
          () => config.asPos('positions.notObject'),
          throwsArgumentError,
        );
      },
    );

    testWithGame<SizzleGame>(
      'Non-numeric axis throws ArgumentError',
      buildGame,
      (game) async {
        final config = Config.parse(src);
        expect(
          () => config.asPos('positions.badX'),
          throwsArgumentError,
        );
      },
    );
  });
}
