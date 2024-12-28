import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sizzle/sizzle.dart';

import '../../sizzle_test_helpers.dart';

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  AssetBundle assets = await DiskAssetBundle.loadFromPath('test/_resources/');

  group('FileService', () {
    FileService fileService = FileService('', assetBundle: assets);

    tearDown(() {
      fileService.clear();
    });

    test('Loads file by path', () async {
      final file = await fileService.load(path: 'test.txt');
      expect(file, isNotNull);
      expect(fileService.contains('test.txt'), true);
      expect(fileService.contains('fail.txt'), false);
    });

    test('Loads file by properties', () async {
      final file = await fileService.load(
        properties: FileProperties('test.txt'),
      );
      expect(file, isNotNull);
      expect(fileService.contains('test.txt'), true);
      expect(fileService.contains('fail.txt'), false);
    });

    test('Loads file by properties with name', () async {
      await fileService.load(
        properties: FileProperties(
          'test.txt',
          name: 'test',
        ),
      );
      expect(fileService.contains('test'), true);
    });

    test('Get previously cached file', () async {
      await fileService.load(path: 'test.txt');

      final file = fileService['test.txt'];
      expect(file, isNotNull);

      final file2 = fileService.get('test.txt');
      expect(file2, isNotNull);
    });

    test('Removes cached file', () async {
      await fileService.load(path: 'test.txt');
      expect(fileService.contains('test.txt'), true);

      fileService.remove('test.txt');
      expect(fileService.contains('test.txt'), false);
    });

    test('Enqueues files', () async {
      fileService.enqueue(path: 'test.txt');
      fileService.enqueue(path: 'test2.txt');
      fileService.enqueueAll(paths: ['test3.txt', 'test4.txt']);

      expect(fileService.queueLength, 4);
    });

    test('Loads queued files', () async {
      fileService.enqueue(path: 'test.txt');
      fileService.enqueue(path: 'test2.txt');
      fileService.enqueueAll(paths: ['test3.txt', 'test4.txt']);

      await fileService.loadQueue();

      expect(fileService.length, 4);
      expect(fileService.queueLength, 0);
    });

    test('Clears cache', () async {
      fileService.enqueueAll(
        paths: [
          'test.txt',
          'test2.txt',
          'test3.txt',
          'test4.txt',
        ],
      );
      await fileService.loadQueue();
      expect(fileService.length, 4);

      fileService.clear();
      expect(fileService.length, 0);
    });

    test('Contains', () async {
      fileService.enqueueAll(
        paths: [
          'test.txt',
          'test2.txt',
          'test3.txt',
          'test4.txt',
        ],
      );
      await fileService.loadQueue();
      expect(fileService.contains('test3.txt'), true);
      expect(fileService.contains('fail.txt'), false);
    });

    test('Enqueues files with properties', () async {
      fileService.enqueue(
        properties: FileProperties('test.txt', name: 'test1'),
      );
      fileService.enqueue(
        properties: FileProperties('test2.txt', name: 'test2'),
      );
      fileService.enqueueAll(
        properties: [
          FileProperties('test3.txt', name: 'test3'),
          FileProperties('test4.txt', name: 'test4'),
        ],
      );
      expect(fileService.queueLength, 4);

      await fileService.loadQueue();
      expect(fileService.length, 4);
      expect(fileService.contains('test1'), true);
    });

    test('Loads string', () async {
      final string = await fileService.loadString(path: 'test2.txt');
      expect(string, 'test2');

      final string2 = fileService.getString('test2.txt');
      expect(string2, string);
    });

    test('Loads string by properties', () async {
      final string = await fileService.loadString(
        properties: FileProperties('test2.txt', name: 'test2'),
      );
      expect(string, 'test2');

      final string2 = fileService.getString('test2');
      expect(string2, string);
    });

    test('Loads json', () async {
      final json = await fileService.loadJson(path: 'test.json');
      expect(json, {'test': 'test'});

      final json2 = fileService.getJson('test.json');
      expect(json2, json);
    });

    test('Loads JX', () async {
      final jx = await fileService.loadJX(path: 'test.jx');
      expect(jx['test'], 'test');

      final jx2 = fileService.getJX('test.jx');
      expect(jx2['test'], jx['test']);
    });
  });
}
