# Frame rate and the fixed timestep

[:arrow_left: Back to documentation](index.md)

- [Two clocks](#two-clocks)
- [Writing a fixedUpdate](#writing-a-fixedupdate)
- [Frame rate modes](#frame-rate-modes)
- [Choosing a mode](#choosing-a-mode)
- [Changing mode at runtime](#changing-mode-at-runtime)
- [Pause reasons](#pause-reasons)
- [Ambient mode](#ambient-mode)
- [Measuring what actually happened](#measuring-what-actually-happened)
- [Hardware frame rate limiting](#hardware-frame-rate-limiting)


## Two clocks

By default a Flutter app paints on every vsync, and Flame calls `update(dt)`
once per painted frame. That single clock does two unrelated jobs: it decides
how often the screen is redrawn, *and* how often the game simulates.

Tying those together causes two problems. Simulation becomes frame-rate
dependent, so physics behaves differently on a 120Hz phone than on a 60Hz one
and worse on a device that is struggling. And you can't trade render work for
battery life, because painting less often also means simulating less often.

Sizzle splits them into two clocks:

| | Called from | Rate | Use it for |
|---|---|---|---|
| `update(dt)` | every painted frame | the paint rate | animation, tweens, effects, anything visual |
| `fixedUpdate(fixedDt)` | a fixed-step accumulator | `fixedUpdateFps` (default 60) | physics, collision, input sampling, deterministic logic |

`fixedDt` is *always* exactly `1 / fixedUpdateFps`, never a variable frame
time. Depending on how long the last frame took, `fixedUpdate` may be called
zero, one, or several times per painted frame - the accumulator carries the
remainder over, so over any span of wall time the number of calls is right.

Set the simulation rate in the constructor:

```dart
SizzleGame(
  scenes: {'game': GameScene.new},
  fixedUpdateFps: 60,
);
```


## Writing a fixedUpdate

Override it on the scene for that screen's simulation:

```dart
class GameScene extends Scene {
  final player = Player();

  @override
  void fixedUpdate(double fixedDt) {
    player.velocity.y += gravity * fixedDt;
    player.position += player.velocity * fixedDt;
    resolveCollisions();
  }

  @override
  void update(double dt) {
    super.update(dt);
    camera.follow(player.position, dt);  // visual, so it follows the paint rate
  }
}
```

Only the *current* scene is stepped, and only while it isn't `paused`, so a
pause menu freezes the world without any extra bookkeeping. Sizzle does not
walk the whole component tree looking for `fixedUpdate` implementations -
dispatch to your own children from the scene's `fixedUpdate` if you need to.

`SizzleGame.fixedUpdate` is available too, for simulation that spans scenes.
The game's hook runs first, then the current scene's, mirroring the way
`update` flows.

If a frame is catastrophically slow, catching up step-by-step would make the
next frame slower still and the game would spiral. Sizzle steps at most five
times per call and then drops the remaining backlog, so a hitch costs you a
moment of simulated time rather than a freeze.


## Frame rate modes

`FrameRateMode` selects how often the game paints. The simulation rate is
unaffected in every mode - `fixedUpdate` keeps running at `fixedUpdateFps`.

| Mode | Ticker | Paints at | Saves |
|---|---|---|---|
| `native` | running | every vsync | - |
| `hardwareHalfRate` | running | the reduced panel rate | display power **and** GPU |
| `softwareHalfRate` | paused | every second simulation tick | GPU only |

In `softwareHalfRate` Sizzle stops Flame's ticker and drives the engine from
its own timer, stepping the renderer every second tick. Paints are still
requested through Flutter's normal `markNeedsPaint` path, so they land on a
vsync boundary and judder stays low.

In `hardwareHalfRate` the ticker keeps running and the *panel* is asked to
refresh less often, so the reduced vsync does the work for us. This is the
only mode that saves display power rather than just GPU time - but see
[below](#hardware-frame-rate-limiting) for why it rarely applies.


## Choosing a mode

- **`native`** - the default. Correct for anything that isn't fighting for
  battery.
- **`softwareHalfRate`** - a fair trade for a slow-moving game, a menu, or an
  idle state. Halves GPU work; input and physics stay fully responsive
  because they're on the other clock.
- **`hardwareHalfRate`** - ask for it when battery matters most (a watch face,
  a long idle screen). It degrades gracefully, so requesting it is never
  worse than requesting `softwareHalfRate`.

Set the starting mode in the constructor:

```dart
SizzleGame(
  scenes: {'game': GameScene.new},
  frameRateMode: FrameRateMode.softwareHalfRate,
);
```

The mode is engaged when the game mounts, not when it is constructed - the
render surface has to exist first.


## Changing mode at runtime

```dart
final effective = await game.setFrameRateMode(FrameRateMode.hardwareHalfRate);
```

The call is asynchronous because a hardware request has to be *verified*
(see below); `native` and `softwareHalfRate` resolve immediately. The
returned mode is the one that ended up in force, which is also readable from
`game.effectiveFrameRateMode`. `game.frameRateMode` reports what you asked
for, so comparing the two tells you whether a fallback happened.

Note that `softwareHalfRate` works by pausing the engine, so `game.paused`
reads `true` while it is active. That is not the same as the game being
stopped - see [Pause reasons](#pause-reasons) below. For the same reason it
does *not* broadcast `SizzleMessage.gamePaused`: the title did not pause.

The engine also broadcasts
[`SizzleMessage.frameRateModeChanged`](services_messages.md#engine-messages)
whenever the effective mode changes, with the new `FrameRateMode` as the
payload. This is the only way to react to the asynchronous hardware
verification settling, or to a fallback happening, without polling
`effectiveFrameRateMode`:

```dart
Services.messages.add(SizzleMessage.frameRateModeChanged, (id, args) {
    if (args != FrameRateMode.hardwareHalfRate) showBatteryWarning();
    return true;
});
```


## Pause reasons

Several unrelated things can want the game stopped, and they overlap: the app
can be backgrounded while the watch is in ambient mode while your pause menu
is open. Sizzle tracks them as a set rather than a single flag, so the game
resumes when the **last** reason clears rather than the first:

```dart
game.pauseReasons;  // {} while running
```

| Reason | Set by |
|---|---|
| `PauseReason.backgrounded` | the OS backgrounding, hiding or detaching the app |
| `PauseReason.ambient` | the watch entering ambient mode |
| `PauseReason.user` | your own `pauseEngine()` / `resumeEngine()` / `paused =` |

The practical consequences:

- `resumeEngine()` clears *your* reason. It does not promise the game starts
  running — if it is also backgrounded, it stays paused until it returns to
  the foreground.
- `SizzleMessage.gamePaused` / `gameResumed` fire once per transition in and
  out of "running", not once per reason.
- The frame rate mode is deliberately **not** a reason.
  `softwareHalfRate` stops the ticker to control the paint rate, not because
  anything wants the game stopped, so `pauseReasons` stays empty there even
  though `game.paused` reads `true`. This is what lets a pause menu actually
  pause a `softwareHalfRate` game.


## Ambient mode

On a watch, "ambient" is the dimmed low-power state the display drops into
when you lower your wrist. **On Wear OS 6+ an app targeting SDK 36 is
always-on whether it asks to be or not**: the activity stays *resumed*, no
lifecycle callback arrives, and there is no way to opt out. Left unhandled, a
game would keep simulating and painting at full rate on a screen nobody is
looking at.

Sizzle does not render an ambient screen. It detects ambient and **stops the
game**, which is almost always what a game wants:

```dart
game.pauseReasons;  // {PauseReason.ambient} while the watch is dimmed
```

Everything follows from that - the physics timer stops, no frames are painted,
and `SizzleMessage.gamePaused` fires as it would for any other pause. When the
user raises their wrist the reason clears and the game resumes.

This needs a platform provider; `sizzle_wearable` supplies one. Without it
`PauseReason.ambient` never appears and nothing changes.

### Staying awake instead

A game with long stretches of no input - an idle round, a cutscene, a timer -
will be put to sleep by the watch long before it is finished. Those games
should hold the display awake explicitly:

```dart
await SizzleWearable.display.setKeepScreenOn(true);
```

Note the two are mutually exclusive: while the screen is held awake the watch
never dims, so ambient never happens. That is the intended trade, but it does
mean a game that holds the display awake for a whole session is choosing to
spend the battery.

Games with near-continuous interaction should leave it off and let the watch
sleep normally.

## Measuring what actually happened

Two meters, both off by default:

```dart
SizzleGame(scenes: {...}, measureFps: true);
// or later
game.measureFps = true;

game.measuredRenderFps;      // frames actually presented, per second
game.measuredFixedUpdateFps; // fixedUpdate calls per second
```

`measuredRenderFps` is read from the scheduler's frame timings rather than
counted in `update`, which makes it the ground truth for "did the limiting
take?" - it also sees frames dropped by the platform.
`measuredFixedUpdateFps` should sit at `fixedUpdateFps`; a persistent sag
means heavy frames are starving the physics timer.

While `measureFps` is off, no timings callback is registered at all, so
leaving it off in production costs nothing. Turning it on is cheap enough to
drive a debug overlay: the meter itself is allocation-free.


## Hardware frame rate limiting

Asking a display to slow down is unreliable in a way that is worth
understanding before you rely on it. On Android, `Surface.setFrameRate` is a
*hint*. Some devices honour it and genuinely drop the panel refresh; many
report support and then ignore the request entirely. The list of supported
display modes does not predict which you have - the only way to know is to
measure the frame cadence afterwards.

So Sizzle measures. `setFrameRateMode(FrameRateMode.hardwareHalfRate)` makes
the request, samples `measuredRenderFps` for about half a second, and keeps
the mode only if the display really slowed down. Otherwise it degrades:

- to `softwareHalfRate` by default, or
- to `native`, with a logged warning, if you pass
  `fallbackToSoftware: false`.

Sizzle is pure Dart and ships no native plugin, so out of the box there is no
provider and `hardwareHalfRate` always resolves to its fallback. A companion
plugin can light up the real path by registering one:

```dart
Device.hwFrameRateProvider = MyPlatformProvider();
Device.isHWFrameRateSupported;  // now reflects the platform
```

Implement `HwFrameRateProvider` with `setHardwareFrameRate` (best-effort;
returning `true` only means the request was accepted) and `clear`. No game
code changes - the same `setFrameRateMode` call starts resolving to real
hardware limiting on devices that honour it.
