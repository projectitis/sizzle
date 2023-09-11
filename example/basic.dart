import 'package:sizzle/sizzle.dart';

void main() {
  final game = SizzleGame(
    scenes: {
      'example': ExampleScene.create,
    },
    targetSize: Vector2(320, 240),
  );

  runApp(GameWidget(game: game));
}

class ExampleScene extends Scene {
  static Component create() => ExampleScene();
}
