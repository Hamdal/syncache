import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

void main() {
  Stored<String> expiredEntry(String value) => Stored(
        value: value,
        meta: Metadata(
          version: 1,
          storedAt: DateTime.now().subtract(const Duration(hours: 2)),
          ttl: const Duration(hours: 1),
        ),
      );

  group('cleanup', () {
    test('removes exactly the expired entries and returns the count', () async {
      final store = MemoryStore<String>();
      final cache = Syncache<String>(store: store);

      await store.write('expired', expiredEntry('old'));
      await store.write(
        'fresh',
        Stored(
          value: 'new',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
      );
      await store.write(
        'no-ttl',
        Stored(
          value: 'forever',
          meta: Metadata(version: 1, storedAt: DateTime(2020)),
        ),
      );

      final removed = await cache.cleanup();

      expect(removed, equals(1));
      expect(await store.read('expired'), isNull);
      expect(await store.read('fresh'), isNotNull);
      expect(await store.read('no-ttl'), isNotNull);
      cache.dispose();
    });

    test('swept keys are reported as invalidations', () async {
      final store = MemoryStore<String>();
      final cache = Syncache<String>(store: store);
      await store.write('expired', expiredEntry('old'));

      await cache.cleanup();

      final stats = await cache.stats;
      expect(stats.invalidations, equals(1));
      cache.dispose();
    });

    test('watchers of swept keys refetch and keep their stream open', () async {
      final store = MemoryStore<String>();
      final cache = Syncache<String>(store: store);

      var fetchCalls = 0;
      final values = <String>[];
      final sub = cache
          .watch(
            key: 'k1',
            fetch: (request) async => 'fresh-${++fetchCalls}',
          )
          .listen(values.add, onError: (Object _) {});
      await pumpEventQueue();
      expect(values, equals(['fresh-1']));

      // Simulate time passing: replace the cached entry with an expired one.
      await store.write('k1', expiredEntry('stale'));

      final removed = await cache.cleanup();
      expect(removed, equals(1));

      await pumpEventQueue();
      expect(values, equals(['fresh-1', 'fresh-2']),
          reason: 'the watcher refetched after the sweep');

      await sub.cancel();
      cache.dispose();
    });

    test('returns 0 for stores that cannot enumerate keys', () async {
      final cache = Syncache<String>(store: _NonIterableStore());
      expect(await cache.cleanup(), equals(0));
      expect((await cache.stats).entryCount, isNull);
      cache.dispose();
    });

    test('throws after dispose', () async {
      final cache = Syncache<String>(store: MemoryStore<String>());
      cache.dispose();
      expect(cache.cleanup, throwsStateError);
    });
  });

  group('periodic cleanupInterval', () {
    test('timer sweeps expired entries and is cancelled on dispose', () {
      fakeAsync((async) async {
        final store = MemoryStore<String>();
        final cache = Syncache<String>(
          store: store,
          cleanupInterval: const Duration(minutes: 10),
        );

        // Written already-expired (fakeAsync fakes timers, not the clock).
        await store.write('stale', expiredEntry('old'));
        await cache.set(key: 'durable', value: 'v2');
        expect(await store.read('stale'), isNotNull);

        async.elapse(const Duration(minutes: 15));

        // The 10-minute timer swept the expired entry; the entry without
        // a TTL stays.
        expect(await store.read('stale'), isNull);
        expect(await store.read('durable'), isNotNull);

        cache.dispose();

        // If the periodic timer were still active, flushTimers would throw.
        async.flushTimers();
      });
    });

    test('dispose prevents further sweeps', () {
      fakeAsync((async) async {
        final store = MemoryStore<String>();
        final cache = Syncache<String>(
          store: store,
          cleanupInterval: const Duration(minutes: 10),
        );

        await store.write('stale', expiredEntry('old'));

        cache.dispose();
        async.elapse(const Duration(minutes: 30));

        expect(await store.read('stale'), isNotNull,
            reason: 'no sweeps may run after dispose');
      });
    });
  });

  group('opportunisticCleanupEvery', () {
    test('sweeps at most once per N writes', () {
      fakeAsync((async) async {
        final store = MemoryStore<String>();
        final cache = Syncache<String>(
          store: store,
          opportunisticCleanupEvery: 2,
        );

        await store.write('stale', expiredEntry('old'));

        // First write: below the threshold, no sweep yet.
        await cache.set(key: 'a', value: '1');
        async.flushMicrotasks();
        expect(await store.read('stale'), isNotNull);

        // Second write: crosses the threshold, sweep removes the expired
        // entry.
        await cache.set(key: 'b', value: '2');
        async.flushMicrotasks();
        expect(await store.read('stale'), isNull);

        cache.dispose();
      });
    });

    test('disabled by default', () {
      fakeAsync((async) async {
        final store = MemoryStore<String>();
        final cache = Syncache<String>(store: store);

        await store.write('stale', expiredEntry('old'));
        for (var i = 0; i < 10; i++) {
          await cache.set(key: 'k$i', value: 'v$i');
        }
        async.flushMicrotasks();
        expect(await store.read('stale'), isNotNull,
            reason: 'default behavior never sweeps on writes');

        cache.dispose();
      });
    });
  });
}

/// A store without key enumeration to verify the optional capability path.
class _NonIterableStore implements Store<String> {
  final Map<String, Stored<String>> _cache = {};

  @override
  Future<void> write(String key, Stored<String> entry) async =>
      _cache[key] = entry;

  @override
  Future<Stored<String>?> read(String key) async => _cache[key];

  @override
  Future<void> delete(String key) async => _cache.remove(key);

  @override
  Future<void> clear() async => _cache.clear();
}
