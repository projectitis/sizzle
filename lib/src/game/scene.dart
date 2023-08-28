import 'dart:ui';

import 'package:flame/components.dart';
import 'package:sizzle/src/game/game.dart';

class Scene extends Component with HasGameRef<SizzleGame> {
  bool paused = false;

  static Component create() => Scene();

  @override
  void update(double dt) {
    if (paused) return;
    super.update(dt);
  }

  @override
  void render(Canvas canvas) {
    if (paused) return;
    super.render(canvas);
  }

  void changeScene(String scene, {bool replace = false}) {
    gameRef.changeScene(scene);
  }
}
