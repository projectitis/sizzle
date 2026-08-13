import 'dart:typed_data';
import 'dart:ui' show FramePhase;

import 'package:flutter/scheduler.dart';

/// Measures the rate at which the engine actually presents frames.
///
/// This is the ground truth for "did the frame-rate limiting take?" - it
/// reads `FrameTiming.vsyncStart` timestamps straight from the scheduler
/// rather than inferring a rate from `update` calls, so it also catches
/// frames dropped by the platform.
///
/// The meter keeps a fixed-size ring buffer of the last [window] frame
/// intervals plus a running sum, so [fps] is O(1) and sampling allocates
/// nothing per frame. It is inert until [start] is called; while stopped no
/// timings callback is registered at all, so the cost of leaving metering off
/// is exactly zero.
///
/// ```dart
/// final meter = FpsMeter()..start();
/// // ... later ...
/// print(meter.fps);
/// meter.stop();
/// ```
class FpsMeter {
  /// Creates a meter averaging over the last [window] frame intervals.
  FpsMeter({int window = 10})
      : assert(window > 1, 'A window of at least 2 frames is required'),
        _deltas = Int32List(window);

  /// Ignore intervals longer than this (2s). A gap that large means the app
  /// was backgrounded or the engine stalled, not a real frame rate.
  static const int _maxDeltaMicros = 2000000;

  /// Ring buffer of frame intervals in microseconds. `Int32List` (not
  /// `Int64List`) so the meter also works when compiled for the web.
  final Int32List _deltas;

  int _head = 0;
  int _count = 0;
  int _sumMicros = 0;
  int _lastTimestampMicros = -1;
  bool _isRunning = false;

  /// The number of intervals the average is taken over.
  int get window => _deltas.length;

  /// Whether a timings callback is currently registered.
  bool get isRunning => _isRunning;

  /// Whether the averaging window is full, i.e. [fps] is now an average over
  /// [window] intervals rather than the handful that have arrived so far.
  ///
  /// Used to tell a settled reading from one taken while samples are still
  /// trickling in - the difference between "the panel is at 30fps" and "the
  /// first frame timing has only just arrived".
  bool get isSaturated => _count >= _deltas.length;

  /// The averaged presented-frame rate, or `0` before enough samples have
  /// arrived.
  double get fps =>
      (_count == 0 || _sumMicros <= 0) ? 0.0 : _count * 1e6 / _sumMicros;

  /// Registers the timings callback and begins sampling. Calling this on an
  /// already-running meter is a no-op.
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    reset();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  /// Unregisters the timings callback and discards any samples. Calling this
  /// on a stopped meter is a no-op.
  void stop() {
    if (!_isRunning) return;
    _isRunning = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    reset();
  }

  /// Discards all samples without changing whether the meter is running.
  /// Use this before a measurement window to avoid averaging in stale frames.
  void reset() {
    _head = 0;
    _count = 0;
    _sumMicros = 0;
    _lastTimestampMicros = -1;
  }

  void _onTimings(List<FrameTiming> timings) {
    for (var i = 0; i < timings.length; i++) {
      addTimestamp(timings[i].timestampInMicroseconds(FramePhase.vsyncStart));
    }
  }

  /// Feeds a raw vsync timestamp, deriving an interval from the previous one.
  /// Exposed so the averaging can be driven directly from tests or a custom
  /// frame source.
  void addTimestamp(int timestampMicros) {
    if (_lastTimestampMicros >= 0) {
      final delta = timestampMicros - _lastTimestampMicros;
      if (delta > 0 && delta < _maxDeltaMicros) {
        addInterval(delta);
      }
    }
    _lastTimestampMicros = timestampMicros;
  }

  /// Feeds one frame interval, in microseconds, into the ring buffer.
  void addInterval(int deltaMicros) {
    if (_count == _deltas.length) {
      _sumMicros -= _deltas[_head];
    } else {
      _count++;
    }
    _deltas[_head] = deltaMicros;
    _sumMicros += deltaMicros;
    _head = (_head + 1) % _deltas.length;
  }
}

/// Counts how often something happens and reports it as a per-second rate
/// over a sliding window.
///
/// Used for `SizzleGame.measuredFixedUpdateFps`, where the interesting signal
/// is whether the physics timer is keeping up rather than how evenly spaced
/// its ticks are. [increment] is a couple of integer operations plus one
/// stopwatch read, cheap enough to call unconditionally.
class RateCounter {
  /// Creates a counter that recomputes [rate] every [windowSeconds].
  RateCounter({this.windowSeconds = 1.0})
      : assert(windowSeconds > 0, 'The window must be positive');

  /// How long each measurement window is, in seconds.
  final double windowSeconds;

  final Stopwatch _stopwatch = Stopwatch();
  int _count = 0;
  double _rate = 0.0;

  /// Occurrences per second over the most recently completed window, or `0`
  /// before the first window has elapsed.
  double get rate => _rate;

  /// Records one occurrence, closing the window if enough time has passed.
  void increment() {
    _count++;
    if (!_stopwatch.isRunning) {
      _stopwatch.start();
      return;
    }
    final elapsed = _stopwatch.elapsedMicroseconds / 1e6;
    if (elapsed >= windowSeconds) {
      _rate = _count / elapsed;
      _count = 0;
      _stopwatch.reset();
    }
  }

  /// Clears the current window and the reported [rate].
  void reset() {
    _count = 0;
    _rate = 0.0;
    _stopwatch
      ..stop()
      ..reset();
  }
}
