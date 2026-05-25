import 'dart:math';

/// Collection of easing functions that map a normalized progress value
/// `p` in `[0, 1]` to an eased value (typically also in `[0, 1]`, though
/// some functions overshoot).
///
/// All methods are pure and static; use them directly:
/// ```dart
/// final eased = Easing.cubicEaseInOut(t);
/// ```
class Easing {
  Easing._();

  static const double _halfPi = pi / 2;

  /// Modeled after the line y = x
  static double none(double p) => p;

  /// Modeled after the parabola y = x^2
  static double quadraticEaseIn(double p) => p * p;

  /// Modeled after the parabola y = -x^2 + 2x
  static double quadraticEaseOut(double p) => -(p * (p - 2));

  /// Modeled after the piecewise quadratic
  /// y = (1/2)((2x)^2)             ; [0, 0.5)
  /// y = -(1/2)((2x-1)*(2x-3) - 1) ; [0.5, 1]
  static double quadraticEaseInOut(double p) {
    if (p < 0.5) {
      return 2 * p * p;
    } else {
      return (-2 * p * p) + (4 * p) - 1;
    }
  }

  /// Modeled after the cubic y = x^3
  static double cubicEaseIn(double p) => p * p * p;

  /// Modeled after the cubic y = (x - 1)^3 + 1
  static double cubicEaseOut(double p) {
    final double f = p - 1;
    return f * f * f + 1;
  }

  /// Modeled after the piecewise cubic
  /// y = (1/2)((2x)^3)       ; [0, 0.5)
  /// y = (1/2)((2x-2)^3 + 2) ; [0.5, 1]
  static double cubicEaseInOut(double p) {
    if (p < 0.5) {
      return 4 * p * p * p;
    } else {
      final double f = (2 * p) - 2;
      return 0.5 * f * f * f + 1;
    }
  }

  /// Modeled after the quartic x^4
  static double quarticEaseIn(double p) => p * p * p * p;

  /// Modeled after the quartic y = 1 - (x - 1)^4
  static double quarticEaseOut(double p) {
    final double f = p - 1;
    return f * f * f * (1 - p) + 1;
  }

  /// Modeled after the piecewise quartic
  /// y = (1/2)((2x)^4)        ; [0, 0.5)
  /// y = -(1/2)((2x-2)^4 - 2) ; [0.5, 1]
  static double quarticEaseInOut(double p) {
    if (p < 0.5) {
      return 8 * p * p * p * p;
    } else {
      final double f = p - 1;
      return -8 * f * f * f * f + 1;
    }
  }

  /// Modeled after the quintic y = x^5
  static double quinticEaseIn(double p) => p * p * p * p * p;

  /// Modeled after the quintic y = (x - 1)^5 + 1
  static double quinticEaseOut(double p) {
    final double f = p - 1;
    return f * f * f * f * f + 1;
  }

  /// Modeled after the piecewise quintic
  /// y = (1/2)((2x)^5)       ; [0, 0.5)
  /// y = (1/2)((2x-2)^5 + 2) ; [0.5, 1]
  static double quinticEaseInOut(double p) {
    if (p < 0.5) {
      return 16 * p * p * p * p * p;
    } else {
      final double f = (2 * p) - 2;
      return 0.5 * f * f * f * f * f + 1;
    }
  }

  /// Modeled after quarter-cycle of sine wave
  static double sineEaseIn(double p) => sin((p - 1) * _halfPi) + 1;

  /// Modeled after quarter-cycle of sine wave (different phase)
  static double sineEaseOut(double p) => sin(p * _halfPi);

  /// Modeled after half sine wave
  static double sineEaseInOut(double p) => 0.5 * (1 - cos(p * pi));

  /// Modeled after shifted quadrant IV of unit circle
  static double circularEaseIn(double p) => 1 - sqrt(1 - (p * p));

  /// Modeled after shifted quadrant II of unit circle
  static double circularEaseOut(double p) => sqrt((2 - p) * p);

  /// Modeled after the piecewise circular function
  /// y = (1/2)(1 - sqrt(1 - 4x^2))           ; [0, 0.5)
  /// y = (1/2)(sqrt(-(2x - 3)*(2x - 1)) + 1) ; [0.5, 1]
  static double circularEaseInOut(double p) {
    if (p < 0.5) {
      return 0.5 * (1 - sqrt(1 - 4 * (p * p)));
    } else {
      return 0.5 * (sqrt(-((2 * p) - 3) * ((2 * p) - 1)) + 1);
    }
  }

  /// Modeled after the exponential function y = 2^(10(x - 1))
  static double exponentialEaseIn(double p) =>
      (p == 0.0) ? p : pow(2, 10 * (p - 1)).toDouble();

  /// Modeled after the exponential function y = -2^(-10x) + 1
  static double exponentialEaseOut(double p) =>
      (p == 1.0) ? p : 1 - pow(2, -10 * p).toDouble();

  /// Modeled after the piecewise exponential
  /// y = (1/2)2^(10(2x - 1))         ; [0,0.5)
  /// y = -(1/2)*2^(-10(2x - 1))) + 1 ; [0.5,1]
  static double exponentialEaseInOut(double p) {
    if (p == 0.0 || p == 1.0) return p;
    if (p < 0.5) {
      return 0.5 * pow(2, (20 * p) - 10).toDouble();
    } else {
      return -0.5 * pow(2, (-20 * p) + 10).toDouble() + 1;
    }
  }

  /// Modeled after the damped sine wave y = sin(13pi/2*x)*pow(2, 10 * (x - 1))
  static double elasticEaseIn(double p) =>
      sin(13 * _halfPi * p) * pow(2, 10 * (p - 1)).toDouble();

  /// Modeled after the damped sine wave
  /// y = sin(-13pi/2*(x + 1))*pow(2, -10x) + 1
  static double elasticEaseOut(double p) =>
      sin(-13 * _halfPi * (p + 1)) * pow(2, -10 * p).toDouble() + 1;

  /// Modeled after the piecewise exponentially-damped sine wave:
  /// y = (1/2)*sin(13pi/2*(2*x))*pow(2, 10 * ((2*x) - 1))      ; [0,0.5)
  /// y = (1/2)*(sin(-13pi/2*((2x-1)+1))*pow(2,-10(2*x-1)) + 2) ; [0.5, 1]
  static double elasticEaseInOut(double p) {
    if (p < 0.5) {
      return 0.5 *
          sin(13 * _halfPi * (2 * p)) *
          pow(2, 10 * ((2 * p) - 1)).toDouble();
    } else {
      return 0.5 *
          (sin(-13 * _halfPi * ((2 * p - 1) + 1)) *
                  pow(2, -10 * (2 * p - 1)).toDouble() +
              2);
    }
  }

  /// Modeled after the overshooting cubic y = x^3-x*sin(x*pi)
  static double backEaseIn(double p) => p * p * p - p * sin(p * pi);

  /// Modeled after overshooting cubic y = 1-((1-x)^3-(1-x)*sin((1-x)*pi))
  static double backEaseOut(double p) {
    final double f = 1 - p;
    return 1 - (f * f * f - f * sin(f * pi));
  }

  /// Modeled after the piecewise overshooting cubic function:
  /// y = (1/2)*((2x)^3-(2x)*sin(2*x*pi))           ; [0, 0.5)
  /// y = (1/2)*(1-((1-x)^3-(1-x)*sin((1-x)*pi))+1) ; [0.5, 1]
  static double backEaseInOut(double p) {
    if (p < 0.5) {
      final double f = 2 * p;
      return 0.5 * (f * f * f - f * sin(f * pi));
    } else {
      final double f = 1 - (2 * p - 1);
      return 0.5 * (1 - (f * f * f - f * sin(f * pi))) + 0.5;
    }
  }

  static double bounceEaseIn(double p) => 1 - bounceEaseOut(1 - p);

  static double bounceEaseOut(double p) {
    if (p < 4 / 11.0) {
      return (121 * p * p) / 16.0;
    } else if (p < 8 / 11.0) {
      return (363 / 40.0 * p * p) - (99 / 10.0 * p) + 17 / 5.0;
    } else if (p < 9 / 10.0) {
      return (4356 / 361.0 * p * p) - (35442 / 1805.0 * p) + 16061 / 1805.0;
    } else {
      return (54 / 5.0 * p * p) - (513 / 25.0 * p) + 268 / 25.0;
    }
  }

  static double bounceEaseInOut(double p) {
    if (p < 0.5) {
      return 0.5 * bounceEaseIn(p * 2);
    } else {
      return 0.5 * bounceEaseOut(p * 2 - 1) + 0.5;
    }
  }
}
