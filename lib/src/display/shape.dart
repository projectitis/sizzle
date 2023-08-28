import 'package:flame/components.dart';

import 'snap.dart';

class SnapRectangleComponent extends RectangleComponent with Snap {
  SnapRectangleComponent({
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
