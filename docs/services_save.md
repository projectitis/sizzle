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
[choosing the save file](#choosing-the-save-file) below to use your own name or
several save slots.

Writing is all-or-nothing on both platforms. Native saves are written to a
temporary file and then renamed into place, so a crash or a kill part-way
through a save leaves the previous save intact rather than a truncated file.
`localStorage` entries are replaced whole by the browser.

On web, `localStorage` is scoped to the origin the game is served from, and is
erased when the player clears site data. It also has a per-origin quota of a few
megabytes, so keep custom save data small. Saving fails if the browser denies
storage access, which happens in private browsing modes that block site data.


## Saving and loading

- [Services.save](../lib/src/utils/services.dart#:~:text=save) - save the
  current session to the device
- [Services.load](../lib/src/utils/services.dart#:~:text=load) - load a saved
  session from the device

Both return `true` on success and `false` on failure, and neither ever throws.
When something goes wrong the reason is reported through
[Services.log](services_log.md), so the returned `bool` is all your game
needs to decide whether to tell the player.

```dart
// Save the current state
if (!await Services.save()) {
    showToast('Could not save your game');
}

// Restore a previous save
await Services.load();
```

`load` returns `true` only when a save was found, validated and applied. It
returns `false` both when there is nothing saved and when the save could not be
used - see [when loading fails](#when-loading-fails) for telling those apart.

Calling `load` replaces all flags, and appends or replaces yarn variables. Clear
the yarn variables first (`Services.dialog.clear(variables: true)`) if you want
a clean slate before loading.

`save` records the state as of the call, not as of the moment the write reaches
the device. Saves and loads are run one at a time in the order they were
requested, so two overlapping saves produce two writes rather than interfering
with each other.


## Choosing the save file

Every method takes an optional `name`. Omit it and the call uses
[Services.saveFile](../lib/src/utils/services.dart#:~:text=saveFile), which
defaults to `Services.defaultSaveFile` (`sizzle.json`):

```dart
// Change the default for every later call
Services.saveFile = 'my_game.json';

// Or override it for a single call, leaving Services.saveFile alone
await Services.save(name: 'my_game.json');
```

The name is used verbatim - as a file name in the documents directory on native
platforms, and as the `localStorage` key on web. It must be valid for the
platform, and it cannot be empty.

Independent save slots are a `name` away:

```dart
Future<void> saveToSlot(int slot) => Services.save(name: 'save_$slot.json');
Future<bool> loadSlot(int slot) => Services.load(name: 'save_$slot.json');
```

Each slot is a separate document. Loading a slot that has never been written
leaves the current flags and yarn variables untouched, and custom data never
leaks from one slot into another.


## Checking for and deleting a save

- [Services.hasSave](../lib/src/utils/services.dart#:~:text=hasSave) - whether
  save data exists
- [Services.deleteSave](../lib/src/utils/services.dart#:~:text=deleteSave) -
  remove save data

```dart
// Only offer "continue" if there is something to continue
continueButton.enabled = await Services.hasSave();

// Clear a slot
await Services.deleteSave(name: 'save_2.json');
```

`hasSave` does not validate what it finds - a damaged save still reports `true`.

`deleteSave` returns `true` if there is no longer a save there, including when
there was nothing to delete. It does not clear the running session: flags and
yarn variables are left exactly as they are.


## When loading fails

A document that cannot be used is **moved aside** to `<name>.corrupt` rather
than deleted. Sizzle never destroys player data on its own, and a damaged save
is often recoverable by hand or by a later version of your game. The next `save`
writes a clean document in its place.

Because the file is moved, `hasSave` has to be checked *before* `load` to tell
"nothing saved" apart from "the save was damaged":

```dart
final had = await Services.hasSave();
if (await Services.load()) {
    continueGame();
} else if (had) {
    // The old document is now sizzle.json.corrupt
    showDamagedSaveDialog();
} else {
    newGame();
}
```

Moving the file aside is best effort. If that write also fails, the document is
left where it is and a warning is logged - a failing load never turns into a
second failure.


## What is validated

A load never leaves your game half restored. The whole document is checked
first, and flags and yarn variables are only touched once every check has
passed.

A wrong container shape means the document is not a Sizzle save at all - a file
from another program, or from an incompatible version - so it is rejected whole.
A single bad entry inside an otherwise sound container is a much smaller
problem, so it is dropped and the rest still loads.

| Condition | Result |
| --- | --- |
| Not valid JSON | Document rejected, logged as an error |
| The root is not an object | Document rejected, logged as an error |
| `_flags` is present but is not a list | Document rejected, logged as an error |
| A `_flags` entry is not a string | Entry dropped, logged as a warning |
| `_yarn` is present but is not an object | Document rejected, logged as an error |
| A `_yarn` name is not a string | Entry dropped, logged as a warning |
| A `_yarn` value is not a string, number or bool | Entry dropped, logged as a warning |

The last row matters more than it looks. Yarn variables can only hold strings,
numbers and bools, and an unsupported value used to be accepted at load time and
then fail much later, inside a dialogue, a long way from the cause.


## Customising what is saved

Two callbacks are available for adding your own data into the save file or
reacting to a load:

- [Services.onSave](../lib/src/utils/services.dart#:~:text=onSave) - called
  while the save document is being built. Mutate the supplied map to add your
  own keys.
- [Services.onLoad](../lib/src/utils/services.dart#:~:text=onLoad) - called
  after a save document has been read and applied. Read your own keys back out
  of the supplied map.

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

Three things to know:

- Everything you add must be JSON-encodable. A `DateTime` or a class of your own
  fails the save, which is reported and logged, leaving whatever was already
  saved untouched.
- Exceptions thrown from these callbacks are **not** caught. A failure in your
  own code is a bug to fix, not a failed save, so it is not swallowed.
- `onLoad` runs after flags and yarn variables have been restored, so it sees
  fully loaded state. Do not call `save` or `load` from inside either callback.

Keys your game does not recognise are preserved. Loading a document written by a
newer version of your game and saving it again keeps that version's keys intact.

The keys `_flags` and `_yarn` are reserved for Sizzle's own data, so avoid
using those names.


## Where the data is stored

[Services.saveStorage](../lib/src/utils/services.dart#:~:text=saveStorage) holds
the `SaveStorage` that save data goes through. It defaults to
`PlatformSaveStorage`, which uses the device locations in the table at the top
of this page.

Assign your own implementation to put save data somewhere else - a cloud
backend, or an encrypted container:

```dart
class CloudSaveStorage implements SaveStorage {
    @override
    Future<String?> read(String name) => api.fetch(name);

    @override
    Future<void> write(String name, String contents) => api.put(name, contents);

    @override
    Future<bool> exists(String name) => api.head(name);

    @override
    Future<void> delete(String name) => api.remove(name);

    @override
    Future<void> rename(String from, String to) => api.move(from, to);
}

Services.saveStorage = CloudSaveStorage();
```

Implementations report failure by throwing; `save` and `load` catch, log and
return `false`, so a backend needs no error handling of its own. `write` must be
all-or-nothing - a half-written document is exactly the corruption this design
exists to prevent.

Sizzle also ships `MemorySaveStorage`, which keeps everything in a map and
persists nothing. Use it to test your own `onSave` and `onLoad` without touching
the device:

```dart
final storage = MemorySaveStorage();
Services.saveStorage = storage;

await Services.save();
expect(storage.entries[Services.saveFile], contains('hi_score'));
```
