import 'dart:convert';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/painting.dart' show decodeImageFromList;
import 'package:flutter/services.dart';

/// A parsed Layered PNG (`.lpng`) document.
///
/// An `.lpng` file is a ZIP archive containing a `manifest.json`, a
/// `thumbnail.png`, and one PNG per image layer. See `scripts/lpng/README.md`
/// for the format specification.
///
/// Load one from an asset with [load], then walk the layer tree, look layers up
/// by [id], and rasterise the whole document or any single layer to a
/// [ui.Image]:
///
/// ```dart
/// final doc = await LayeredPng.load('assets/character.lpng');
/// for (final layer in doc.walk()) {
///   print('${layer.name} ${layer.isGroup ? '(group)' : ''}');
/// }
/// final logo = doc.layerById('pirelli_logo');
/// final image = await logo!.toImage();
/// // ... draw image, then doc.dispose() when finished.
/// ```
///
/// Every layer PNG is decoded up front during [load], so [LpngLayer.image] and
/// [LpngLayer.bounds] are available synchronously afterwards. Call [dispose]
/// when finished to release the decoded images.
class LayeredPng {
  LayeredPng._();

  /// Document id, if provided.
  String? id;

  /// The document name, if provided.
  String name = '';

  /// Canvas width in pixels.
  int width = 0;

  /// Canvas height in pixels.
  int height = 0;

  /// Resolution in dots-per-inch, if provided.
  double? dpi;

  /// The lpng format version the file was written with.
  String version = '';

  /// Top-level layers, ordered **bottom-to-top** (index 0 is drawn first, and
  /// therefore appears underneath the others).
  final List<LpngLayer> layers = <LpngLayer>[];

  /// The decoded document thumbnail (max 128x128 by default), or `null` if the
  /// archive did not contain one.
  ui.Image? thumbnail;

  /// The document bounds: `(0, 0)` to `(width, height)`.
  ui.Rect get bounds =>
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());

  /// Load and parse an `.lpng` [assetPath] from [bundle] (defaults to the
  /// root asset bundle). All layer images are decoded before this completes.
  static Future<LayeredPng> load(String assetPath,
      {AssetBundle? bundle}) async {
    final data = await (bundle ?? rootBundle).load(assetPath);
    return fromBytes(data.buffer.asUint8List());
  }

  /// Parse an `.lpng` document from its raw ZIP [bytes]. Useful for tests or
  /// loading from sources other than the asset bundle.
  static Future<LayeredPng> fromBytes(Uint8List bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);

    final manifestFile = archive.findFile('manifest.json');
    if (manifestFile == null) {
      throw const FormatException('lpng archive has no manifest.json');
    }
    final manifest = jsonDecode(
      utf8.decode(manifestFile.content as List<int>),
    ) as Map<String, dynamic>;

    final doc = LayeredPng._()
      ..id = manifest['id'] as String?
      ..name = manifest['name'] as String? ?? ''
      ..width = (manifest['w'] as num?)?.toInt() ?? 0
      ..height = (manifest['h'] as num?)?.toInt() ?? 0
      ..dpi = (manifest['dpi'] as num?)?.toDouble()
      ..version = manifest['v'] as String? ?? '';

    final rawLayers = manifest['layers'] as List<dynamic>? ?? const [];
    for (final raw in rawLayers) {
      doc.layers.add(
        await _buildLayer(raw as Map<String, dynamic>, archive, 0, 0),
      );
    }

    doc.thumbnail = await _decodeImage(archive, 'thumbnail.png');
    return doc;
  }

  static Future<LpngLayer> _buildLayer(
    Map<String, dynamic> raw,
    Archive archive,
    double parentX,
    double parentY,
  ) async {
    final src = raw['src'] as String?;
    final x = (raw['x'] as num?)?.toDouble() ?? 0;
    final y = (raw['y'] as num?)?.toDouble() ?? 0;

    final layer = LpngLayer._()
      ..id = raw['id'] as String?
      ..name = raw['name'] as String?
      ..src = src
      ..x = x
      ..y = y
      ..absX = parentX + x
      ..absY = parentY + y
      ..opacity = (raw['opacity'] as num?)?.toDouble() ?? 1.0
      ..visible = raw['visibility'] as bool? ?? true
      ..blendName = raw['blend'] as String? ?? 'normal'
      ..blend = LpngBlendMode.parse(raw['blend'] as String?);

    if (src != null) {
      layer.image = await _decodeImage(archive, src);
    }

    final children = raw['layers'] as List<dynamic>? ?? const [];
    for (final child in children) {
      layer.layers.add(
        await _buildLayer(
          child as Map<String, dynamic>,
          archive,
          layer.absX,
          layer.absY,
        ),
      );
    }
    return layer;
  }

  static Future<ui.Image?> _decodeImage(Archive archive, String name) async {
    final file = archive.findFile(name);
    if (file == null) return null;
    return decodeImageFromList(Uint8List.fromList(file.content as List<int>));
  }

  /// Depth-first, pre-order iteration over every layer in the document
  /// (top-level layers and all their descendants).
  Iterable<LpngLayer> walk() sync* {
    for (final layer in layers) {
      yield* layer.walk();
    }
  }

  /// Find a layer anywhere in the tree by its [id], or `null` if none matches.
  LpngLayer? layerById(String id) {
    for (final layer in layers) {
      final found = layer.layerById(id);
      if (found != null) return found;
    }
    return null;
  }

  /// Rasterise the entire document to a [width] x [height] image, compositing
  /// every visible layer with its offset, opacity and blend mode.
  Future<ui.Image> toImage() {
    return _record(width, height, (canvas) {
      for (final layer in layers) {
        _paintLayer(canvas, layer);
      }
    });
  }

  /// Dispose every decoded layer image and the thumbnail. The document should
  /// not be used afterwards.
  void dispose() {
    for (final layer in walk()) {
      layer.image?.dispose();
      layer.image = null;
    }
    thumbnail?.dispose();
    thumbnail = null;
  }
}

/// A single node in a [LayeredPng] tree — either an **image** (has [src] /
/// [image]) or a **group** (no [src]; composites its [layers]).
class LpngLayer {
  LpngLayer._();

  /// Unique id, if provided.
  String? id;

  /// The layer name, if provided. Not guaranteed unique.
  String? name;

  /// PNG filename inside the archive. `null` for groups.
  String? src;

  /// Offset from the parent's origin (the canvas for a top-level layer, or the
  /// parent group's tight bounding box otherwise).
  double x = 0;
  double y = 0;

  /// Absolute offset within the document, i.e. [x]/[y] accumulated down from
  /// the root. Used for compositing and [bounds].
  double absX = 0;
  double absY = 0;

  /// Layer opacity, `0.0`–`1.0`.
  double opacity = 1.0;

  /// Whether the layer is visible. Hidden layers are still parsed and decoded.
  bool visible = true;

  /// The parsed blend mode. Unrecognised names fall back to
  /// [LpngBlendMode.normal] (the original string is kept in [blendName]).
  LpngBlendMode blend = LpngBlendMode.normal;

  /// The raw blend mode string from the manifest (`'normal'` when omitted).
  String blendName = 'normal';

  /// Child layers, ordered bottom-to-top.
  final List<LpngLayer> layers = <LpngLayer>[];

  /// The decoded PNG for this layer, or `null` for a group (or before load).
  ui.Image? image;

  /// Whether this layer is a group (has no image of its own).
  bool get isGroup => src == null;

  /// The absolute bounding box of this layer's subtree in document
  /// coordinates: the union of this layer's own image and all descendants.
  ui.Rect get bounds {
    ui.Rect? rect;
    final img = image;
    if (img != null) {
      rect = ui.Rect.fromLTWH(
        absX,
        absY,
        img.width.toDouble(),
        img.height.toDouble(),
      );
    }
    for (final child in layers) {
      final childBounds = child.bounds;
      rect = rect == null ? childBounds : rect.expandToInclude(childBounds);
    }
    return rect ?? ui.Rect.fromLTWH(absX, absY, 0, 0);
  }

  /// Depth-first, pre-order iteration over this layer and all its descendants.
  Iterable<LpngLayer> walk() sync* {
    yield this;
    for (final child in layers) {
      yield* child.walk();
    }
  }

  /// Find this layer or a descendant by [id], or `null` if none matches.
  LpngLayer? layerById(String id) {
    if (this.id == id) return this;
    for (final child in layers) {
      final found = child.layerById(id);
      if (found != null) return found;
    }
    return null;
  }

  /// Rasterise this layer (and its descendants) to an image sized to [bounds].
  ///
  /// The returned image is cropped to the subtree's content; use [bounds] to
  /// know where it sits in the document. Descendants are composited with their
  /// own opacity and blend modes. This layer's *own* opacity is applied, but
  /// its own blend mode is not — there is no backdrop to blend against in an
  /// isolated render.
  Future<ui.Image> toImage() {
    final b = bounds;
    final w = b.width.ceil();
    final h = b.height.ceil();
    return _record(w < 1 ? 1 : w, h < 1 ? 1 : h, (canvas) {
      canvas.translate(-b.left, -b.top);
      if (opacity < 1.0) {
        canvas.saveLayer(null, _alphaPaint(opacity));
        _paintContent(canvas, this);
        canvas.restore();
      } else {
        _paintContent(canvas, this);
      }
    });
  }
}

/// Photoshop blend modes, named in lowerCamelCase as they appear in a
/// manifest. Only a subset maps to a native [ui.BlendMode]; the rest fall back
/// to [ui.BlendMode.srcOver] when compositing (see [uiBlendMode]).
enum LpngBlendMode {
  normal,
  dissolve,
  darken,
  multiply,
  colorBurn,
  linearBurn,
  darkerColor,
  lighten,
  screen,
  colorDodge,
  linearDodge,
  lighterColor,
  overlay,
  softLight,
  hardLight,
  vividLight,
  linearLight,
  pinLight,
  hardMix,
  difference,
  exclusion,
  subtract,
  divide,
  hue,
  saturation,
  color,
  luminosity,

  /// Group-only mode: children blend against the backdrop behind the group
  /// rather than being isolated. Maps to no [ui.BlendMode].
  passThrough;

  /// Parse a manifest blend string. `'normal'`/`'srcOver'` (and `null`) map to
  /// [normal]; unrecognised strings also fall back to [normal].
  static LpngBlendMode parse(String? value) {
    switch (value) {
      case null:
      case 'normal':
      case 'srcOver':
        return normal;
      case 'dissolve':
        return dissolve;
      case 'darken':
        return darken;
      case 'multiply':
        return multiply;
      case 'colorBurn':
        return colorBurn;
      case 'linearBurn':
        return linearBurn;
      case 'darkerColor':
        return darkerColor;
      case 'lighten':
        return lighten;
      case 'screen':
        return screen;
      case 'colorDodge':
        return colorDodge;
      case 'linearDodge':
        return linearDodge;
      case 'lighterColor':
        return lighterColor;
      case 'overlay':
        return overlay;
      case 'softLight':
        return softLight;
      case 'hardLight':
        return hardLight;
      case 'vividLight':
        return vividLight;
      case 'linearLight':
        return linearLight;
      case 'pinLight':
        return pinLight;
      case 'hardMix':
        return hardMix;
      case 'difference':
        return difference;
      case 'exclusion':
        return exclusion;
      case 'subtract':
        return subtract;
      case 'divide':
        return divide;
      case 'hue':
        return hue;
      case 'saturation':
        return saturation;
      case 'color':
        return color;
      case 'luminosity':
        return luminosity;
      case 'passThrough':
        return passThrough;
      default:
        return normal;
    }
  }

  /// The native [ui.BlendMode] used when compositing, or `null` for
  /// [passThrough]. Modes with no `dart:ui` equivalent (e.g. [linearBurn],
  /// [vividLight], [subtract]) fall back to [ui.BlendMode.srcOver].
  ui.BlendMode? get uiBlendMode {
    switch (this) {
      case normal:
        return ui.BlendMode.srcOver;
      case darken:
        return ui.BlendMode.darken;
      case multiply:
        return ui.BlendMode.multiply;
      case colorBurn:
        return ui.BlendMode.colorBurn;
      case lighten:
        return ui.BlendMode.lighten;
      case screen:
        return ui.BlendMode.screen;
      case colorDodge:
        return ui.BlendMode.colorDodge;
      case linearDodge:
        return ui.BlendMode.plus; // "Linear Dodge (Add)" ~= plus
      case overlay:
        return ui.BlendMode.overlay;
      case softLight:
        return ui.BlendMode.softLight;
      case hardLight:
        return ui.BlendMode.hardLight;
      case difference:
        return ui.BlendMode.difference;
      case exclusion:
        return ui.BlendMode.exclusion;
      case hue:
        return ui.BlendMode.hue;
      case saturation:
        return ui.BlendMode.saturation;
      case color:
        return ui.BlendMode.color;
      case luminosity:
        return ui.BlendMode.luminosity;
      case passThrough:
        return null;
      default:
        // dissolve, linearBurn, darkerColor, lighterColor, vividLight,
        // linearLight, pinLight, hardMix, subtract, divide — no ui equivalent.
        return ui.BlendMode.srcOver;
    }
  }
}

// ---------------------------------------------------------------------------
// Compositing helpers (shared by the document and individual layers).
// ---------------------------------------------------------------------------

Future<ui.Image> _record(
  int width,
  int height,
  void Function(ui.Canvas canvas) draw,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  draw(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

ui.Paint _alphaPaint(double opacity) {
  final a = (opacity.clamp(0.0, 1.0) * 255).round();
  return ui.Paint()..color = ui.Color.fromARGB(a, 255, 255, 255);
}

/// Paint a layer (with its own opacity/blend against the current backdrop)
/// onto [canvas] at its absolute position.
void _paintLayer(ui.Canvas canvas, LpngLayer layer) {
  if (!layer.visible) return;

  // passThrough groups and plain normal layers do not need isolation.
  final needsIsolation = layer.opacity < 1.0 ||
      (layer.blend != LpngBlendMode.normal &&
          layer.blend != LpngBlendMode.passThrough);

  if (needsIsolation) {
    final paint = _alphaPaint(layer.opacity);
    final mode = layer.blend.uiBlendMode;
    if (mode != null) paint.blendMode = mode;
    canvas.saveLayer(null, paint);
    _paintContent(canvas, layer);
    canvas.restore();
  } else {
    _paintContent(canvas, layer);
  }
}

/// Draw a layer's own image (if any) then its children, without applying the
/// layer's own opacity/blend.
void _paintContent(ui.Canvas canvas, LpngLayer layer) {
  final img = layer.image;
  if (img != null) {
    canvas.drawImage(img, ui.Offset(layer.absX, layer.absY), ui.Paint());
  }
  for (final child in layer.layers) {
    _paintLayer(canvas, child);
  }
}
