/// Pooled mixin for objects that should be pooled
mixin Pooled {
  /// [reset] is called when the object is returned to the pool. It
  /// should reset the object to its initial state.
  void reset() {}
}

/// A pool of objects that can be reused
class Pool<T extends Pooled> {
  final List<T> _pool = <T>[];
  final T Function() _creator;

  /// Number of objects created, whether
  /// or not they are currently in the pool.
  int _created = 0;
  int get created => _created;

  /// Number of objects currently in the pool
  int get length => _pool.length;

  /// Create a pool with a [_creator] function
  Pool(this._creator);

  /// Get an object from the pool. If the pool is empty, a new object
  /// is created using the creator function.
  T get() {
    if (_pool.isEmpty) {
      _created++;
      return _creator();
    } else {
      return _pool.removeLast();
    }
  }

  /// Return or add an object to the pool
  void add(T obj) {
    obj.reset();
    _pool.add(obj);
  }

  /// Clear the pool and release all objects
  /// for garbage collection
  void clear() {
    _pool.clear();
    _created = 0;
  }
}
