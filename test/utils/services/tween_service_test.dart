import 'package:flutter_test/flutter_test.dart';
import 'package:sizzle/sizzle.dart';

void main() {
  group('TweenService', () {
    late TweenService service;

    setUp(() {
      service = TweenService();
    });

    test('Linear tween lands on `to` and fires onComplete exactly once', () {
      double value = -1;
      int completes = 0;
      service.add(
        from: 0,
        to: 100,
        duration: 1.0,
        onUpdate: (v) => value = v,
        onComplete: (_) => completes++,
      );
      for (int i = 0; i < 10; i++) {
        service.update(0.1);
      }
      expect(value, closeTo(100, 1e-9));
      expect(completes, 1);
      expect(service.activeCount, 0);
    });

    test('onStart fires after delay; nothing fires during delay', () {
      int starts = 0;
      int updates = 0;
      service.add(
        from: 0,
        to: 1,
        duration: 1.0,
        delay: 0.5,
        onStart: (_) => starts++,
        onUpdate: (_) => updates++,
      );
      service.update(0.2);
      expect(starts, 0);
      expect(updates, 0);
      service.update(0.2);
      expect(starts, 0);
      expect(updates, 0);
      service.update(0.2); // total 0.6 — delay elapsed
      expect(starts, 1);
      expect(updates, 1);
    });

    test('cancel() stops further callbacks and removes the tween', () {
      int updates = 0;
      int completes = 0;
      final Tween t = service.add(
        from: 0,
        to: 1,
        duration: 1.0,
        onUpdate: (_) => updates++,
        onComplete: (_) => completes++,
      );
      service.update(0.1);
      expect(updates, 1);
      t.cancel();
      service.update(0.1);
      service.update(1.0);
      expect(updates, 1);
      expect(completes, 0);
      expect(t.isActive, isFalse);
      expect(service.activeCount, 0);
    });

    test('Cancelling a sibling tween from inside onUpdate is safe', () {
      late Tween second;
      int secondUpdates = 0;
      service.add(
        from: 0,
        to: 1,
        duration: 1.0,
        onUpdate: (_) => second.cancel(),
      );
      second = service.add(
        from: 0,
        to: 1,
        duration: 1.0,
        onUpdate: (_) => secondUpdates++,
      );
      service.update(0.1);
      service.update(0.1);
      // First update flushes pending adds, then ticks both. The first
      // tween's onUpdate cancels the second before the second runs, so
      // secondUpdates stays 0 on tick 1. On tick 2 the cancelled tween is
      // already gone.
      expect(secondUpdates, 0);
      expect(service.activeCount, 1);
    });

    test('A tween added from inside onComplete survives to the next tick', () {
      int outerUpdates = 0;
      int innerUpdates = 0;
      service.add(
        from: 0,
        to: 1,
        duration: 0.1,
        onUpdate: (_) => outerUpdates++,
        onComplete: (_) {
          service.add(
            from: 0,
            to: 1,
            duration: 0.1,
            onUpdate: (_) => innerUpdates++,
          );
        },
      );
      service.update(0.2); // completes outer; queues inner via pending list
      expect(outerUpdates, 1);
      expect(innerUpdates, 0);
      service.update(0.2); // flushes pending; completes inner
      expect(innerUpdates, 1);
      expect(service.activeCount, 0);
    });

    test('timeScale = 0 freezes; restoring resumes from where it stopped', () {
      double value = -1;
      service.add(
        from: 0,
        to: 100,
        duration: 1.0,
        onUpdate: (v) => value = v,
      );
      service.update(0.5);
      expect(value, closeTo(50, 1e-9));
      service.timeScale = 0;
      service.update(10.0);
      expect(value, closeTo(50, 1e-9));
      service.timeScale = 1.0;
      service.update(0.5);
      expect(value, closeTo(100, 1e-9));
    });

    test('Value lands on `to` despite dt jitter past duration', () {
      double value = -1;
      service.add(
        from: 0,
        to: 100,
        duration: 1.0,
        onUpdate: (v) => value = v,
      );
      service.update(0.6);
      service.update(0.634); // total 1.234s — overshoots duration
      expect(value, closeTo(100, 1e-9));
      expect(service.activeCount, 0);
    });

    test('pause stops advancement; resume picks up where it stopped', () {
      double value = -1;
      int completes = 0;
      final Tween t = service.add(
        from: 0,
        to: 100,
        duration: 1.0,
        onUpdate: (v) => value = v,
        onComplete: (_) => completes++,
      );

      service.update(0.3);
      expect(value, closeTo(30, 1e-9));
      t.pause();
      service.update(10.0); // no advancement
      expect(value, closeTo(30, 1e-9));
      expect(completes, 0);
      t.resume();
      service.update(0.7);
      expect(value, closeTo(100, 1e-9));
      expect(completes, 1);
    });

    test('Easing function is applied to the eased value', () {
      double midValue = -1;
      service.add(
        from: 0,
        to: 1,
        duration: 1.0,
        ease: Easing.cubicEaseInOut,
        onUpdate: (v) => midValue = v,
      );
      service.update(0.5);
      expect(midValue, closeTo(0.5, 1e-9));
    });

    test('cancelAll cancels everything and leaves the service empty', () {
      service.add(from: 0, to: 1, duration: 1.0);
      service.add(from: 0, to: 1, duration: 1.0);
      service.cancelAll();
      service.update(0.1);
      expect(service.activeCount, 0);
    });

    test('onStart receives `from`; onComplete receives `to`', () {
      double? startValue;
      double? endValue;
      service.add(
        from: 10,
        to: 90,
        duration: 1.0,
        onStart: (v) => startValue = v,
        onComplete: (v) => endValue = v,
      );
      service.update(0.5);
      expect(startValue, 10);
      expect(endValue, isNull);
      service.update(0.6);
      expect(endValue, 90);
    });

    test('progress reflects raw normalized time after start', () {
      final Tween t = service.add(from: 0, to: 1, duration: 1.0);
      expect(t.progress, 0);
      service.update(0.25);
      expect(t.progress, closeTo(0.25, 1e-9));
      service.update(0.25);
      expect(t.progress, closeTo(0.5, 1e-9));
    });
  });

  group('TweenService.addColor', () {
    late TweenService service;

    setUp(() {
      service = TweenService();
    });

    test('Linearly interpolates between two colours and ends on `to`', () {
      const Color red = Color(0xffff0000);
      const Color blue = Color(0xff0000ff);
      Color? mid;
      Color? end;
      service.addColor(
        from: red,
        to: blue,
        duration: 1.0,
        onUpdate: (c) => mid = c,
        onComplete: (c) => end = c,
      );
      service.update(0.5);
      expect(mid, isNotNull);
      // Red channel halves, blue channel doubles from zero.
      expect((mid!.r * 255 - 127).abs(), lessThanOrEqualTo(1));
      expect((mid!.b * 255 - 127).abs(), lessThanOrEqualTo(1));
      service.update(0.5);
      expect(end, blue);
    });

    test('onStart receives `from` colour; onComplete receives `to` colour', () {
      const Color a = Color(0xff112233);
      const Color b = Color(0xffaabbcc);
      Color? startColor;
      Color? endColor;
      service.addColor(
        from: a,
        to: b,
        duration: 1.0,
        onStart: (c) => startColor = c,
        onComplete: (c) => endColor = c,
      );
      service.update(0.5);
      expect(startColor, a);
      expect(endColor, isNull);
      service.update(0.6);
      expect(endColor, b);
    });

    test('ColorTween exposes its colorFrom/colorTo and is a Tween', () {
      const Color a = Color(0xff112233);
      const Color b = Color(0xffaabbcc);
      final ColorTween t = service.addColor(from: a, to: b, duration: 1.0);
      expect(t, isA<Tween>());
      expect(t.colorFrom, a);
      expect(t.colorTo, b);
    });

    test('cancel() on a ColorTween stops further callbacks', () {
      int updates = 0;
      int completes = 0;
      final ColorTween t = service.addColor(
        from: const Color(0xff000000),
        to: const Color(0xffffffff),
        duration: 1.0,
        onUpdate: (_) => updates++,
        onComplete: (_) => completes++,
      );
      service.update(0.1);
      expect(updates, 1);
      t.cancel();
      service.update(1.0);
      expect(updates, 1);
      expect(completes, 0);
      expect(service.activeCount, 0);
    });
  });
}
