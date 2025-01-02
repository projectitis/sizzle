import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sizzle/sizzle.dart';

import 'package:flutter/painting.dart';

import '../sizzle_test_helpers.dart';

class TestScene extends Scene {
  static Component create() => TestScene();
}

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
        scene: Scene.create,
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
        scene: Scene.create,
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
        scene: Scene.create,
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
        scene: Scene.create,
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
        scene: Scene.create,
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
        scene: Scene.create,
        targetSize: Vector2(150, 100),
        letterBoxColor: const Color.fromARGB(255, 9, 60, 78),
      ),
      size: Vector2(300, 200),
      goldenFile: '$goldens/game-resize.png',
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
        scene: Scene.create,
        targetSize: Vector2(150, 100),
        letterBoxColor: const Color.fromARGB(255, 9, 60, 78),
        scaleToWholePixels: true,
      ),
      size: Vector2(300, 200),
      goldenFile: '$goldens/game-resize-whole-pixels.png',
    );
  });
}
