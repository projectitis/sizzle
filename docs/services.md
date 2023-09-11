# Game services

[:arrow_left: Back to documentation](index.md)

The `Services` are static methods that can be accessed from anywhere within
your code, much like a global variable. Since they're static there's no need
to create an instance of the services.

- [Loading assets](#loading-assets)
- [Managing dialog](#managing-dialog)
- [Tracking player actions with flags](#flags)
- [Save games](#save-games)


## Loading assets

There are various methods to load and cache assets. Caching means that
re-using the asset will take much less time on subsequent loads, but will take
up memory. Caching is optional.

The following methods are available:

- [Services.loadImage](../lib/src/game/services.dart#:~:text=loadImage) for loading `Image` objects
- [Services.loadFile](../lib/src/game/services.dart#:~:text=loadFile) for loading a file as `ByteData`
- [Services.loadString](../lib/src/game/services.dart#:~:text=loadString) for loading a file as a `String`
- [Services.loadJson](../lib/src/game/services.dart#:~:text=loadJson) for loading an parsing a JSON file
- [Services.clearCache](../lib/src/game/services.dart#:~:text=clearCache) for clearing some or all of the cached files


## Managing dialog

Yarn Spinner is a popular and powerful dialog system. Sizzle wraps the yarn spinner 'jenny' package provided by Flame, and gives us some easy-to-use utility methods. Use the Sizzle
[`DialogComponent`][DialogComponent] for a speech bubble-like dialog window.

Dialog (and Yarn Spinner) is it's own whole topic, which covered here (coming soon).

- [Services.loadDialog](../lib/src/game/services.dart#:~:text=loadDialog) for loading yarn file assets
- [Services.startDialog](../lib/src/game/services.dart#:~:text=startDialog) for starting a dialog interaction
- [Services.clearDialog](../lib/src/game/services.dart#:~:text=startDialog) for clearing yarn nodes, variables etc


## Flags

Flags are the preferred way to keep track of events within a Sizzle game. They
are simple boolean values (actually- they either exist, or they don't). They
can be used for tracking if specific game actions have taken place or not. For
example:

```dart
// Player has opened a chest that has the castle key
Services.flag('castle_key');

// Later we check if the player has the castle key
if (Services.flagged('castle_key')){
    // Do stuff

    // Now we drop the key
    Services.flag('castle_key', false);
}
```

Support for flags is included throughout Sizzle. You can set and check flags
directly from Yarn Spinner dialog, and they are automatically saved/loaded when
the user saves the game progress (see [save games](#save-games)).

- [Services.flag](../lib/src/game/services.dart#:~:text=flag) set or unset a flag
- [Services.flagged](../lib/src/game/services.dart#:~:text=flagged) check if flag is set


## Save games

User data can be saved and later reloaded. Sizzle provides hooks into both the
`load` and `save` methods to allow the user full control of what is saved and
how it is restored.

The save data will contain all [flags](#flags) and all current yarn spinner
variables by default. So when it's reloaded, game and dialog history is
maintained.

- [Services.save](../lib/src/game/services.dart#:~:text=save) save session to the device
- [Services.load](../lib/src/game/services.dart#:~:text=load) load session from the device

[DialogComponent]: ../lib/src/display/dialog.dart
