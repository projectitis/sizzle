# Flag service

[:arrow_left: Back to services](services.md)

Flags are the preferred way to keep track of events within a Sizzle game. They
are simple boolean values (actually - they either exist, or they don't). They
can be used for tracking if specific game actions have taken place or not.

The flag service is accessed via the global services class:

```dart
Services.flags
```

Support for flags is included throughout Sizzle. You can set and check flags
directly from Yarn Spinner [dialog](services_dialog.md), and they are
automatically persisted with [save games](services_save.md).


## Setting and checking flags

```dart
// Player has opened a chest that has the castle key
Services.flags['castle_key'] = true;

// Later we check if the player has the castle key
if (Services.flags.flagged('castle_key')) {
    // Do stuff

    // Now we drop the key
    Services.flags['castle_key'] = false;
}
```

The array syntax (`Services.flags['x']`) reads as a `bool` and writes a `bool`,
so flags can be used in conditionals directly. The
[flag](../lib/src/utils/services/flag_service.dart#:~:text=flag) method is also
available if you prefer a method-based API:

```dart
// Equivalent to Services.flags['castle_key'] = true
Services.flags.flag('castle_key');

// Equivalent to Services.flags['castle_key'] = false
Services.flags.flag('castle_key', false);
```


## Bulk operations

- [Services.flags.flags](../lib/src/utils/services/flag_service.dart#:~:text=get+flags) -
  read or replace the full list of flags
- [Services.flags.clear](../lib/src/utils/services/flag_service.dart#:~:text=clear) -
  remove every flag

```dart
// Read all flags
final List<String> all = Services.flags.flags;

// Replace all flags in one go
Services.flags.flags = ['has_sword', 'visited_inn'];

// Remove every flag
Services.flags.clear();
```


## Methods at a glance

- [`flags['name'] = true`](../lib/src/utils/services/flag_service.dart#:~:text=operator+%5B%5D%3D)
  / [flag](../lib/src/utils/services/flag_service.dart#:~:text=flag) - set or
  unset a flag
- [`flags['name']`](../lib/src/utils/services/flag_service.dart#:~:text=operator+%5B%5D)
  / [flagged](../lib/src/utils/services/flag_service.dart#:~:text=flagged) -
  check whether a flag is set
- [flags](../lib/src/utils/services/flag_service.dart#:~:text=get+flags) - read
  or replace the full list of flags
- [clear](../lib/src/utils/services/flag_service.dart#:~:text=clear) - remove
  all flags
