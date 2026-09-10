# Save games

[:arrow_left: Back to services](services.md)

User data can be saved to disk and later reloaded. Sizzle provides hooks into
both the `load` and `save` methods to allow you full control of what is saved
and how it is restored.

The save data will contain all [flags](services_flags.md) and all current Yarn
Spinner variables (see [dialog](services_dialog.md)) by default. So when it's
reloaded, game and dialog history is maintained.

The save data is a single JSON document. Where it is stored depends on the
platform:

| Platform | Location |
| --- | --- |
| Android, iOS, Windows, macOS, Linux | The file `sizzle.json` in the application's documents directory |
| Web | The `localStorage` entry `sizzle.json`, since web builds have no file system |

The name `sizzle.json` is the default. See
[changing the save file name](#changing-the-save-file-name) below to use your
own name or several save slots.

On web, `localStorage` is scoped to the origin the game is served from, and is
erased when the player clears site data. It also has a per-origin quota of a few
megabytes, so keep custom save data small. Writing throws if the browser denies
storage access, which happens in private browsing modes that block site data.


## Changing the save file name

[Services.saveFile](../lib/src/utils/services.dart#:~:text=saveFile) holds the
name used by `save` and `load`. It defaults to `Services.defaultSaveFile`
(`sizzle.json`). Set it before the first save or load to use your own name:

```dart
Services.saveFile = 'my_game.json';
```

The name is used verbatim - as a file name in the documents directory on native
platforms, and as the `localStorage` key on web. It must be valid for the
platform, and it cannot be empty.

Changing it between calls gives you independent save slots:

```dart
Future<void> saveToSlot(int slot) async {
    Services.saveFile = 'save_$slot.json';
    await Services.save();
}
```

Each slot is a separate save file, so loading a slot that has never been written
leaves the current flags and yarn variables untouched (see `load` below).


## Saving and loading

- [Services.save](../lib/src/utils/services.dart#:~:text=save) - save the
  current session to the device
- [Services.load](../lib/src/utils/services.dart#:~:text=load) - load a saved
  session from the device

```dart
// Save the current state
await Services.save();

// Restore a previous save
await Services.load();
```

Calling `load` appends or replaces flags and yarn variables. Clear them first
(`Services.flags.clear()` /
`Services.dialog.clear(variables: true)`) if you want a clean slate before
loading.


## Customising what is saved

Two callbacks are available for adding your own data into the save file or
reacting to a load:

- [Services.onSave](../lib/src/utils/services.dart#:~:text=onSave) - called
  immediately before the save file is written. Mutate the supplied map to add
  your own keys.
- [Services.onLoad](../lib/src/utils/services.dart#:~:text=onLoad) - called
  immediately after the save file is read. Read your own keys back out of the
  supplied map.

```dart
Services.onSave = (data) {
    data['player'] = {
        'name': playerName,
        'health': playerHealth,
    };
};

Services.onLoad = (data) {
    final player = data['player'] as Map<String, dynamic>?;
    if (player != null) {
        playerName = player['name'] as String;
        playerHealth = player['health'] as int;
    }
};
```

The keys `_flags` and `_yarn` are reserved for Sizzle's own data, so avoid
using those names.
