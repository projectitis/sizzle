# Layered PNG (`.lpng`)

[:arrow_left: Back to documentation](index.md)

- [What is a Layered PNG?](#what-is-a-layered-png)
- [Loading a document](#loading-a-document)
- [Stepping through layers](#stepping-through-layers)
- [Finding a layer by id](#finding-a-layer-by-id)
- [Rendering to an image](#rendering-to-an-image)
- [Blend modes](#blend-modes)
- [Disposing](#disposing)
- [Producing `.lpng` files](#producing-lpng-files)


## What is a Layered PNG?

A Layered PNG (`.lpng`) is a simple layered-image format: a ZIP archive holding
a `manifest.json`, a `thumbnail.png`, and one PNG per image layer. It is loosely
based on [OpenRaster](https://www.openraster.org/) but uses a JSON manifest.
The `LayeredPng` class loads one from your assets, exposes the layer tree, and
rasterises the whole document — or any single layer — to a `dart:ui` image.

The manifest is a document object with a tree of layers. Each layer is either an
**image** (it has a `src` PNG) or a **group** (no `src`; it composites its
children). Layers carry an optional `id`, `name`, offset (`x`/`y` from the
parent), `opacity`, `visibility` and `blend` mode. See
[`scripts/lpng/README.md`](../scripts/lpng/README.md) for the full spec and the
PSD-to-lpng converter.


## Loading a document

```dart
import 'package:sizzle/sizzle.dart';

final doc = await LayeredPng.load('assets/character.lpng');

print('${doc.name} ${doc.width}x${doc.height}');   // metadata
print(doc.thumbnail);                               // ui.Image? preview
```

`load` reads the asset, unzips it, parses the manifest and **decodes every layer
PNG up front**, so image access afterwards is synchronous. To load from bytes
you already have (e.g. in a test), use `LayeredPng.fromBytes(bytes)`.


## Stepping through layers

Top-level layers are in `doc.layers`, ordered **bottom-to-top** (index `0` is
drawn first / underneath). Each layer's children are in `layer.layers`.

To visit the whole tree, use `walk()` — a depth-first, pre-order iterable:

```dart
for (final layer in doc.walk()) {
  final kind = layer.isGroup ? 'group' : 'image';
  print('${layer.name}  ($kind)  opacity=${layer.opacity}');
}
```

`layer.walk()` does the same for a single subtree (starting with the layer
itself).


## Finding a layer by id

`layerById` searches the whole tree (or a subtree) and returns the first match,
or `null`:

```dart
final logo = doc.layerById('pirelli_logo');
final childOnly = doc.layerById('logos')?.layerById('pirelli_logo');
```

Ids are only present when the file was exported with `--set-id`; otherwise look
layers up by walking and matching on `name`.


## Rendering to an image

Rasterise the whole document at its canvas size:

```dart
final ui.Image full = await doc.toImage();      // width x height
```

Rasterise any single layer. The result is cropped to the layer's content
(`bounds` tells you where it sits in the document), and children are composited
with their own opacity and blend modes:

```dart
final layer = doc.layerById('logos')!;
final ui.Image image = await layer.toImage();   // sized to layer.bounds
final where = layer.bounds.topLeft;             // document-space position
```

For a plain image layer you can also reach the decoded PNG directly, without any
compositing, via `layer.image` (`null` for groups).

> The layer's **own** opacity is applied by `toImage`, but its own blend mode is
> not — there is no backdrop to blend against in an isolated render. Blend modes
> only take effect when a layer is composited over others (i.e. in the document
> `toImage`, or within a group).


## Blend modes

`LpngBlendMode` covers all the Photoshop blend names. Many map directly to a
`dart:ui` `BlendMode`; the rest fall back to `srcOver` when compositing:

| Native `ui.BlendMode` | `srcOver` fallback |
| --------------------- | ------------------ |
| normal, darken, multiply, colorBurn, lighten, screen, colorDodge, overlay, softLight, hardLight, difference, exclusion, hue, saturation, color, luminosity, linearDodge (→ `plus`) | dissolve, linearBurn, darkerColor, lighterColor, vividLight, linearLight, pinLight, hardMix, subtract, divide |

`passThrough` (a group-only mode) maps to no `BlendMode`: its children blend
against the backdrop behind the group rather than being isolated. The raw
manifest string is always available on `layer.blendName` if you need to
implement an unsupported mode yourself.


## Disposing

Decoded images are retained for the life of the document. Call `dispose()` when
you are finished to release every layer image and the thumbnail:

```dart
doc.dispose();
```


## Producing `.lpng` files

Convert a Photoshop `.psd` with the bundled Python script:

```bash
python scripts/lpng/psd_to_lpng.py input.psd --set-id --optimize
```

See [`scripts/lpng/README.md`](../scripts/lpng/README.md) for all options
(output path, thumbnail size, id generation, canvas cropping) and important
notes — most notably that **Photoshop layer effects are not rendered**, so a
layer that relies on one (e.g. a Color Overlay) should be rasterised in
Photoshop before export.
