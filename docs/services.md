# Game services

[:arrow_left: Back to documentation](index.md)

The `Services` are a static class that can be accessed from anywhere within
your code, much like a global variable. Since it's static there's no need to
create an instance of the services. For example:

```dart
// Access the images service to grab a queued image
Image player = Services.images['images/player-sprite.png'];
```

Each service handles one area of the game. They share a common queue/load/cache
shape where appropriate, so once you're familiar with one of the asset
services, the others should feel familiar too.

- [Image service](services_images.md) - load, transform and cache `Image`
  assets via `Services.images`
- [File service](services_files.md) - load and cache arbitrary files (raw,
  string, JSON, JX) via `Services.files`
- [SVG service](services_svg.md) - parse and cache `Svg` assets via
  `Services.svg`
- [Dialog service](services_dialog.md) - load and run Yarn Spinner dialog via
  `Services.dialog`
- [Flag service](services_flags.md) - track boolean game state via
  `Services.flags`
- [Save games](services_save.md) - persist flags, dialog state and your own
  data via `Services.save` / `Services.load`
- [Logging](services_log.md) - structured logging via `Services.log`

The currently running game can also be accessed via `Services.game`.
