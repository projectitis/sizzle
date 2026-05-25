# Tween service

[:arrow_left: Back to services](services.md)

The tween service drives arbitrary property animations - any value that can be
interpolated between a start and an end can be tweened without writing a
custom update loop. It is accessed via the global services class:

```dart
Services.tween
```

The service is ticked automatically by `SizzleGame.update`, so any tween you
add will keep running until it completes or you cancel it. Pausing the game
(setting `game.paused = true` on the Flame game) pauses every tween for free.


## Adding a tween

- [Services.tween.add](../lib/src/utils/services/tween_service.dart#:~:text=Tween+add) -
  schedule a `double` tween

```dart
Services.tween.add(
    from: 0,
    to: 100,
    duration: 1.0,
    ease: Easing.cubicEaseInOut,
    onUpdate: (v) => sprite.position.x = v,
);
```

All required parameters are `from`, `to` and `duration` (seconds). Everything
else is optional:

- `delay` - seconds to wait before the tween starts. Nothing fires during the
  delay.
- `ease` - an easing function. Defaults to `Easing.none` (linear). See
  [Easing functions](#easing-functions) below.
- `onStart` - fired once, immediately after the delay elapses. Receives `from`.
- `onUpdate` - fired every frame while the tween is running. Receives the
  current eased value scaled between `from` and `to`.
- `onComplete` - fired once when the tween reaches `to`. Receives `to`. Not
  fired if the tween is cancelled.

All three callbacks share the same signature:

```dart
typedef TweenCallback = void Function(double value);
```

The final frame is guaranteed to deliver exactly `to`, regardless of how the
last `dt` lands relative to `duration`. The property will never be left a
fraction short of the destination.


## Controlling a running tween

`add` returns a [`Tween`](../lib/src/utils/services/tween_service.dart#:~:text=class+Tween)
handle. Store it if you need to interact with the tween later:

```dart
final tween = Services.tween.add(
    from: 0,
    to: 1,
    duration: 0.5,
    onUpdate: (v) => overlay.opacity = v,
);

// Pause and resume
tween.pause();
tween.resume();

// Abort the tween. Does not fire onComplete.
tween.cancel();
```

The handle also exposes read-only state for inspection:

- [`tween.isActive`](../lib/src/utils/services/tween_service.dart#:~:text=isActive) -
  `true` until the tween completes naturally or is cancelled
- [`tween.hasStarted`](../lib/src/utils/services/tween_service.dart#:~:text=hasStarted) -
  `false` while still in the delay, `true` once the run phase has begun
- [`tween.isPaused`](../lib/src/utils/services/tween_service.dart#:~:text=isPaused) -
  `true` while paused
- [`tween.progress`](../lib/src/utils/services/tween_service.dart#:~:text=get+progress) -
  raw normalised time in `[0, 1]`; `0` during delay, `1` once complete


## Tweening colours

- [Services.tween.addColor](../lib/src/utils/services/tween_service.dart#:~:text=ColorTween+addColor) -
  schedule a `Color` tween

`addColor` interpolates between two colours using `Color.lerp`. It accepts the
same `duration`, `delay`, `ease` and lifecycle callbacks as `add`, but the
callbacks receive a `Color` instead of a `double`:

```dart
Services.tween.addColor(
    from: const Color(0xffff0000),
    to: const Color(0xff0000ff),
    duration: 1.0,
    ease: Easing.sineEaseInOut,
    onUpdate: (c) => paint.color = c,
);
```

The returned [`ColorTween`](../lib/src/utils/services/tween_service.dart#:~:text=class+ColorTween)
is a subclass of `Tween`, so all the same control methods (`pause`, `resume`,
`cancel`) and inspection properties apply. The original colours are exposed as
`colorFrom` and `colorTo`.

```dart
typedef ColorTweenCallback = void Function(Color value);
```


## Global time control

- [Services.tween.timeScale](../lib/src/utils/services/tween_service.dart#:~:text=timeScale)
  scales the `dt` applied to every tween on every update. The default is `1.0`
  (real-time).

```dart
// Slow motion - everything ticks at half speed
Services.tween.timeScale = 0.5;

// Freeze every tween without touching the game
Services.tween.timeScale = 0;

// Back to real time
Services.tween.timeScale = 1.0;
```

`timeScale` is useful for slow-mo effects, fast-forwarding intro sequences,
and pausing all tween-driven animation without pausing the rest of the game.


## Bulk operations

- [Services.tween.cancelAll](../lib/src/utils/services/tween_service.dart#:~:text=cancelAll) -
  cancel every active tween. Does not fire `onComplete`. Useful for tests and
  hard resets.
- [Services.tween.activeCount](../lib/src/utils/services/tween_service.dart#:~:text=activeCount) -
  the number of tweens currently being driven, including any added since the
  last update.


## Lifecycle in detail

The order of events for a tween with `delay: 0.2, duration: 1.0` is:

1. Frames during the first 0.2 seconds: nothing fires.
2. The frame the delay elapses: `onStart(from)`, then `onUpdate(from)` (with
   any leftover dt already applied to the run phase).
3. Each subsequent frame: `onUpdate(easedValue)`.
4. The frame the run phase elapses: `onUpdate(to)`, then `onComplete(to)`.
   The tween is removed from the service.

Cancelling at any point removes the tween on the next sweep without firing
`onComplete`. It is safe to call `cancel()` from inside any callback, and
safe to call `add()` from inside any callback - new tweens added from a
callback start on the *next* update tick.


## Easing functions

Easing functions live on the [`Easing`](../lib/src/math/easing.dart) class.
All easing methods have the signature `double Function(double t)` and accept
a normalised time `t` in `[0, 1]`. Available functions:

- `Easing.none` - linear (the default)
- `Easing.quadraticEaseIn` / `Out` / `InOut`
- `Easing.cubicEaseIn` / `Out` / `InOut`
- `Easing.quarticEaseIn` / `Out` / `InOut`
- `Easing.quinticEaseIn` / `Out` / `InOut`
- `Easing.sineEaseIn` / `Out` / `InOut`
- `Easing.circularEaseIn` / `Out` / `InOut`
- `Easing.exponentialEaseIn` / `Out` / `InOut`
- `Easing.elasticEaseIn` / `Out` / `InOut`
- `Easing.backEaseIn` / `Out` / `InOut`
- `Easing.bounceEaseIn` / `Out` / `InOut`

You can also pass your own function, since `EasingFunction` is just a typedef
for `double Function(double t)`.


## Methods at a glance

- [add](../lib/src/utils/services/tween_service.dart#:~:text=Tween+add) -
  schedule a `double` tween
- [addColor](../lib/src/utils/services/tween_service.dart#:~:text=ColorTween+addColor) -
  schedule a `Color` tween
- [cancelAll](../lib/src/utils/services/tween_service.dart#:~:text=cancelAll) -
  cancel every active tween
- [timeScale](../lib/src/utils/services/tween_service.dart#:~:text=timeScale) -
  scale `dt` for every tween
- [activeCount](../lib/src/utils/services/tween_service.dart#:~:text=activeCount) -
  inspect how many tweens are currently being driven

And on the returned [`Tween`](../lib/src/utils/services/tween_service.dart#:~:text=class+Tween)
/ [`ColorTween`](../lib/src/utils/services/tween_service.dart#:~:text=class+ColorTween)
handle:

- [pause](../lib/src/utils/services/tween_service.dart#:~:text=void+pause) /
  [resume](../lib/src/utils/services/tween_service.dart#:~:text=void+resume) /
  [cancel](../lib/src/utils/services/tween_service.dart#:~:text=void+cancel)
- [isActive](../lib/src/utils/services/tween_service.dart#:~:text=isActive) /
  [hasStarted](../lib/src/utils/services/tween_service.dart#:~:text=hasStarted) /
  [isPaused](../lib/src/utils/services/tween_service.dart#:~:text=isPaused) /
  [progress](../lib/src/utils/services/tween_service.dart#:~:text=get+progress)
