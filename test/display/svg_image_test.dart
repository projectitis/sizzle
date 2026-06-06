import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sizzle/sizzle.dart';

import '../sizzle_test_helpers.dart';

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final AssetBundle assets =
      await DiskAssetBundle.loadFromPath('test/_resources/');

  group('SvgImage', () {
    late FileService fileService;
    late ImageService imageService;

    setUp(() {
      fileService = FileService('', assetBundle: assets);
      imageService = ImageService('', assetBundle: assets);
    });

    tearDown(() {
      fileService.clear();
      imageService.clear();
    });

    test('load() returns a sprite with the expected displaySize', () async {
      final svg = await SvgImage.load(
        'sizzle-icon.svg',
        contextScale: 1.0,
        dpr: 1.0,
        fileService: fileService,
        imageService: imageService,
      );

      expect(svg.sprite, isNotNull);
      expect(svg.sprite.image.width, greaterThan(0));
      expect(svg.displaySize.x, equals(svg.sprite.image.width.toDouble()));
      expect(svg.displaySize.y, equals(svg.sprite.image.height.toDouble()));
    });

    test('load() invokes onRender once for the initial rasterization',
        () async {
      var calls = 0;
      await SvgImage.load(
        'sizzle-icon.svg',
        contextScale: 1.0,
        dpr: 1.0,
        onRender: (svg) {
          calls++;
          return svg;
        },
        fileService: fileService,
        imageService: imageService,
      );

      expect(calls, 1);
    });

    test('render() swaps sprite.image in place; sprite reference is stable',
        () async {
      final svg = await SvgImage.load(
        'sizzle-icon.svg',
        contextScale: 1.0,
        dpr: 1.0,
        fileService: fileService,
        imageService: imageService,
      );
      final sprite = svg.sprite;
      final initialImage = sprite.image;

      await svg.render();

      expect(svg.sprite, same(sprite));
      expect(sprite.image, isNot(same(initialImage)));
    });

    test('render() invokes the one-shot onRender callback', () async {
      final svg = await SvgImage.load(
        'sizzle-icon.svg',
        contextScale: 1.0,
        dpr: 1.0,
        fileService: fileService,
        imageService: imageService,
      );

      String? received;
      await svg.render(
        onRender: (s) {
          received = s;
          return s;
        },
      );

      expect(received, isNotNull);
      expect(received, contains('<svg'));
    });

    test('render() uses the stored onRender field when no argument is given',
        () async {
      var calls = 0;
      final svg = await SvgImage.load(
        'sizzle-icon.svg',
        contextScale: 1.0,
        dpr: 1.0,
        fileService: fileService,
        imageService: imageService,
      );
      svg.onRender = (s) {
        calls++;
        return s;
      };

      await svg.render();
      await svg.render();

      expect(calls, 2);
    });

    test('render() argument overrides the stored onRender for one call',
        () async {
      var stored = 0;
      var oneShot = 0;
      final svg = await SvgImage.load(
        'sizzle-icon.svg',
        contextScale: 1.0,
        dpr: 1.0,
        fileService: fileService,
        imageService: imageService,
      );
      svg.onRender = (s) {
        stored++;
        return s;
      };

      await svg.render(
        onRender: (s) {
          oneShot++;
          return s;
        },
      );

      expect(stored, 0);
      expect(oneShot, 1);
    });

    test('render() always receives the original asset SVG (non-cumulative)',
        () async {
      final received = <String>[];
      final svg = await SvgImage.load(
        'sizzle-icon.svg',
        contextScale: 1.0,
        dpr: 1.0,
        fileService: fileService,
        imageService: imageService,
      );

      await svg.render(
        onRender: (s) {
          received.add(s);
          return s.replaceAll('rgb(48,48,48)', 'rgb(255,0,0)');
        },
      );
      await svg.render(
        onRender: (s) {
          received.add(s);
          return s;
        },
      );

      expect(received.length, 2);
      expect(received[0], equals(received[1]));
      expect(received[0], contains('rgb(48,48,48)'));
    });

    test('render() replaces the ImageService cache entry under the same key',
        () async {
      final svg = await SvgImage.load(
        'sizzle-icon.svg',
        contextScale: 1.0,
        dpr: 1.0,
        fileService: fileService,
        imageService: imageService,
      );
      const cacheName = 'sizzle-icon.svg@1.0000';
      final initial = imageService[cacheName];
      expect(initial, isNotNull);
      expect(initial, same(svg.sprite.image));

      await svg.render();

      final after = imageService[cacheName];
      expect(after, isNotNull);
      expect(after, same(svg.sprite.image));
      expect(after, isNot(same(initial)));
    });

    test('render() disposes the previous image', () async {
      final svg = await SvgImage.load(
        'sizzle-icon.svg',
        contextScale: 1.0,
        dpr: 1.0,
        fileService: fileService,
        imageService: imageService,
      );
      final initialImage = svg.sprite.image;
      expect(initialImage.debugDisposed, false);

      await svg.render();

      expect(initialImage.debugDisposed, true);
    });
  });
}
