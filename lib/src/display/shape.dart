import 'package:flame/components.dart';

import 'sprite.dart';

class BitmapRectangleComponent extends RectangleComponent with Snap {
  BitmapRectangleComponent({
    super.position,
    super.size,
    super.angle,
    super.anchor,
    super.children,
    super.priority,
    super.paint,
    super.paintLayers,
  });
}
