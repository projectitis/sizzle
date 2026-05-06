import 'package:sizzle/sizzle.dart';

void main() {
  final game = SizzleGame(
    scenes: {
      'example': ExampleScene.new,
    },
    targetSize: Vector2(320, 240),
  );

  runApp(GameWidget(game: game));
}

class ExampleScene extends Scene {}
