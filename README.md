![sizzle](sizzle-logo.png "sizzle")


# Sizzle

**A bitmap/pixel game engine based on Flame**

<!--<a title="Pub" href="https://pub.dev/packages/sizzle">
<img src="https://img.shields.io/badge/pub-v0.1-blue"/></a>-->

```{warn}
This package is in alpha and not yet production ready. Use at own risk!
```

This package takes all the hard work out of making a perfect pixel-art game. It's compatible with
other Flame features, so you can make use of audio, bloc, forge2d etc. The maintainers of this
package also regularly contribute to Flame itself.


## Features

- Set target canvas size, and sizzle will scale and letterbox the game for you
- Either use smooth movement, or snap to pixels
- Compact animated sprite format (PlySprite) and exporter from Aseprite
- Speech bubble dialog system based on yarn spinner (jenny)
- Persist game state (saves to local device)
- Central management of asset loading, saving and caching


## Documentation

[Documentation](/docs/index.md) can be found in the docs folder.


## Getting started

- Add `sizzle` using `dart pub add sizzle`


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
