#!/usr/bin/env python3
"""
psd_to_lpng.py — Convert a Photoshop PSD file to a Layered PNG (.lpng) file.

A .lpng file is a ZIP archive containing:
  - manifest.json   : the document/layer tree (see example-manifest.json)
  - thumbnail.png   : a full-image preview, max 128x128, aspect preserved
  - imageN.png ...  : one PNG per rasterised (non-group) layer (with
                      --optimize, layers with identical pixels share one PNG)

The manifest root is a document object:

    {
      "id": "<file stem, only with --set-id>",
      "name": "<file stem>",
      "w": <canvas width>,
      "h": <canvas height>,
      "dpi": <dots per inch, optional>,
      "v": "<lpng format version>",
      "layers": [ ... ]
    }

Each entry in "layers" is a layer. A layer with a "src" is an image; a layer
without a "src" (but with its own "layers") is a group. All properties are
optional and defaults are omitted rather than written explicitly:

    name        layer name from the PSD (need not be unique)
    src         PNG filename inside the zip (absent => group). More than one
                layer may reference the same file.
    x, y        integer offset from the parent's origin (default 0)
    opacity     0.0 .. 1.0 (default 1.0)
    visibility  bool (default true)
    blend       Photoshop blend mode name in lowerCamelCase (default "normal")
    id          unique id (layers and the document; only emitted with --set-id)
    layers      child layers (groups, and images that contain nested layers)

Layer array order is bottom-to-top (index 0 is drawn first / underneath).

Requirements:
    pip install psd-tools Pillow

Usage:
    python psd_to_lpng.py input.psd [output.lpng] [--out FILE] [--set-id]
                          [--optimize] [--thumbnail N|WxH]
"""

import argparse
import hashlib
import io
import json
import os
import re
import sys
import zipfile

try:
    from psd_tools import PSDImage
    from psd_tools.constants import Resource, Tag
except ImportError:
    sys.exit(
        "Error: psd-tools is required. Install it with:\n"
        "    pip install psd-tools Pillow"
    )

try:
    from PIL import Image
except ImportError:
    sys.exit("Error: Pillow is required. Install it with:\n    pip install Pillow")


# lpng format version written to the manifest as "v".
LPNG_VERSION = "0.1.0"

# Default maximum thumbnail size (fits within THUMB_MAX x THUMB_MAX).
THUMB_MAX = 128

# Photoshop layer-effect (layer style) keys -> human labels, for warnings.
# psd-tools does not render these into the composited pixels, so a layer that
# relies on them (e.g. a Color Overlay) will export with its raw pixels only.
EFFECT_LABELS = {
    b"SoFi": "color overlay",
    b"GrFl": "gradient overlay",
    b"patternFill": "pattern overlay",
    b"DrSh": "drop shadow",
    b"IrSh": "inner shadow",
    b"OrGl": "outer glow",
    b"IrGl": "inner glow",
    b"ebbl": "bevel & emboss",
    b"ChFX": "satin",
    b"FrFX": "stroke",
}


# Adjustment-layer kinds have no pixels of their own (they modify the layers
# below). lpng has no equivalent concept, so these are skipped with a warning.
ADJUSTMENT_KINDS = {
    "brightness",
    "levels",
    "curves",
    "exposure",
    "vibrance",
    "huesaturation",
    "colorbalance",
    "blackandwhite",
    "photofilter",
    "channelmixer",
    "colorlookup",
    "invert",
    "posterize",
    "threshold",
    "gradientmap",
    "selectivecolor",
}


def warn(message):
    print(f"  warning: {message}", file=sys.stderr)


def parse_thumbnail_size(value):
    """Parse a --thumbnail argument: "128" -> (128, 128), "128x64" -> (128, 64)."""
    parts = value.lower().split("x")
    try:
        if len(parts) == 1:
            n = int(parts[0])
            size = (n, n)
        elif len(parts) == 2:
            size = (int(parts[0]), int(parts[1]))
        else:
            raise ValueError
    except ValueError:
        raise argparse.ArgumentTypeError(
            f"invalid thumbnail size '{value}' (expected e.g. 128 or 128x64)"
        )
    if size[0] <= 0 or size[1] <= 0:
        raise argparse.ArgumentTypeError(
            f"thumbnail size must be positive (got '{value}')"
        )
    return size


def blend_to_string(mode):
    """Map a psd-tools BlendMode to a lowerCamelCase Photoshop name.

    Returns None for the default "normal" mode (so it is omitted from the
    manifest). "passThrough" is emitted explicitly because it is semantically
    different from "normal" for groups.
    """
    if mode is None:
        return None
    name = getattr(mode, "name", str(mode))  # e.g. "COLOR_BURN"
    if name == "NORMAL":
        return None
    parts = name.lower().split("_")
    return parts[0] + "".join(p.capitalize() for p in parts[1:])


def enabled_effects(layer):
    """Return a list of human labels for the layer's enabled layer effects.

    psd-tools does not composite Photoshop layer styles (color overlay, drop
    shadow, etc.), so these are detected only to warn the user. Returns [] when
    there are no enabled effects (or the master effects switch is off).
    """
    try:
        tb = layer.tagged_blocks
        data = tb.get_data(Tag.OBJECT_BASED_EFFECTS_LAYER_INFO)
    except Exception:
        data = None
    if data is None:
        return []
    master = data.get(b"masterFXSwitch")
    if master is not None and not bool(master):
        return []
    labels = []
    for key, value in data.items():
        try:
            enabled = value.get(b"enab")
        except (AttributeError, TypeError):
            continue
        if enabled is not None and bool(enabled):
            labels.append(EFFECT_LABELS.get(key, key.decode("ascii", "replace")))
    return labels


def clean_name(name):
    """Strip null bytes and surrounding whitespace from a PSD layer name."""
    if not name:
        return ""
    return name.replace("\x00", "").strip()


def slugify(name):
    """Reduce a layer name to lowercase letters, numbers and underscores."""
    slug = re.sub(r"[^a-z0-9]+", "_", (name or "").lower()).strip("_")
    return slug or "layer"


def unique_id(name, registry):
    """Return a unique id derived from name, suffixing _2, _3, ... on clashes."""
    base = slugify(name)
    candidate = base
    n = 2
    while candidate in registry:
        candidate = f"{base}_{n}"
        n += 1
    registry.add(candidate)
    return candidate


def get_dpi(psd):
    """Best-effort read of horizontal DPI from the PSD resolution resource."""
    try:
        info = psd.image_resources.get_data(Resource.RESOLUTION_INFO)
        value = getattr(info, "horizontal", None)
        if value is None:
            return None
        value = float(value)
        # Resolution is sometimes exposed as 16.16 fixed point.
        if value > 5000:
            value /= 65536.0
        if value <= 0:
            return None
        return round(value)
    except Exception:
        return None


class Converter:
    def __init__(self, set_id, canvas, optimize):
        self.set_id = set_id
        self.canvas = canvas      # (width, height) of the document
        self.optimize = optimize
        self.images = {}          # filename -> PNG bytes
        self.image_counter = 0
        self.id_registry = set()
        self.pixel_hashes = {}    # pixel hash -> filename (--optimize only)
        self.deduped = 0          # layers that reused an existing image

    def next_src(self):
        self.image_counter += 1
        return f"image{self.image_counter}.png"

    def store_image(self, image):
        """Encode an image and return its filename inside the zip.

        With --optimize, layers with byte-identical pixels share a single PNG:
        the first occurrence is encoded and stored, later ones just point their
        "src" at it. Without --optimize every layer gets its own copy.
        """
        if self.optimize:
            key = (image.size, hashlib.sha256(image.tobytes()).digest())
            existing = self.pixel_hashes.get(key)
            if existing is not None:
                self.deduped += 1
                return existing

        buffer = io.BytesIO()
        image.save(buffer, format="PNG")
        src = self.next_src()
        self.images[src] = buffer.getvalue()
        if self.optimize:
            self.pixel_hashes[key] = src
        return src

    def clip_to_canvas(self, image, left, top):
        """Crop an image to the intersection of its rect and the canvas.

        Returns (cropped_image, new_left, new_top) or None if the layer lies
        entirely outside the canvas.
        """
        width, height = self.canvas
        l = max(left, 0)
        t = max(top, 0)
        r = min(left + image.width, width)
        b = min(top + image.height, height)
        if r <= l or b <= t:
            return None
        if (l, t, r, b) == (left, top, left + image.width, top + image.height):
            return image, left, top  # already within bounds, no crop needed
        cropped = image.crop((l - left, t - top, r - left, b - top))
        return cropped, l, t

    def rasterise(self, layer):
        """Composite a single layer to a PIL image (respecting masks/effects).

        Hidden layers are still rasterised (force=True) so their pixels are
        preserved; visibility is recorded separately in the manifest.
        Returns None if the layer has no drawable pixels.
        """
        try:
            image = layer.composite(force=True)
        except Exception as exc:
            warn(f"could not composite layer '{layer.name}': {exc}")
            return None
        if image is None:
            return None
        if image.width == 0 or image.height == 0:
            return None
        return image.convert("RGBA")

    def build(self, layer):
        """Build a node dict for a layer, or None if it is skipped.

        The node carries a temporary '_bbox' (absolute PSD left/top/right/bottom)
        and '_children'; these are resolved into relative x/y by finalize().
        """
        kind = getattr(layer, "kind", None)

        if layer.is_group():
            children = []
            for child in layer:
                node = self.build(child)
                if node is not None:
                    children.append(node)
            if not children:
                warn(f"skipping empty group '{layer.name}'")
                return None
            # Group bbox is the tight union of its (kept) children.
            left = min(c["_bbox"][0] for c in children)
            top = min(c["_bbox"][1] for c in children)
            right = max(c["_bbox"][2] for c in children)
            bottom = max(c["_bbox"][3] for c in children)
            node = {
                "name": clean_name(layer.name),
                "_bbox": (left, top, right, bottom),
                "_children": children,
            }
            self._add_common(node, layer)
            return node

        if kind in ADJUSTMENT_KINDS:
            warn(f"skipping adjustment layer '{layer.name}' ({kind}, unsupported)")
            return None

        effects = enabled_effects(layer)
        if effects:
            warn(
                f"layer '{clean_name(layer.name)}' has layer effects "
                f"({', '.join(effects)}) that are NOT rendered - rasterise it "
                f"in Photoshop before export to bake them in"
            )

        image = self.rasterise(layer)
        if image is None:
            warn(f"skipping layer '{layer.name}' (no drawable pixels)")
            return None

        left, top = layer.offset  # (left, top) of the layer's bbox

        if self.optimize:
            clipped = self.clip_to_canvas(image, left, top)
            if clipped is None:
                warn(
                    f"skipping layer '{clean_name(layer.name)}' "
                    f"(entirely outside the canvas)"
                )
                return None
            image, left, top = clipped

        bbox = (left, top, left + image.width, top + image.height)

        src = self.store_image(image)

        node = {
            "name": clean_name(layer.name),
            "src": src,
            "_bbox": bbox,
            "_children": [],
        }
        self._add_common(node, layer)
        return node

    def _add_common(self, node, layer):
        """Attach opacity / visibility / blend, omitting defaults."""
        opacity = round(layer.opacity / 255.0, 3)
        if opacity != 1.0:
            node["opacity"] = opacity
        if not layer.visible:
            node["visibility"] = False
        blend = blend_to_string(layer.blend_mode)
        if blend is not None:
            node["blend"] = blend

    def finalize(self, node, parent_left, parent_top):
        """Resolve absolute bboxes into relative x/y and assign ids in order.

        Emits a clean dict with a stable key order and no temporary fields.
        """
        left, top, _, _ = node["_bbox"]
        x = left - parent_left
        y = top - parent_top

        out = {}
        if self.set_id:
            out["id"] = unique_id(node.get("name", ""), self.id_registry)
        if "name" in node:
            out["name"] = node["name"]
        if "src" in node:
            out["src"] = node["src"]
        if x != 0:
            out["x"] = x
        if y != 0:
            out["y"] = y
        if "opacity" in node:
            out["opacity"] = node["opacity"]
        if "visibility" in node:
            out["visibility"] = node["visibility"]
        if "blend" in node:
            out["blend"] = node["blend"]

        children = node.get("_children", [])
        if children:
            out["layers"] = [self.finalize(c, left, top) for c in children]
        return out


def build_thumbnail(psd, max_size):
    """Composite the document and return PNG bytes of a preview.

    The preview fits within max_size (width, height) preserving aspect ratio,
    and is never upscaled beyond the document's own resolution.
    """
    try:
        full = psd.composite(force=True)
    except Exception as exc:
        warn(f"could not composite document for thumbnail: {exc}")
        return None
    if full is None:
        return None
    thumb = full.convert("RGBA")
    # Image.thumbnail only ever shrinks, so thumbnails are never upscaled.
    thumb.thumbnail(max_size, Image.LANCZOS)
    buffer = io.BytesIO()
    thumb.save(buffer, format="PNG")
    return buffer.getvalue()


def convert(input_path, output_path, set_id, optimize, thumbnail_size):
    print(f"Reading {input_path} ...")
    psd = PSDImage.open(input_path)

    converter = Converter(
        set_id=set_id,
        canvas=(psd.width, psd.height),
        optimize=optimize,
    )

    print("Rasterising layers ...")
    top_nodes = []
    for layer in psd:
        node = converter.build(layer)
        if node is not None:
            top_nodes.append(node)

    stem = os.path.splitext(os.path.basename(input_path))[0]

    manifest = {}
    # Only emit an id when requested; the document id is derived from the file
    # name (and reserved first so child ids can't collide with it).
    if set_id:
        manifest["id"] = unique_id(stem, converter.id_registry)
    manifest["name"] = stem
    manifest["w"] = psd.width
    manifest["h"] = psd.height
    dpi = get_dpi(psd)
    if dpi is not None:
        manifest["dpi"] = dpi
    manifest["v"] = LPNG_VERSION

    # Top-level layers are positioned relative to the canvas origin (0, 0).
    manifest["layers"] = [converter.finalize(n, 0, 0) for n in top_nodes]

    print("Building thumbnail ...")
    thumbnail = build_thumbnail(psd, thumbnail_size)

    print(f"Writing {output_path} ...")
    with zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr(
            "manifest.json",
            json.dumps(manifest, indent=2, ensure_ascii=False),
        )
        if thumbnail is not None:
            zf.writestr("thumbnail.png", thumbnail)
        for src, data in converter.images.items():
            zf.writestr(src, data)

    deduped = ""
    if converter.deduped:
        deduped = f" ({converter.deduped} duplicate layer(s) shared)"
    print(
        f"Done. {len(converter.images)} layer image(s){deduped}, "
        f"{'thumbnail, ' if thumbnail else ''}manifest.json."
    )


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Convert a PSD file to a Layered PNG (.lpng) file."
    )
    parser.add_argument("input", help="Input .psd file")
    parser.add_argument(
        "output",
        nargs="?",
        help="Output .lpng file (default: input name with .lpng extension)",
    )
    parser.add_argument(
        "-o",
        "--out",
        dest="out",
        help="Output .lpng file (overrides the positional output argument).",
    )
    parser.add_argument(
        "--set-id",
        action="store_true",
        help="Generate a unique id for every layer, derived from its name.",
    )
    parser.add_argument(
        "--optimize",
        action="store_true",
        help="Crop each layer PNG to the canvas bounds, discarding pixels that "
        "fall outside the document, and store only one copy of layers with "
        "identical pixels (smaller files; layers appear at final size).",
    )
    parser.add_argument(
        "--thumbnail",
        type=parse_thumbnail_size,
        default=(THUMB_MAX, THUMB_MAX),
        metavar="SIZE",
        help="Maximum thumbnail size as N or WxH (default: %d). Aspect ratio is "
        "preserved and the thumbnail is never upscaled." % THUMB_MAX,
    )
    args = parser.parse_args(argv)

    if not os.path.isfile(args.input):
        sys.exit(f"Error: input file not found: {args.input}")

    output = args.out or args.output
    if output is None:
        output = os.path.splitext(args.input)[0] + ".lpng"

    convert(args.input, output, args.set_id, args.optimize, args.thumbnail)


if __name__ == "__main__":
    main()
