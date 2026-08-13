# Layered PNG (`.lpng`)

A simple, open layered-image format — loosely inspired by
[OpenRaster](https://www.openraster.org/), but using a JSON manifest instead of
XML and plain PNGs for layer data.

## Container

An `.lpng` file is a ZIP archive containing:

| Entry           | Description                                                     |
| --------------- | --------------------------------------------------------------- |
| `manifest.json` | The document + layer tree (see below).                          |
| `thumbnail.png` | Full-image preview, max **128×128**, aspect ratio preserved.    |
| `imageN.png`    | One PNG per rasterised (non-group) layer, cropped to its bounds.|

## Manifest

The manifest root is a **document object**:

```json
{
  "id": "root",
  "name": "Character Sheet",
  "w": 600,
  "h": 800,
  "dpi": 300,
  "v": "0.1.0",
  "layers": [ ... ]
}
```

| Key      | Meaning                                            |
| -------- | -------------------------------------------------- |
| `id`     | Document id, derived from the file name. Only emitted with `--set-id`. |
| `name`   | Document name (the source file's stem).            |
| `w`, `h` | Canvas size in pixels.                             |
| `dpi`    | Resolution, if known (omitted otherwise).          |
| `v`      | lpng format version.                               |
| `layers` | Array of layers, **bottom-to-top** (index 0 = drawn first / underneath). |

### Layers

Each entry in `layers` is either an **image** (has `src`) or a **group** (has
`layers` but no `src`). Every property is optional, and defaults are omitted
rather than written explicitly.

| Key          | Type    | Default    | Notes                                                                 |
| ------------ | ------- | ---------- | --------------------------------------------------------------------- |
| `id`         | string  | —          | Unique across the manifest. Only emitted with `--set-id`.             |
| `name`       | string  | —          | From the PSD layer name; need not be unique.                          |
| `src`        | string  | —          | PNG filename in the zip. Absent ⇒ this layer is a group. Several layers may reference the same file (see `--optimize`). |
| `x`, `y`     | number  | `0`        | Integer offset from the **parent's** origin (parent = canvas for top level, else the group's tight bounding box). |
| `opacity`    | number  | `1.0`      | `0.0`–`1.0`.                                                          |
| `visibility` | boolean | `true`     | `false` for hidden layers (the PNG is still included).                |
| `blend`      | string  | `"normal"` | Photoshop blend mode in lowerCamelCase (`normal`/`srcOver` are interchangeable). |
| `layers`     | array   | —          | Child layers (present on groups, and on images with nested children). |

Blend mode names follow Photoshop, camel-cased: `multiply`, `colorBurn`,
`linearDodge`, `softLight`, `hardLight`, `difference`, `exclusion`,
`passThrough`, etc. A consumer only needs to implement the modes it supports and
may fall back to `srcOver` for the rest.

## Converting a PSD

```bash
pip install -r requirements.txt          # psd-tools + Pillow

python psd_to_lpng.py input.psd                 # -> input.lpng
python psd_to_lpng.py input.psd out.lpng        # explicit output (positional)
python psd_to_lpng.py input.psd --out out.lpng  # explicit output (flag)
python psd_to_lpng.py input.psd --set-id        # generate ids from names
python psd_to_lpng.py input.psd --optimize      # crop to canvas + share duplicates
python psd_to_lpng.py input.psd --thumbnail 64  # cap thumbnail at 64x64
python psd_to_lpng.py input.psd --thumbnail 128x64
```

| Flag             | Effect                                                                 |
| ---------------- | --------------------------------------------------------------------- |
| `-o`, `--out`    | Output file name (overrides the positional argument).                 |
| `--set-id`       | Emit ids. Every layer gets a unique id derived from its name (lowercase letters, numbers and underscores), suffixing `_2`, `_3`, … on clashes; the document id is derived from the file name. Without this flag, no `id` fields are written (not even on the document). |
| `--optimize`     | Crop each layer PNG to the canvas bounds, discarding pixels that fall outside the document. Offsets and group bounds are adjusted to match, and layers entirely off-canvas are dropped. Layers already appear at final display resolution, so this mainly trims oversized/off-canvas layers — often a large file-size win. Also stores only one PNG for layers whose pixels are identical (after cropping); the duplicates point their `src` at the same file. |
| `--thumbnail`    | Maximum thumbnail size as `N` (e.g. `128` → 128×128) or `WxH` (e.g. `128x64`). Default `128`. Aspect ratio is preserved and the thumbnail is **never upscaled** past the document's own resolution. |

### Conversion behaviour

- **Groups** get a tight bounding box (the union of their children); children
  are positioned relative to it.
- **Text, shapes, smart objects and fill layers** are rasterised to PNG as they
  appear (including layer masks and effects).
- **Adjustment layers** (curves, levels, hue/saturation, …) have no pixels of
  their own and are **skipped with a warning** — lpng has no equivalent concept.
- Hidden layers are still exported; `visibility: false` is recorded.

### Layer effects / styles are NOT rendered

Photoshop **layer effects** (a.k.a. layer styles: Color Overlay, Drop Shadow,
Stroke, Bevel & Emboss, glows, etc.) are **not** applied to the exported PNGs —
psd-tools cannot composite them, so only the layer's raw pixels are written.

For example, a black shape with a white *Color Overlay* exports as **black**.

The converter detects enabled effects and prints a warning naming the layer and
the effects it found. **If a layer relies on an effect, rasterise that layer in
Photoshop before exporting** (Layer → Rasterize → Layer Style, or merge the
style down) so the effect is baked into the pixels.
