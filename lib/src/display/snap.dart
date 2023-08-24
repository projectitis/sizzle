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
  /// Scale automatically to game.bitmapScale
  bool useBitmapScale = true;

  /// Always snap position to the nearest whole pixel
  bool snap = true;

  /// Always snap position to the nearest whole pixel
  Vector2 bitmapPosition = Vector2.zero();

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

  AnchorWindow get anchorWindow {
    return _anchorWindow;
  }

  set anchorWindow(AnchorWindow window) {
    _anchorWindow = window;
    _update();
  }

  void _update() {
    if (useBitmapScale) {
      scale = game.bitmapScale;
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
      _anchorOffset.x + (snap ? bitmapPosition.x.round() : bitmapPosition.x) * scale.x,
      _anchorOffset.y + (snap ? bitmapPosition.y.round() : bitmapPosition.y) * scale.y,
    );
    super.update(dt);
  }

  @override
  bool containsLocalPoint(Vector2 point) {
    point.setValues(
      point.x + game.gameWindowOffset.x / game.bitmapScale.x,
      point.y + game.gameWindowOffset.y / game.bitmapScale.y,
    );
    return super.containsLocalPoint(point);
  }
}

class BitmapSpriteComponent extends SpriteComponent with Snap {}
