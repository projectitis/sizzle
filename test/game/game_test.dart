import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sizzle/sizzle.dart';

import 'package:flutter/painting.dart';

import '../sizzle_test_helpers.dart';

class TestScene extends Scene {}

class LeveledScene extends Scene {
  LeveledScene(this.level);
  final int level;
}

class SceneA extends Scene {}

class SceneB extends Scene {}

class SceneC extends Scene {}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  AssetBundle assets = await DiskAssetBundle.loadFromPath('test/_resources/');

  group('SizzleGame', () {
    ImageService imageService = ImageService('', assetBundle: assets);

    tearDown(() {
      imageService.clear();
    });

    testGolden(
      'Scale to full screen',
      (game) async {
        final scene = game.currentScene!;
        final rect = SnapRectangleComponent(
          size: Vector2(148, 98),
          paint: Paint()..color = const Color.fromARGB(255, 25, 111, 131),
        );
        rect.position = Vector2(1, 1);
        scene.add(rect);
      },
      game: SizzleGame(
        scene: Scene.new,
        targetSize: Vector2(150, 100),
      ),
      size: Vector2(300, 200),
      goldenFile: '$goldens/game-default.png',
    );

    testGolden(
      'Scale to full screen with letterbox',
      (game) async {
        final scene = game.currentScene!;
        final rect = SnapRectangleComponent(
          size: Vector2(148, 98),
          paint: Paint()..color = const Color.fromARGB(255, 25, 111, 131),
        );
        rect.position = Vector2(1, 1);
        scene.add(rect);
      },
      game: SizzleGame(
        scene: Scene.new,
        targetSize: Vector2(150, 100),
        letterBoxColor: const Color.fromARGB(255, 9, 60, 78),
      ),
      size: Vector2(300, 240),
      goldenFile: '$goldens/game-letterbox.png',
    );

    testGolden(
      'Scale to whole pixels',
      (game) async {
        final scene = game.currentScene!;
        final rect = SnapRectangleComponent(
          size: Vector2(78, 48),
          paint: Paint()..color = const Color.fromARGB(255, 25, 111, 131),
        );
        rect.position = Vector2(1, 1);
        scene.add(rect);

        final sprite = SpriteComponent.fromImage(
          await imageService.load(path: 'sizzle-icon-16.png'),
          position: Vector2(30, 20),
        );
        rect.add(sprite);
      },
      game: SizzleGame(
        scene: Scene.new,
        targetSize: Vector2(80, 50),
        scaleToWholePixels: true,
        letterBoxColor: const Color.fromARGB(255, 9, 60, 78),
      ),
      size: Vector2(300, 240),
      goldenFile: '$goldens/game-whole-pixels.png',
    );

    testGolden(
      'Maximum scale',
      (game) async {
        final scene = game.currentScene!;
        final rect = SnapRectangleComponent(
          size: Vector2(78, 48),
          paint: Paint()..color = const Color.fromARGB(255, 25, 111, 131),
        );
        rect.position = Vector2(1, 1);
        scene.add(rect);

        final sprite = SpriteComponent.fromImage(
          await imageService.load(path: 'sizzle-icon-16.png'),
          position: Vector2(30, 20),
        );
        rect.add(sprite);
      },
      game: SizzleGame(
        scene: Scene.new,
        targetSize: Vector2(80, 50),
        letterBoxColor: const Color.fromARGB(255, 9, 60, 78),
        scale: Range(1.0, 2.5),
      ),
      size: Vector2(300, 240),
      goldenFile: '$goldens/game-max-scale.png',
    );

    testGolden(
      'Minimum scale',
      (game) async {
        final scene = game.currentScene!;
        final rect = SnapRectangleComponent(
          size: Vector2(78, 48),
          paint: Paint()..color = const Color.fromARGB(255, 25, 111, 131),
        );
        rect.position = Vector2(1, 1);
        scene.add(rect);

        final sprite = SpriteComponent.fromImage(
          await imageService.load(path: 'sizzle-icon-16.png'),
          position: Vector2(30, 20),
        );
        rect.add(sprite);
      },
      game: SizzleGame(
        scene: Scene.new,
        targetSize: Vector2(80, 50),
        letterBoxColor: const Color.fromARGB(255, 9, 60, 78),
        scale: Range(4.0, 10.0),
      ),
      size: Vector2(300, 240),
      goldenFile: '$goldens/game-min-scale.png',
    );

    testGolden(
      'Resize',
      (game) async {
        final scene = game.currentScene!;
        final rect = SnapRectangleComponent(
          size: Vector2(148, 98),
          paint: Paint()..color = const Color.fromARGB(255, 25, 111, 131),
        );
        rect.position = Vector2(1, 1);
        scene.add(rect);

        game.onGameResize(Vector2(250, 150));
      },
      game: SizzleGame(
        scene: Scene.new,
        targetSize: Vector2(150, 100),
        letterBoxColor: const Color.fromARGB(255, 9, 60, 78),
      ),
      size: Vector2(300, 200),
      goldenFile: '$goldens/game-resize.png',
    );

    testWithGame<SizzleGame>(
      'Custom factory passes constructor arguments to the scene',
      () => SizzleGame(
        scenes: {
          'level': () => LeveledScene(42),
        },
        targetSize: Vector2(150, 100),
      ),
      (game) async {
        await game.ready();
        final scene = game.currentScene;
        expect(scene, isA<LeveledScene>());
        expect((scene! as LeveledScene).level, 42);
      },
    );

    testWithGame<SizzleGame>(
      'Custom factory is invoked once per scene mount',
      () {
        int callCount = 0;
        return SizzleGame(
          scenes: {
            'counted': () {
              callCount++;
              return LeveledScene(callCount);
            },
          },
          targetSize: Vector2(150, 100),
        );
      },
      (game) async {
        await game.ready();
        final scene = game.currentScene;
        expect(scene, isA<LeveledScene>());
        expect((scene! as LeveledScene).level, 1);
      },
    );

    testWithGame<SizzleGame>(
      'changeScene pushes the new scene on top by default',
      () => SizzleGame(
        scenes: {
          'a': SceneA.new,
          'b': SceneB.new,
        },
        targetSize: Vector2(150, 100),
      ),
      (game) async {
        await game.ready();
        expect(game.router.stack.length, 1);
        expect(game.currentScene, isA<SceneA>());

        game.changeScene('b');
        await game.ready();

        expect(game.router.stack.length, 2);
        expect(game.currentScene, isA<SceneB>());
      },
    );

    testWithGame<SizzleGame>(
      'changeScene with replace: true swaps the top route in place',
      () => SizzleGame(
        scenes: {
          'a': SceneA.new,
          'b': SceneB.new,
          'c': SceneC.new,
        },
        targetSize: Vector2(150, 100),
      ),
      (game) async {
        await game.ready();
        game.changeScene('b');
        await game.ready();
        expect(game.router.stack.length, 2);

        game.changeScene('c', replace: true);
        await game.ready();

        expect(game.router.stack.length, 2);
        expect(game.currentScene, isA<SceneC>());
        expect(game.router.stack.first.name, 'a');
      },
    );

    testWithGame<SizzleGame>(
      'Scene.changeScene forwards replace to the game',
      () => SizzleGame(
        scenes: {
          'a': SceneA.new,
          'b': SceneB.new,
          'c': SceneC.new,
        },
        targetSize: Vector2(150, 100),
      ),
      (game) async {
        await game.ready();
        game.currentScene!.changeScene('b');
        await game.ready();
        expect(game.router.stack.length, 2);

        game.currentScene!.changeScene('c', replace: true);
        await game.ready();

        expect(game.router.stack.length, 2);
        expect(game.currentScene, isA<SceneC>());
      },
    );

    testGolden(
      'Resize with whole pixels',
      (game) async {
        final scene = game.currentScene!;
        final rect = SnapRectangleComponent(
          size: Vector2(148, 98),
          paint: Paint()..color = const Color.fromARGB(255, 25, 111, 131),
        );
        rect.position = Vector2(1, 1);
        scene.add(rect);

        game.onGameResize(Vector2(250, 150));
      },
      game: SizzleGame(
        scene: Scene.new,
        targetSize: Vector2(150, 100),
        letterBoxColor: const Color.fromARGB(255, 9, 60, 78),
        scaleToWholePixels: true,
      ),
      size: Vector2(300, 200),
      goldenFile: '$goldens/game-resize-whole-pixels.png',
    );
  });
}
