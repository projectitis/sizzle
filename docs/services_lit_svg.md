# Lit SVG service

[:arrow_left: Back to services](services.md)

The lit-SVG service parses and caches SVG assets so they can be drawn through
the `LitSvgComponent`. It mirrors the same queue/load/cache pattern used by
the [image](services_images.md) and [file](services_files.md) services and is
accessed via the global services class:

```dart
Services.litSvg
```

> Use this service when you need **runtime lit rendering** of a vector shape
> (per-frame lighting changes, normal-mapped surfaces). If you just want to
> load an SVG and treat it as a static `Image`, the [image
> service](services_images.md#svg-assets) rasterizes any `.svg` asset on
> load and caches it like a PNG.

## Workflow for caching SVGs

The suggested workflow for working with SVGs is:
1. SVGs are enqueued and loaded
2. SVGs are used
3. SVG cache is cleared (if required)

SVGs are keyed in the cache by their asset path and are loaded relative to the
`assets/` folder.

### Enqueuing SVGs

- [Services.litSvg.enqueue](../lib/src/utils/services/lit_svg_service.dart#:~:text=enqueue)
- [Services.litSvg.enqueueAll](../lib/src/utils/services/lit_svg_service.dart#:~:text=enqueueAll)
- [Services.litSvg.loadQueue](../lib/src/utils/services/lit_svg_service.dart#:~:text=loadQueue)

```dart
// Enqueue an SVG
Services.litSvg.enqueue(path: 'images/ui/icon.svg');

// Or enqueue several at once
Services.litSvg.enqueueAll(paths: [
    'images/ui/logo.svg',
    'images/ui/cursor.svg',
]);

// Somewhere in onLoad (before any SVGs are accessed)
await Services.litSvg.loadQueue();
```


### Accessing SVGs

- [Services.litSvg.get](../lib/src/utils/services/lit_svg_service.dart#:~:text=LitSvgData%3F+get)
- [Services.litSvg.contains](../lib/src/utils/services/lit_svg_service.dart#:~:text=contains)

Use the `get` method or array syntax to fetch a parsed SVG. Both return `null`
if the SVG isn't cached.

```dart
final LitSvgData? icon = Services.litSvg['images/ui/icon.svg'];
final LitSvgData? logo = Services.litSvg.get('images/ui/logo.svg');
```


### Clearing cached SVGs

- [Services.litSvg.remove](../lib/src/utils/services/lit_svg_service.dart#:~:text=remove)
- [Services.litSvg.clear](../lib/src/utils/services/lit_svg_service.dart#:~:text=clear)

Use `remove` to drop a single SVG, or `clear` to wipe the whole cache.

```dart
Services.litSvg.remove('images/ui/icon.svg');
Services.litSvg.clear();
```


### Self-managing SVGs (without the queue)

- [Services.litSvg.load](../lib/src/utils/services/lit_svg_service.dart#:~:text=load)

To load and use an SVG without queueing it, pass `cache: false` to the load
method.

```dart
final LitSvgData svg = await Services.litSvg.load(
    path: 'images/temp.svg',
    cache: false,
);
```
