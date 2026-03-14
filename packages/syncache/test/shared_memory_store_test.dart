import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

void main() {
  group('SharedMemoryStore', () {
    tearDown(() {
      // Clean up after each test
      SharedMemoryStore.clearAll();
    });

    test('stores and retrieves values', () async {
      final store = SharedMemoryStore<String>(namespace: 'test');
      final stored = Stored(
        value: 'hello',
        meta: Metadata(version: 1, storedAt: DateTime.now()),
      );

      await store.write('key1', stored);
      final result = await store.read('key1');

      expect(result, isNotNull);
      expect(result!.value, equals('hello'));
    });

    test('returns null for non-existent key', () async {
      final store = SharedMemoryStore<String>(namespace: 'test');

      final result = await store.read('nonexistent');

      expect(result, isNull);
    });

    test('shares data between instances with same namespace', () async {
      final store1 = SharedMemoryStore<String>(namespace: 'shared');
      final store2 = SharedMemoryStore<String>(namespace: 'shared');
      final stored = Stored(
        value: 'shared value',
        meta: Metadata(version: 1, storedAt: DateTime.now()),
      );

      await store1.write('key', stored);
      final result = await store2.read('key');

      expect(result, isNotNull);
      expect(result!.value, equals('shared value'));
    });

    test('isolates data between different namespaces', () async {
      final store1 = SharedMemoryStore<String>(namespace: 'ns1');
      final store2 = SharedMemoryStore<String>(namespace: 'ns2');
      final stored = Stored(
        value: 'ns1 value',
        meta: Metadata(version: 1, storedAt: DateTime.now()),
      );

      await store1.write('key', stored);
      final result = await store2.read('key');

      expect(result, isNull);
    });

    test('deletes individual keys', () async {
      final store = SharedMemoryStore<String>(namespace: 'test');
      final stored = Stored(
        value: 'value',
        meta: Metadata(version: 1, storedAt: DateTime.now()),
      );

      await store.write('key', stored);
      await store.delete('key');
      final result = await store.read('key');

      expect(result, isNull);
    });

    test('clear removes all keys in namespace', () async {
      final store = SharedMemoryStore<String>(namespace: 'test');
      final stored1 = Stored(
        value: 'value1',
        meta: Metadata(version: 1, storedAt: DateTime.now()),
      );
      final stored2 = Stored(
        value: 'value2',
        meta: Metadata(version: 1, storedAt: DateTime.now()),
      );

      await store.write('key1', stored1);
      await store.write('key2', stored2);
      await store.clear();

      expect(await store.read('key1'), isNull);
      expect(await store.read('key2'), isNull);
    });

    test('clearNamespace removes specific namespace', () async {
      final store1 = SharedMemoryStore<String>(namespace: 'ns1');
      final store2 = SharedMemoryStore<String>(namespace: 'ns2');
      final stored = Stored(
        value: 'value',
        meta: Metadata(version: 1, storedAt: DateTime.now()),
      );

      await store1.write('key', stored);
      await store2.write('key', stored);

      SharedMemoryStore.clearNamespace('ns1');

      expect(await store1.read('key'), isNull);
      expect(await store2.read('key'), isNotNull);
    });

    test('clearAll removes all namespaces', () async {
      final store1 = SharedMemoryStore<String>(namespace: 'ns1');
      final store2 = SharedMemoryStore<String>(namespace: 'ns2');
      final stored = Stored(
        value: 'value',
        meta: Metadata(version: 1, storedAt: DateTime.now()),
      );

      await store1.write('key', stored);
      await store2.write('key', stored);

      SharedMemoryStore.clearAll();

      expect(await store1.read('key'), isNull);
      expect(await store2.read('key'), isNull);
    });

    test('namespaces returns list of active namespaces', () async {
      final store1 = SharedMemoryStore<String>(namespace: 'users');
      final store2 = SharedMemoryStore<String>(namespace: 'products');
      final stored = Stored(
        value: 'value',
        meta: Metadata(version: 1, storedAt: DateTime.now()),
      );

      await store1.write('key', stored);
      await store2.write('key', stored);

      final namespaces = SharedMemoryStore.namespaces;

      expect(namespaces, containsAll(['users', 'products']));
    });

    test('hasNamespace returns correct state', () async {
      final store = SharedMemoryStore<String>(namespace: 'existing');
      final stored = Stored(
        value: 'value',
        meta: Metadata(version: 1, storedAt: DateTime.now()),
      );

      expect(SharedMemoryStore.hasNamespace('existing'), isFalse);

      await store.write('key', stored);

      expect(SharedMemoryStore.hasNamespace('existing'), isTrue);
      expect(SharedMemoryStore.hasNamespace('nonexistent'), isFalse);
    });

    test('uses default namespace when none specified', () async {
      final store1 = SharedMemoryStore<String>();
      final store2 = SharedMemoryStore<String>();
      final stored = Stored(
        value: 'default value',
        meta: Metadata(version: 1, storedAt: DateTime.now()),
      );

      await store1.write('key', stored);
      final result = await store2.read('key');

      expect(result, isNotNull);
      expect(result!.value, equals('default value'));
      expect(store1.namespace, equals('default'));
    });

    test('data persists when store instance is discarded', () async {
      final stored = Stored(
        value: 'persistent',
        meta: Metadata(version: 1, storedAt: DateTime.now()),
      );

      // Write with one instance
      await SharedMemoryStore<String>(namespace: 'persist')
          .write('key', stored);

      // Create new instance and read
      final newStore = SharedMemoryStore<String>(namespace: 'persist');
      final result = await newStore.read('key');

      expect(result, isNotNull);
      expect(result!.value, equals('persistent'));
    });
  });
}
