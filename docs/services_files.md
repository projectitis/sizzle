# File service

[:arrow_left: Back to services](services.md)

The file service provides asset loading, parsing and caching for arbitrary
files. It is accessed via the global services class:

```dart
Services.files
```

## Workflow for caching files

The suggested workflow for working with files is:
1. Files are enqueued and loaded
2. Files are used
3. File cache is cleared (if required)

It mirrors the same enqueue/`loadQueue` pattern used by the
[image service](services_images.md). Files are loaded relative to the
`assets/` folder.

### Enqueuing files

- [Services.files.enqueue](../lib/src/utils/services/file_service.dart#:~:text=enqueue)
- [Services.files.enqueueAll](../lib/src/utils/services/file_service.dart#:~:text=enqueueAll)
- [Services.files.loadQueue](../lib/src/utils/services/file_service.dart#:~:text=loadQueue)

Different parts of your game can enqueue the files they need in their
constructors. The queue is loaded once - usually from your game controller's
`onLoad` - so all files are available before any scene tries to use them.

```dart
// In a UI constructor
Services.files.enqueue(path: 'data/levels.json');
Services.files.enqueue(properties: FileProperties(
    'data/dialog/intro.yarn',
    name: 'intro',
));

// Or enqueue several at once
Services.files.enqueueAll(paths: [
    'data/items.json',
    'data/maps.json',
]);

// Somewhere in onLoad (before any files are accessed)
await Services.files.loadQueue();
```

`FileProperties` accepts an optional `name` to use as a shorter cache key.
Without it the path is used as the name.


### Accessing files

Cached files can be accessed in their raw `ByteData` form, or decoded as
`String`, `JSON` or [JX](https://pub.dev/packages/jx) on demand. The `[]`
operator and `get` both return raw `ByteData`.

- [Services.files.get](../lib/src/utils/services/file_service.dart#:~:text=ByteData%3F+get) -
  raw bytes
- [Services.files.getString](../lib/src/utils/services/file_service.dart#:~:text=getString) -
  decoded string
- [Services.files.getJson](../lib/src/utils/services/file_service.dart#:~:text=getJson) -
  parsed JSON
- [Services.files.getJX](../lib/src/utils/services/file_service.dart#:~:text=getJX) -
  parsed JX
- [Services.files.contains](../lib/src/utils/services/file_service.dart#:~:text=contains) -
  check if cached

```dart
final ByteData? raw = Services.files['data/levels.json'];
final String yarn = Services.files.getString('intro');
final dynamic levels = Services.files.getJson('data/levels.json');
```


### Clearing cached files

- [Services.files.remove](../lib/src/utils/services/file_service.dart#:~:text=remove)
- [Services.files.clear](../lib/src/utils/services/file_service.dart#:~:text=clear)

Use `remove` to drop a single entry, or `clear` to wipe the whole cache.

```dart
Services.files.remove('data/levels.json');
Services.files.clear();
```


### Self-managing files (without the queue)

- [Services.files.load](../lib/src/utils/services/file_service.dart#:~:text=load)
- [Services.files.loadString](../lib/src/utils/services/file_service.dart#:~:text=loadString)
- [Services.files.loadJson](../lib/src/utils/services/file_service.dart#:~:text=loadJson)
- [Services.files.loadJX](../lib/src/utils/services/file_service.dart#:~:text=loadJX)

To load a file without queueing or caching it, pass `cache: false` to one of
the load methods. Each load method also accepts a `FileProperties` instead of
a `path` if you want to specify a custom name.

```dart
// Load a one-off JSON file without caching
final dynamic data = await Services.files.loadJson(
    path: 'data/temp_config.json',
    cache: false,
);
```
