import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

void main() {
  group('PrefetchRequest', () {
    test('has correct default values', () {
      final request = PrefetchRequest<String>(
        key: 'test',
        fetch: (_) async => 'data',
      );

      expect(request.key, equals('test'));
      expect(request.policy, equals(Policy.refresh));
      expect(request.ttl, isNull);
      expect(request.retry, isNull);
    });

    test('accepts custom policy', () {
      final request = PrefetchRequest<String>(
        key: 'test',
        fetch: (_) async => 'data',
        policy: Policy.offlineFirst,
      );

      expect(request.policy, equals(Policy.offlineFirst));
    });

    test('accepts ttl and retry config', () {
      final retryConfig = RetryConfig(maxAttempts: 5);
      final request = PrefetchRequest<String>(
        key: 'test',
        fetch: (_) async => 'data',
        ttl: Duration(hours: 1),
        retry: retryConfig,
      );

      expect(request.ttl, equals(Duration(hours: 1)));
      expect(request.retry, equals(retryConfig));
    });
  });

  group('PrefetchResult', () {
    test('success creates correct result', () {
      final result = PrefetchResult.success('test-key');

      expect(result.key, equals('test-key'));
      expect(result.success, isTrue);
      expect(result.error, isNull);
      expect(result.stackTrace, isNull);
    });

    test('failure creates correct result', () {
      final error = Exception('Test error');
      final stackTrace = StackTrace.current;
      final result = PrefetchResult.failure('test-key', error, stackTrace);

      expect(result.key, equals('test-key'));
      expect(result.success, isFalse);
      expect(result.error, equals(error));
      expect(result.stackTrace, equals(stackTrace));
    });

    test('toString returns readable format', () {
      expect(
        PrefetchResult.success('key').toString(),
        equals('PrefetchResult.success(key)'),
      );

      final failResult = PrefetchResult.failure(
        'key',
        Exception('error'),
        StackTrace.current,
      );
      expect(failResult.toString(), contains('PrefetchResult.failure'));
      expect(failResult.toString(), contains('key'));
    });
  });

  group('Syncache.prefetch', () {
    late Syncache<String> cache;
    late MemoryStore<String> store;

    setUp(() {
      store = MemoryStore<String>();
      cache = Syncache<String>(store: store);
    });

    test('prefetches single item successfully', () async {
      var fetchCount = 0;

      final results = await cache.prefetch([
        PrefetchRequest(
          key: 'test',
          fetch: (_) async {
            fetchCount++;
            return 'data';
          },
        ),
      ]);

      expect(results.length, equals(1));
      expect(results[0].success, isTrue);
      expect(results[0].key, equals('test'));
      expect(fetchCount, equals(1));

      // Verify data is in cache
      final cached = await store.read('test');
      expect(cached, isNotNull);
      expect(cached!.value, equals('data'));
    });

    test('prefetches multiple items in parallel', () async {
      final fetchOrder = <String>[];
      // ignore: unused_local_variable
      final fetchCompleters = <String, Future<String>>{};

      // Create slow fetchers to verify parallel execution
      Future<String> createFetcher(String key) async {
        fetchOrder.add('start:$key');
        await Future.delayed(Duration(milliseconds: 50));
        fetchOrder.add('end:$key');
        return 'data:$key';
      }

      final results = await cache.prefetch([
        PrefetchRequest(key: 'a', fetch: (_) => createFetcher('a')),
        PrefetchRequest(key: 'b', fetch: (_) => createFetcher('b')),
        PrefetchRequest(key: 'c', fetch: (_) => createFetcher('c')),
      ]);

      expect(results.length, equals(3));
      expect(results.every((r) => r.success), isTrue);

      // Verify parallel execution - all starts should come before all ends
      expect(fetchOrder.take(3).toSet(),
          equals({'start:a', 'start:b', 'start:c'}));
    });

    test('returns results in same order as requests', () async {
      final results = await cache.prefetch([
        PrefetchRequest(key: 'first', fetch: (_) async => 'a'),
        PrefetchRequest(key: 'second', fetch: (_) async => 'b'),
        PrefetchRequest(key: 'third', fetch: (_) async => 'c'),
      ]);

      expect(results[0].key, equals('first'));
      expect(results[1].key, equals('second'));
      expect(results[2].key, equals('third'));
    });

    test('captures failures without throwing', () async {
      final results = await cache.prefetch([
        PrefetchRequest(
          key: 'success',
          fetch: (_) async => 'data',
        ),
        PrefetchRequest(
          key: 'failure',
          fetch: (_) async => throw Exception('Network error'),
        ),
      ]);

      expect(results.length, equals(2));
      expect(results[0].success, isTrue);
      expect(results[0].key, equals('success'));
      expect(results[1].success, isFalse);
      expect(results[1].key, equals('failure'));
      expect(results[1].error, isA<Exception>());
    });

    test('uses Policy.refresh by default', () async {
      // Pre-populate cache
      await store.write(
        'test',
        Stored(
          value: 'old',
          meta: Metadata(
            version: 1,
            storedAt: DateTime.now(),
          ),
        ),
      );

      var fetched = false;
      await cache.prefetch([
        PrefetchRequest(
          key: 'test',
          fetch: (_) async {
            fetched = true;
            return 'new';
          },
        ),
      ]);

      // Should have fetched even though cache had valid data
      expect(fetched, isTrue);

      final cached = await store.read('test');
      expect(cached!.value, equals('new'));
    });

    test('respects custom policy in request', () async {
      // Pre-populate cache with valid data
      await store.write(
        'test',
        Stored(
          value: 'cached',
          meta: Metadata(
            version: 1,
            storedAt: DateTime.now(),
            ttl: Duration(hours: 1),
          ),
        ),
      );

      var fetched = false;
      await cache.prefetch([
        PrefetchRequest(
          key: 'test',
          fetch: (_) async {
            fetched = true;
            return 'new';
          },
          policy: Policy.offlineFirst, // Should use cache
        ),
      ]);

      // Should NOT have fetched because offlineFirst uses valid cache
      expect(fetched, isFalse);
    });

    test('applies ttl from request', () async {
      final ttl = Duration(minutes: 30);

      await cache.prefetch([
        PrefetchRequest(
          key: 'test',
          fetch: (_) async => 'data',
          ttl: ttl,
        ),
      ]);

      final cached = await store.read('test');
      expect(cached!.meta.ttl, equals(ttl));
    });

    test('uses retry config from request', () async {
      var fetchCount = 0;

      final results = await cache.prefetch([
        PrefetchRequest(
          key: 'test',
          fetch: (_) async {
            fetchCount++;
            if (fetchCount < 3) {
              throw Exception('Transient error');
            }
            return 'data';
          },
          retry: RetryConfig(
            maxAttempts: 3,
            delay: (_) => Duration.zero,
          ),
        ),
      ]);

      expect(results[0].success, isTrue);
      expect(fetchCount, equals(3));
    });

    test('returns empty list for empty requests', () async {
      final results = await cache.prefetch([]);
      expect(results, isEmpty);
    });

    test('continues prefetching even when some fail', () async {
      var successFetched = false;

      final results = await cache.prefetch([
        PrefetchRequest(
          key: 'fail1',
          fetch: (_) async => throw Exception('Error 1'),
        ),
        PrefetchRequest(
          key: 'success',
          fetch: (_) async {
            successFetched = true;
            return 'data';
          },
        ),
        PrefetchRequest(
          key: 'fail2',
          fetch: (_) async => throw Exception('Error 2'),
        ),
      ]);

      expect(successFetched, isTrue);
      expect(results[0].success, isFalse);
      expect(results[1].success, isTrue);
      expect(results[2].success, isFalse);
    });
  });

  group('Syncache.prefetchOne', () {
    late Syncache<String> cache;
    late MemoryStore<String> store;

    setUp(() {
      store = MemoryStore<String>();
      cache = Syncache<String>(store: store);
    });

    test('returns true on success', () async {
      final success = await cache.prefetchOne(
        key: 'test',
        fetch: (_) async => 'data',
      );

      expect(success, isTrue);

      final cached = await store.read('test');
      expect(cached!.value, equals('data'));
    });

    test('returns false on failure', () async {
      final success = await cache.prefetchOne(
        key: 'test',
        fetch: (_) async => throw Exception('Error'),
      );

      expect(success, isFalse);
    });

    test('uses Policy.refresh by default', () async {
      // Pre-populate cache
      await store.write(
        'test',
        Stored(
          value: 'old',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
      );

      var fetched = false;
      await cache.prefetchOne(
        key: 'test',
        fetch: (_) async {
          fetched = true;
          return 'new';
        },
      );

      expect(fetched, isTrue);
    });

    test('respects custom policy', () async {
      // Pre-populate cache with valid data
      await store.write(
        'test',
        Stored(
          value: 'cached',
          meta: Metadata(
            version: 1,
            storedAt: DateTime.now(),
            ttl: Duration(hours: 1),
          ),
        ),
      );

      var fetched = false;
      await cache.prefetchOne(
        key: 'test',
        fetch: (_) async {
          fetched = true;
          return 'new';
        },
        policy: Policy.offlineFirst,
      );

      expect(fetched, isFalse);
    });

    test('applies ttl parameter', () async {
      await cache.prefetchOne(
        key: 'test',
        fetch: (_) async => 'data',
        ttl: Duration(minutes: 15),
      );

      final cached = await store.read('test');
      expect(cached!.meta.ttl, equals(Duration(minutes: 15)));
    });

    test('uses retry config', () async {
      var fetchCount = 0;

      final success = await cache.prefetchOne(
        key: 'test',
        fetch: (_) async {
          fetchCount++;
          if (fetchCount < 2) {
            throw Exception('Error');
          }
          return 'data';
        },
        retry: RetryConfig(
          maxAttempts: 3,
          delay: (_) => Duration.zero,
        ),
      );

      expect(success, isTrue);
      expect(fetchCount, equals(2));
    });
  });

  group('Syncache.prefetch with observers', () {
    late Syncache<String> cache;
    late MemoryStore<String> store;
    late _RecordingObserver observer;

    setUp(() {
      store = MemoryStore<String>();
      observer = _RecordingObserver();
      cache = Syncache<String>(store: store, observers: [observer]);
    });

    test('notifies observers for each prefetch', () async {
      await cache.prefetch([
        PrefetchRequest(key: 'a', fetch: (_) async => 'data-a'),
        PrefetchRequest(key: 'b', fetch: (_) async => 'data-b'),
      ]);

      final fetchStarts =
          observer.events.where((e) => e.startsWith('onFetchStart:')).toList();
      final fetchSuccesses = observer.events
          .where((e) => e.startsWith('onFetchSuccess:'))
          .toList();

      expect(fetchStarts.length, equals(2));
      expect(fetchSuccesses.length, equals(2));
    });

    test('notifies observers for failed prefetch', () async {
      await cache.prefetch([
        PrefetchRequest(
          key: 'test',
          fetch: (_) async => throw Exception('Error'),
        ),
      ]);

      final fetchErrors =
          observer.events.where((e) => e.startsWith('onFetchError:')).toList();

      expect(fetchErrors.length, equals(1));
    });
  });

  group('Syncache.prefetch with deduplication', () {
    late Syncache<String> cache;
    late MemoryStore<String> store;

    setUp(() {
      store = MemoryStore<String>();
      cache = Syncache<String>(store: store);
    });

    test('deduplicates concurrent prefetch for same key', () async {
      var fetchCount = 0;

      // Start prefetch and regular get for same key concurrently
      // ignore: unused_local_variable
      final results = await Future.wait([
        cache.prefetch([
          PrefetchRequest(
            key: 'test',
            fetch: (_) async {
              fetchCount++;
              await Future.delayed(Duration(milliseconds: 50));
              return 'data';
            },
          ),
        ]),
        cache.get(
          key: 'test',
          fetch: (_) async {
            fetchCount++;
            await Future.delayed(Duration(milliseconds: 50));
            return 'data';
          },
          policy: Policy.networkOnly,
        ),
      ]);

      // Should deduplicate to single fetch
      expect(fetchCount, equals(1));
    });
  });
}

/// A recording observer for testing.
class _RecordingObserver extends SyncacheObserver {
  final List<String> events = [];

  @override
  void onFetchStart(String key) {
    events.add('onFetchStart: $key');
  }

  @override
  void onFetchSuccess(String key, Duration duration) {
    events.add('onFetchSuccess: $key');
  }

  @override
  void onFetchError(String key, Object error, StackTrace stackTrace) {
    events.add('onFetchError: $key, error=$error');
  }

  @override
  void onStore(String key) {
    events.add('onStore: $key');
  }
}
