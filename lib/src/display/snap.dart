import 'package:flame/components.dart';

import '../utils/services.dart';
import '../game/game.dart';

enum AnchorWindow {
  /// The maximum game window (some parts may not be visible). This
  /// corresponds to the `maxSize` passed in to the `SizzleGame`
  /// constructor.
  maxWindow,

  /// The currently viewable game area. Somewhere between game and target
  /// window. On platforms that allow resizing the screen, this window can
  /// change zie throughout the lifetime of the game. This window is best
  /// used for aligning UI elements.
  viewWindow,

  /// The smallest visible area, always guaranteed to be visible. This
  /// corresponds to the `targetSize` passed in to the `SizzleGame`
  /// constructor.
  targetWindow,
}

mixin Snap on PositionComponent {
  /// Scale automatically to game.snapScale
  bool useSnapScale = true;

  /// Always snap position to the nearest whole pixel
  bool useSnap = true;

  /// Always snap position to the nearest whole pixel
  final Vector2 _snapPosition = Vector2.zero();

  /// Where to base coordinates on
  AnchorWindow _anchorWindow = AnchorWindow.maxWindow;

  /// Calculations for anchor window
  final Vector2 _anchorOffset = Vector2.zero();

  /// Getter for game instance
  SizzleGame get game => Services.game;

  @override
  set position(Vector2 position) {
    super.position = position;
    if (useSnap) {
      _snapPosition.setFrom(position);
    }
  }

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
      case AnchorWindow.targetWindow:
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
      case AnchorWindow.maxWindow:
        _anchorOffset.setZero();
        break;
    }
    if (useSnap) {
      _anchorOffset.setValues(
        (_anchorOffset.x / scale.x).round() * scale.x,
        (_anchorOffset.y / scale.y).round() * scale.y,
      );
    }
  }

  @override
  void update(double dt) {
    position.setValues(
      _anchorOffset.x +
          (useSnap ? _snapPosition.x.round() : _snapPosition.x) * scale.x,
      _anchorOffset.y +
          (useSnap ? _snapPosition.y.round() : _snapPosition.y) * scale.y,
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

class SnapPositionComponent extends PositionComponent with Snap {
  SnapPositionComponent({
    super.position,
    super.size,
    super.scale,
    super.angle,
    super.nativeAngle = 0,
    super.anchor,
    super.children,
    super.priority,
    super.key,
  });
}

class SnapSpriteComponent extends SpriteComponent with Snap {
  SnapSpriteComponent({
    super.sprite,
    super.autoResize,
    super.paint,
    super.position,
    super.size,
    super.scale,
    super.angle,
    super.nativeAngle,
    super.anchor,
    super.children,
    super.priority,
    super.key,
  });
}
