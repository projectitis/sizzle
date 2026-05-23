import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sizzle/sizzle.dart';

import '../../sizzle_test_helpers.dart';

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  AssetBundle assets = await DiskAssetBundle.loadFromPath('test/_resources/');

  group('LitSvgService', () {
    LitSvgService litSvgService = LitSvgService('', assetBundle: assets);

    tearDown(() {
      litSvgService.clear();
    });

    test('Loads SVG by path', () async {
      final svg = await litSvgService.load(path: 'svg/example.svg');
      expect(svg, isNotNull);
      expect(svg.groups.length, 4);
      expect(litSvgService.length, 1);
      expect(litSvgService.contains('svg/example.svg'), true);
    });

    test('Returns cached instance on second load', () async {
      final a = await litSvgService.load(path: 'svg/example.svg');
      final b = await litSvgService.load(path: 'svg/example.svg');
      expect(identical(a, b), true);
      expect(litSvgService.length, 1);
    });

    test('Indexer and get retrieve the cached SVG', () async {
      await litSvgService.load(path: 'svg/example.svg');
      expect(litSvgService['svg/example.svg'], isNotNull);
      expect(litSvgService.get('svg/example.svg'), isNotNull);
    });

    test('Removes SVG from cache', () async {
      await litSvgService.load(path: 'svg/example.svg');
      expect(litSvgService.isNotEmpty, true);
      litSvgService.remove('svg/example.svg');
      expect(litSvgService.isEmpty, true);
    });

    test('Clear empties the cache', () async {
      await litSvgService.load(path: 'svg/example.svg');
      expect(litSvgService.isNotEmpty, true);
      litSvgService.clear();
      expect(litSvgService.isEmpty, true);
    });

    test('cache: false skips caching', () async {
      final svg = await litSvgService.load(
        path: 'svg/example.svg',
        cache: false,
      );
      expect(svg, isNotNull);
      expect(litSvgService.isEmpty, true);
    });

    test('Enqueue + loadQueue', () async {
      litSvgService.enqueue(path: 'svg/example.svg');
      expect(litSvgService.isEmpty, true);

      await litSvgService.loadQueue();

      expect(litSvgService.length, 1);
      expect(litSvgService.contains('svg/example.svg'), true);
    });

    test('enqueueAll + loadQueue', () async {
      litSvgService.enqueueAll(paths: ['svg/example.svg']);
      await litSvgService.loadQueue();
      expect(litSvgService.contains('svg/example.svg'), true);
    });
  });
}
