import 'package:sizzle/src/utils/bitset.dart';
import 'package:test/test.dart';

void main() {
  group('Bitset', () {
    test('initial length matches constructor argument', () {
      final b = Bitset(1024, 1024);
      expect(b.length, 1024);
    });

    test('initial length 0 is valid; words is empty', () {
      final b = Bitset(0, 32);
      expect(b.length, 0);
      expect(b.words, isEmpty);
    });

    test('all bits start false', () {
      final b = Bitset(64, 32);
      for (var i = 0; i < 64; i++) {
        expect(b[i], isFalse, reason: 'bit $i should be false');
      }
    });

    test('set true then read returns true', () {
      final b = Bitset(64, 32);
      b[5] = true;
      b[31] = true;
      b[32] = true;
      b[63] = true;
      expect(b[5], isTrue);
      expect(b[31], isTrue);
      expect(b[32], isTrue);
      expect(b[63], isTrue);
    });

    test('set true then set false clears the bit', () {
      final b = Bitset(32, 32);
      b[7] = true;
      expect(b[7], isTrue);
      b[7] = false;
      expect(b[7], isFalse);
    });

    test('setting one bit does not affect neighbouring bits in same word', () {
      final b = Bitset(32, 32);
      b[10] = true;
      for (var i = 0; i < 32; i++) {
        expect(b[i], i == 10);
      }
    });

    test('read at negative index throws RangeError', () {
      final b = Bitset(32, 32);
      expect(() => b[-1], throwsRangeError);
    });

    test('read at index == length throws RangeError', () {
      final b = Bitset(32, 32);
      expect(() => b[32], throwsRangeError);
    });

    test('read past length throws RangeError', () {
      final b = Bitset(32, 32);
      expect(() => b[100], throwsRangeError);
    });

    test('write at negative index throws RangeError', () {
      final b = Bitset(32, 32);
      expect(() => b[-1] = true, throwsRangeError);
    });

    test('write past length auto-grows by one growthStep chunk', () {
      final b = Bitset(32, 32);
      b[32] = true;
      expect(b.length, 64);
      expect(b[32], isTrue);
    });

    test('write far past length grows by enough whole chunks', () {
      final b = Bitset(32, 32);
      b[200] = true;
      expect(b.length, greaterThanOrEqualTo(201));
      expect(b.length % 32, 0);
      expect(b[200], isTrue);
    });

    test('growth uses growthStepBits, not the next power of two', () {
      final b = Bitset(1024, 1024);
      b[1024] = true;
      expect(b.length, 2048);
      b[5000] = true;
      // Needed: 5001 bits. From 2048, need 3 chunks of 1024 = 3072 added → 5120.
      expect(b.length, 5120);
    });

    test('growth preserves previously-set bits', () {
      final b = Bitset(32, 32);
      b[3] = true;
      b[17] = true;
      b[200] = true;
      expect(b[3], isTrue);
      expect(b[17], isTrue);
      expect(b[200], isTrue);
    });

    test('words snapshot reflects current state', () {
      final b = Bitset(64, 32);
      b[0] = true;
      b[33] = true;
      final w = b.words;
      expect(w.length, 2);
      expect(w[0] & 1, 1);
      expect(w[1] & 2, 2);
    });

    test('words snapshot is unmodifiable', () {
      final b = Bitset(32, 32);
      final w = b.words;
      expect(() => w[0] = 0xFF, throwsUnsupportedError);
    });

    test('fromWords round-trips bit state', () {
      final original = Bitset(64, 32);
      original[1] = true;
      original[40] = true;
      original[63] = true;

      final restored = Bitset.fromWords(
        length: original.length,
        growthStepBits: original.growthStepBits,
        words: original.words,
      );

      expect(restored.length, 64);
      for (var i = 0; i < 64; i++) {
        expect(restored[i], original[i], reason: 'bit $i');
      }
    });

    test('fromWords pads words list if shorter than length requires', () {
      // Length 64 needs 2 words; supply 0 words.
      final b = Bitset.fromWords(length: 64, growthStepBits: 32, words: []);
      expect(b.length, 64);
      for (var i = 0; i < 64; i++) {
        expect(b[i], isFalse);
      }
    });

    test('fromWords allows continued writes that auto-grow', () {
      final b = Bitset.fromWords(
        length: 32,
        growthStepBits: 32,
        words: [0],
      );
      b[100] = true;
      expect(b[100], isTrue);
      expect(b.length, greaterThanOrEqualTo(101));
    });
  });
}
