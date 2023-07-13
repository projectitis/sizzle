import 'dart:async';

import 'package:flame/components.dart';

import 'sprite.dart';

/// Show a text dialog
class DialogComponent extends PositionComponent {
  Function()? onHide;

  Vector2 dialogSize;
  Vector2 dialogHandle;
  bool showing = false;
  PositionComponent? _trackTarget;

  String dialogSpriteName;
  late NineTileBoxComponent bg;

  DialogComponent(this.dialogSpriteName, this.dialogSize, this.dialogHandle) : super();

  @override
  FutureOr<void> onLoad() async {
    final bgTiles = NineTileBox.withGrid(
      await Sprite.load(dialogSpriteName),
      leftWidth: 5,
      rightWidth: 4,
      topHeight: 4,
      bottomHeight: 7,
    );
    bg = NineTileBoxComponent(
      nineTileBox: bgTiles,
      size: Vector2(80, 40),
      position: Vector2(0, -40),
    );
    add(bg);

    return super.onLoad();
  }

  void show(String text, {String? title, Vector2? position, PositionComponent? trackTarget}) {
    _trackTarget = trackTarget;
    if (position != null) this.position.setFrom(position);
  }

  void hide() {
    onHide?.call();
  }

  @override
  void update(double dt) {
    if (_trackTarget != null) {
      position.x = _trackTarget!.position.x - dialogHandle.x;
      position.y = _trackTarget!.position.y - dialogHandle.y;
    }
    super.update(dt);
  }
}
