/// A growable bit array, indexed by `[]` like a `List<bool>` but packed
/// into 32-bit words for compact storage and fast `json.encode`
/// round-trips.
///
/// Writes past the current [length] grow the array by whole
/// [growthStepBits] chunks. Reads past [length] throw — callers must
/// length-check explicitly if a default-false probe is needed.
class Bitset {
  /// Create with [initialBits] of capacity (rounded up to a whole 32-bit
  /// word) and [growthStepBits] added each time a `set` exceeds the
  /// current length.
  Bitset(int initialBits, this.growthStepBits)
      : assert(initialBits >= 0, 'initialBits must be non-negative'),
        assert(growthStepBits > 0, 'growthStepBits must be positive'),
        _length = initialBits,
        _words = List<int>.filled(_wordsFor(initialBits), 0, growable: true);

  /// Restore from persisted state. Caller supplies the same
  /// [growthStepBits] used originally; [length] is in bits and [words]
  /// holds the packed 32-bit storage from [Bitset.words].
  Bitset.fromWords({
    required int length,
    required this.growthStepBits,
    required List<int> words,
  })  : assert(length >= 0, 'length must be non-negative'),
        assert(growthStepBits > 0, 'growthStepBits must be positive'),
        _length = length,
        _words = List<int>.of(words, growable: true) {
    final needed = _wordsFor(length);
    while (_words.length < needed) _words.add(0);
  }

  static int _wordsFor(int bits) => (bits + 31) >> 5;

  /// Bits added each time a write exceeds the current capacity.
  final int growthStepBits;

  int _length;
  final List<int> _words;

  /// Current capacity, in bits.
  int get length => _length;

  /// Snapshot of the underlying 32-bit storage. Word `w` holds bits
  /// `[w*32, w*32+31]`; bit `b` is at mask `1 << (b & 31)`. Returned
  /// as an unmodifiable view — mutate the bitset through `[]=` instead.
  List<int> get words => List<int>.unmodifiable(_words);

  /// Read bit at [index]. Throws [RangeError] if [index] is negative or
  /// `>= length`. Out-of-range reads are an error (not silently false)
  /// so callers reason about capacity explicitly.
  bool operator [](int index) {
    if (index < 0 || index >= _length) {
      throw RangeError.index(index, this, 'index', null, _length);
    }
    return (_words[index >> 5] & (1 << (index & 31))) != 0;
  }

  /// Write [value] at [index]. Throws [RangeError] for negative
  /// indices. Indices `>= length` auto-grow the bitset by whole
  /// [growthStepBits] chunks.
  void operator []=(int index, bool value) {
    if (index < 0) {
      throw RangeError.range(index, 0, null, 'index');
    }
    if (index >= _length) {
      final deficit = index - _length + 1;
      final chunks = (deficit + growthStepBits - 1) ~/ growthStepBits;
      _length += chunks * growthStepBits;
      final neededWords = _wordsFor(_length);
      while (_words.length < neededWords) _words.add(0);
    }
    final mask = 1 << (index & 31);
    if (value) {
      _words[index >> 5] |= mask;
    } else {
      _words[index >> 5] &= ~mask;
    }
  }
}
