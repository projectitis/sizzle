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

  /// Set the range to the same values as another range
  void setFrom(Range other) {
    _min = other._min;
    _max = other._max;
  }

  /// Set the range from the same values of a Vector2
  void setFromVector2(Vector2 vector) {
    min = vector.x;
    max = vector.y;
  }

  /// Set the range from the same values of an Offset
  void setFromOffset(Offset offset) {
    min = offset.dx;
    max = offset.dy;
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

  /// Multiple this range by a value and return a new range
  Range operator *(double value) {
    return Range(_min * value, _max * value);
  }

  /// Divide this range by a value and return a new range
  Range operator /(double value) {
    return Range(_min / value, _max / value);
  }

  /// Add another range to this range and return a new range
  Range operator +(Range other) {
    return Range(_min + other._min, _max + other._max);
  }

  /// Subtract another range from this range and return a new range
  Range operator -(Range other) {
    return Range(_min - other._min, _max - other._max);
  }

  /// Return a new range that is the negative of this range
  Range operator -() {
    return Range(-_min, -_max);
  }

  /// Multiply the min and max by a value of this range
  void multiply(double value) {
    _min *= value;
    _max *= value;
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

/// Calculate the bounding box of a rectangle rotated around its center.
Rect boundingBox(Size size, double angle) {
  double absCosRA = cos(angle).abs();
  double absSinRA = sin(angle).abs();
  double bbW = size.width * absCosRA + size.height * absSinRA;
  double bbH = size.width * absSinRA + size.height * absCosRA;
  double ox = (size.width - bbW) / 2;
  double oy = (size.height - bbH) / 2;
  return Rect.fromLTWH(ox, oy, bbW, bbH);
}

extension RectExt on Rect {
  Rect bounds(double angle) {
    return boundingBox(size, angle);
  }
}
