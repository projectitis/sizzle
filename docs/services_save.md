# Save games

[:arrow_left: Back to services](services.md)

User data can be saved to disk and later reloaded. Sizzle provides hooks into
both the `load` and `save` methods to allow you full control of what is saved
and how it is restored.

The save data will contain all [flags](services_flags.md) and all current Yarn
Spinner variables (see [dialog](services_dialog.md)) by default. So when it's
reloaded, game and dialog history is maintained.

The save file is a single JSON file (`sizzle.json`) stored in the application's
documents directory.


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
