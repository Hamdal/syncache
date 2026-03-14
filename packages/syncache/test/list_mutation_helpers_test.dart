import 'dart:async';

import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

/// Simple item for testing list operations.
class _Item {
  final String id;
  final String name;
  final int value;

  const _Item({required this.id, required this.name, this.value = 0});

  _Item copyWith({String? id, String? name, int? value}) {
    return _Item(
      id: id ?? this.id,
      name: name ?? this.name,
      value: value ?? this.value,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _Item &&
      id == other.id &&
      name == other.name &&
      value == other.value;

  @override
  int get hashCode => Object.hash(id, name, value);

  @override
  String toString() => '_Item(id: $id, name: $name, value: $value)';
}

/// A network that is always offline for testing mutation queuing.
class _OfflineNetwork implements Network {
  @override
  bool get isOnline => false;
}

/// A controllable network for testing.
class _ControllableNetwork implements Network {
  bool _isOnline = true;

  @override
  bool get isOnline => _isOnline;

  void goOnline() => _isOnline = true;
  void goOffline() => _isOnline = false;
}

void main() {
  group('ListOperation', () {
    group('AppendOperation', () {
      test('appends item to end of list', () {
        final op = ListOperation<int>.append(4);
        final result = op.apply([1, 2, 3]);
        expect(result, equals([1, 2, 3, 4]));
      });

      test('appends to empty list', () {
        final op = ListOperation<String>.append('first');
        final result = op.apply([]);
        expect(result, equals(['first']));
      });

      test('item getter returns the item', () {
        final op = ListOperation<int>.append(42);
        expect(op.item, equals(42));
      });
    });

    group('PrependOperation', () {
      test('prepends item to beginning of list', () {
        final op = ListOperation<int>.prepend(0);
        final result = op.apply([1, 2, 3]);
        expect(result, equals([0, 1, 2, 3]));
      });

      test('prepends to empty list', () {
        final op = ListOperation<String>.prepend('first');
        final result = op.apply([]);
        expect(result, equals(['first']));
      });

      test('item getter returns the item', () {
        final op = ListOperation<int>.prepend(42);
        expect(op.item, equals(42));
      });
    });

    group('InsertOperation', () {
      test('inserts item at specified index', () {
        final op = ListOperation<int>.insert(1, 99);
        final result = op.apply([1, 2, 3]);
        expect(result, equals([1, 99, 2, 3]));
      });

      test('inserts at index 0 (beginning)', () {
        final op = ListOperation<int>.insert(0, 99);
        final result = op.apply([1, 2, 3]);
        expect(result, equals([99, 1, 2, 3]));
      });

      test('inserts at end when index equals length', () {
        final op = ListOperation<int>.insert(3, 99);
        final result = op.apply([1, 2, 3]);
        expect(result, equals([1, 2, 3, 99]));
      });

      test('clamps negative index to 0', () {
        final op = ListOperation<int>.insert(-5, 99);
        final result = op.apply([1, 2, 3]);
        expect(result, equals([99, 1, 2, 3]));
      });

      test('clamps index beyond length to end', () {
        final op = ListOperation<int>.insert(100, 99);
        final result = op.apply([1, 2, 3]);
        expect(result, equals([1, 2, 3, 99]));
      });

      test('inserts into empty list', () {
        final op = ListOperation<String>.insert(0, 'first');
        final result = op.apply([]);
        expect(result, equals(['first']));
      });

      test('item getter returns the item', () {
        final op = ListOperation<int>.insert(5, 42);
        expect(op.item, equals(42));
      });
    });

    group('UpdateWhereOperation', () {
      test('updates items matching predicate', () {
        final op = ListOperation<int>.updateWhere(
          (i) => i % 2 == 0,
          (i) => i * 10,
        );
        final result = op.apply([1, 2, 3, 4, 5]);
        expect(result, equals([1, 20, 3, 40, 5]));
      });

      test('updates all items when all match', () {
        final op = ListOperation<int>.updateWhere(
          (i) => true,
          (i) => i + 1,
        );
        final result = op.apply([1, 2, 3]);
        expect(result, equals([2, 3, 4]));
      });

      test('updates no items when none match', () {
        final op = ListOperation<int>.updateWhere(
          (i) => false,
          (i) => i * 10,
        );
        final result = op.apply([1, 2, 3]);
        expect(result, equals([1, 2, 3]));
      });

      test('works with complex objects', () {
        final items = [
          const _Item(id: '1', name: 'Alice'),
          const _Item(id: '2', name: 'Bob'),
          const _Item(id: '3', name: 'Charlie'),
        ];
        final op = ListOperation<_Item>.updateWhere(
          (item) => item.id == '2',
          (item) => item.copyWith(name: 'Bobby'),
        );
        final result = op.apply(items);
        expect(result[0].name, equals('Alice'));
        expect(result[1].name, equals('Bobby'));
        expect(result[2].name, equals('Charlie'));
      });

      test('item getter returns null', () {
        final op = ListOperation<int>.updateWhere((i) => true, (i) => i);
        expect(op.item, isNull);
      });
    });

    group('RemoveWhereOperation', () {
      test('removes items matching predicate', () {
        final op = ListOperation<int>.removeWhere((i) => i % 2 == 0);
        final result = op.apply([1, 2, 3, 4, 5]);
        expect(result, equals([1, 3, 5]));
      });

      test('removes all items when all match', () {
        final op = ListOperation<int>.removeWhere((i) => true);
        final result = op.apply([1, 2, 3]);
        expect(result, isEmpty);
      });

      test('removes no items when none match', () {
        final op = ListOperation<int>.removeWhere((i) => false);
        final result = op.apply([1, 2, 3]);
        expect(result, equals([1, 2, 3]));
      });

      test('works with complex objects', () {
        final items = [
          const _Item(id: '1', name: 'Alice'),
          const _Item(id: '2', name: 'Bob'),
          const _Item(id: '3', name: 'Charlie'),
        ];
        final op = ListOperation<_Item>.removeWhere((item) => item.id == '2');
        final result = op.apply(items);
        expect(result.length, equals(2));
        expect(result[0].name, equals('Alice'));
        expect(result[1].name, equals('Charlie'));
      });

      test('item getter returns null', () {
        final op = ListOperation<int>.removeWhere((i) => true);
        expect(op.item, isNull);
      });
    });

    test('operations do not modify original list', () {
      final original = [1, 2, 3];
      final ops = [
        ListOperation<int>.append(4),
        ListOperation<int>.prepend(0),
        ListOperation<int>.insert(1, 99),
        ListOperation<int>.updateWhere((i) => i == 2, (i) => 20),
        ListOperation<int>.removeWhere((i) => i == 2),
      ];

      for (final op in ops) {
        op.apply(original);
        expect(original, equals([1, 2, 3]),
            reason: 'Original list was modified by $op');
      }
    });
  });

  group('SyncacheListExtension', () {
    late Syncache<List<_Item>> cache;
    late MemoryStore<List<_Item>> store;

    setUp(() {
      store = MemoryStore<List<_Item>>();
      cache = Syncache<List<_Item>>(store: store);
    });

    tearDown(() {
      cache.dispose();
    });

    group('mutateList', () {
      test('applies append operation optimistically', () async {
        // Pre-populate cache
        final initialItems = [
          const _Item(id: '1', name: 'First'),
          const _Item(id: '2', name: 'Second'),
        ];
        await store.write(
          'items',
          Stored(
            value: initialItems,
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        var sendCalled = false;
        await cache.mutateList(
          key: 'items',
          operation: ListOperation.append(const _Item(id: '3', name: 'Third')),
          send: () async {
            sendCalled = true;
          },
        );

        // Verify optimistic update was applied
        final result = await cache.get(
          key: 'items',
          fetch: (_) async => [],
        );
        expect(result.length, equals(3));
        expect(result[2].name, equals('Third'));
        expect(sendCalled, isTrue);
      });

      test('applies prepend operation optimistically', () async {
        await store.write(
          'items',
          Stored(
            value: [const _Item(id: '1', name: 'First')],
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        await cache.mutateList(
          key: 'items',
          operation: ListOperation.prepend(const _Item(id: '0', name: 'Zero')),
          send: () async {},
        );

        final result = await cache.get(key: 'items', fetch: (_) async => []);
        expect(result.length, equals(2));
        expect(result[0].name, equals('Zero'));
        expect(result[1].name, equals('First'));
      });

      test('applies updateWhere operation optimistically', () async {
        await store.write(
          'items',
          Stored(
            value: [
              const _Item(id: '1', name: 'First'),
              const _Item(id: '2', name: 'Second'),
            ],
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        await cache.mutateList(
          key: 'items',
          operation: ListOperation.updateWhere(
            (item) => item.id == '1',
            (item) => item.copyWith(name: 'Updated First'),
          ),
          send: () async {},
        );

        final result = await cache.get(key: 'items', fetch: (_) async => []);
        expect(result[0].name, equals('Updated First'));
        expect(result[1].name, equals('Second'));
      });

      test('applies removeWhere operation optimistically', () async {
        await store.write(
          'items',
          Stored(
            value: [
              const _Item(id: '1', name: 'First'),
              const _Item(id: '2', name: 'Second'),
              const _Item(id: '3', name: 'Third'),
            ],
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        await cache.mutateList(
          key: 'items',
          operation: ListOperation.removeWhere((item) => item.id == '2'),
          send: () async {},
        );

        final result = await cache.get(key: 'items', fetch: (_) async => []);
        expect(result.length, equals(2));
        expect(result[0].name, equals('First'));
        expect(result[1].name, equals('Third'));
      });

      test('throws CacheMissException when key not in cache', () async {
        expect(
          () => cache.mutateList(
            key: 'nonexistent',
            operation: ListOperation.append(const _Item(id: '1', name: 'Test')),
            send: () async {},
          ),
          throwsA(isA<CacheMissException>()),
        );
      });

      test('notifies watchers on mutation', () async {
        await store.write(
          'items',
          Stored(
            value: [const _Item(id: '1', name: 'First')],
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        final updates = <List<_Item>>[];
        final subscription = cache
            .watch(key: 'items', fetch: (_) async => [])
            .listen((items) => updates.add(items));

        // Wait for initial value
        await Future.delayed(const Duration(milliseconds: 50));

        await cache.mutateList(
          key: 'items',
          operation: ListOperation.append(const _Item(id: '2', name: 'Second')),
          send: () async {},
        );

        // Wait for update
        await Future.delayed(const Duration(milliseconds: 50));

        await subscription.cancel();

        expect(updates.length, greaterThanOrEqualTo(2));
        expect(updates.last.length, equals(2));
      });

      test('queues mutation when offline', () async {
        final offlineCache = Syncache<List<_Item>>(
          store: store,
          network: _OfflineNetwork(),
        );

        await store.write(
          'items',
          Stored(
            value: [const _Item(id: '1', name: 'First')],
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        await offlineCache.mutateList(
          key: 'items',
          operation: ListOperation.append(const _Item(id: '2', name: 'Second')),
          send: () async {},
        );

        expect(offlineCache.hasPendingMutations, isTrue);
        expect(offlineCache.pendingMutationCount, equals(1));

        offlineCache.dispose();
      });
    });

    group('mutateListItem', () {
      test('updates item with server response', () async {
        final controllableNetwork = _ControllableNetwork();
        final networkCache = Syncache<List<_Item>>(
          store: store,
          network: controllableNetwork,
        );

        await store.write(
          'items',
          Stored(
            value: [const _Item(id: '1', name: 'First')],
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        // Append with temp ID, server returns real ID
        await networkCache.mutateListItem(
          key: 'items',
          operation: ListOperation.append(const _Item(id: 'temp', name: 'New')),
          send: (item) async {
            // Simulate server assigning real ID
            return item.copyWith(id: 'server-123');
          },
          idSelector: (item) => item.id,
        );

        // Wait for sync
        await Future.delayed(const Duration(milliseconds: 100));

        final result =
            await networkCache.get(key: 'items', fetch: (_) async => []);
        expect(result.length, equals(2));
        expect(result[1].id, equals('server-123'));
        expect(result[1].name, equals('New'));

        networkCache.dispose();
      });

      test('updates correct item based on idSelector', () async {
        final controllableNetwork = _ControllableNetwork();
        final networkCache = Syncache<List<_Item>>(
          store: store,
          network: controllableNetwork,
        );

        await store.write(
          'items',
          Stored(
            value: [
              const _Item(id: '1', name: 'First'),
              const _Item(id: '2', name: 'Second'),
            ],
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        await networkCache.mutateListItem(
          key: 'items',
          operation:
              ListOperation.prepend(const _Item(id: 'temp', name: 'Zero')),
          send: (item) async =>
              item.copyWith(id: 'real-0', name: 'Zero Updated'),
          idSelector: (item) => item.id,
        );

        // Wait for sync
        await Future.delayed(const Duration(milliseconds: 100));

        final result =
            await networkCache.get(key: 'items', fetch: (_) async => []);
        expect(result[0].id, equals('real-0'));
        expect(result[0].name, equals('Zero Updated'));
        expect(result[1].name, equals('First'));

        networkCache.dispose();
      });

      test('handles insert operation', () async {
        final controllableNetwork = _ControllableNetwork();
        final networkCache = Syncache<List<_Item>>(
          store: store,
          network: controllableNetwork,
        );

        await store.write(
          'items',
          Stored(
            value: [
              const _Item(id: '1', name: 'First'),
              const _Item(id: '3', name: 'Third'),
            ],
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        await networkCache.mutateListItem(
          key: 'items',
          operation:
              ListOperation.insert(1, const _Item(id: 'temp', name: 'Second')),
          send: (item) async => item.copyWith(id: '2'),
          idSelector: (item) => item.id,
        );

        // Wait for sync
        await Future.delayed(const Duration(milliseconds: 100));

        final result =
            await networkCache.get(key: 'items', fetch: (_) async => []);
        expect(result.length, equals(3));
        expect(result[1].id, equals('2'));
        expect(result[1].name, equals('Second'));

        networkCache.dispose();
      });

      test('throws CacheMissException when key not in cache', () async {
        expect(
          () => cache.mutateListItem(
            key: 'nonexistent',
            operation: ListOperation.append(const _Item(id: '1', name: 'Test')),
            send: (item) async => item,
            idSelector: (item) => item.id,
          ),
          throwsA(isA<CacheMissException>()),
        );
      });
    });

    group('invalidation', () {
      test('mutateList with invalidateTags triggers tag invalidation',
          () async {
        final taggableStore = MemoryStore<List<_Item>>();
        final taggableCache = Syncache<List<_Item>>(store: taggableStore);

        // Pre-populate cache with tagged entries
        await taggableStore.writeWithTags(
          'items',
          Stored(
            value: [const _Item(id: '1', name: 'First')],
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
          ['items-tag'],
        );

        await taggableStore.writeWithTags(
          'related',
          Stored(
            value: [const _Item(id: 'r1', name: 'Related')],
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
          ['items-tag'],
        );

        await taggableCache.mutateList(
          key: 'items',
          operation: ListOperation.append(const _Item(id: '2', name: 'Second')),
          send: () async {},
          invalidateTags: ['items-tag'],
        );

        // Wait for sync
        await Future.delayed(const Duration(milliseconds: 100));

        // The related entry should be invalidated
        final relatedEntry = await taggableStore.read('related');
        expect(relatedEntry, isNull);

        taggableCache.dispose();
      });

      test('mutateList with invalidates triggers key invalidation', () async {
        await store.write(
          'items',
          Stored(
            value: [const _Item(id: '1', name: 'First')],
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        await store.write(
          'items-count',
          Stored(
            value: [const _Item(id: 'count', name: '1')],
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        await cache.mutateList(
          key: 'items',
          operation: ListOperation.append(const _Item(id: '2', name: 'Second')),
          send: () async {},
          invalidates: ['items-count'],
        );

        // Wait for sync
        await Future.delayed(const Duration(milliseconds: 100));

        // items-count should be invalidated
        final countEntry = await store.read('items-count');
        expect(countEntry, isNull);
      });
    });
  });
}
