import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sizzle/sizzle.dart';

import '../../sizzle_test_helpers.dart';

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  AssetBundle assets = await DiskAssetBundle.loadFromPath('test/_resources/');

  group('SvgService', () {
    SvgService svgService = SvgService('', assetBundle: assets);

    tearDown(() {
      svgService.clear();
    });

    test('Loads SVG by path', () async {
      final svg = await svgService.load(path: 'svg/example.svg');
      expect(svg, isNotNull);
      expect(svg.groups.length, 4);
      expect(svgService.length, 1);
      expect(svgService.contains('svg/example.svg'), true);
    });

    test('Returns cached instance on second load', () async {
      final a = await svgService.load(path: 'svg/example.svg');
      final b = await svgService.load(path: 'svg/example.svg');
      expect(identical(a, b), true);
      expect(svgService.length, 1);
    });

    test('Indexer and get retrieve the cached SVG', () async {
      await svgService.load(path: 'svg/example.svg');
      expect(svgService['svg/example.svg'], isNotNull);
      expect(svgService.get('svg/example.svg'), isNotNull);
    });

    test('Removes SVG from cache', () async {
      await svgService.load(path: 'svg/example.svg');
      expect(svgService.isNotEmpty, true);
      svgService.remove('svg/example.svg');
      expect(svgService.isEmpty, true);
    });

    test('Clear empties the cache', () async {
      await svgService.load(path: 'svg/example.svg');
      expect(svgService.isNotEmpty, true);
      svgService.clear();
      expect(svgService.isEmpty, true);
    });

    test('cache: false skips caching', () async {
      final svg = await svgService.load(
        path: 'svg/example.svg',
        cache: false,
      );
      expect(svg, isNotNull);
      expect(svgService.isEmpty, true);
    });

    test('Enqueue + loadQueue', () async {
      svgService.enqueue(path: 'svg/example.svg');
      expect(svgService.isEmpty, true);

      await svgService.loadQueue();

      expect(svgService.length, 1);
      expect(svgService.contains('svg/example.svg'), true);
    });

    test('enqueueAll + loadQueue', () async {
      svgService.enqueueAll(paths: ['svg/example.svg']);
      await svgService.loadQueue();
      expect(svgService.contains('svg/example.svg'), true);
    });
  });
}
