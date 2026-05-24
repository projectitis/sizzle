# Config

[:arrow_left: Back to documentation](index.md)

- [What is Config?](#what-is-config)
- [The `.jx` file structure](#the-jx-file-structure)
- [Modifiers](#modifiers)
- [Loading a config](#loading-a-config)
- [Reading values](#reading-values)
- [Re-flattening at runtime](#re-flattening-at-runtime)
- [Errors and gotchas](#errors-and-gotchas)


## What is Config?

`Config` loads a `.jx` file at runtime and flattens it into a simple
`section → property → value` lookup. The same file can carry per-device,
per-orientation or per-capability overrides, picked up at load time based on a
capabilities map you supply.

Use it when you have values that vary by deployment target — UI offsets that
differ on mobile vs desktop, scale factors that differ between landscape and
portrait, asset names that change for a smartwatch build — and you'd rather
keep those variations in one place than in branching code.


## The `.jx` file structure

A config file is a JX object at the root. The top-level keys are **sections**,
each section contains **properties** and optional **modifier blocks**:

```js
{
    ui: {
        // Defaults
        titleColor: '#ffffff';
        titleScale: 1.0;

        // Override for mobile devices
        #mobile: {
            titleScale: 0.5;
        };

        // Override for any landscape display
        #landscape: {
            titleScale: 0.8;
        };
    };

    physics: {
        gravity: 9.8;
    };
}
```

Two structural rules:

- **Sections are top-level only.** A section cannot contain another section.
- **Properties cannot live at the root.** Every property must be inside a
  section.

JX is a [JSON superset](https://pub.dev/packages/jx): it allows unquoted keys,
single-quoted strings, `//` comments, and uses `;` or `,` as separators
between keys. **Every key:value pair needs a separator** — including pairs
whose value is an object, so remember the `;` after a closing `}`.

Property values are taken **literally**. If a property value happens to be an
object or array, Sizzle does not enter it to resolve nested modifiers — it's
just a value. Only modifier blocks at the section level (or nested inside
other modifier blocks) participate in flattening.


## Modifiers

A modifier is a key that starts with `#`. It applies its inner properties
only when the capability of the same name (without the `#`) is `true` in the
capabilities map you pass to [`Config.load`](../lib/src/utils/config.dart#:~:text=Future%3CConfig%3E+load)
or [`Config.parse`](../lib/src/utils/config.dart#:~:text=static+Config+parse).

Modifier names are arbitrary strings — Sizzle does not check them against a
fixed list. Anything you put in the capabilities map can be referenced, and
anything not in the map (or set to `false`) is silently skipped.

Modifiers may be **nested**, meaning logical AND. For example, this only
applies on mobile devices in landscape:

```js
ui: {
    titleScale: 1.0;
    #mobile: {
        #landscape: {
            titleScale: 0.7;
        };
    };
};
```

When several modifier blocks set the same property and more than one matches,
**document order wins** — the parser walks top-to-bottom and each matching
write overwrites the previous one. This lets defaults sit at the top of a
section, with overrides listed underneath in increasing specificity.


## Loading a config

Two entry points: [`Config.load`](../lib/src/utils/config.dart#:~:text=Future%3CConfig%3E+load)
for asset-bundle files, and [`Config.parse`](../lib/src/utils/config.dart#:~:text=static+Config+parse)
for an in-memory string.

```dart
final config = await Config.load('config/game.config.jx', {
    'mobile': true,
    'landscape': true,
    'touch': true,
});

// Or from a string
final config = Config.parse(jxSource, {'mobile': true});
```

`Config.load` reads through [`Services.files`](services_files.md) so the same
asset path conventions apply. The file is not added to the file cache — the
parsed `Config` is the authoritative copy.

The capabilities map is an arbitrary `Map<String, bool>` keyed by modifier
name (without the `#` prefix). A key missing from the map is treated the
same as one mapped to `false`. The map is optional; omit it for a defaults-
only load:

```dart
final config = await Config.load('config/game.config.jx');
```


## Reading values

Property paths are always exactly `"section.property"` — one dot, two
non-empty parts. Drilling into nested objects with extra dots is not
supported (the value at a property is returned literally if you need the
whole object).

### Typed accessors

Each typed accessor takes the path, an optional `defaultValue`, and returns
the value or the default (or `null`) if the key is missing. They throw
[`ArgumentError`](https://api.flutter.dev/flutter/dart-core/ArgumentError-class.html)
if the value is present but doesn't have the expected type.

- [`asStr`](../lib/src/utils/config.dart#:~:text=asStr) — string; strict, no
  coercion
- [`asInt`](../lib/src/utils/config.dart#:~:text=asInt) — int; accepts `int`,
  or `double` via `toInt()` (truncating)
- [`asDouble`](../lib/src/utils/config.dart#:~:text=asDouble) — double;
  accepts `double`, or `int` via `toDouble()`
- [`asBool`](../lib/src/utils/config.dart#:~:text=asBool) — bool; strict,
  strings like `'true'` are not coerced
- [`asColor`](../lib/src/utils/config.dart#:~:text=asColor) — `Color` from an
  RGB int; alpha is forced to fully opaque
- [`asARGBColor`](../lib/src/utils/config.dart#:~:text=asARGBColor) — `Color`
  from an ARGB int (`0xAARRGGBB`), used as-is
- [`asRGBAColor`](../lib/src/utils/config.dart#:~:text=asRGBAColor) — `Color`
  from an RGBA int (`0xRRGGBBAA`); the low alpha byte is rotated into the
  high position

```dart
final title = config.asStr('ui.titleText', defaultValue: 'Untitled');
final scale = config.asDouble('ui.titleScale', defaultValue: 1.0);
final speed = config.asInt('physics.maxSpeed', defaultValue: 100);
final debug = config.asBool('debug.enabled', defaultValue: false);
final tint  = config.asColor('ui.tint', defaultValue: const Color(0xffffffff));
```

The three color helpers all accept a numeric value and differ only in how
they interpret it:

| Helper          | Source format | Example input | Resulting `Color`  |
| --------------- | ------------- | ------------- | ------------------ |
| `asColor`       | `0xRRGGBB`    | `0xff8800`    | `Color(0xffff8800)`|
| `asARGBColor`   | `0xAARRGGBB`  | `0x80ff0000`  | `Color(0x80ff0000)`|
| `asRGBAColor`   | `0xRRGGBBAA`  | `0xff000080`  | `Color(0x80ff0000)`|

JX hex literals make these readable in the file itself:

```js
ui: {
    tint:      0xff8800;       // RGB     -> opaque orange
    overlay:   0x80000000;     // ARGB    -> 50% black
    highlight: 0xff000080;     // RGBA    -> red, 50% alpha
};
```

`asColor` is the right choice when the source values are plain RGB and you
just want them opaque. Use `asARGBColor` or `asRGBAColor` when the source
file deliberately encodes alpha — pick the one that matches the convention
of whoever authored the file.

### Raw access

The `[]` operator returns the literal value at the path, or `null` if it's
missing. Use this when the value is itself an object or array — anything
you stored as a property is handed back exactly as JX parsed it.

```dart
final raw = config['style.padding'];        // Map / List / primitive / null
```

### `asOffset` — fractional or absolute offsets

[`asOffset`](../lib/src/utils/config.dart#:~:text=asOffset) reads a number
and interprets it as a position within a `[min, max]` range. The same number
can express both a fraction and an absolute offset, depending on its
magnitude:

| Value `v`      | Result                                |
| -------------- | ------------------------------------- |
| `0 ≤ v ≤ 1`    | lerp from `min` to `max`              |
| `-1 ≤ v < 0`   | lerp from `max` back toward `min`     |
| `v > 1`        | `min + v` (absolute offset from min)  |
| `v < -1`       | `max + v` (absolute offset from max)  |

```dart
// With min=100, max=200:
config.asOffset('panel.x', 100, 200);   //  0.5 →  150 (midpoint)
config.asOffset('panel.x', 100, 200);   // -0.2 →  180 (fifth in from max)
config.asOffset('panel.x', 100, 200);   //  2.0 →  102 (2 px past min)
config.asOffset('panel.x', 100, 200);   // -2.0 →  198 (2 px in from max)
```

This is useful for layout values that should follow the same anchor in any
window size: a fraction expresses "halfway across", an absolute value
expresses "exactly two pixels from the edge".

### `asPos` — 2D position relative to a SizzleGame window

[`asPos`](../lib/src/utils/config.dart#:~:text=asPos) reads an object with
optional `x`, `y` and `window` properties and returns a `Vector2` of screen
pixels relative to the current [SizzleGame](game_structure.md). `x` and `y`
follow the same rules as `asOffset`; the `window` property picks which of
the game's windows to resolve against:

| `window` value   | Window used                          |
| ---------------- | ------------------------------------ |
| missing or other | `SizzleGame.viewWindow` (default)    |
| `'target'`       | `SizzleGame.safeWindow` (target area)|
| `'max'`          | `SizzleGame.gameWindow` (max area)   |

Missing axes default to `0` (the window's near edge on that axis).

```js
panel: {
    pos:    { x: 0.5, y: 0.5 };                       // center of view
    title:  { x: 0.5, y: 0.1, window: 'target' };     // 10% down the target area
    badge:  { x: -8,  y: 8,   window: 'max' };        // 8px in from max area's right/top
};
```

```dart
final centre = config.asPos('panel.pos');       // Vector2(viewCentreX, viewCentreY)
final title  = config.asPos('panel.title');
final badge  = config.asPos('panel.badge');
```


## Re-flattening at runtime

The flattened snapshot is built from the parsed tree at load time, so reading
values is cheap. The tree itself is retained, so you can re-flatten against a
new capabilities map without reparsing the file — useful for orientation
changes:

```dart
config.onChange = () => refreshLayout();
config.capabilities = {'mobile': true, 'portrait': true};
```

Assigning [`capabilities`](../lib/src/utils/config.dart#:~:text=set+capabilities)
re-walks the tree and fires the optional `onChange` callback. Assigning a
capabilities map that is **equivalent** to the current one — including a
key explicitly set to `false` versus a key omitted entirely — is a no-op
and `onChange` is not fired.

`onChange` is a single, assignable callback in the same shape as
`Services.onSave` / `Services.onLoad`. There is no listener list; if you need
multiple subscribers, fan out from your callback.


## Errors and gotchas

- **Missing key vs wrong type.** Missing keys never throw — they return the
  `defaultValue` (or `null`). Wrong types **do** throw `ArgumentError` so
  authoring bugs in your `.jx` file surface immediately.
- **Path shape.** `operator[]` and the `as*` helpers require exactly
  `'section.property'`. `config['section']` (no dot) and `config['a.b.c']`
  (extra dots) both throw `ArgumentError`.
- **Root-level errors.** A property at the root, or a `#`-prefixed modifier
  at the root, throws `FormatException` at load time. Wrap everything in a
  section.
- **Unknown modifiers.** `#somethingNew` in the file is silently skipped if
  the capabilities map doesn't include it. This means a typo in either the
  file or the map fails quietly — values just stay at their defaults.
- **Separators after `}`.** JX requires a `;` or `,` between every
  key:value pair in an object, even when the value is itself an object.
  Forgetting the separator after `}` causes the next key to be parsed as a
  member of the just-closed object, not as a sibling.
