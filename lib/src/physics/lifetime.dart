import 'package:flame/components.dart';

/// Add lifetime to a [PositionComponent]. This mixin will add a time-to-live
/// to the component. The component should be removed from the game once the
/// time-to-live has expired.
mixin Lifetime on PositionComponent {
  double ttl = 0.0;

  /// Update the time-to-live of this component. If the time-to-live has
  /// expired, [lifeEnded] will be called. If [lifeEnded] returns true, the
  /// component will be removed from the game.
  @override
  void update(double dt) {
    super.update(dt);
    if (ttl > 0) {
      ttl -= dt;
      if (ttl <= 0) {
        if (onLifeEnded()) {
          removeFromParent();
        }
      }
    }
  }

  /// Called when the time-to-live has expired. Return true to remove the
  /// component from the game.
  bool onLifeEnded() {
    return true;
  }
}
