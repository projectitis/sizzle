# Dialog service

[:arrow_left: Back to services](services.md)

Yarn Spinner is a popular and powerful dialog system. Sizzle wraps the yarn
spinner [`jenny`](https://pub.dev/packages/jenny) package provided by Flame and
gives us some easy-to-use utility methods. Use the Sizzle
[`DialogComponent`][DialogComponent] for a speech bubble-like dialog window.

The dialog service is accessed via the global services class:

```dart
Services.dialog
```

Dialog (and Yarn Spinner) is its own whole topic, which is covered here
(coming soon).


## Loading and starting dialog

- [Services.dialog.load](../lib/src/utils/services/dialog_service.dart#:~:text=load) -
  load and parse one or more yarn files
- [Services.dialog.parse](../lib/src/utils/services/dialog_service.dart#:~:text=parse) -
  parse a yarn string directly
- [Services.dialog.start](../lib/src/utils/services/dialog_service.dart#:~:text=start) -
  start a dialog node, presented through one or more `DialogueView`s

```dart
// Load yarn files (replaces any previously loaded nodes)
await Services.dialog.load(
    ['dialog/intro.yarn', 'dialog/shop.yarn'],
    replaceNodes: true,
);

// Start a dialog node, presenting it through a DialogComponent view
await Services.dialog.start('intro_start', [dialogComponent]);
```

`start` returns a `Future` that completes when the dialog finishes. Only one
dialog can run at a time.


## Clearing dialog state

- [Services.dialog.clear](../lib/src/utils/services/dialog_service.dart#:~:text=clear)

Clearing data can be useful when moving between different areas of the game. By
default `clear` removes loaded yarn nodes only, but each category can be
toggled independently. Node visit counts are never cleared.

```dart
// Clear nodes only (default)
Services.dialog.clear();

// Clear nodes, variables, and characters
Services.dialog.clear(variables: true, characters: true);
```


## Yarn integration with flags

Sizzle automatically wires up two yarn helpers so [flags](services_flags.md)
can be read and written from your dialog scripts:

- `<<flag flag1,!flag2>>` sets `flag1` and unsets `flag2`
- `flagged("flag1,!flag2")` returns true when `flag1` is set and `flag2` is
  unset

Yarn variables are also automatically persisted with [save games](services_save.md).


## Direct yarn access

Most code should use the high-level methods above, but the underlying
[`YarnProject`](https://pub.dev/documentation/jenny/latest/jenny/YarnProject-class.html)
is exposed at `Services.dialog.yarn` for advanced cases such as registering
custom commands or characters.

[DialogComponent]: ../lib/src/display/dialog.dart
