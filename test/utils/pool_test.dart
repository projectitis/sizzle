import 'package:sizzle/src/utils/pool.dart';
import 'package:test/test.dart';

class PooledMock with Pooled {
  static Pool<PooledMock> pool = Pool<PooledMock>(PooledMock.new);
  bool isReset = false;

  PooledMock() {
    isReset = false;
  }

  @override
  void reset() {
    isReset = true;
  }
}

void main() {
  group('Pool', () {
    tearDown(() {
      PooledMock.pool.clear();
    });

    test('Pool is created empty', () {
      expect(PooledMock.pool.length, isZero);
    });

    test('Can create objects', () {
      final obj = PooledMock.pool.get();
      expect(obj, isA<PooledMock>());
      expect(PooledMock.pool.length, isZero);
      expect(PooledMock.pool.created, 1);
    });

    test('Can return objects', () {
      final obj = PooledMock.pool.get();
      PooledMock.pool.add(obj);
      expect(PooledMock.pool.length, 1);
      expect(PooledMock.pool.created, 1);
    });

    test('Objects are reset', () {
      final obj = PooledMock.pool.get();
      PooledMock.pool.add(obj);
      expect(obj.isReset, isTrue);
    });

    test('Can get objects from pool', () {
      final obj = PooledMock.pool.get();
      PooledMock.pool.add(obj);
      final obj2 = PooledMock.pool.get();
      expect(obj, equals(obj2));
    });

    test('Pool is cleared', () {
      final obj = PooledMock.pool.get();
      PooledMock.pool.add(obj);
      PooledMock.pool.clear();
      expect(PooledMock.pool.length, isZero);
      expect(PooledMock.pool.created, 0);
    });
  });
}
