import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sizzle/sizzle.dart';

/// Build a small PNG of [w]x[h] filled with [color].
Future<Uint8List> _png(int w, int h, ui.Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = color,
  );
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Zip a manifest + named PNGs into `.lpng` bytes.
Uint8List _lpng(Map<String, dynamic> manifest, Map<String, Uint8List> images) {
  final archive = Archive();
  final manifestBytes = utf8.encode(jsonEncode(manifest));
  archive.addFile(
    ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
  );
  images.forEach((name, bytes) {
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

/// A synthetic document exercising ids, nesting, offsets, opacity, blend,
/// visibility and a passThrough group.
Future<LayeredPng> _syntheticDoc() async {
  final manifest = <String, dynamic>{
    'id': 'root',
    'name': 'syn',
    'w': 10,
    'h': 10,
    'v': '0.1.0',
    'layers': [
      {'id': 'bg', 'name': 'bg', 'src': 'a.png'},
      {
        'id': 'grp',
        'name': 'grp',
        'x': 2,
        'y': 3,
        'blend': 'passThrough',
        'layers': [
          {
            'id': 'child',
            'name': 'child',
            'src': 'b.png',
            'x': 1,
            'y': 1,
            'opacity': 0.5,
            'blend': 'multiply',
          },
          {
            'id': 'hidden',
            'name': 'hidden',
            'src': 'c.png',
            'visibility': false,
          },
        ],
      },
    ],
  };
  final bytes = _lpng(manifest, {
    'a.png': await _png(10, 10, const ui.Color(0xFF0000FF)),
    'b.png': await _png(4, 4, const ui.Color(0xFFFF0000)),
    'c.png': await _png(4, 4, const ui.Color(0xFF00FF00)),
  });
  return LayeredPng.fromBytes(bytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LayeredPng parsing (synthetic)', () {
    test('reads document metadata and defaults', () async {
      final doc = await _syntheticDoc();
      expect(doc.id, 'root');
      expect(doc.name, 'syn');
      expect(doc.width, 10);
      expect(doc.height, 10);
      expect(doc.version, '0.1.0');
      expect(doc.dpi, isNull);
      expect(doc.layers.length, 2);
      doc.dispose();
    });

    test('walk visits every layer depth-first, pre-order', () async {
      final doc = await _syntheticDoc();
      expect(
        doc.walk().map((l) => l.name).toList(),
        ['bg', 'grp', 'child', 'hidden'],
      );
      doc.dispose();
    });

    test('layerById finds nested layers and returns null when absent',
        () async {
      final doc = await _syntheticDoc();
      expect(doc.layerById('child')?.name, 'child');
      expect(doc.layerById('hidden')?.name, 'hidden');
      expect(doc.layerById('missing'), isNull);
      // Search can also start from a subtree.
      final grp = doc.layerById('grp')!;
      expect(grp.layerById('child')?.name, 'child');
      expect(grp.layerById('bg'), isNull);
      doc.dispose();
    });

    test('layer properties, defaults and isGroup', () async {
      final doc = await _syntheticDoc();

      final bg = doc.layerById('bg')!;
      expect(bg.isGroup, isFalse);
      expect(bg.image, isNotNull);
      expect(bg.opacity, 1.0);
      expect(bg.visible, isTrue);
      expect(bg.blend, LpngBlendMode.normal);

      final grp = doc.layerById('grp')!;
      expect(grp.isGroup, isTrue);
      expect(grp.image, isNull);
      expect(grp.blend, LpngBlendMode.passThrough);

      final child = doc.layerById('child')!;
      expect(child.opacity, 0.5);
      expect(child.blend, LpngBlendMode.multiply);

      final hidden = doc.layerById('hidden')!;
      expect(hidden.visible, isFalse);
      doc.dispose();
    });

    test('absolute offset accumulates down the tree', () async {
      final doc = await _syntheticDoc();
      // grp at (2,3); child at (1,1) relative -> absolute (3,4).
      final child = doc.layerById('child')!;
      expect(child.absX, 3);
      expect(child.absY, 4);
      doc.dispose();
    });

    test('bounds are the union of a subtree in document space', () async {
      final doc = await _syntheticDoc();
      // child abs (3,4) 4x4 -> (3,4,7,8); hidden abs (2,3) 4x4 -> (2,3,6,7).
      final grp = doc.layerById('grp')!;
      expect(grp.bounds, const ui.Rect.fromLTRB(2, 3, 7, 8));
      doc.dispose();
    });

    test('layers sharing a src share one decoded image, disposed once',
        () async {
      // The exporter's --optimize flag points identical layers at one PNG.
      final manifest = <String, dynamic>{
        'name': 'shared',
        'w': 8,
        'h': 8,
        'v': '0.1.0',
        'layers': [
          {'id': 'one', 'src': 'a.png'},
          {'id': 'two', 'src': 'a.png', 'x': 4},
          {'id': 'other', 'src': 'b.png'},
        ],
      };
      final doc = await LayeredPng.fromBytes(
        _lpng(manifest, {
          'a.png': await _png(4, 4, const ui.Color(0xFF0000FF)),
          'b.png': await _png(4, 4, const ui.Color(0xFFFF0000)),
        }),
      );

      final one = doc.layerById('one')!;
      final two = doc.layerById('two')!;
      final other = doc.layerById('other')!;
      expect(one.image, isNotNull);
      expect(identical(one.image, two.image), isTrue);
      expect(identical(one.image, other.image), isFalse);

      // Would assert on a double dispose of the shared image.
      doc.dispose();
    });
  });

  group('LayeredPng rendering (synthetic)', () {
    test('document rasterises to canvas size', () async {
      final doc = await _syntheticDoc();
      final image = await doc.toImage();
      expect(image.width, 10);
      expect(image.height, 10);
      image.dispose();
      doc.dispose();
    });

    test('image layer rasterises to its own size', () async {
      final doc = await _syntheticDoc();
      final image = await doc.layerById('child')!.toImage();
      expect(image.width, 4);
      expect(image.height, 4);
      image.dispose();
      doc.dispose();
    });

    test('group rasterises to its subtree bounds', () async {
      final doc = await _syntheticDoc();
      // grp bounds are 5x5 (2,3)-(7,8).
      final image = await doc.layerById('grp')!.toImage();
      expect(image.width, 5);
      expect(image.height, 5);
      image.dispose();
      doc.dispose();
    });
  });

  group('LpngBlendMode', () {
    test('normal and srcOver are interchangeable; unknown falls back', () {
      expect(LpngBlendMode.parse('normal'), LpngBlendMode.normal);
      expect(LpngBlendMode.parse('srcOver'), LpngBlendMode.normal);
      expect(LpngBlendMode.parse(null), LpngBlendMode.normal);
      expect(LpngBlendMode.parse('nonsense'), LpngBlendMode.normal);
      expect(LpngBlendMode.parse('multiply'), LpngBlendMode.multiply);
    });

    test('maps supported modes to ui.BlendMode and passThrough to null', () {
      expect(LpngBlendMode.multiply.uiBlendMode, ui.BlendMode.multiply);
      expect(LpngBlendMode.screen.uiBlendMode, ui.BlendMode.screen);
      expect(LpngBlendMode.passThrough.uiBlendMode, isNull);
      // Unsupported PS mode falls back to srcOver.
      expect(LpngBlendMode.vividLight.uiBlendMode, ui.BlendMode.srcOver);
    });
  });

  group('LayeredPng real fixture (test/_resources/test.lpng)', () {
    Future<LayeredPng> loadFixture() async {
      final bytes = await File('test/_resources/test.lpng').readAsBytes();
      return LayeredPng.fromBytes(bytes);
    }

    test('parses metadata, tree and thumbnail', () async {
      final doc = await loadFixture();
      expect(doc.name, 'test2-rasterised');
      expect(doc.width, 800);
      expect(doc.height, 600);
      expect(doc.dpi, 144);
      expect(doc.version, '0.1.0');
      expect(doc.thumbnail, isNotNull);

      // Top-level: Background, base road, Logos (group), Title.
      expect(
        doc.layers.map((l) => l.name).toList(),
        ['Background', 'base road', 'Logos', 'Title'],
      );

      // Nested Pirelli logo: group Logos(37,-20) + (4,438) -> abs (41,418).
      final logos = doc.layers.firstWhere((l) => l.name == 'Logos');
      expect(logos.isGroup, isTrue);
      final pirelli = logos.layers.firstWhere((l) => l.name == 'Pirelli logo');
      expect(pirelli.absX, 41);
      expect(pirelli.absY, 418);
      expect(pirelli.opacity, closeTo(0.698, 1e-6));

      final title = doc.layers.firstWhere((l) => l.name == 'Title');
      expect(title.blend, LpngBlendMode.screen);
      doc.dispose();
    });

    test('flattens the document to the canvas size', () async {
      final doc = await loadFixture();
      final image = await doc.toImage();
      expect(image.width, 800);
      expect(image.height, 600);
      image.dispose();
      doc.dispose();
    });
  });
}
