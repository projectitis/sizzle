import 'dart:math';

import 'package:flame/extensions.dart';

extension MutableRectangleExt on MutableRectangle {
  void setValues(double left, double top, double width, double height) {
    this.left = left;
    this.top = top;
    this.width = width;
    this.height = height;
  }
}

/// Utility class that describes a range defined by a minimum and maximum value
class Range {
  late double _min;
  late double _max;

  Range(double min, double max) {
    if (min < max) {
      _min = min;
      _max = max;
    } else {
      _min = max;
      _max = min;
    }
  }
  Range.all(double value)
      : _min = value,
        _max = value;

  /// Return a zero range, where both min and max are 0
  static Range get zero => Range(0, 0);

  /// Set the range to 0
  void setZero() {
    _min = 0;
    _max = 0;
  }

  /// Return a range between negative infinity and infinity
  static Range get infinite => Range(double.negativeInfinity, double.infinity);

  /// Set the range to infinite
  void setInfinite() {
    _min = double.negativeInfinity;
    _max = double.infinity;
  }

  /// The minimum value of the range
  double get min => _min;
  set min(double value) {
    if (_max < value) {
      _min = _max;
      _max = value;
    } else {
      _min = value;
    }
  }

  /// The maximum value of the range
  double get max => _max;
  set max(double value) {
    if (_min > value) {
      _max = _min;
      _min = value;
    } else {
      _max = value;
    }
  }

  /// Clamp a number to this range
  double clamp(double value) {
    return value.clamp(min, max);
  }

  /// Clamp a Vector2 to this range
  void clampVector2(Vector2 vector) {
    vector.clampLength(min, max);
  }

  /// Linearly interpolate between the min and max values
  double lerp(double t) {
    return min + (max - min) * t;
  }

  /// linearly interpolate inversely between the min and max values
  double inverseLerp(double value) {
    return (value - min) / (max - min);
  }

  /// Check if a value is within this range
  bool contains(double value) {
    return value >= min && value <= max;
  }

  /// Check if this range is 0
  bool get isZero {
    return min == 0 && max == 0;
  }

  /// Check if this range is not 0
  bool get isNotZero {
    return min != 0 || max != 0;
  }

  /// Check if this range is infinite
  bool get isInfinite {
    return min == double.negativeInfinity && max == double.infinity;
  }

  /// Check if this range is not infinite
  bool get isNotInfinite {
    return min != double.negativeInfinity || max != double.infinity;
  }

  /// Return a random number within this range
  double random() {
    return Random().nextDouble() * (max - min) + min;
  }
}
