import 'package:flutter_test/flutter_test.dart';
import 'package:sizzle/sizzle.dart';

void main() {
  group('FpsMeter', () {
    test('reports zero before any samples arrive', () {
      expect(FpsMeter().fps, 0.0);
    });

    test('averages a steady cadence', () {
      final meter = FpsMeter(window: 10);
      for (var i = 0; i < 20; i++) {
        meter.addInterval(16667);
      }
      expect(meter.fps, closeTo(60.0, 0.1));
    });

    test('averages over a partly filled window', () {
      final meter = FpsMeter(window: 10);
      for (var i = 0; i < 3; i++) {
        meter.addInterval(33333);
      }
      expect(meter.fps, closeTo(30.0, 0.1));
    });

    test('evicts samples older than the window', () {
      final meter = FpsMeter(window: 4);
      for (var i = 0; i < 4; i++) {
        meter.addInterval(33333);
      }
      expect(meter.fps, closeTo(30.0, 0.1));

      // A full window of new intervals should leave no trace of the old rate.
      for (var i = 0; i < 4; i++) {
        meter.addInterval(16667);
      }
      expect(meter.fps, closeTo(60.0, 0.1));
    });

    test('derives intervals from vsync timestamps', () {
      final meter = FpsMeter(window: 8);
      var timestamp = 1000000;
      for (var i = 0; i < 6; i++) {
        meter.addTimestamp(timestamp);
        timestamp += 16667;
      }
      expect(meter.fps, closeTo(60.0, 0.1));
    });

    test('ignores stalls, which are not a frame rate', () {
      final meter = FpsMeter(window: 8);
      var timestamp = 1000000;
      for (var i = 0; i < 6; i++) {
        meter.addTimestamp(timestamp);
        timestamp += 16667;
      }
      // A five second gap means the app was backgrounded, not running at
      // 0.2fps - the average should be untouched.
      meter.addTimestamp(timestamp + 5000000);
      expect(meter.fps, closeTo(60.0, 0.1));
    });

    test('reset discards samples but keeps the window size', () {
      final meter = FpsMeter(window: 4);
      meter.addInterval(16667);
      meter.reset();
      expect(meter.fps, 0.0);
      expect(meter.window, 4);
    });

    test('is not running until started', () {
      expect(FpsMeter().isRunning, isFalse);
    });
  });

  group('RateCounter', () {
    test('reports zero until the first window closes', () {
      final counter = RateCounter();
      for (var i = 0; i < 10; i++) {
        counter.increment();
      }
      expect(counter.rate, 0.0);
    });

    test('reports occurrences per second once a window closes', () async {
      final counter = RateCounter(windowSeconds: 0.05);
      final elapsed = Stopwatch()..start();
      while (elapsed.elapsedMilliseconds < 200) {
        counter.increment();
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      // ~200 increments per second in principle; timer granularity makes the
      // exact figure unpredictable, so only assert it is a plausible rate.
      expect(counter.rate, greaterThan(0.0));
      expect(counter.rate, lessThan(1000.0));
    });

    test('reset clears the reported rate', () async {
      final counter = RateCounter(windowSeconds: 0.01);
      counter.increment();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      counter.increment();
      expect(counter.rate, greaterThan(0.0));

      counter.reset();
      expect(counter.rate, 0.0);
    });
  });
}
