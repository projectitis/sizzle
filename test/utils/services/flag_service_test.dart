import 'package:flutter_test/flutter_test.dart';
import 'package:sizzle/sizzle.dart';

void main() async {
  group('FlagService', () {
    FlagService flagService = FlagService();

    tearDown(() {
      flagService.clear();
    });

    test('Starts empty', () async {
      expect(flagService.flags.isEmpty, true);

      expect(flagService.flagged('test'), false);
    });

    test('Can set flags', () async {
      flagService.flag('test1');
      flagService.flag('test2');

      expect(flagService.flags.contains('test1'), true);
      expect(flagService.flags.contains('test2'), true);
      expect(flagService.flagged('test1'), true);
      expect(flagService.flagged('test2'), true);
    });

    test('Can unset flags', () async {
      flagService.flag('test1');
      flagService.flag('test2');

      expect(flagService.flags.length, 2);

      flagService.flag('test1', false);

      expect(flagService.flags.length, 1);
      expect(flagService.flagged('test1'), false);
      expect(flagService.flagged('test2'), true);
    });

    test('Can clear flags', () async {
      flagService.flag('test1');
      flagService.flag('test2');

      expect(flagService.flags.isNotEmpty, true);

      flagService.clear();

      expect(flagService.flags.isEmpty, true);
    });

    test('Can access flags using array syntax', () async {
      flagService['test1'] = true;
      flagService['test2'] = true;

      expect(flagService['test1'], true);
      expect(flagService['test2'], true);
      expect(
        () {
          return flagService['test3'];
        },
        returnsNormally,
      );
    });
  });
}
