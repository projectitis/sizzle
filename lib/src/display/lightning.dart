import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:sizzle/src/utils/pool.dart';

import '../math/math.dart';

enum WidthFade {
  none,
  fadeIn,
  fadeOut,
  fadeInOut;

  bool get hasFadeIn => this == WidthFade.fadeIn || this == WidthFade.fadeInOut;
  bool get hasFadeOut =>
      this == WidthFade.fadeOut || this == WidthFade.fadeInOut;
}

/// An animated lightning bolt effect
///
/// The bolt starts animating when it is added to the game. The bolt will remove
/// itself once animation is complete (and be added back to the pool).
///
/// Note: `Lightning.create` is a convenience method for `Lightning.pool.get`
/// and `Lightning.recycle` is a convenience method for `Lightning.pool.add()`.
///
/// Example:
/// ```dart
/// // Lightning with default values (blue)
/// Lightning lightning = Lightning.create();
/// lightning.set(start: Vector2(50, 50), end: Vector2(400, 100));
/// add(lightning);
///
/// // Red lightning with faster animation
/// Lightning redLightning = Lightning.pool.get();
/// redLightning.set(
///   start: Vector2(50, 50),
///   end: Vector2(400, 100),
///   color: Color.fromARGB(255, 255, 60, 0),
///   glowColor: Color.fromARGB(145, 119, 0, 2),
///   rate: 30,
/// );
/// add(redLightning);
/// ```
class Lightning extends Component implements Pooled {
  static final Pool<Lightning> pool = Pool<Lightning>(Lightning.new);

  /// Create a new lightning bolt from the pool
  Lightning create() => Lightning.pool.get();

  /// Recycle the lightning bolt back into the pool
  void recycle() => Lightning.pool.add(this);

  /// Default values
  static const double _defaultFadeInTime = 0.3;
  static const double _defaultFadeOutTime = 0.3;
  static const double _defaultTimeToLive = 1.2;
  static const Color _defaultColor = Color.fromARGB(255, 92, 244, 255);
  static const Color _defaultGlowColor = Color.fromARGB(128, 8, 89, 96);
  static final Range _defaultWidth = Range(0.5, 2.0);
  static final Range _defaultGlowWidth = Range(2.0, 10.0);
  static final WidthFade _defaultWidthFade = WidthFade.fadeInOut;
  static const int _defaultNumberOfSegments = 10;
  static final Range _defaultChaos = Range(0.2, 0.5);
  static const double _defaultRate = 20.0;

  late final Vector2 _start = Vector2.zero();
  late final Vector2 _end = Vector2(1.0, 1.0); // Needs some length

  double _fadeInTime = _defaultFadeInTime;
  double _fadeOutTime = _defaultFadeOutTime;
  double _time = _defaultTimeToLive;

  double _fadeOutStart = 0.0;

  double _elapsed = 0.0;

  Color color = _defaultColor;
  Color glowColor = _defaultGlowColor;

  Range width = _defaultWidth;
  Range glowWidth = _defaultGlowWidth;
  WidthFade _widthFade = _defaultWidthFade;

  int _numberOfSegments = _defaultNumberOfSegments;
  int _middleSegment = 0;

  /// Segments that make up the lightning bolt. (x, y) are the exact spaced
  /// points, and (z, w) are the points that are deviated from the direct path
  /// that make up the actual bolts. It's done this way to prevent calculating
  /// the deviation from direct path every frame.
  final List<_Segment> _segments = [];

  /// The deviation that each segment can have from it's direct path.
  final Range _chaos = Range(_defaultChaos.min, _defaultChaos.max);
  final Range _chaosLength = Range(_defaultChaos.min, _defaultChaos.max);

  /// The rate at which the lightning animates, in fps
  double _rate = _defaultRate;
  double get rate => _rate;
  set rate(double value) {
    _rate = value;
    _ratePeriod = 1 / value;
  }

  double _ratePeriod = 0;
  double _rateElapsed = 0;

  /// Temps to prevent creating new instances every frame
  final Vector2 _tempFrom = Vector2.zero();
  final Vector2 _tempTo = Vector2.zero();
  final Paint _paint = Paint();
  final Paint _glowPaint = Paint();
  final Random _random = Random();

  /// Create an animated lightning bolt effect
  ///
  /// [start] and [end] are the start and end points of the bolt. The bolt
  /// starts animating when it is added to the game. The bolt will remove itself
  /// after the [time] has elapsed. The randomness of the bolt is determined by
  /// [chaos]. If [fadeInTime] is set the minimum chaos value will be applied,
  /// and will ease toward the maximum chaos. If [fadeOutTime] is set the chaos
  /// will ease back to the minimum chaos. The bolt will animate at [rate] fps.
  ///
  /// The [color] is the color of the bolt, and [glowColor] is the color of the
  /// glow behind the bolt. The [width] is the width of the bolt, and the
  /// [glowWidth] is the width of the glow. The width eases to the full value at
  /// the middle of the bolt, and eases back to be narrower at the ends.
  ///
  /// The [numberOfSegments] is the number of segments that make up the bolt.
  Lightning({
    Vector2? start,
    Vector2? end,
    double? fadeInTime,
    double? fadeOutTime,
    double? time,
    double? rate,
    Color? color,
    Color? glowColor,
    Range? width,
    Range? glowWidth,
    WidthFade? widthFade,
    int? numberOfSegments,
    Range? chaos,
  }) {
    set(
      start: start,
      end: end,
      fadeInTime: fadeInTime,
      fadeOutTime: fadeOutTime,
      time: time,
      rate: rate,
      color: color,
      glowColor: glowColor,
      width: width,
      glowWidth: glowWidth,
      widthFade: widthFade,
      numberOfSegments: numberOfSegments,
      chaos: chaos,
    );
    _paint.strokeCap = StrokeCap.butt;
    _glowPaint.strokeCap = StrokeCap.butt;
  }

  /// Set the properties of the animated lightning bolt effect
  ///
  /// [start] and [end] are the start and end points of the bolt. The bolt
  /// starts animating when it is added to the game. The bolt will remove itself
  /// after the [time] has elapsed. The randomness of the bolt is determined by
  /// [chaos]. If [fadeInTime] is set the minimum chaos value will be applied,
  /// and will ease toward the maximum chaos. If [fadeOutTime] is set the chaos
  /// will ease back to the minimum chaos. The bolt will animate at [rate] fps.
  ///
  /// The [color] is the color of the bolt, and [glowColor] is the color of the
  /// glow behind the bolt. The [width] is the width of the bolt, and the
  /// [glowWidth] is the width of the glow. The width eases to the full value at
  /// the middle of the bolt, and eases back to be narrower at the ends.
  ///
  /// The [numberOfSegments] is the number of segments that make up the bolt.
  ///
  /// The bolt will begin animating when it is added to the game, and will be
  /// recycled to the pool once it has finished animating.
  void set({
    Vector2? start,
    Vector2? end,
    double? fadeInTime,
    double? fadeOutTime,
    double? time,
    double? rate,
    Color? color,
    Color? glowColor,
    Range? width,
    Range? glowWidth,
    WidthFade? widthFade,
    int? numberOfSegments,
    Range? chaos,
  }) {
    _start.setFrom(start ?? _start);
    _end.setFrom(end ?? _end);
    _fadeInTime = fadeInTime ?? _fadeInTime;
    _fadeOutTime = fadeOutTime ?? _fadeOutTime;
    _time = time ?? _time;
    _fadeOutStart = _time - _fadeOutTime;
    this.rate = rate ?? this.rate;
    this.color = color ?? this.color;
    this.glowColor = glowColor ?? this.glowColor;
    this.width = width ?? this.width;
    this.glowWidth = glowWidth ?? this.glowWidth;
    _widthFade = widthFade ?? _widthFade;
    _numberOfSegments = numberOfSegments ?? _numberOfSegments;
    _chaos.setFrom(chaos ?? _chaos);

    // Calculate initial segment positions as a straight line.
    // The [_jiggle] method will jiggle these positions.
    _segments.clear();
    _segments.add(_Segment(_start.clone()));
    Vector2 next = _start.clone();
    double segmentLength = _start.distanceTo(_end) / _numberOfSegments;
    _middleSegment = (_numberOfSegments / 2).floor();
    double t = 0;
    double j = 0;
    for (int i = 1; i < _numberOfSegments; i++) {
      next.lerp(_end, segmentLength / next.distanceTo(_end));
      _segments.add(_Segment(next.clone()));

      t = 1.0;
      j = i - 1;
      if (j < _middleSegment && _widthFade.hasFadeIn) {
        t = j / _middleSegment;
      } else if (j > _middleSegment && _widthFade.hasFadeOut) {
        t = 1 - (j - _middleSegment) / _middleSegment;
      }
      _segments[i].paint.strokeWidth = this.width.lerp(t);
      _segments[i].glowPaint.strokeWidth = this.glowWidth.lerp(t);
    }
    _segments.add(_Segment(_end.clone()));
    if (_widthFade.hasFadeOut) {
      _segments.last.paint.strokeWidth = this.width.min;
      _segments.last.glowPaint.strokeWidth = this.glowWidth.min;
    } else {
      _segments.last.paint.strokeWidth = this.width.max;
      _segments.last.glowPaint.strokeWidth = this.glowWidth.max;
    }

    _chaosLength.setFrom(_chaos);
    _chaosLength.multiply(segmentLength);

    _elapsed = 0.0;
    _rateElapsed = 0.0;

    _jiggle();
  }

  /// Reset back to default properties.
  ///
  /// Called automatically when the lightning bolt is recycled to the pool.
  @override
  void reset() {
    _segments.clear();
    _start.setZero();
    _end.setValues(1.0, 1.0);
    _fadeInTime = _defaultFadeInTime;
    _fadeOutTime = _defaultFadeOutTime;
    _time = _defaultTimeToLive;
    _fadeOutStart = _time - _fadeOutTime;
    color = _defaultColor;
    glowColor = _defaultGlowColor;
    width = _defaultWidth;
    glowWidth = _defaultGlowWidth;
    _widthFade = _defaultWidthFade;
    _numberOfSegments = _defaultNumberOfSegments;
    _middleSegment = (_numberOfSegments / 2).floor();
    _chaos.min = _defaultChaos.min;
    _chaos.max = _defaultChaos.max;
    rate = _defaultRate;

    _elapsed = 0.0;
    _rateElapsed = 0.0;
  }

  @override
  void onRemove() {
    recycle();
    super.onRemove();
  }

  @override
  void update(double dt) {
    _elapsed += dt;
    _rateElapsed += dt;
    if (_elapsed >= _time) {
      removeFromParent();
    } else if (_rateElapsed >= _ratePeriod) {
      _rateElapsed -= _ratePeriod;
      _jiggle();
    }

    super.update(dt);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    /// Loop through segments and draw glow
    _tempFrom.setFrom(_segments.first.jiggled);
    for (int i = 1; i < _segments.length; i++) {
      _tempTo.setFrom(_segments[i].jiggled);
      canvas.drawLine(
        _tempFrom.toOffset(),
        _tempTo.toOffset(),
        _segments[i].glowPaint..color = glowColor,
      );
      _tempFrom.setFrom(_tempTo);
    }

    /// Loop through segments and draw bolt
    _tempFrom.setFrom(_segments.first.jiggled);
    for (int i = 1; i < _segments.length; i++) {
      _tempTo.setFrom(_segments[i].jiggled);
      canvas.drawLine(
        _tempFrom.toOffset(),
        _tempTo.toOffset(),
        _segments[i].paint..color = color,
      );
      _tempFrom.setFrom(_tempTo);
    }
  }

  /// Add jiggle to the lightning bolt
  void _jiggle() {
    double t = 1.0;
    if (_elapsed < _fadeInTime) {
      t = _elapsed / _fadeInTime;
    } else if (_elapsed > _fadeOutStart) {
      t = 1 - (_elapsed - _fadeOutStart) / _fadeOutTime;
    }
    double chaos = _chaosLength.lerp(t);
    for (int i = 1; i < _segments.length - 1; i++) {
      _segments[i].jiggled.x =
          _segments[i].original.x - chaos + _random.nextDouble() * chaos * 2;
      _segments[i].jiggled.y =
          _segments[i].original.y - chaos + _random.nextDouble() * chaos * 2;
    }
  }
}

class _Segment {
  final Vector2 original;
  final Vector2 jiggled;
  final Paint paint = Paint();
  final Paint glowPaint = Paint();

  _Segment(this.original) : jiggled = original.clone() {
    paint.strokeCap = StrokeCap.butt;
    glowPaint.strokeCap = StrokeCap.butt;
  }
}
