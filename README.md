A bitmap/pixel game engline based on Flame.

> This package is in alpha not yet production ready. Use at own risk

This package takes all the hard work out of making a perfect pixelart game. It's compatible with other Flame features, so you can make use of audio,

## Features

- Set target canvas size, and sizzle will scale and letterbox the game for you
- Either use smooth movement, or snap to pixels
- Dialog system with conversation tree
- Persist game state (saves to local device)

## Getting started

- Add `sizzle:` to your `pubspec.yaml`

## Usage

For a full example, see [examples](/example/).

```dart
import 'package:flutter/material.dart';
import 'package:sizzle/sizzle.dart';

void main() {
  final game = SizzleGame(
    scene: ExampleScene.create,
    targetSize: Vector2(320, 240),
  );

  runApp(GameWidget(game: game));
}

class ExampleScene extends Scene {
  static Component create() => ExampleScene();
}
```
