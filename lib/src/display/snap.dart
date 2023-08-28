import 'dart:ui';

import 'package:flame/components.dart';

import 'package:sizzle/src/game/services.dart';
import 'package:sizzle/src/game/game.dart';

enum AnchorWindow {
  /// The maximum game window (some parts may not be visible)
  gameWindow,

  /// The viewable game area. Somewhere between game and safe window
  viewWindow,

  /// The smallest visible area, always guaranteed to be visible
  safeWindow,
}

mixin Snap on PositionComponent {
  /// Scale automatically to game.snapScale
  bool useSnapScale = true;

  /// Always snap position to the nearest whole pixel
  bool snap = true;

  /// Always snap position to the nearest whole pixel
  Vector2 snapPosition = Vector2.zero();

  /// Where to base coordinates on
  AnchorWindow _anchorWindow = AnchorWindow.gameWindow;

  /// Calculations for anchor window
  final Vector2 _anchorOffset = Vector2.zero();

  /// Getter for game instance
  SizzleGame get game => Services.game;

  @override
  void onMount() {
    super.onMount();
    _update();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _update();
  }

  AnchorWindow get anchorWindow => _anchorWindow;
  set anchorWindow(AnchorWindow window) {
    _anchorWindow = window;
    _update();
  }

  void _update() {
    if (useSnapScale) {
      scale = game.snapScale;
    }
    switch (anchorWindow) {
      case AnchorWindow.safeWindow:
        _anchorOffset.setValues(
          game.safeWindow.left,
          game.safeWindow.top,
        );
        break;
      case AnchorWindow.viewWindow:
        _anchorOffset.setValues(
          game.gameWindow.left,
          game.gameWindow.top,
        );
        break;
      case AnchorWindow.gameWindow:
      default:
        _anchorOffset.setZero();
        break;
    }
    if (snap) {
      _anchorOffset.setValues(
        (_anchorOffset.x / scale.x).round() * scale.x,
        (_anchorOffset.y / scale.y).round() * scale.y,
      );
    }
  }

  @override
  void update(double dt) {
    position.setValues(
      _anchorOffset.x + (snap ? snapPosition.x.round() : snapPosition.x) * scale.x,
      _anchorOffset.y + (snap ? snapPosition.y.round() : snapPosition.y) * scale.y,
    );
    super.update(dt);
  }

  @override
  bool containsLocalPoint(Vector2 point) {
    point.setValues(
      point.x + game.gameWindowOffset.x / game.snapScale.x,
      point.y + game.gameWindowOffset.y / game.snapScale.y,
    );
    return super.containsLocalPoint(point);
  }
}

class SnapSpriteComponent extends SpriteComponent with Snap {
  SnapSpriteComponent({
    Sprite? sprite,
    bool? autoResize,
    Paint? paint,
    super.position,
    Vector2? size,
    super.scale,
    super.angle,
    super.nativeAngle,
    super.anchor,
    super.children,
    super.priority,
    super.key,
  }) : super(sprite: sprite, autoResize: autoResize, paint: paint, size: size);
}
