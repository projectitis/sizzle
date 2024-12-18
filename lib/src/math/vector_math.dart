import 'dart:math';

import 'package:flame/extensions.dart';

/// Extend the Vector2 class with some utility methods
extension Vector2Ext on Vector2 {
  /// Calculate the angle between this vector (as a point) and another point
  double angleToPoint(Vector2 other) {
    double dx = other.x - x;
    double dy = other.y - y;
    return atan2(dy, dx);
  }

  /// Calculate the angle between this vector (as a point) and the origin
  double angleToOrigin() {
    return atan2(y, x);
  }
}
