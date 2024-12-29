import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';
import 'package:sizzle/sizzle.dart';

import 'package:flutter/widgets.dart';

/// Utility function for writing tests that require a [SizzleGame] instance.
///
/// This function creates a [SizzleGame] object, properly initializes it, then
/// passes on to the user-provided [testBody], and in the end disposes of the
/// game object.
///
/// Example of usage:
/// ```dart
/// testWithSizzleGame(
///   'MyComponent can be added to a game',
///   (game) async {
///     final component = MyComponent()..addToParent(game);
///     await game.ready();
///     expect(component.isMounted, true);
///   },
/// );
/// ```
///
/// The `game` instance supplied by this function to your [testBody] is a
/// standard [SizzleGame]. If you want to have any other game instance, use the
/// [testWithGame] function.
@isTest
Future<void> testWithSizzleGame(
  String testName,
  AsyncGameFunction<SizzleGame> testBody, {
  Timeout? timeout,
  dynamic tags,
  dynamic skip,
  Map<String, dynamic>? onPlatform,
  int? retry,
}) {
  return testWithGame<SizzleGame>(
    testName,
    SizzleGame.new,
    testBody,
    timeout: timeout,
    tags: tags,
    skip: skip,
    onPlatform: onPlatform,
    retry: retry,
  );
}

/// Utility function for writing tests that require a custom game instance.
///
/// This function [create]s the game instance, initializes it, then passes it
/// to the user-provided [testBody], and in the end disposes of the game object.
///
/// Example of usage:
/// ```dart
/// testWithGame<MyGame>(
///   'MyComponent can be added to MyGame',
///   () => MyGame(mySecret: 3781),
///   (MyGame game) async {
///     final component = MyComponent()..addToParent(game);
///     await game.ready();
///     expect(component.isMounted, true);
///   },
/// );
/// ```
@isTest
Future<void> testWithGame<T extends SizzleGame>(
  String testName,
  CreateFunction<T> create,
  AsyncGameFunction<T> testBody, {
  Timeout? timeout,
  dynamic tags,
  dynamic skip,
  Map<String, dynamic>? onPlatform,
  int? retry,
}) async {
  test(
    testName,
    () async {
      final game = await initializeGame<T>(create);
      await testBody(game);

      game.onRemove();
    },
    timeout: timeout,
    tags: tags,
    skip: skip,
    onPlatform: onPlatform,
    retry: retry,
  );
}

Future<T> initializeGame<T extends SizzleGame>(CreateFunction<T> create) async {
  final game = create();
  game.onGameResize(Vector2(800, 600));
  // ignore: invalid_use_of_internal_member
  await game.load();
  // ignore: invalid_use_of_internal_member
  game.mount();
  game.update(0);
  return game;
}

Future<SizzleGame> initializeSizzleGame() => initializeGame(SizzleGame.new);

typedef CreateFunction<T> = T Function();
typedef AsyncVoidFunction = Future<void> Function();
typedef AsyncGameFunction<T extends Game> = Future<void> Function(T game);

/// Test that a game renders correctly.
///
/// The way golden tests work is as follows: you set up a scene in [testBody],
/// then the test framework renders your game widget into an image, and compares
/// that image against stored [goldenFile]. The test passes if two images are
/// identical, or fails if the images differ even in a single pixel.
///
/// The term _golden file_ refers to the true rendering of a given game scene,
/// captured at the creation of the test. In order to create a golden file, you
/// first specify its desired name in the [goldenFile] parameter, and then run
/// the tests using the command
/// ```
/// flutter test --update-goldens
/// ```
///
/// The [testBody] is given a `game` parameter (which is by default a new
/// [SizzleGame] instance, but you can also supply your own [game] object), and
/// is expected to set up a scene for rendering. Usually this involves adding
/// necessary game components, and possibly advancing the game clock. As a
/// convenience, we will run `await game.ready()` before rendering, to ensure
/// that all components that might be pending are properly mounted.
///
/// The [size] parameter controls the size of the "device" on which the game
/// widget is rendered, if omitted it defaults to 2400x1800. This size will be
/// equal to the canvas size of the game.
@isTest
void testGolden(
  String testName,
  PrepareGameFunction testBody, {
  required String goldenFile,
  Vector2? size,
  SizzleGame? game,
  bool skip = false,
}) {
  testWidgets(
    testName,
    (tester) async {
      final gameInstance = game ?? SizzleGame();
      const myKey = ValueKey('game-instance');

      await tester.runAsync(() async {
        Widget widget = GameWidget(key: myKey, game: gameInstance);
        if (size != null) {
          widget = Center(
            child: SizedBox(
              width: size.x,
              height: size.y,
              child: RepaintBoundary(
                child: widget,
              ),
            ),
          );
        }
        await tester.pumpWidget(widget);
        await tester.pump();
        await testBody(gameInstance);
        await gameInstance.ready();
        await tester.pump();
      });

      await expectLater(
        find.byKey(myKey),
        matchesGoldenFile(goldenFile),
      );
    },
    skip: skip,
  );
}

typedef PrepareGameFunction = Future<void> Function(SizzleGame game);

/// The path to the goldens directory
String goldens =
    '${Directory.current.path.replaceAll(r'\', '/')}/test/_goldens';

/// A custom [AssetBundle] that reads files from a directory.
///
/// This is meant to be used in place of [rootBundle] for testing
class DiskAssetBundle extends CachingAssetBundle {
  static const _assetManifestDotJson = 'AssetManifest.json';

  /// Creates a [DiskAssetBundle] by loading files from [path].
  static Future<AssetBundle> loadFromPath(
    String path, {
    String? from,
  }) async {
    // Prepare the file search pattern
    path = _formatPath(path);
    String pattern = path;
    if (!pattern.endsWith('/')) {
      pattern += '/';
    }
    pattern += '**';

    // Load the assets
    final cache = <String, ByteData>{};
    await for (final entity in Glob(pattern).list(root: from)) {
      if (entity is File) {
        final bytes = await (entity as File).readAsBytes();

        // Keep only the asset name relative to the folder
        String name = _formatPath(entity.path);
        name = name.substring(name.indexOf(path) + path.length);
        cache[name] = ByteData.view(bytes.buffer);
      }
    }

    // Create the asset manifest
    final manifest = <String, List<String>>{};
    cache.forEach((key, _) {
      manifest[key] = [key];
    });
    cache[_assetManifestDotJson] = ByteData.view(
      Uint8List.fromList(jsonEncode(manifest).codeUnits).buffer,
    );

    return DiskAssetBundle._(cache);
  }

  /// Format a file path to only forward slashes
  static String _formatPath(String path) {
    return path.replaceAll(r'\', '/');
  }

  /// The cache of assets
  final Map<String, ByteData> _cache;

  /// Private constructor
  DiskAssetBundle._(this._cache);

  /// Load an asset from the cache
  @override
  Future<ByteData> load(String key) async {
    return _cache[key]!;
  }
}
