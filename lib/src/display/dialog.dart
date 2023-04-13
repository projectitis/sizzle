import '../../sizzle.dart';

/// Show a text dialog
class Dialog extends BitmapSpriteComponent {
  Function()? onHide;

  Vector2 dialogSize;
  Vector2 dialogHandle;
  bool showing = false;
  PositionComponent? _trackTarget;

  Dialog(this.dialogSize, this.dialogHandle) : super();

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
