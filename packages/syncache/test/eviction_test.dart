import 'dart:async';

import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

/// Observer recording eviction and invalidation events.
class _RecordingObserver extends SyncacheObserver {
  final List<String> events = [];

  @override
  void onEvict(String key) => events.add('evict:$key');

  @override
  void onInvalidate(String key) => events.add('invalidate:$key');
}

void main() {
  Stored<String> entry(String value) => Stored(
        value: value,
        meta: Metadata(version: 1, storedAt: DateTime.now()),
      );

  group('MemoryStore LRU eviction', () {
    test('evicts least-recently-used entry when maxLength exceeded', () async {
      final store = MemoryStore<String>(maxLength: 2);

      await store.write('k1', entry('v1'));
      await store.write('k2', entry('v2'));
      // Touch k1 so k2 becomes the least-recently-used entry.
      await store.read('k1');

      await store.write('k3', entry('v3'));

      expect(await store.read('k1'), isNotNull, reason: 'k1 was touched');
      expect(await store.read('k2'), isNull, reason: 'k2 was the LRU entry');
      expect(await store.read('k3'), isNotNull);
      expect(await store.length, equals(2));
    });

    test('rewriting an existing key refreshes its recency', () async {
      final store = MemoryStore<String>(maxLength: 2);

      await store.write('k1', entry('v1'));
      await store.write('k2', entry('v2'));
      await store.write('k1', entry('v1-updated'));

      await store.write('k3', entry('v3'));

      expect(await store.read('k1'), isNotNull,
          reason: 'k1 was refreshed, not the LRU entry');
      expect((await store.read('k1'))!.value, equals('v1-updated'));
      expect(await store.read('k2'), isNull);
    });

    test('maxLength null (default) keeps the store unbounded', () async {
      final store = MemoryStore<String>();

      for (var i = 0; i < 100; i++) {
        await store.write('k$i', entry('v$i'));
      }

      expect(await store.length, equals(100));
      expect(await store.read('k0'), isNotNull);
      expect(store.maxLength, isNull);
    });

    test('eviction removes tag mappings together with the entry', () async {
      final store = MemoryStore<String>(maxLength: 2);

      await store.writeWithTags('k1', entry('v1'), ['users']);
      await store.writeWithTags('k2', entry('v2'), ['users']);
      await store.read('k1'); // make k2 the LRU entry

      await store.write('k3', entry('v3')); // evicts k2

      expect(await store.read('k2'), isNull);
      expect(await store.getTags('k2'), isEmpty);
      expect(await store.getKeysByTag('users'), ['k1']);
    });

    test('setting maxLength directly evicts down to the limit', () async {
      final store = MemoryStore<String>();

      for (var i = 0; i < 5; i++) {
        await store.write('k$i', entry('v$i'));
      }

      store.maxLength = 2;

      expect(await store.length, equals(2));
      // The two most recently written entries survive.
      expect(await store.read('k3'), isNotNull);
      expect(await store.read('k4'), isNotNull);
    });

    test('onEvict callback fires for every evicted key', () async {
      final evicted = <String>[];
      final store = MemoryStore<String>(
        maxLength: 2,
        onEvict: evicted.add,
      );

      await store.write('k1', entry('v1'));
      await store.write('k2', entry('v2'));
      await store.write('k3', entry('v3'));
      await store.write('k4', entry('v4'));

      expect(evicted, ['k1', 'k2']);
    });
  });

  group('Syncache eviction integration', () {
    test('eviction is reported to observers as onEvict', () async {
      final observer = _RecordingObserver();
      final cache = Syncache<String>(
        store: MemoryStore<String>(maxLength: 1),
        observers: [observer],
      );

      await cache.set(key: 'k1', value: 'v1');
      await cache.set(key: 'k2', value: 'v2'); // evicts k1

      expect(observer.events, contains('evict:k1'));
      expect(observer.events, isNot(contains('invalidate:k1')),
          reason: 'eviction is a capacity event, not an invalidation');
      cache.dispose();
    });

    test('eviction is not refetched through watchers', () async {
      final cache = Syncache<String>(
        store: MemoryStore<String>(maxLength: 1),
      );

      final values = <String>[];
      final sub = cache
          .watch(
            key: 'k1',
            fetch: (request) async => 'fresh-k1',
          )
          .listen(values.add);
      await pumpEventQueue();

      await cache.set(key: 'k2', value: 'v2'); // evicts k1

      await pumpEventQueue();
      final valueCountBefore = values.length;
      await Future<void>.delayed(Duration.zero);
      expect(values.length, valueCountBefore,
          reason: 'watchers keep their last value on eviction');

      await sub.cancel();
      cache.dispose();
    });

    test('stats count evictions', () async {
      final cache = Syncache<String>(
        store: MemoryStore<String>(maxLength: 1),
      );

      await cache.set(key: 'k1', value: 'v1');
      await cache.set(key: 'k2', value: 'v2'); // evicts k1

      final stats = await cache.stats;
      expect(stats.evictions, equals(1));
      expect(stats.entryCount, equals(1));
      cache.dispose();
    });
  });
}
