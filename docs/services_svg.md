# SVG service

[:arrow_left: Back to services](services.md)

The SVG service parses and caches SVG assets so they can be drawn through the
`SvgComponent`. It mirrors the same queue/load/cache pattern used by the
[image](services_images.md) and [file](services_files.md) services and is
accessed via the global services class:

```dart
Services.svg
```

## Workflow for caching SVGs

The suggested workflow for working with SVGs is:
1. SVGs are enqueued and loaded
2. SVGs are used
3. SVG cache is cleared (if required)

SVGs are keyed in the cache by their asset path and are loaded relative to the
`assets/` folder.

### Enqueuing SVGs

- [Services.svg.enqueue](../lib/src/utils/services/svg_service.dart#:~:text=enqueue)
- [Services.svg.enqueueAll](../lib/src/utils/services/svg_service.dart#:~:text=enqueueAll)
- [Services.svg.loadQueue](../lib/src/utils/services/svg_service.dart#:~:text=loadQueue)

```dart
// Enqueue an SVG
Services.svg.enqueue(path: 'images/ui/icon.svg');

// Or enqueue several at once
Services.svg.enqueueAll(paths: [
    'images/ui/logo.svg',
    'images/ui/cursor.svg',
]);

// Somewhere in onLoad (before any SVGs are accessed)
await Services.svg.loadQueue();
```


### Accessing SVGs

- [Services.svg.get](../lib/src/utils/services/svg_service.dart#:~:text=Svg%3F+get)
- [Services.svg.contains](../lib/src/utils/services/svg_service.dart#:~:text=contains)

Use the `get` method or array syntax to fetch a parsed SVG. Both return `null`
if the SVG isn't cached.

```dart
final Svg? icon = Services.svg['images/ui/icon.svg'];
final Svg? logo = Services.svg.get('images/ui/logo.svg');
```


### Clearing cached SVGs

- [Services.svg.remove](../lib/src/utils/services/svg_service.dart#:~:text=remove)
- [Services.svg.clear](../lib/src/utils/services/svg_service.dart#:~:text=clear)

Use `remove` to drop a single SVG, or `clear` to wipe the whole cache.

```dart
Services.svg.remove('images/ui/icon.svg');
Services.svg.clear();
```


### Self-managing SVGs (without the queue)

- [Services.svg.load](../lib/src/utils/services/svg_service.dart#:~:text=load)

To load and use an SVG without queueing it, pass `cache: false` to the load
method.

```dart
final Svg svg = await Services.svg.load(
    path: 'images/temp.svg',
    cache: false,
);
```
