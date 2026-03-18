import 'dart:async';

import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

/// A Network implementation that is always offline.
class _OfflineNetwork implements Network {
  @override
  bool get isOnline => false;
}

/// A simple observer that records events.
class _TestObserver extends SyncacheObserver {
  final events = <String>[];

  @override
  void onCacheHit(String key) => events.add('cache_hit:$key');

  @override
  void onCacheMiss(String key) => events.add('cache_miss:$key');

  @override
  void onFetchStart(String key) => events.add('fetch_start:$key');

  @override
  void onFetchSuccess(String key, Duration duration) =>
      events.add('fetch_success:$key');

  @override
  void onFetchError(String key, Object error, StackTrace stackTrace) =>
      events.add('fetch_error:$key:$error');

  @override
  void onStore(String key) => events.add('store:$key');

  @override
  void onInvalidate(String key) => events.add('invalidate:$key');

  @override
  void onClear() => events.add('clear');
}

void main() {
  group('Policy.cacheAndRefresh', () {
    late Syncache<String> cache;
    late MemoryStore<String> store;

    setUp(() {
      store = MemoryStore<String>();
      cache = Syncache<String>(store: store);
    });

    group('get', () {
      test('returns cached value immediately and triggers background refresh',
          () async {
        // Pre-populate cache with valid (non-expired) value
        await store.write(
          'car-key',
          Stored(
            value: 'cached-value',
            meta: Metadata(
              version: 1,
              storedAt: DateTime.now(),
              ttl: const Duration(hours: 1),
            ),
          ),
        );

        var fetchCount = 0;
        final completer = Completer<String>();

        final result = await cache.get(
          key: 'car-key',
          fetch: (_) async {
            fetchCount++;
            return completer.future;
          },
          policy: Policy.cacheAndRefresh,
        );

        // Should return cached value immediately
        expect(result, equals('cached-value'));

        // Allow microtask to start background fetch
        await Future.delayed(Duration.zero);

        // Background fetch should have started (even though cache is valid)
        expect(fetchCount, equals(1));

        // Complete the background fetch
        completer.complete('fresh-value');
        await Future.delayed(const Duration(milliseconds: 50));

        // Cache should now have fresh value
        final cached = await store.read('car-key');
        expect(cached!.value, equals('fresh-value'));
      });

      test('returns stale cached value and triggers background refresh',
          () async {
        // Pre-populate cache with expired value
        await store.write(
          'stale-car-key',
          Stored(
            value: 'stale-value',
            meta: Metadata(
              version: 1,
              storedAt: DateTime.now().subtract(const Duration(hours: 2)),
              ttl: const Duration(hours: 1),
            ),
          ),
        );

        var fetchCount = 0;
        final completer = Completer<String>();

        final result = await cache.get(
          key: 'stale-car-key',
          fetch: (_) async {
            fetchCount++;
            return completer.future;
          },
          policy: Policy.cacheAndRefresh,
        );

        // Should return stale value immediately
        expect(result, equals('stale-value'));

        // Allow microtask to start background fetch
        await Future.delayed(Duration.zero);

        // Background fetch should have started
        expect(fetchCount, equals(1));

        // Complete the background fetch
        completer.complete('fresh-value');
        await Future.delayed(const Duration(milliseconds: 50));

        // Cache should now have fresh value
        final cached = await store.read('stale-car-key');
        expect(cached!.value, equals('fresh-value'));
      });

      test('fetches and returns when no cache exists', () async {
        var fetchCount = 0;

        final result = await cache.get(
          key: 'no-cache-key',
          fetch: (_) async {
            fetchCount++;
            return 'fetched-value';
          },
          policy: Policy.cacheAndRefresh,
        );

        expect(result, equals('fetched-value'));
        expect(fetchCount, equals(1));

        // Verify it was cached
        final cached = await store.read('no-cache-key');
        expect(cached!.value, equals('fetched-value'));
      });

      test('throws CacheMissException when offline with no cache', () async {
        final offlineCache = Syncache<String>(
          store: store,
          network: _OfflineNetwork(),
        );

        expect(
          () => offlineCache.get(
            key: 'offline-no-cache',
            fetch: (_) async => 'value',
            policy: Policy.cacheAndRefresh,
          ),
          throwsA(isA<CacheMissException>()),
        );
      });

      test('returns cached value without background refresh when offline',
          () async {
        final offlineCache = Syncache<String>(
          store: store,
          network: _OfflineNetwork(),
        );

        // Pre-populate cache
        await store.write(
          'offline-cached-key',
          Stored(
            value: 'cached-value',
            meta: Metadata(
              version: 1,
              storedAt: DateTime.now(),
              ttl: const Duration(hours: 1),
            ),
          ),
        );

        var fetchCount = 0;

        final result = await offlineCache.get(
          key: 'offline-cached-key',
          fetch: (_) async {
            fetchCount++;
            return 'should-not-fetch';
          },
          policy: Policy.cacheAndRefresh,
        );

        expect(result, equals('cached-value'));
        // Should not attempt fetch when offline
        expect(fetchCount, equals(0));
      });

      test('background fetch error does not affect returned cached value',
          () async {
        await store.write(
          'error-key',
          Stored(
            value: 'cached-value',
            meta: Metadata(
              version: 1,
              storedAt: DateTime.now(),
              ttl: const Duration(hours: 1),
            ),
          ),
        );

        final result = await cache.get(
          key: 'error-key',
          fetch: (_) async {
            throw Exception('Network error');
          },
          policy: Policy.cacheAndRefresh,
        );

        // Should return cached value
        expect(result, equals('cached-value'));

        // Wait for background fetch to complete (with error)
        await Future.delayed(const Duration(milliseconds: 50));

        // Cache should still have original value
        final cached = await store.read('error-key');
        expect(cached!.value, equals('cached-value'));
      });
    });

    group('getWithMeta', () {
      test('returns cached value with metadata and triggers background refresh',
          () async {
        final storedAt = DateTime.now();
        await store.write(
          'meta-key',
          Stored(
            value: 'cached-value',
            meta: Metadata(
              version: 1,
              storedAt: storedAt,
              ttl: const Duration(hours: 1),
            ),
          ),
        );

        var fetchCount = 0;
        final completer = Completer<String>();

        final result = await cache.getWithMeta(
          key: 'meta-key',
          fetch: (_) async {
            fetchCount++;
            return completer.future;
          },
          policy: Policy.cacheAndRefresh,
        );

        // Should return cached value with metadata
        expect(result.value, equals('cached-value'));
        expect(result.meta.isFromCache, isTrue);
        expect(result.meta.isStale, isFalse);

        // Allow microtask to start background fetch
        await Future.delayed(Duration.zero);

        // Background fetch should have started
        expect(fetchCount, equals(1));

        // Complete background fetch
        completer.complete('fresh-value');
        await Future.delayed(const Duration(milliseconds: 50));

        // Cache should be updated
        final cached = await store.read('meta-key');
        expect(cached!.value, equals('fresh-value'));
      });

      test('returns stale metadata when cache is expired', () async {
        await store.write(
          'stale-meta-key',
          Stored(
            value: 'stale-value',
            meta: Metadata(
              version: 1,
              storedAt: DateTime.now().subtract(const Duration(hours: 2)),
              ttl: const Duration(hours: 1),
            ),
          ),
        );

        final completer = Completer<String>();

        final result = await cache.getWithMeta(
          key: 'stale-meta-key',
          fetch: (_) async => completer.future,
          policy: Policy.cacheAndRefresh,
        );

        expect(result.value, equals('stale-value'));
        expect(result.meta.isFromCache, isTrue);
        expect(result.meta.isStale, isTrue);

        completer.complete('fresh-value');
      });

      test('throws CacheMissException when offline with no cache', () async {
        final offlineCache = Syncache<String>(
          store: store,
          network: _OfflineNetwork(),
        );

        expect(
          () => offlineCache.getWithMeta(
            key: 'no-cache-meta',
            fetch: (_) async => 'value',
            policy: Policy.cacheAndRefresh,
          ),
          throwsA(isA<CacheMissException>()),
        );
      });
    });

    group('watch', () {
      test('emits cached value then fresh value after background refresh',
          () async {
        await store.write(
          'watch-car-key',
          Stored(
            value: 'cached-value',
            meta: Metadata(
              version: 1,
              storedAt: DateTime.now(),
              ttl: const Duration(hours: 1),
            ),
          ),
        );

        final completer = Completer<String>();
        final values = <String>[];

        final subscription = cache
            .watch(
              key: 'watch-car-key',
              fetch: (_) async => completer.future,
              policy: Policy.cacheAndRefresh,
            )
            .listen(values.add);

        // Wait for initial emission
        await Future.delayed(const Duration(milliseconds: 50));

        // Should have cached value
        expect(values, contains('cached-value'));

        // Complete background refresh
        completer.complete('fresh-value');
        await Future.delayed(const Duration(milliseconds: 50));

        // Should have both cached and fresh values
        expect(values, contains('cached-value'));
        expect(values, contains('fresh-value'));

        await subscription.cancel();
      });

      test('emits only fresh value when no cache exists', () async {
        final values = <String>[];

        final subscription = cache
            .watch(
              key: 'watch-no-cache',
              fetch: (_) async => 'fresh-value',
              policy: Policy.cacheAndRefresh,
            )
            .listen(values.add);

        await Future.delayed(const Duration(milliseconds: 50));

        expect(values, equals(['fresh-value']));

        await subscription.cancel();
      });
    });

    group('request deduplication', () {
      test('deduplicates background refresh requests', () async {
        await store.write(
          'dedup-car-key',
          Stored(
            value: 'cached-value',
            meta: Metadata(
              version: 1,
              storedAt: DateTime.now(),
              ttl: const Duration(hours: 1),
            ),
          ),
        );

        var fetchCount = 0;
        final completer = Completer<String>();

        Future<String> fetcher(SyncacheRequest _) async {
          fetchCount++;
          return completer.future;
        }

        // Start concurrent requests
        final result1 = await cache.get(
          key: 'dedup-car-key',
          fetch: fetcher,
          policy: Policy.cacheAndRefresh,
        );
        final result2 = await cache.get(
          key: 'dedup-car-key',
          fetch: fetcher,
          policy: Policy.cacheAndRefresh,
        );

        // Both should return cached value immediately
        expect(result1, equals('cached-value'));
        expect(result2, equals('cached-value'));

        // Complete background refresh
        completer.complete('fresh-value');
        await Future.delayed(const Duration(milliseconds: 50));

        // Should have only triggered one background fetch
        expect(fetchCount, equals(1));

        // Cache should have fresh value
        final cached = await store.read('dedup-car-key');
        expect(cached!.value, equals('fresh-value'));
      });
    });

    group('observer notifications', () {
      late _TestObserver observer;
      late Syncache<String> observedCache;

      setUp(() {
        observer = _TestObserver();
        observedCache = Syncache<String>(
          store: store,
          observers: [observer],
        );
      });

      test('notifies onCacheHit when cache exists', () async {
        await store.write(
          'observer-hit-key',
          Stored(
            value: 'cached-value',
            meta: Metadata(
              version: 1,
              storedAt: DateTime.now(),
              ttl: const Duration(hours: 1),
            ),
          ),
        );

        final completer = Completer<String>();

        await observedCache.get(
          key: 'observer-hit-key',
          fetch: (_) async => completer.future,
          policy: Policy.cacheAndRefresh,
        );

        expect(observer.events, contains('cache_hit:observer-hit-key'));

        completer.complete('fresh');
      });

      test('notifies onCacheMiss when no cache exists', () async {
        await observedCache.get(
          key: 'observer-miss-key',
          fetch: (_) async => 'fetched',
          policy: Policy.cacheAndRefresh,
        );

        expect(observer.events, contains('cache_miss:observer-miss-key'));
      });

      test('notifies onFetchError when background refresh fails', () async {
        await store.write(
          'observer-error-key',
          Stored(
            value: 'cached-value',
            meta: Metadata(
              version: 1,
              storedAt: DateTime.now(),
              ttl: const Duration(hours: 1),
            ),
          ),
        );

        await observedCache.get(
          key: 'observer-error-key',
          fetch: (_) async => throw Exception('Network error'),
          policy: Policy.cacheAndRefresh,
        );

        // Wait for background fetch to fail
        await Future.delayed(const Duration(milliseconds: 50));

        expect(
          observer.events,
          contains(startsWith('fetch_error:observer-error-key:')),
        );
      });

      test('notifies onStore after successful background refresh', () async {
        await store.write(
          'observer-store-key',
          Stored(
            value: 'cached-value',
            meta: Metadata(
              version: 1,
              storedAt: DateTime.now(),
              ttl: const Duration(hours: 1),
            ),
          ),
        );

        await observedCache.get(
          key: 'observer-store-key',
          fetch: (_) async => 'fresh-value',
          policy: Policy.cacheAndRefresh,
        );

        // Wait for background fetch to complete
        await Future.delayed(const Duration(milliseconds: 50));

        expect(observer.events, contains('store:observer-store-key'));
      });
    });

    group('comparison with staleWhileRefresh', () {
      test(
          'cacheAndRefresh refreshes even when cache is valid, staleWhileRefresh does not',
          () async {
        // Pre-populate cache with valid (non-expired) value
        await store.write(
          'compare-key',
          Stored(
            value: 'cached-value',
            meta: Metadata(
              version: 1,
              storedAt: DateTime.now(),
              ttl: const Duration(hours: 1),
            ),
          ),
        );

        var swrFetchCount = 0;
        var carFetchCount = 0;

        // staleWhileRefresh should NOT trigger background refresh for valid cache
        await cache.get(
          key: 'compare-key',
          fetch: (_) async {
            swrFetchCount++;
            return 'swr-fresh';
          },
          policy: Policy.staleWhileRefresh,
        );

        // Allow microtask queue to flush
        await Future.delayed(Duration.zero);

        expect(swrFetchCount, equals(0),
            reason: 'staleWhileRefresh should not fetch when cache is valid');

        // cacheAndRefresh SHOULD trigger background refresh even for valid cache
        final completer = Completer<String>();
        await cache.get(
          key: 'compare-key',
          fetch: (_) async {
            carFetchCount++;
            return completer.future;
          },
          policy: Policy.cacheAndRefresh,
        );

        // Allow microtask to start background fetch
        await Future.delayed(Duration.zero);

        expect(carFetchCount, equals(1),
            reason: 'cacheAndRefresh should always fetch when online');

        completer.complete('car-fresh');
      });
    });
  });
}
