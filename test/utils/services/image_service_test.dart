import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sizzle/sizzle.dart';

import '../../sizzle_test_helpers.dart';

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  AssetBundle assets = await DiskAssetBundle.loadFromPath('test/_resources/');

  group('ImageService', () {
    ImageService imageService = ImageService('', assetBundle: assets);

    tearDown(() {
      imageService.clear();
    });

    test('Loads image by path', () async {
      final image = await imageService.load(path: 'sizzle-icon.png');
      expect(image, isNotNull);
      expect(imageService.isNotEmpty, true);
      expect(imageService.length, 1);
    });

    test('Loads image by properties', () async {
      final image = await imageService.load(
        properties: ImageProperties('sizzle-icon.png'),
      );
      expect(image, isNotNull);
      expect(imageService.isNotEmpty, true);
      expect(imageService.length, 1);
    });

    test('Loads image by properties with name', () async {
      await imageService.load(
        properties: ImageProperties(
          'sizzle-icon.png',
          name: 'sizzle',
        ),
      );
      expect(imageService.contains('sizzle'), true);
    });

    test('Get previously cached image', () async {
      await imageService.load(path: 'sizzle-icon.png');

      final image = imageService['sizzle-icon.png'];
      expect(image, isNotNull);

      final image2 = imageService.get('sizzle-icon.png');
      expect(image2, isNotNull);
    });

    test('Removes cached image', () async {
      await imageService.load(path: 'sizzle-icon.png');
      expect(imageService.isNotEmpty, true);

      imageService.remove('sizzle-icon.png');
      expect(imageService.isNotEmpty, false);
    });

    test('Clears cache', () async {
      await imageService.load(path: 'sizzle-icon.png');
      expect(imageService.isNotEmpty, true);

      imageService.clear();
      expect(imageService.isNotEmpty, false);
    });

    test('Contains', () async {
      await imageService.load(path: 'sizzle-icon.png');
      expect(imageService.contains('sizzle-icon.png'), true);
      expect(imageService.contains('flame-icon.png'), false);
    });

    test('Enqueues images', () async {
      imageService.enqueue(
        properties: ImageProperties(
          'sizzle-icon.png',
          name: 'image1',
        ),
      );
      imageService.enqueue(
        properties: ImageProperties(
          'sizzle-icon.png',
          name: 'image2',
        ),
      );
      imageService.enqueue(
        properties: ImageProperties(
          'sizzle-icon.png',
          name: 'image3',
        ),
      );
      expect(imageService.isEmpty, true);

      await imageService.loadQueue();

      expect(imageService.isEmpty, false);
      expect(imageService.length, 3);
      expect(imageService.contains('image1'), true);
      expect(imageService.contains('image2'), true);
      expect(imageService.contains('image3'), true);
    });

    test('Enqueues all images', () async {
      imageService.enqueueAll(
        properties: [
          ImageProperties('sizzle-icon.png', name: 'image1'),
          ImageProperties('sizzle-icon.png', name: 'image2'),
          ImageProperties('sizzle-icon.png', name: 'image3'),
        ],
      );
      expect(imageService.isEmpty, true);

      await imageService.loadQueue();

      expect(imageService.isEmpty, false);
      expect(imageService.length, 3);
      expect(imageService.contains('image1'), true);
      expect(imageService.contains('image2'), true);
      expect(imageService.contains('image3'), true);
    });

    test('Without transform', () async {
      final image = await imageService.load(
        properties: ImageProperties('sizzle-icon.png'),
      );

      await expectLater(
        image,
        matchesGoldenFile('$goldens/sizzle-icon.png'),
      );
    });

    test('With scale', () async {
      final image1 = await imageService.load(
        properties: ImageProperties(
          'sizzle-icon.png',
          scale: Vector2.all(0.5),
          name: 'scale1',
        ),
      );
      final image2 = await imageService.load(
        properties: ImageProperties(
          'sizzle-icon.png',
          scale: Vector2(1.2, 0.75),
          name: 'scale2',
        ),
      );

      await expectLater(
        image1,
        matchesGoldenFile('$goldens/sizzle-icon-scale1.png'),
      );
      await expectLater(
        image2,
        matchesGoldenFile('$goldens/sizzle-icon-scale2.png'),
      );
    });

    test('With flip', () async {
      final image1 = await imageService.load(
        properties: ImageProperties(
          'sizzle-icon.png',
          flipX: true,
          name: 'flipX',
        ),
      );
      final image2 = await imageService.load(
        properties: ImageProperties(
          'sizzle-icon.png',
          flipY: true,
          name: 'flipY',
        ),
      );
      final image3 = await imageService.load(
        properties: ImageProperties(
          'sizzle-icon.png',
          flipX: true,
          flipY: true,
          name: 'flipXY',
        ),
      );

      await expectLater(
        image1,
        matchesGoldenFile('$goldens/sizzle-icon-flipx.png'),
      );
      await expectLater(
        image2,
        matchesGoldenFile('$goldens/sizzle-icon-flipy.png'),
      );
      await expectLater(
        image3,
        matchesGoldenFile('$goldens/sizzle-icon-flipxy.png'),
      );
    });

    test('With rotation', () async {
      // No crop
      final image1 = await imageService.load(
        properties: ImageProperties(
          'sizzle-icon.png',
          angle: radians(30),
          name: 'rotate30',
        ),
      );
      // Fit to crop
      final image2 = await imageService.load(
        properties: ImageProperties(
          'sizzle-icon.png',
          angle: radians(30),
          fitCrop: true,
          crop: Rect.fromLTWH(0, 0, 100, 100),
          name: 'rotate30-fit',
        ),
      );
      // Crop
      final image3 = await imageService.load(
        properties: ImageProperties(
          'sizzle-icon.png',
          angle: radians(30),
          crop: Rect.fromLTWH(100, 100, 100, 100),
          name: 'rotate30-crop',
        ),
      );
      // Negative rotation
      final image4 = await imageService.load(
        properties: ImageProperties(
          'sizzle-icon.png',
          angle: radians(-30),
          name: 'rotate-30',
        ),
      );
      // Large rotation
      final image5 = await imageService.load(
        properties: ImageProperties(
          'sizzle-icon.png',
          angle: radians(125),
          name: 'rotate125',
        ),
      );

      await expectLater(
        image1,
        matchesGoldenFile('$goldens/sizzle-icon-rotate30.png'),
      );
      await expectLater(
        image2,
        matchesGoldenFile('$goldens/sizzle-icon-rotate30-fit.png'),
      );
      await expectLater(
        image3,
        matchesGoldenFile('$goldens/sizzle-icon-rotate30-crop.png'),
      );
      await expectLater(
        image4,
        matchesGoldenFile('$goldens/sizzle-icon-rotate-30.png'),
      );
      await expectLater(
        image5,
        matchesGoldenFile('$goldens/sizzle-icon-rotate125.png'),
      );
    });

    test('With blendMode', () async {
      final image = await imageService.load(
        properties: ImageProperties(
          'sizzle-icon.png',
          blendMode: BlendMode.screen,
          name: 'blendmode',
        ),
      );

      await expectLater(
        image,
        matchesGoldenFile('$goldens/sizzle-icon-blendmode.png'),
      );
    });

    test('With rotation and no antialias', () async {
      final image = await imageService.load(
        properties: ImageProperties(
          'sizzle-icon.png',
          angle: radians(30),
          antiAlias: false,
          name: 'no-aa',
        ),
      );

      await expectLater(
        image,
        matchesGoldenFile('$goldens/sizzle-icon-no-aa.png'),
      );
    });

    test('With scale and low quality', () async {
      final image = await imageService.load(
        properties: ImageProperties(
          'sizzle-icon.png',
          scale: Vector2(1.2, 0.75),
          filterQuality: FilterQuality.none,
          name: 'scale-low',
        ),
      );

      await expectLater(
        image,
        matchesGoldenFile('$goldens/sizzle-icon-scale-low.png'),
      );
    });

    test('With multiple transforms', () async {
      final image1 = await imageService.load(
        properties: ImageProperties(
          'sizzle-icon.png',
          scale: Vector2(0.3, 1.0),
          angle: radians(45),
          flipX: true,
          name: 'tx1',
        ),
      );
      final image2 = await imageService.load(
        properties: ImageProperties(
          'sizzle-icon.png',
          scale: Vector2(0.3, 1.0),
          angle: radians(45),
          flipY: true,
          crop: Rect.fromLTWH(0, 0, 200, 200),
          fitCrop: true,
          name: 'tx2',
        ),
      );

      await expectLater(
        image1,
        matchesGoldenFile('$goldens/sizzle-icon-tx1.png'),
      );
      await expectLater(
        image2,
        matchesGoldenFile('$goldens/sizzle-icon-tx2.png'),
      );
    });
  });
}
