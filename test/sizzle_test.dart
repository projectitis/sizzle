import 'package:sizzle/sizzle.dart';
import 'package:test/test.dart';

void main() {
  group('Framework tests', () {
    final awesome = true;

    setUp(() {
      // Additional setup goes here.
    });

    test('First Test', () {
      expect(awesome, isTrue);
    });
  });
}
