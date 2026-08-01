# Message service

[:arrow_left: Back to services](services.md)

The message service is a lightweight publish/subscribe hub. One part of your
game announces that something happened, and any other part that cares reacts -
without either side holding a reference to the other. It is accessed via the
global services class:

```dart
Services.messages
```

Messages are identified by a plain `int`. Dispatch is **synchronous**: `send`
invokes every listener inline and returns once they have all run. There is no
queue, no `Stream`, no per-send allocation, and nothing to tick from `update`.


## Listening for a message

- [Services.messages.add](../lib/src/utils/services/message_service.dart#:~:text=MessageListener+add) -
  register a callback against a message id

```dart
Services.messages.add(Msg.playerDied, (id, args) {
    lives -= 1;
    hud.update();
    return true;
});
```

The callback signature is:

```dart
typedef MessageCallback = bool Function(int id, dynamic args);
```

- `id` is the message id that was sent. Useful when one callback is registered
  against several ids.
- `args` is the optional payload supplied by the sender, or `null` if none was
  given.
- The **return value controls the listener's lifetime**: return `true` to stay
  registered, `false` to be removed. A `false` return is the idiomatic way to
  write a one-shot listener:

```dart
// Fires once, then unregisters itself
Services.messages.add(Msg.levelLoaded, (id, args) {
    startIntroCutscene();
    return false;
});
```

The same callback can be registered against the same id more than once. Each
registration is independent and fires separately.


## Sending a message

- [Services.messages.send](../lib/src/utils/services/message_service.dart#:~:text=int+send) -
  fire a message to every listener registered against that id

```dart
// No payload
Services.messages.send(Msg.playerDied);

// With a payload - any object at all
Services.messages.send(Msg.scoreChanged, 1500);
Services.messages.send(Msg.doorOpened, {'door': 'north', 'locked': false});
Services.messages.send(Msg.enemyHit, enemy);
```

`send` returns the number of listeners it invoked, which is handy for asserting
that something is actually wired up. Sending an id nobody listens to is free
and returns `0`.

```{warn}
The payload is passed **by reference**. Every listener receives the same
instance, so treat `args` as read-only - mutating it is visible to every
listener that runs after yours.
```

Listeners are invoked in the order they were registered. Do not rely on this
for correctness if you can avoid it; if two systems must run in a fixed order,
that ordering is usually better expressed explicitly.


## Message ids

Ids are arbitrary `int`s - positive, negative, large, whatever suits. Unused
ids cost nothing.

```{warn}
**Ids 0-999 are reserved for Sizzle itself.** Allocate your game's ids from
`1000` upward, so that messages added to the engine in future never collide
with yours. This is a convention, not a rule - nothing in the code enforces
it, and the service will happily accept any `int`.
```

Engine messages live as static constants on
[`SizzleMessage`](../lib/src/utils/services/message_service.dart#:~:text=class+SizzleMessage)
- see [Engine messages](#engine-messages) below for what Sizzle broadcasts.

Do the same for your own messages. A class of constants is readable,
greppable, and lets separate parts of a game (or a plugin) claim their own
sub-ranges without colliding:

```dart
abstract class Msg {
  static const int playerDied = 1000;
  static const int scoreChanged = 1001;
  static const int levelLoaded = 1002;
}

Services.messages.send(Msg.scoreChanged, score);
```

Avoid deriving ids from an enum's `index`. Inserting or reordering a value
silently renumbers everything after it, which is hard to spot and easy to get
wrong across a save file or a plugin boundary.


## Removing a listener

There are three ways to unregister, in rough order of preference.

**Return `false` from the callback.** Best when the listener itself knows when
it is finished.

**Cancel the handle.** `add` returns a
[`MessageListener`](../lib/src/utils/services/message_service.dart#:~:text=class+MessageListener).
Store it if something outside the callback decides when it ends:

```dart
final listener = Services.messages.add(Msg.tick, onTick);

// Later
listener.cancel();
```

**Call `remove` with the callback.** Works when you have the function reference
but not the handle:

- [Services.messages.remove](../lib/src/utils/services/message_service.dart#:~:text=bool+remove) -
  remove the first live listener on an id matching a callback

```dart
Services.messages.add(Msg.tick, onTick);
Services.messages.remove(Msg.tick, onTick);
```

If the same callback is registered against that id more than once, `remove`
only removes the earliest registration. Use the handle when the distinction
matters.

The handle also supports temporarily muting a listener without unregistering
it:

- [`listener.pause()`](../lib/src/utils/services/message_service.dart#:~:text=void+pause) /
  [`listener.resume()`](../lib/src/utils/services/message_service.dart#:~:text=void+resume) -
  suppress and restore delivery
- [`listener.isActive`](../lib/src/utils/services/message_service.dart#:~:text=isActive) -
  `false` once removed by any means
- [`listener.isPaused`](../lib/src/utils/services/message_service.dart#:~:text=isPaused) -
  `true` while paused


## Components that listen

`Services.messages` is a static singleton and knows nothing about the component
tree, so a listener registered by a scene will happily outlive that scene. The
[`HasMessages`](../lib/src/utils/services/message_service.dart#:~:text=mixin+HasMessages)
mixin ties listener lifetime to component lifetime - anything registered with
`listen` is cancelled automatically in `onRemove`:

```dart
class HudScene extends Scene with HasMessages {
  @override
  Future<void> onLoad() async {
    listen(Msg.scoreChanged, (id, args) {
      scoreLabel.text = 'Score: $args';
      return true;
    });
  }
}
```

Use this by default for anything registered from a `Component` or `Scene`.
Reach for the raw `Services.messages.add` only for listeners that genuinely
need to outlive the component that created them.


## Listening from inside a callback

It is safe to call `add`, `remove`, `cancel`, `clear` and even `send` from
inside a listener callback. The guarantees are:

- A listener **added** during a dispatch does not receive the message being
  dispatched. It becomes eligible on the next `send`.
- A listener **cancelled** during a dispatch is skipped, even if it had not
  been reached yet.
- A **nested `send` of the same id** runs to completion and then the outer
  dispatch resumes where it left off. Watch for infinite recursion - the
  service does not guard against a message that re-sends itself.

Internally, listener lists are never mutated while a dispatch is in flight;
removals are flagged and compacted once the outermost `send` unwinds.


## Engine messages

Sizzle broadcasts a small number of global state changes on
[`SizzleMessage`](../lib/src/utils/services/message_service.dart#:~:text=class+SizzleMessage).
These are events a game previously had no way to observe without subclassing.

| Message | Sent when | `args` |
|---|---|---|
| `SizzleMessage.sceneChanged` | A scene becomes active | route name, `String?` |
| `SizzleMessage.frameRateModeChanged` | The effective frame rate mode changes | `FrameRateMode` |
| `SizzleMessage.appLifecycleChanged` | The OS backgrounds/foregrounds the app | `AppLifecycleState` |
| `SizzleMessage.gamePaused` | The game loop pauses | `null` |
| `SizzleMessage.gameResumed` | The game loop resumes | `null` |

`SizzleMessage.noop` (id `0`) does nothing; it exists as a defined entry in the
reserved range and a convenient placeholder for tests and default values.

```dart
Services.messages.add(SizzleMessage.sceneChanged, (id, args) {
    Services.log.info('now showing $args');
    return true;
});

Services.messages.add(SizzleMessage.frameRateModeChanged, (id, args) {
    if (args == FrameRateMode.softwareHalfRate) showBatterySaverIcon();
    return true;
});
```

Note that `AppLifecycleState` is a Flutter type, not a Sizzle one - a listener
that inspects it needs `import 'package:flutter/widgets.dart';` alongside the
usual Sizzle import.

Three behaviours are worth knowing about:

**`sceneChanged` fires from `Scene.onMount`**, not from `changeScene`. By the
time the message arrives the scene is fully live, so `Services.game.currentScene`
already points at it. The trade-off is that a route *returned to* by popping
the navigation stack does not remount, so no message is sent. `changeScene`
only ever pushes, so this only affects games driving `SizzleGame.router`
directly.

**`frameRateModeChanged` reports the *effective* mode**, and only fires on an
actual change. This is the only way to observe the asynchronous hardware
refresh-rate check settling, or a request for `FrameRateMode.hardwareHalfRate`
falling back to software or native on a platform that cannot honour it.
Previously that fallback was only written to the log.

**Backgrounding sends two messages.** The OS pausing the app produces both
`appLifecycleChanged` and `gamePaused`. They are separate facts, not a
double-send. Conversely, `FrameRateMode.softwareHalfRate` pauses the engine
ticker as an implementation detail and deliberately does *not* send
`gamePaused` - the title did not pause.


## Bulk operations

- [Services.messages.clear](../lib/src/utils/services/message_service.dart#:~:text=void+clear) -
  remove every listener on one id, or every listener on every id when the id is
  omitted. Useful for tests and hard resets.
- [Services.messages.count](../lib/src/utils/services/message_service.dart#:~:text=int+count) -
  the number of live listeners on an id, or across every id when omitted.
  Paused listeners are counted.

```dart
Services.messages.clear(Msg.tick);   // just this message
Services.messages.clear();           // everything

Services.messages.count(Msg.tick);   // listeners on one id
Services.messages.count();           // listeners in total
```


## Methods at a glance

- [add](../lib/src/utils/services/message_service.dart#:~:text=MessageListener+add) -
  register a callback against a message id
- [send](../lib/src/utils/services/message_service.dart#:~:text=int+send) -
  fire a message, with an optional payload
- [remove](../lib/src/utils/services/message_service.dart#:~:text=bool+remove) -
  unregister by callback reference
- [clear](../lib/src/utils/services/message_service.dart#:~:text=void+clear) -
  remove every listener on one id, or on all ids
- [count](../lib/src/utils/services/message_service.dart#:~:text=int+count) -
  inspect how many listeners are registered

And on the returned
[`MessageListener`](../lib/src/utils/services/message_service.dart#:~:text=class+MessageListener)
handle:

- [cancel](../lib/src/utils/services/message_service.dart#:~:text=void+cancel) /
  [pause](../lib/src/utils/services/message_service.dart#:~:text=void+pause) /
  [resume](../lib/src/utils/services/message_service.dart#:~:text=void+resume)
- [isActive](../lib/src/utils/services/message_service.dart#:~:text=isActive) /
  [isPaused](../lib/src/utils/services/message_service.dart#:~:text=isPaused)
