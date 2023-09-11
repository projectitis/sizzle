# Structure of a game

[:arrow_left: Back to documentation](index.md)

- [Typical game example](#typical-game-example)
- [Scenes](#scenes)
- [Screen size](#screen-size)
- [Letterbox](#letterbox)
- [Pixel size](#pixel-size)


## Typical game example

A typical Sizzle game might look something like this.

```dart
import 'package:sizzle/sizzle.dart';

import '/src/scenes/intro_scene.dart';
import '/src/scenes/menu_scene.dart';
import '/src/scenes/game_scene.dart';
import '/src/scenes/credits_scene.dart';

void main() {
  final game = SizzleGame(
    scenes: {
      'intro': IntroScene.create,
      'menu': MenuScene.create,
      'game': GameScene.create,
      'credits': CreditsScene.create,
    },
    targetSize: Vector2(240, 180),
    maxSize: Vector2(360, 180),
  );

  runApp(GameWidget(game: game));
}
```


## Scenes

One of the first things you may notice is that a Sizzle game is scene-based.
The user defines the scenes in the game, optionally specified the starting
scene (otherwise the first scene is used), and the scenes are then managed
by the [`SizzleGame`][SizzleGame].

Pass a list of scenes into the constructor using `scenes`, or if you only
have a single scene, pass it in with `scene`.

Different parts of the game, such as the into, achievements, settings, etc
would normally each be a different scene. games that have varied play - such
as mini-games for example - could also be implemented as scenes.

Scenes are implemented as classes that extend [`Scene`][Scene]. Each scene
has a factory method called `create` to construct a new instance. This is
because an instance of a scene is not created until it is required.

Calling [`SizzleGame`][SizzleGame] from within a [`Scene`][Scene], or from
within [`SizzleGame`][SizzleGame], will change the scene.

Scenes use the Flame `RouterComponent` behind the scenes (no pun intended),
but all the work is managed for you. Each [`Scene`][Scene] is a flame
`Component`.


## Screen size

Sizzle is all about pixel games, but Dart is all about cross-platform, so we
can't always guarantee the size of the screen the user will be playing the game
on! In order to support a range of screen sizes across these platforms, use
`targetSize` and `maxSize`.

No matter what the screen size is set to, Sizzle will ensure that the area
given by `targetSize` is always visible. As the screen is resized (for example,
the user is resizing the browser) Sizzle will maintain the target area is
visible and will scale the pixel size automatically.

Depending on the screen size, your game may be drawn outside the target area
as well. You can set `maxSize` to determine the maximum screen area that should
be drawn.

As a developer you need to make sure your game is visible and looks good up to
'max' area, but that anything outside of the 'target' area might be obscured
for some people. Make sure that the UI and all important actions happen within
the target area.

Setting the `maxSize` equal to the `targetSize` is often a good idea. This
means you don't have to deal with anything outside of the 'target' area and
can guarantee that anything within the 'target' are is always visible.


## Letterbox

Outside of `maxSize` the game will be letterboxed. By default the area outside
the letterbox is black, but this can be changed by passing `letterBoxColor`
into the constructor of the game.


## Pixel size

The actual size of each 'pixel' in your game is determined by the user's screen
size and the `targetSize` (see above).

Often this means that a game pixel is not a whole number of screen pixels
across -for example, each game pixel could be 4.5x4.5 screen pixels in
width/height. If this is not the effect that you are after, try setting
`scaleToWholePixels` to `true` in the constructor. This will ensure that pixels
in your game are always a whole number of real pixels.

<!-- links -->
[SizzleGame]: ../lib/src/game/game.dart
[Scene]: ../lib/src/game/scene.dart
