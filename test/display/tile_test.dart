import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sizzle/sizzle.dart';

import '../sizzle_test_helpers.dart';

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  AssetBundle assets = await DiskAssetBundle.loadFromPath('test/_resources/');
  print('assets: $assets');

  group('TileService', () {
    TileService tileService = TileService(
      'test/_resources/',
      16,
      16,
      assetBundle: assets,
    );

    tearDown(() {
      tileService.clear();
    });

    test('loads and processes autotiles correctly', () async {
      // Load the test autotiles image
      final image = await tileService.load(path: 'test-autotiles.png');

      // Verify the image was loaded
      expect(image, isNotNull);
      expect(image.width, 11 * 16);
      expect(image.height, 5 * 16);

      // Verify tiles were created
      expect(tileService.tiles.length, 11 * 5 - 8); // 8 blank tiles

      // Test all tiles are correct
      for (int i = 0; i < tileService.tiles.length; i++) {
        final tile = tileService.getTile(i);
        await expectLater(
          tile.image,
          matchesGoldenFile('$goldens/${tile.name}.png'),
        );
      }
    });
  });
}
