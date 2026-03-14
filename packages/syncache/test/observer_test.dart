import 'dart:async';

import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

/// Test observer that records all events for verification.
class RecordingObserver extends SyncacheObserver {
  final List<String> events = [];

  void clear() => events.clear();

  @override
  void onCacheHit(String key) {
    events.add('cache_hit:$key');
  }

  @override
  void onCacheMiss(String key) {
    events.add('cache_miss:$key');
  }

  @override
  void onFetchStart(String key) {
    events.add('fetch_start:$key');
  }

  @override
  void onFetchSuccess(String key, Duration duration) {
    events.add('fetch_success:$key');
  }

  @override
  void onFetchError(String key, Object error, StackTrace stackTrace) {
    events.add('fetch_error:$key:$error');
  }

  @override
  void onInvalidate(String key) {
    events.add('invalidate:$key');
  }

  @override
  void onClear() {
    events.add('clear');
  }

  @override
  void onMutationStart(String key) {
    events.add('mutation_start:$key');
  }

  @override
  void onMutationSuccess(String key) {
    events.add('mutation_success:$key');
  }

  @override
  void onMutationError(String key, Object error, StackTrace stackTrace) {
    events.add('mutation_error:$key:$error');
  }

  @override
  void onStore(String key) {
    events.add('store:$key');
  }
}

void main() {
  group('SyncacheObserver', () {
    late Syncache<String> cache;
    late MemoryStore<String> store;
    late RecordingObserver observer;

    setUp(() {
      store = MemoryStore<String>();
      observer = RecordingObserver();
      cache = Syncache<String>(
        store: store,
        observers: [observer],
      );
    });

    group('cache hit/miss', () {
      test('notifies onCacheHit when value found in cache', () async {
        // Pre-populate cache
        await store.write(
          'test-key',
          Stored(
            value: 'cached-value',
            meta: Metadata(
              version: 1,
              storedAt: DateTime.now(),
              ttl: const Duration(hours: 1),
            ),
          ),
        );

        await cache.get(
          key: 'test-key',
          fetch: (_) async => 'fetched-value',
        );

        expect(observer.events, contains('cache_hit:test-key'));
        expect(observer.events, isNot(contains('cache_miss:test-key')));
      });

      test('notifies onCacheMiss when value not found', () async {
        await cache.get(
          key: 'missing-key',
          fetch: (_) async => 'fetched-value',
        );

        expect(observer.events, contains('cache_miss:missing-key'));
        expect(observer.events, isNot(contains('cache_hit:missing-key')));
      });

      test('notifies onCacheMiss when value expired', () async {
        // Pre-populate with expired value
        await store.write(
          'expired-key',
          Stored(
            value: 'expired-value',
            meta: Metadata(
              version: 1,
              storedAt: DateTime.now().subtract(const Duration(hours: 2)),
              ttl: const Duration(hours: 1),
            ),
          ),
        );

        await cache.get(
          key: 'expired-key',
          fetch: (_) async => 'fresh-value',
        );

        expect(observer.events, contains('cache_miss:expired-key'));
      });

      test('notifies onCacheHit with staleWhileRefresh policy', () async {
        await store.write(
          'stale-key',
          Stored(
            value: 'stale-value',
            meta: Metadata(
              version: 1,
              storedAt: DateTime.now(),
              ttl: const Duration(hours: 1),
            ),
          ),
        );

        await cache.get(
          key: 'stale-key',
          fetch: (_) async => 'fresh-value',
          policy: Policy.staleWhileRefresh,
        );

        expect(observer.events, contains('cache_hit:stale-key'));
      });
    });

    group('fetch events', () {
      test('notifies onFetchStart and onFetchSuccess', () async {
        await cache.get(
          key: 'fetch-key',
          fetch: (_) async => 'fetched-value',
          policy: Policy.networkOnly,
        );

        expect(observer.events, contains('fetch_start:fetch-key'));
        expect(observer.events, contains('fetch_success:fetch-key'));
      });

      test('notifies onFetchError when fetch fails', () async {
        try {
          await cache.get(
            key: 'error-key',
            fetch: (_) async => throw Exception('Network error'),
            policy: Policy.networkOnly,
          );
        } catch (_) {}

        expect(observer.events, contains('fetch_start:error-key'));
        expect(
          observer.events,
          contains(startsWith('fetch_error:error-key:')),
        );
      });

      test('notifies onStore after successful fetch', () async {
        await cache.get(
          key: 'store-key',
          fetch: (_) async => 'value',
          policy: Policy.networkOnly,
        );

        expect(observer.events, contains('store:store-key'));
      });

      test('fetch events occur in correct order', () async {
        await cache.get(
          key: 'order-key',
          fetch: (_) async => 'value',
          policy: Policy.networkOnly,
        );

        final fetchStart = observer.events.indexOf('fetch_start:order-key');
        final fetchSuccess = observer.events.indexOf('fetch_success:order-key');
        final onStore = observer.events.indexOf('store:order-key');

        expect(fetchStart, lessThan(fetchSuccess));
        expect(fetchSuccess, lessThan(onStore));
      });
    });

    group('invalidate and clear', () {
      test('notifies onInvalidate when key invalidated', () async {
        await store.write(
          'invalidate-key',
          Stored(
            value: 'value',
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        await cache.invalidate('invalidate-key');

        expect(observer.events, contains('invalidate:invalidate-key'));
      });

      test('notifies onClear when cache cleared', () async {
        await store.write(
          'key1',
          Stored(
            value: 'value1',
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        await cache.clear();

        expect(observer.events, contains('clear'));
      });
    });

    group('mutation events', () {
      test('notifies onMutationStart when mutation begins', () async {
        await store.write(
          'mutate-key',
          Stored(
            value: 'original',
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        unawaited(cache.mutate(
          key: 'mutate-key',
          mutation: Mutation<String>(
            apply: (v) => 'mutated-$v',
            send: (v) async => v,
          ),
        ));

        await Future.delayed(const Duration(milliseconds: 10));

        expect(observer.events, contains('mutation_start:mutate-key'));
      });

      test('notifies onMutationSuccess when mutation sync succeeds', () async {
        await store.write(
          'sync-key',
          Stored(
            value: 'original',
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        await cache.mutate(
          key: 'sync-key',
          mutation: Mutation<String>(
            apply: (v) => 'mutated-$v',
            send: (v) async => 'server-$v',
          ),
        );

        await Future.delayed(const Duration(milliseconds: 50));

        expect(observer.events, contains('mutation_success:sync-key'));
      });

      test('notifies onMutationError when mutation sync fails', () async {
        await store.write(
          'fail-key',
          Stored(
            value: 'original',
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        await cache.mutate(
          key: 'fail-key',
          mutation: Mutation<String>(
            apply: (v) => 'mutated-$v',
            send: (v) async => throw Exception('Sync failed'),
          ),
        );

        await Future.delayed(const Duration(milliseconds: 50));

        expect(
          observer.events,
          contains(startsWith('mutation_error:fail-key:')),
        );
      });

      test('notifies onStore after optimistic mutation', () async {
        await store.write(
          'store-mutate-key',
          Stored(
            value: 'original',
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        unawaited(cache.mutate(
          key: 'store-mutate-key',
          mutation: Mutation<String>(
            apply: (v) => 'mutated-$v',
            send: (v) async => v,
          ),
        ));

        await Future.delayed(const Duration(milliseconds: 10));

        expect(observer.events, contains('store:store-mutate-key'));
      });
    });

    group('multiple observers', () {
      test('notifies all observers', () async {
        final observer2 = RecordingObserver();
        final multiCache = Syncache<String>(
          store: MemoryStore<String>(),
          observers: [observer, observer2],
        );

        await multiCache.get(
          key: 'multi-key',
          fetch: (_) async => 'value',
          policy: Policy.networkOnly,
        );

        expect(observer.events, contains('fetch_start:multi-key'));
        expect(observer2.events, contains('fetch_start:multi-key'));
      });

      test('continues if one observer throws', () async {
        final throwingObserver = _ThrowingObserver();
        final safeCache = Syncache<String>(
          store: MemoryStore<String>(),
          observers: [throwingObserver, observer],
        );

        // Should not throw despite observer error
        await safeCache.get(
          key: 'safe-key',
          fetch: (_) async => 'value',
          policy: Policy.networkOnly,
        );

        // Second observer should still receive events
        expect(observer.events, contains('fetch_start:safe-key'));
      });
    });

    group('no observers', () {
      test('works without observers', () async {
        final noObserverCache = Syncache<String>(
          store: MemoryStore<String>(),
        );

        // Should work fine with no observers
        final result = await noObserverCache.get(
          key: 'no-observer-key',
          fetch: (_) async => 'value',
          policy: Policy.networkOnly,
        );

        expect(result, equals('value'));
      });
    });
  });

  group('LoggingObserver', () {
    test('can be instantiated with defaults', () {
      final observer = LoggingObserver();
      expect(observer.prefix, equals('Syncache'));
      expect(observer.includeStackTrace, isFalse);
    });

    test('can be instantiated with custom options', () {
      final observer = LoggingObserver(
        prefix: 'MyCache',
        includeStackTrace: true,
      );
      expect(observer.prefix, equals('MyCache'));
      expect(observer.includeStackTrace, isTrue);
    });
  });
}

/// Observer that throws on every callback to test error isolation.
class _ThrowingObserver extends SyncacheObserver {
  @override
  void onCacheHit(String key) => throw Exception('Observer error');

  @override
  void onCacheMiss(String key) => throw Exception('Observer error');

  @override
  void onFetchStart(String key) => throw Exception('Observer error');

  @override
  void onFetchSuccess(String key, Duration duration) =>
      throw Exception('Observer error');

  @override
  void onFetchError(String key, Object error, StackTrace stackTrace) =>
      throw Exception('Observer error');
}
