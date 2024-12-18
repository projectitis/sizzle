# Image service

[:arrow_left: Back to services](services.md)

The `Image services` provides image utility classes, loading and caching. The image services
are accessed via the global services class:

``` dart
Services.images
```

## Workflow for caching images

The suggested workflow for working with images is:
1. Images are enqueued and loaded
3. Images are used
4. Image cache is cleared (if required)

### Enqueuing images

- [Services.images.enqueue](../lib/src/game/utils/services/image_service.dart#:~:text=enqueue)
- [Services.images.loadQueue](../lib/src/game/utils/services/image_service.dart#:~:text=loadQueue)

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

``` dart
// In UI constructor
Services.images.enqueue(path: 'images/ui/background.png');
Services.images.enqueue(path: 'images/ui/border.png');
Services.images.enqueue(properties: ImageProperties(
    'images/ui/ticker.png',
    scale: 0.5,
));

// In player constructor
Services.images.enqueue(properties: ImageProperties(
    'images/player/sprite_sheet.png',
    name: 'player-right',
    scale: 0.5,
));
Services.images.enqueue(properties: ImageProperties(
    'images/player/sprite_sheet.png',
    name: 'player-left',
    scale: 0.5,
    flipX: true,
));

// Somewhere in the onLoad method (before any images are accessed)
await Services.images.loadQueue();
```


### Accessing images

- [Services.images.get](../lib/src/game/utils/services/image_service.dart#:~:text=get(String+name))

Use the `get` method or array syntax to get images that have been cached using `enqueue` and
`loadQueue`, or individually using `load`.

``` dart
// Grab a queued image using array syntax
Image uiBackground = Services.images['images/ui/background.png'];

// Grab a queued image using the [get] method
Image uiBorder = Services.images.get('images/ui/ticker.png');

// Grab a queued image using a shorter name set during load (see above)
Image playerLeft = Services.images['player-left'];

// Throws an exception
Image doesNotExist = Services.images['does-not-exist'];
```


### Clearing queued images

- [Services.images.remove](../lib/src/game/utils/services/image_service.dart#:~:text=remove)
- [Services.images.clear](../lib/src/game/utils/services/image_service.dart#:~:text=clear)

Use `remove` to remove individual images from the cache, or `clear` to remove all images from the
cache. They will be properly disposed to avoid memory leaks.

**Important:** Never call `dispose` on a queued image. This will invalidate the image in the queue
and future attempts to use it will fail. Instead, call `Services.images.remove` for that image.

``` dart
// Remove an image from the queue and dispose of it
Services.images.remove('images/ui/background.png');

// Remove and dispose all queued images
Services.images.clear();
```


### Self-managing images (without the queue)

- [Services.images.load](../lib/src/game/utils/services/image_service.dart#:~:text=load)

To load and use images without queueing them, simply pass `queue = false` to the load method.

``` dart
// Use the image service to load an image, but manage it myself
Image myImage = await Services.images.load(path: 'images/smile.png', cache: false);

// The image is not cached, so this will throw
Image tryCachedImage = Services.images['images/smile.png'];

// Remember to dispose of the image when no longer required
myImage.dispose();
```
