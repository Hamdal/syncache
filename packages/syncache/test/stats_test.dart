import 'dart:async';

import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

/// A network whose connectivity the test controls.
class _FakeNetwork implements Network {
  bool online = true;

  @override
  bool get isOnline => online;
}

void main() {
  group('SyncacheStats', () {
    test('counters track a scripted sequence exactly', () async {
      final cache = Syncache<String>(store: MemoryStore<String>());
      var calls = 0;

      // 1. Cold get: miss -> fetch start -> fetch success -> store.
      await cache.get(
        key: 'k',
        fetch: (request) async => 'v${++calls}',
      );
      expect(
        await cache.stats,
        SyncacheStats(
          hits: 0,
          misses: 1,
          fetchesStarted: 1,
          fetchesSucceeded: 1,
          fetchesFailed: 0,
          fetchesRetried: 0,
          fetchesCancelled: 0,
          stores: 1,
          invalidations: 0,
          evictions: 0,
          pendingMutations: 0,
          entryCount: 1,
        ),
      );

      // 2. Warm get: hit.
      await cache.get(key: 'k', fetch: (request) async => 'v${++calls}');
      final stats = await cache.stats;
      expect(stats.hits, equals(1));
      expect(stats.misses, equals(1),
          reason: 'the warm read must not count as a miss');

      // 3. Invalidate.
      await cache.invalidate('k');
      expect((await cache.stats).invalidations, equals(1));

      // 4. set() stores.
      await cache.set(key: 'k', value: 'direct');
      expect((await cache.stats).stores, equals(2));

      cache.dispose();
    });

    test('failed fetch with retry counts attempts', () async {
      final cache = Syncache<String>(
        store: MemoryStore<String>(),
        defaultRetry: RetryConfig(
          maxAttempts: 1,
          delay: (_) => Duration.zero,
        ),
      );

      await expectLater(
        cache.get(
            key: 'f',
            fetch: (request) async {
              throw Exception('boom');
            }),
        throwsA(anything),
      );

      final stats = await cache.stats;
      expect(stats.misses, equals(1));
      expect(stats.fetchesStarted, equals(2),
          reason: 'initial attempt + one retry');
      expect(stats.fetchesFailed, equals(2));
      expect(stats.fetchesRetried, equals(1));
      expect(stats.fetchesSucceeded, equals(0));
      cache.dispose();
    });

    test('cancellation counts as cancelled, not failed', () async {
      final cache = Syncache<String>(store: MemoryStore<String>());
      final token = CancellationToken();
      final fetchStarted = Completer<void>();
      final gate = Completer<void>();

      final future = cache.get(
        key: 'c',
        fetch: (request) async {
          fetchStarted.complete();
          await gate.future;
          return 'late';
        },
        cancel: token,
      );

      // Cancel only once the fetch is in flight — cancelling earlier hits
      // the engine's entry check, which throws before any event fires.
      await fetchStarted.future;
      token.cancel();
      gate.complete();
      await expectLater(future, throwsA(isA<CancelledException>()));

      final stats = await cache.stats;
      // The engine emits onFetchCancelled when it detects the cancellation
      // after the fetch returns and once more while unwinding.
      expect(stats.fetchesCancelled, equals(2));
      expect(stats.fetchesFailed, equals(0));
      expect(stats.fetchesStarted, equals(1));
      cache.dispose();
    });

    test('offline mutation stays pending in the snapshot', () async {
      final network = _FakeNetwork();
      network.online = false;
      final cache = Syncache<String>(
        store: MemoryStore<String>(),
        network: network,
      );
      await cache.set(key: 'm', value: 'v');
      await cache.mutate(
        key: 'm',
        mutation: Mutation<String>(
          apply: (v) => '$v!',
          send: (v) async => v,
        ),
      );

      final stats = await cache.stats;
      expect(stats.pendingMutations, equals(1));
      expect(cache.pendingMutationCount, equals(1));

      // Coming back online and flushing drains the queue.
      network.online = true;
      await cache.processPendingMutations();
      final afterSync = await cache.stats;
      expect(afterSync.pendingMutations, equals(0));
      expect(afterSync.stores, equals(3),
          reason: 'optimistic write + set + server-confirmed write');
      cache.dispose();
    });

    test('evictions are counted', () async {
      final cache = Syncache<String>(
        store: MemoryStore<String>(maxLength: 1),
      );

      await cache.set(key: 'k1', value: 'v1');
      await cache.set(key: 'k2', value: 'v2');

      final stats = await cache.stats;
      expect(stats.evictions, equals(1));
      expect(stats.entryCount, equals(1));
      cache.dispose();
    });

    test('resetStats zeroes everything and accepts a subset', () async {
      final cache = Syncache<String>(store: MemoryStore<String>());
      await cache.get(key: 'k', fetch: (request) async => 'v');
      await cache.get(key: 'k', fetch: (request) async => 'v');
      await cache.invalidate('k');

      // Full reset.
      cache.resetStats();
      var stats = await cache.stats;
      expect(stats.hits, equals(0));
      expect(stats.misses, equals(0));
      expect(stats.fetchesStarted, equals(0));
      expect(stats.invalidations, equals(0));

      // Counters keep accumulating after a reset.
      await cache.set(key: 'k', value: 'x');
      await cache.get(key: 'k', fetch: (request) async => 'v');
      stats = await cache.stats;
      expect(stats.hits, equals(1));

      // Per-counter reset: only the named counters are zeroed.
      await cache.invalidate('k');
      cache.resetStats({SyncacheCounter.hits});
      stats = await cache.stats;
      expect(stats.hits, equals(0));
      expect(stats.invalidations, equals(1),
          reason: 'invalidations were not part of the reset subset');

      cache.dispose();
    });

    test('entryCount is null for stores without key enumeration', () async {
      final cache = Syncache<String>(store: _OpaqueStore());
      expect((await cache.stats).entryCount, isNull);
      cache.dispose();
    });

    test('SyncacheStats.zero has all counters at zero', () {
      expect(
        SyncacheStats.zero,
        const SyncacheStats(
          hits: 0,
          misses: 0,
          fetchesStarted: 0,
          fetchesSucceeded: 0,
          fetchesFailed: 0,
          fetchesRetried: 0,
          fetchesCancelled: 0,
          stores: 0,
          invalidations: 0,
          evictions: 0,
          pendingMutations: 0,
        ),
      );
    });

    test('stats collector is not visible in the observers list', () {
      final cache = Syncache<String>(store: MemoryStore<String>());
      expect(cache.observers, isEmpty);
      cache.dispose();
    });
  });
}

/// A minimal store without enumeration support.
class _OpaqueStore implements Store<String> {
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
