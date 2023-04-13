import 'dart:typed_data';
import 'dart:ui';

import '../game/game.dart';
import 'package:flame/components.dart';

class BitmapSpriteComponent extends SpriteComponent with HasGameRef<SizzleGame> {
  final Float64List _pixelSnapTransform =
      Float64List.fromList([1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]);
  final Vector2 _pixelSnapScale = Vector2.zero();

  /// Always snap position to the nearest whole pixel
  bool snap = true;

  void _setPixelScale() {
    scale.setFrom(gameRef.bitmapScale);
    _pixelSnapScale.setValues(1.0 / gameRef.bitmapScale.x, 1.0 / gameRef.bitmapScale.y);
  }

  @override
  void onMount() {
    super.onMount();
    _setPixelScale();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _setPixelScale();
  }

  @override
  void render(Canvas canvas) {
    if (snap) {
      _pixelSnapTransform[12] = -(position.x * _pixelSnapScale.x - (position.x * _pixelSnapScale.x).floor());
      _pixelSnapTransform[13] = -(position.y * _pixelSnapScale.y - (position.y * _pixelSnapScale.y).floor());
      canvas.save();
      canvas.transform(_pixelSnapTransform);
      super.render(canvas);
      canvas.restore();
    } else {
      super.render(canvas);
    }
  }
}
