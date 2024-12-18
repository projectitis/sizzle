class FlagService {
  static final List<String> _flags = [];

  /// Set or unset a flag
  bool flag(String f, [bool v = true]) {
    if (v) {
      if (_flags.contains(f)) return true;
      _flags.add(f);
    } else {
      return _flags.remove(f);
    }
    return false;
  }

  /// Set a flag using array syntax
  void operator []=(String f, bool v) {
    flag(f, v);
  }

  /// Check a flag using array syntax
  bool operator [](String f) {
    return _flags.contains(f);
  }

  /// Check a flag
  bool flagged(String f) {
    return _flags.contains(f);
  }

  /// Return full list of flags
  List<String> get flags {
    return _flags;
  }

  // Replace all flags
  set flags(List<String> flags) {
    _flags.clear();
    _flags.addAll(flags);
  }

  /// Clear all flags
  void clear() {
    _flags.clear();
  }
}
