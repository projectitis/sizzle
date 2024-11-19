import 'dart:math';

import 'package:flame/components.dart';

import '../math/math.dart';
import '../math/vector_math.dart';

/// Add movement to a [PositionComponent]. This mixin will add velocity and
/// acceleration to the component. The position will be updated based on the
/// velocity and acceleration. Angular velocity and acceleration are also
/// supported.
mixin Movement on PositionComponent {
  /// The velocity in pixels per second
  final Vector2 velocity = Vector2.zero();

  /// The min and max limits of velocity
  final Range velocityRange = Range.infinite;

  /// The acceleration in pixels per second squared
  final Vector2 acceleration = Vector2.zero();

  /// The angular velocity in radians per second
  double angularVelocity = 0;

  /// The min and max limits of angular velocity
  final Range angularVelocityRange = Range.infinite;

  /// The angular acceleration in radians per second squared
  double angularAcceleration = 0;

  /// The next position of this component. Used during update
  final Vector2 _nextPosition = Vector2.zero();

  /// Update the position of this component based on the velocity and
  /// acceleration. [hasCollided] should be implemented to check if the next
  /// position will collide with something. The position will only be updated
  /// if the next position does not collide.
  @override
  void update(double dt) {
    angularVelocity += angularAcceleration * dt;
    if (angularVelocityRange.isNotInfinite) {
      angularVelocity = angularVelocityRange.clamp(angularVelocity);
    }
    velocity.add(acceleration * dt);
    if (velocityRange.isNotInfinite) {
      velocityRange.clampVector2(velocity);
    }
    velocity.rotate(angularVelocity * dt);

    _nextPosition.setFrom(position);
    _nextPosition.add(velocity * dt);
    if (!hasCollided(_nextPosition)) {
      position.setFrom(_nextPosition);
    }
    super.update(dt);
  }

  /// Implement this method to check if the next position will collide with
  /// something. If it does collide, process the collision (for example, this
  /// object may be destroyed, or it may change direction, or it may bounce).
  /// Return true to set the new position to [nextPosition]. [nextPosition] may
  /// be modified to change the new position.
  bool hasCollided(Vector2 nextPosition) {
    return false;
  }

  /// Bounce this component off a surface with the given normal angle.
  void reflect(double angle) {
    velocity.rotate(pi + angle - velocity.angleToOrigin());
  }
}
