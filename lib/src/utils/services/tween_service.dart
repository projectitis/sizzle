import 'dart:ui';

import '../../math/easing.dart';

/// Signature for an easing function used by [TweenService.add]. Receives a
/// normalised time `t` in `[0, 1]` and returns the eased progress.
typedef EasingFunction = double Function(double t);

/// Callback for tween lifecycle events. Receives the current value:
/// `from` for `onStart`, the eased value for `onUpdate`, `to` for
/// `onComplete`.
typedef TweenCallback = void Function(double value);

/// Handle to a tween scheduled on [TweenService]. The service owns the
/// instance; callers receive it from [TweenService.add] and use it to
/// inspect state, [pause]/[resume], or [cancel].
class Tween {
  Tween._({
    required this.from,
    required this.to,
    required this.duration,
    required this.delay,
    required this.ease,
    this.onStart,
    this.onUpdate,
    this.onComplete,
  })  : _change = to - from,
        _invDuration = duration > 0 ? 1.0 / duration : 0.0,
        _epsDuration = duration - 1e-9;

  /// Start value passed to [onUpdate] when the tween begins.
  final double from;

  /// End value passed to [onUpdate] on the final tick.
  final double to;

  /// Total run time in seconds, excluding [delay].
  final double duration;

  /// Seconds to wait before [onStart] fires.
  final double delay;

  /// Easing function applied to the normalised time `t` before scaling
  /// between [from] and [to].
  final EasingFunction ease;

  /// Fired once when [delay] elapses, immediately before the first
  /// [onUpdate] of the run. Receives [from].
  final TweenCallback? onStart;

  /// Fired on every update tick while the tween is running. Receives the
  /// eased value scaled between [from] and [to].
  final TweenCallback? onUpdate;

  /// Fired once when the tween reaches [to]. Receives [to]. Not fired
  /// when [cancel] is called.
  final TweenCallback? onComplete;

  final double _change;
  final double _invDuration;
  final double _epsDuration;
  double _elapsedDelay = 0.0;
  double _elapsedRun = 0.0;
  bool _hasStarted = false;
  bool _isPaused = false;
  bool _isCancelled = false;
  bool _isComplete = false;

  /// `true` until the tween completes naturally or is [cancel]led.
  bool get isActive => !_isCancelled && !_isComplete;

  /// `true` once [delay] has elapsed and the run phase has begun.
  bool get hasStarted => _hasStarted;

  /// `true` while paused by [pause].
  bool get isPaused => _isPaused;

  /// Normalised progress in `[0, 1]` through the run phase (after [delay]).
  /// Returns `0` while still in delay and `1` once complete.
  double get progress {
    if (!_hasStarted) return 0.0;
    if (_isComplete) return 1.0;
    if (duration <= 0) return 1.0;
    final double p = _elapsedRun * _invDuration;
    return p < 0 ? 0 : (p > 1 ? 1 : p);
  }

  /// Suspend updates. The tween stops advancing until [resume] is called.
  /// Has no effect once the tween has completed or been cancelled.
  void pause() {
    if (isActive) _isPaused = true;
  }

  /// Resume a [pause]d tween. No-op if not currently paused.
  void resume() {
    _isPaused = false;
  }

  /// Stop the tween. Removes it from the service on the next sweep. Does
  /// not fire [onComplete]. Safe to call from inside any callback.
  void cancel() {
    _isCancelled = true;
  }
}

/// Callback for [ColorTween] lifecycle events. Receives the current
/// interpolated colour.
typedef ColorTweenCallback = void Function(Color value);

/// A [Tween] that interpolates between two [Color]s using [Color.lerp].
///
/// Drives the base [Tween] over `0..1` (so the eased value is fed straight
/// to `Color.lerp`) and forwards each lifecycle event to the supplied
/// colour-typed callbacks: `onStart` receives [colorFrom], `onUpdate`
/// receives the lerped colour, `onComplete` receives [colorTo].
class ColorTween extends Tween {
  ColorTween._({
    required Color start,
    required Color end,
    required super.duration,
    super.delay = 0.0,
    super.ease = Easing.none,
    ColorTweenCallback? onStart,
    ColorTweenCallback? onUpdate,
    ColorTweenCallback? onComplete,
  })  : colorFrom = start,
        colorTo = end,
        super._(
          from: 0,
          to: 1,
          onStart: onStart == null ? null : (_) => onStart(start),
          onUpdate: onUpdate == null
              ? null
              : (t) => onUpdate(Color.lerp(start, end, t)!),
          onComplete: onComplete == null ? null : (_) => onComplete(end),
        );

  /// The colour the tween starts at; reported to `onStart` and to
  /// `onUpdate` on the first run-tick.
  final Color colorFrom;

  /// The colour the tween ends at; reported to `onUpdate` and `onComplete`
  /// on the final tick.
  final Color colorTo;
}

/// Drives a list of [Tween]s every frame. The default instance lives at
/// `Services.tween` and is ticked automatically by `SizzleGame.update`.
///
/// Typical use:
/// ```dart
/// final tween = Services.tween.add(
///   from: 0,
///   to: 100,
///   duration: 1.0,
///   ease: Easing.cubicEaseInOut,
///   onUpdate: (v) => sprite.position.x = v,
///   onComplete: (v) => print('done at $v'),
/// );
/// // Later, if needed:
/// tween.cancel();
/// ```
class TweenService {
  /// Multiplier applied to `dt` on every [update] call. `0` freezes every
  /// tween; values >1 fast-forward; the default `1.0` is real-time.
  double timeScale = 1.0;

  final List<Tween> _tweens = [];
  final List<Tween> _pendingAdds = [];

  /// Schedule a new tween. Returns a [Tween] handle the caller can store
  /// to query state, pause/resume, or cancel.
  ///
  /// During [delay] no callbacks fire. The first tick after the delay
  /// elapses fires [onStart] (if provided) followed by [onUpdate] with the
  /// initial eased value. On the final tick the value is clamped to [to],
  /// [onUpdate] fires with exactly [to], then [onComplete] fires, then the
  /// tween is removed.
  Tween add({
    required double from,
    required double to,
    required double duration,
    double delay = 0.0,
    EasingFunction ease = Easing.none,
    TweenCallback? onStart,
    TweenCallback? onUpdate,
    TweenCallback? onComplete,
  }) {
    assert(duration > 0, 'Tween duration must be greater than 0');
    assert(delay >= 0, 'Tween delay must be non-negative');
    final Tween t = Tween._(
      from: from,
      to: to,
      duration: duration,
      delay: delay,
      ease: ease,
      onStart: onStart,
      onUpdate: onUpdate,
      onComplete: onComplete,
    );
    _pendingAdds.add(t);
    return t;
  }

  /// Schedule a [ColorTween] that interpolates between two [Color]s using
  /// [Color.lerp]. Same lifecycle and timing semantics as [add]; the
  /// callbacks receive colours instead of doubles.
  ColorTween addColor({
    required Color from,
    required Color to,
    required double duration,
    double delay = 0.0,
    EasingFunction ease = Easing.none,
    ColorTweenCallback? onStart,
    ColorTweenCallback? onUpdate,
    ColorTweenCallback? onComplete,
  }) {
    assert(duration > 0, 'Tween duration must be greater than 0');
    assert(delay >= 0, 'Tween delay must be non-negative');
    final ColorTween t = ColorTween._(
      start: from,
      end: to,
      duration: duration,
      delay: delay,
      ease: ease,
      onStart: onStart,
      onUpdate: onUpdate,
      onComplete: onComplete,
    );
    _pendingAdds.add(t);
    return t;
  }

  /// Advance every active tween by `dt` seconds (scaled by [timeScale]).
  /// Called by `SizzleGame.update`; callers should not invoke this
  /// directly.
  void update(double dt) {
    if (timeScale == 0) return;
    final double scaledDt = dt * timeScale;

    if (_pendingAdds.isNotEmpty) {
      _tweens.addAll(_pendingAdds);
      _pendingAdds.clear();
    }

    for (int i = 0; i < _tweens.length; i++) {
      final Tween t = _tweens[i];
      if (t._isCancelled || t._isComplete || t._isPaused) continue;

      double remaining = scaledDt;

      if (!t._hasStarted) {
        t._elapsedDelay += remaining;
        if (t._elapsedDelay < t.delay) continue;
        remaining = t._elapsedDelay - t.delay;
        t._hasStarted = true;
        t.onStart?.call(t.from);
        if (t._isCancelled) continue;
        if (t.duration <= 0) {
          t._isComplete = true;
          t.onUpdate?.call(t.to);
          if (t._isCancelled) continue;
          t.onComplete?.call(t.to);
          continue;
        }
        // First run-tick uses the leftover from the delay frame.
      }

      t._elapsedRun += remaining;
      if (t._elapsedRun >= t._epsDuration) {
        t._isComplete = true;
        t.onUpdate?.call(t.to);
        if (t._isCancelled) continue;
        t.onComplete?.call(t.to);
      } else {
        final double v =
            t.from + t._change * t.ease(t._elapsedRun * t._invDuration);
        t.onUpdate?.call(v);
      }
    }

    _tweens.removeWhere((t) => t._isCancelled || t._isComplete);
  }

  /// Cancel every active tween. Does not fire `onComplete` for any of
  /// them. Useful for tests and hard resets.
  void cancelAll() {
    for (final Tween t in _tweens) {
      t._isCancelled = true;
    }
    for (final Tween t in _pendingAdds) {
      t._isCancelled = true;
    }
    _tweens.removeWhere((t) => t._isCancelled);
    _pendingAdds.removeWhere((t) => t._isCancelled);
  }

  /// Number of tweens currently being driven, including any added since
  /// the last [update] call.
  int get activeCount => _tweens.length + _pendingAdds.length;
}
