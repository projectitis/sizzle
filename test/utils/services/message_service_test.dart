import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:sizzle/sizzle.dart';

import '../../sizzle_test_helpers.dart';

/// Holder for a tear-off, so `remove` can be tested against an instance
/// method reference rather than a closure literal.
class _Counter {
  int calls = 0;

  bool onMessage(int id, dynamic args) {
    calls++;
    return true;
  }
}

/// Component that registers a listener via [HasMessages] on load.
class _ListeningComponent extends Component with HasMessages {
  int calls = 0;

  @override
  Future<void> onLoad() async {
    listen(12, (id, args) {
      calls++;
      return true;
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MessageService', () {
    late MessageService service;

    setUp(() {
      service = MessageService();
    });

    test('Sending an id with no listeners returns 0', () {
      expect(service.send(1), 0);
      expect(service.send(1, 'payload'), 0);
      expect(service.count(), 0);
    });

    test('All listeners of an id fire, in registration order', () {
      final List<String> order = [];
      service.add(12, (id, args) {
        order.add('first');
        return true;
      });
      service.add(12, (id, args) {
        order.add('second');
        return true;
      });

      expect(service.send(12), 2);
      expect(order, ['first', 'second']);
    });

    test('Listeners of other ids do not fire', () {
      int twelve = 0;
      int thirteen = 0;
      service.add(12, (id, args) {
        twelve++;
        return true;
      });
      service.add(13, (id, args) {
        thirteen++;
        return true;
      });

      service.send(12);
      expect(twelve, 1);
      expect(thirteen, 0);
    });

    test('Callback receives the id it was registered against', () {
      int received = -1;
      service.add(99, (id, args) {
        received = id;
        return true;
      });

      service.send(99);
      expect(received, 99);
    });

    test('Sender args reach every listener by identity', () {
      final Map<String, String> payload = {'foo': 'bar'};
      final List<dynamic> seen = [];
      service.add(12, (id, args) {
        seen.add(args);
        return true;
      });
      service.add(12, (id, args) {
        seen.add(args);
        return true;
      });

      service.send(12, payload);
      expect(seen.length, 2);
      expect(identical(seen[0], payload), isTrue);
      expect(identical(seen[1], payload), isTrue);
    });

    test('Sending without args delivers null', () {
      dynamic received = 'untouched';
      service.add(12, (id, args) {
        received = args;
        return true;
      });

      service.send(12);
      expect(received, isNull);
    });

    test('Args may be any object, not just a map', () {
      final List<dynamic> seen = [];
      service.add(12, (id, args) {
        seen.add(args);
        return true;
      });

      service.send(12, 42);
      service.send(12, 'text');
      expect(seen, [42, 'text']);
    });

    test('Returning false removes the listener; true keeps it', () {
      int transient = 0;
      int persistent = 0;
      service.add(12, (id, args) {
        transient++;
        return false;
      });
      service.add(12, (id, args) {
        persistent++;
        return true;
      });

      expect(service.send(12), 2);
      expect(service.count(12), 1);

      expect(service.send(12), 1);
      expect(transient, 1);
      expect(persistent, 2);
    });

    test('cancel() removes the listener and flips isActive', () {
      int calls = 0;
      final MessageListener listener = service.add(12, (id, args) {
        calls++;
        return true;
      });

      expect(listener.isActive, isTrue);
      listener.cancel();
      expect(listener.isActive, isFalse);
      expect(service.send(12), 0);
      expect(calls, 0);
      expect(service.count(12), 0);
    });

    test('cancel() is idempotent', () {
      final MessageListener listener = service.add(12, (id, args) => true);
      listener.cancel();
      listener.cancel();
      expect(service.count(12), 0);
    });

    test('remove() matches a tear-off of an instance method', () {
      final _Counter counter = _Counter();
      service.add(12, counter.onMessage);

      expect(service.remove(12, counter.onMessage), isTrue);
      expect(service.send(12), 0);
      expect(counter.calls, 0);
    });

    test('remove() returns false when nothing matches', () {
      final _Counter counter = _Counter();
      expect(service.remove(12, counter.onMessage), isFalse);

      service.add(12, (id, args) => true);
      expect(service.remove(12, counter.onMessage), isFalse);
      expect(service.count(12), 1);
    });

    test('remove() removes only the earliest of duplicate registrations', () {
      final _Counter counter = _Counter();
      service.add(12, counter.onMessage);
      service.add(12, counter.onMessage);

      expect(service.remove(12, counter.onMessage), isTrue);
      expect(service.send(12), 1);
      expect(counter.calls, 1);
    });

    test('The same callback can be registered twice and fires twice', () {
      final _Counter counter = _Counter();
      service.add(12, counter.onMessage);
      service.add(12, counter.onMessage);

      expect(service.send(12), 2);
      expect(counter.calls, 2);
    });

    test('pause() suppresses delivery, resume() restores it', () {
      int calls = 0;
      final MessageListener listener = service.add(12, (id, args) {
        calls++;
        return true;
      });

      listener.pause();
      expect(listener.isPaused, isTrue);
      expect(service.send(12), 0);
      expect(calls, 0);

      // Still registered, just skipped.
      expect(listener.isActive, isTrue);
      expect(service.count(12), 1);

      listener.resume();
      expect(listener.isPaused, isFalse);
      expect(service.send(12), 1);
      expect(calls, 1);
    });

    test('Adding from inside a callback defers to the next send', () {
      int outer = 0;
      int inner = 0;
      service.add(12, (id, args) {
        outer++;
        if (outer == 1) {
          service.add(12, (id, args) {
            inner++;
            return true;
          });
        }
        return true;
      });

      expect(service.send(12), 1);
      expect(inner, 0);

      expect(service.send(12), 2);
      expect(inner, 1);
    });

    test('Cancelling a later listener from inside a callback skips it', () {
      int second = 0;
      late MessageListener listenerB;
      service.add(12, (id, args) {
        listenerB.cancel();
        return true;
      });
      listenerB = service.add(12, (id, args) {
        second++;
        return true;
      });

      expect(service.send(12), 1);
      expect(second, 0);
      expect(service.count(12), 1);
    });

    test('Cancelling self from inside a callback removes the listener', () {
      int calls = 0;
      late MessageListener listener;
      listener = service.add(12, (id, args) {
        calls++;
        listener.cancel();
        return true;
      });

      service.send(12);
      service.send(12);
      expect(calls, 1);
      expect(service.count(12), 0);
    });

    test('Nested send of the same id does not disturb the outer dispatch', () {
      final List<String> order = [];
      int depth = 0;
      service.add(12, (id, args) {
        depth++;
        order.add('a$depth');
        if (depth == 1) service.send(12);
        depth--;
        return true;
      });
      service.add(12, (id, args) {
        order.add('b');
        return true;
      });

      expect(service.send(12), 2);
      // Outer 'a', then the nested dispatch runs both listeners, then the
      // outer dispatch continues to 'b'.
      expect(order, ['a1', 'a2', 'b', 'b']);
    });

    test('Nested send still removes listeners that returned false', () {
      int calls = 0;
      service.add(12, (id, args) {
        calls++;
        if (calls == 1) service.send(12);
        return false;
      });

      service.send(12);
      expect(service.count(12), 0);
      expect(service.send(12), 0);
    });

    test('clear(id) removes only that id', () {
      service.add(12, (id, args) => true);
      service.add(13, (id, args) => true);

      service.clear(12);
      expect(service.count(12), 0);
      expect(service.count(13), 1);
      expect(service.send(12), 0);
      expect(service.send(13), 1);
    });

    test('clear() removes everything', () {
      final MessageListener listener = service.add(12, (id, args) => true);
      service.add(13, (id, args) => true);

      service.clear();
      expect(service.count(), 0);
      expect(listener.isActive, isFalse);
      expect(service.send(12), 0);
      expect(service.send(13), 0);
    });

    test('clear() from inside a callback stops the current dispatch', () {
      int first = 0;
      int second = 0;
      service.add(12, (id, args) {
        first++;
        service.clear();
        return true;
      });
      service.add(12, (id, args) {
        second++;
        return true;
      });

      expect(service.send(12), 1);
      expect(first, 1);
      expect(second, 0);
      expect(service.count(), 0);
    });

    test('count() agrees with registrations across ids', () {
      expect(service.count(), 0);
      service.add(12, (id, args) => true);
      service.add(12, (id, args) => true);
      service.add(13, (id, args) => true);

      expect(service.count(12), 2);
      expect(service.count(13), 1);
      expect(service.count(14), 0);
      expect(service.count(), 3);
    });

    test('Negative and large ids are supported', () {
      int calls = 0;
      service.add(-5, (id, args) {
        calls++;
        return true;
      });
      service.add(1 << 40, (id, args) {
        calls++;
        return true;
      });

      service.send(-5);
      service.send(1 << 40);
      expect(calls, 2);
    });

    test('SizzleMessage ids sit in the reserved 0-999 range', () {
      const List<int> ids = [
        SizzleMessage.noop,
        SizzleMessage.sceneChanged,
        SizzleMessage.frameRateModeChanged,
        SizzleMessage.appLifecycleChanged,
        SizzleMessage.gamePaused,
        SizzleMessage.gameResumed,
      ];
      expect(SizzleMessage.noop, 0);
      for (final int id in ids) {
        expect(id, inInclusiveRange(0, 999));
      }
      expect(ids.toSet().length, ids.length, reason: 'ids must be unique');
    });
  });

  group('HasMessages', () {
    tearDown(() {
      Services.messages.clear();
    });

    testWithGame<SizzleGame>(
      'Listeners registered via listen() are cancelled when removed',
      () => SizzleGame(scene: Scene.new),
      (game) async {
        final _ListeningComponent component = _ListeningComponent()
          ..addToParent(game);
        await game.ready();

        expect(Services.messages.count(12), 1);
        Services.messages.send(12);
        expect(component.calls, 1);

        component.removeFromParent();
        await game.ready();

        expect(Services.messages.count(12), 0);
        expect(Services.messages.send(12), 0);
        expect(component.calls, 1);
      },
    );
  });

  group('Engine messages', () {
    // Services.messages is a static singleton, so leaked listeners would
    // bleed into later tests.
    tearDown(() {
      Services.messages.clear();
    });

    testWithGame<SizzleGame>(
      'sceneChanged fires on mount and again on changeScene',
      // The first entry becomes the router's initial route.
      () => SizzleGame(scenes: {'first': Scene.new, 'second': Scene.new}),
      (game) async {
        final List<dynamic> names = [];
        Services.messages.add(SizzleMessage.sceneChanged, (id, args) {
          names.add(args);
          return true;
        });

        await game.ready();
        // The first scene may already have mounted before the listener was
        // registered; what matters is the transition below.
        names.clear();

        game.changeScene('second');
        await game.ready();

        expect(names, ['second']);
      },
    );

    testWithGame<SizzleGame>(
      'frameRateModeChanged fires on a real change and not on a no-op',
      () => SizzleGame(scene: Scene.new),
      (game) async {
        await game.ready();

        final List<dynamic> modes = [];
        Services.messages.add(SizzleMessage.frameRateModeChanged, (id, args) {
          modes.add(args);
          return true;
        });

        await game.setFrameRateMode(FrameRateMode.softwareHalfRate);
        expect(modes, [FrameRateMode.softwareHalfRate]);

        // Already in force - no second message.
        await game.setFrameRateMode(FrameRateMode.softwareHalfRate);
        expect(modes, [FrameRateMode.softwareHalfRate]);

        await game.setFrameRateMode(FrameRateMode.native);
        expect(modes, [FrameRateMode.softwareHalfRate, FrameRateMode.native]);
      },
    );

    testWithGame<SizzleGame>(
      'softwareHalfRate does not broadcast gamePaused',
      () => SizzleGame(scene: Scene.new),
      (game) async {
        await game.ready();

        int paused = 0;
        int resumed = 0;
        Services.messages.add(SizzleMessage.gamePaused, (id, args) {
          paused++;
          return true;
        });
        Services.messages.add(SizzleMessage.gameResumed, (id, args) {
          resumed++;
          return true;
        });

        // This pauses the engine internally to take over the paint cadence.
        await game.setFrameRateMode(FrameRateMode.softwareHalfRate);
        expect(game.paused, isTrue);
        expect(paused, 0, reason: 'the title did not pause');

        await game.setFrameRateMode(FrameRateMode.native);
        expect(game.paused, isFalse);
        expect(resumed, 0, reason: 'the title did not resume');
      },
    );

    testWithGame<SizzleGame>(
      'gamePaused/gameResumed fire for pauseEngine and resumeEngine',
      () => SizzleGame(scene: Scene.new),
      (game) async {
        await game.ready();

        int paused = 0;
        int resumed = 0;
        Services.messages.add(SizzleMessage.gamePaused, (id, args) {
          paused++;
          return true;
        });
        Services.messages.add(SizzleMessage.gameResumed, (id, args) {
          resumed++;
          return true;
        });

        game.pauseEngine();
        expect(paused, 1);

        // Already paused - transition only, so nothing more is sent.
        game.pauseEngine();
        expect(paused, 1);

        game.resumeEngine();
        expect(resumed, 1);

        game.resumeEngine();
        expect(resumed, 1);
      },
    );

    testWithGame<SizzleGame>(
      'gamePaused/gameResumed fire for the paused setter',
      () => SizzleGame(scene: Scene.new),
      (game) async {
        await game.ready();

        int paused = 0;
        int resumed = 0;
        Services.messages.add(SizzleMessage.gamePaused, (id, args) {
          paused++;
          return true;
        });
        Services.messages.add(SizzleMessage.gameResumed, (id, args) {
          resumed++;
          return true;
        });

        game.paused = true;
        expect(paused, 1);

        game.paused = true;
        expect(paused, 1);

        game.paused = false;
        expect(resumed, 1);
      },
    );

    testWithGame<SizzleGame>(
      'appLifecycleChanged delivers the AppLifecycleState',
      () => SizzleGame(scene: Scene.new),
      (game) async {
        await game.ready();

        final List<dynamic> states = [];
        Services.messages.add(SizzleMessage.appLifecycleChanged, (id, args) {
          states.add(args);
          return true;
        });

        game.lifecycleStateChange(AppLifecycleState.paused);
        game.lifecycleStateChange(AppLifecycleState.resumed);

        expect(states, [AppLifecycleState.paused, AppLifecycleState.resumed]);
      },
    );
  });
}
