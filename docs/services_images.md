# Image service

[:arrow_left: Back to services](services.md)

The `Image services` provides image utility methods, loading and caching. The image services
are accessed via the global services class:

``` dart
Services.images
```

## Workflow for caching images

The suggested workflow for working with images is:
1. Images are enqueued and loaded
2. Images are used
3. Image cache is cleared (if required)

### Enqueuing images

- [Services.images.enqueue](../lib/src/utils/services/image_service.dart#:~:text=enqueue)
- [Services.images.loadQueue](../lib/src/utils/services/image_service.dart#:~:text=loadQueue)

Various parts of your game may require images. Each of these should enqueue the images in their
constructor. For example, different UI elements will need images, the map will need images, the
player sprite requires images etc.

Images can be enqueued with additional properties that will transform the image during load.

Enqueued images are not available until `loadQueue` is called. This should be called once from a
central place - since it is asynchronous, this is usually your game controller's `onLoad` method.
If there are many images to load, consider displaying a loading graphic.

Images are queued until they are removed or the queue is cleared. Attempting to `load` or 
`loadQueue` will ignore images that are already queued, so it is safe to call it without checking
the queue first. 

```dart
// In UI constructor
Services.images.enqueue(path: 'images/ui/background.png');
Services.images.enqueue(path: 'images/ui/border.png');
Services.images.enqueue(properties: ImageProperties(
    'images/ui/ticker.png',
    scale: Vector2.all(0.5),
));

// In player constructor
Services.images.enqueue(properties: ImageProperties(
    'images/player/sprite_sheet.png',
    name: 'player-right',
    scale: Vector2.all(0.5),
));
Services.images.enqueue(properties: ImageProperties(
    'images/player/sprite_sheet.png',
    name: 'player-left',
    scale: Vector2.all(0.5),
    flipX: true,
));

// Somewhere in the onLoad method (before any images are accessed)
await Services.images.loadQueue();
```


### Accessing images

- [Services.images.get](../lib/src/utils/services/image_service.dart#:~:text=get(String+name))

Use the `get` method or array syntax to get images that have been cached using `enqueue` and
`loadQueue`, or individually using `load`.

```dart
// Grab a queued image using array syntax
Image uiBackground = Services.images['images/ui/background.png'];

// Grab a queued image using the [get] method
Image uiBorder = Services.images.get('images/ui/ticker.png');

// Grab a queued image using a shorter name set during load (see above)
Image playerLeft = Services.images['player-left'];

// Returns null
Image? doesNotExist = Services.images['does-not-exist'];
```

Use [`Services.images.contains`](../lib/src/utils/services/image_service.dart#:~:text=contains)
to check whether a name is cached without triggering a null read.


### Clearing queued images

- [Services.images.remove](../lib/src/utils/services/image_service.dart#:~:text=remove)
- [Services.images.clear](../lib/src/utils/services/image_service.dart#:~:text=clear)

Use `remove` to remove individual images from the cache, or `clear` to remove all images from the
cache. They will be properly disposed to avoid memory leaks.

**Important:** Never call `dispose` on a queued image. This will invalidate the image in the queue
and future attempts to use it will fail. Instead, call `Services.images.remove` for that image.

```dart
// Remove an image from the queue and dispose of it
Services.images.remove('images/ui/background.png');

// Remove and dispose all queued images
Services.images.clear();
```


### Self-managing images (without the queue)

- [Services.images.load](../lib/src/utils/services/image_service.dart#:~:text=load)

To load and use images without queueing them, simply pass `cache: false` to the load method.

```dart
// Use the image service to load an image, but manage it myself
Image myImage = await Services.images.load(path: 'images/smile.png', cache: false);

// The image is not cached, so this returns null
Image? tryCachedImage = Services.images['images/smile.png'];

// Remember to dispose of the image when no longer required
myImage.dispose();
```


## Image properties

`ImageProperties` describes both the asset to load and the transformations to
apply to it before caching. The transformation pipeline runs once at load time
so the cached `Image` is already in its final form.

| Property | Description |
| -------- | ----------- |
| `path` | Asset path, relative to the `assets/` folder. Required. |
| `name` | Optional shorter name to use as the cache key. Defaults to `path`. |
| `scale` | `Vector2` scale factor applied per axis. |
| `crop` | `Rect` describing the area of the image to keep. |
| `angle` | Rotation in radians. See `fitCrop` for how it interacts with `crop`. |
| `fitCrop` | When rotating, scale the rotated image so that `crop`'s width and height fully fit. Position of the crop is ignored when `fitCrop` is true. |
| `flipX` | Mirror the image horizontally. |
| `flipY` | Mirror the image vertically. |
| `antiAlias` | Use antialiasing when transforming the image (defaults to `true`). |
| `blendMode` | `BlendMode` used while drawing the transformed image (defaults to `srcOver`). |
| `filterQuality` | `FilterQuality` used while drawing the transformed image (defaults to `low`). |
| `ignoreDefaultProperties` | When true, the global default properties are skipped for this image. |

If no transforming properties are set, the original `Image` is cached as-is and
no extra GPU work is performed.


### Default image properties

Set `Services.images.defaultProperties` to transform all loaded images by these properties. This
is useful if you need to scale all images based on the device that is being used (e.g. on desktop
don't scale, but on mobile scale all images to 50%).

This is how it's done:

```dart
Services.images.defaultProperties = ImageProperties(
    '', // Leave the path blank (it is not used)
    scale: Vector2.all(0.5),
);
```

The default properties can be cleared by setting it to `null`.

```dart
Services.images.defaultProperties = null;
```

The properties of individual images will be _merged_ with the default properties. The following
code will result in an image that is both scaled to 50% and flipped horizontally.

```dart
Services.images.defaultProperties = ImageProperties(
    '', // Leave the path blank (it is not used)
    scale: Vector2.all(0.5),
);

Services.images.load(properties: ImageProperties(
    'images/player/sprite_sheet.png',
    flipX: true,
));
```

To completely ignore the default properties, set the `ignoreDefaultProperties` property to `true`.
The following code will result in an image that is flipped vertically. None of the default
properties are applied (scale, flipX, angle, antiAlias).

```dart
Services.images.defaultProperties = ImageProperties(
    '', // Leave the path blank (it is not used)
    scale: Vector2.all(0.5),
    flipX: true,
    angle: 37.0,
    antiAlias: false,
);

Services.images.load(properties: ImageProperties(
    'images/player/sprite_sheet.png',
    flipY: true,
    ignoreDefaultProperties: true,
));
```
