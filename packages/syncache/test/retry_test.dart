import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

void main() {
  group('RetryConfig', () {
    test('defaultDelay uses exponential backoff', () {
      expect(RetryConfig.defaultDelay(0), equals(Duration(milliseconds: 200)));
      expect(RetryConfig.defaultDelay(1), equals(Duration(milliseconds: 400)));
      expect(RetryConfig.defaultDelay(2), equals(Duration(milliseconds: 800)));
      expect(RetryConfig.defaultDelay(3), equals(Duration(milliseconds: 1600)));
    });

    test('none disables retries', () {
      expect(RetryConfig.none.maxAttempts, equals(0));
      expect(RetryConfig.none.enabled, isFalse);
    });

    test('enabled returns true when maxAttempts > 0', () {
      expect(RetryConfig(maxAttempts: 1).enabled, isTrue);
      expect(RetryConfig(maxAttempts: 0).enabled, isFalse);
    });

    test('shouldRetry returns true by default', () {
      final config = RetryConfig();
      expect(config.shouldRetry(Exception('test')), isTrue);
      expect(config.shouldRetry(StateError('test')), isTrue);
    });

    test('shouldRetry respects retryIf predicate', () {
      final config = RetryConfig(
        retryIf: (e) => e is FormatException,
      );

      expect(config.shouldRetry(FormatException('test')), isTrue);
      expect(config.shouldRetry(StateError('test')), isFalse);
    });
  });

  group('Syncache retry', () {
    late Syncache<String> cache;
    late MemoryStore<String> store;

    setUp(() {
      store = MemoryStore<String>();
      cache = Syncache<String>(store: store);
    });

    test('succeeds on first attempt without retry', () async {
      var fetchCount = 0;

      final result = await cache.get(
        key: 'test',
        fetch: (_) async {
          fetchCount++;
          return 'data';
        },
        retry: RetryConfig(maxAttempts: 3),
      );

      expect(result, equals('data'));
      expect(fetchCount, equals(1));
    });

    test('retries on transient failure and succeeds', () async {
      var fetchCount = 0;

      final result = await cache.get(
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
          delay: (_) => Duration.zero, // No delay for tests
        ),
      );

      expect(result, equals('data'));
      expect(fetchCount, equals(3));
    });

    test('throws after exhausting all retries', () async {
      var fetchCount = 0;

      await expectLater(
        cache.get(
          key: 'test',
          fetch: (_) async {
            fetchCount++;
            throw Exception('Persistent error');
          },
          retry: RetryConfig(
            maxAttempts: 2,
            delay: (_) => Duration.zero,
          ),
        ),
        throwsA(isA<Exception>()),
      );

      // 1 initial + 2 retries = 3 total attempts
      expect(fetchCount, equals(3));
    });

    test('respects retryIf predicate', () async {
      var fetchCount = 0;

      await expectLater(
        cache.get(
          key: 'test',
          fetch: (_) async {
            fetchCount++;
            throw StateError('Non-retryable error');
          },
          retry: RetryConfig(
            maxAttempts: 3,
            delay: (_) => Duration.zero,
            retryIf: (e) => e is FormatException, // Only retry FormatException
          ),
        ),
        throwsA(isA<StateError>()),
      );

      // Should not retry because StateError doesn't match retryIf
      expect(fetchCount, equals(1));
    });

    test('retries only matching errors', () async {
      var fetchCount = 0;

      final result = await cache.get(
        key: 'test',
        fetch: (_) async {
          fetchCount++;
          if (fetchCount == 1) {
            throw FormatException('Retryable');
          }
          return 'data';
        },
        retry: RetryConfig(
          maxAttempts: 3,
          delay: (_) => Duration.zero,
          retryIf: (e) => e is FormatException,
        ),
      );

      expect(result, equals('data'));
      expect(fetchCount, equals(2));
    });

    test('uses custom delay function', () async {
      var fetchCount = 0;
      final delays = <int>[];

      final result = await cache.get(
        key: 'test',
        fetch: (_) async {
          fetchCount++;
          if (fetchCount < 3) {
            throw Exception('Error');
          }
          return 'data';
        },
        retry: RetryConfig(
          maxAttempts: 3,
          delay: (attempt) {
            delays.add(attempt);
            return Duration.zero;
          },
        ),
      );

      expect(result, equals('data'));
      expect(delays, equals([0, 1])); // Delays for attempts 0 and 1
    });

    test('uses defaultRetry when retry parameter not provided', () async {
      var fetchCount = 0;

      cache = Syncache<String>(
        store: store,
        defaultRetry: RetryConfig(
          maxAttempts: 2,
          delay: (_) => Duration.zero,
        ),
      );

      final result = await cache.get(
        key: 'test',
        fetch: (_) async {
          fetchCount++;
          if (fetchCount < 2) {
            throw Exception('Error');
          }
          return 'data';
        },
      );

      expect(result, equals('data'));
      expect(fetchCount, equals(2));
    });

    test('override parameter takes precedence over defaultRetry', () async {
      var fetchCount = 0;

      cache = Syncache<String>(
        store: store,
        defaultRetry: RetryConfig(
          maxAttempts: 5,
          delay: (_) => Duration.zero,
        ),
      );

      await expectLater(
        cache.get(
          key: 'test',
          fetch: (_) async {
            fetchCount++;
            throw Exception('Error');
          },
          retry: RetryConfig(
            maxAttempts: 1,
            delay: (_) => Duration.zero,
          ),
        ),
        throwsA(isA<Exception>()),
      );

      // Should use override (1 retry), not defaultRetry (5 retries)
      expect(fetchCount, equals(2)); // 1 initial + 1 retry
    });

    test('RetryConfig.none disables retries', () async {
      var fetchCount = 0;

      await expectLater(
        cache.get(
          key: 'test',
          fetch: (_) async {
            fetchCount++;
            throw Exception('Error');
          },
          retry: RetryConfig.none,
        ),
        throwsA(isA<Exception>()),
      );

      expect(fetchCount, equals(1));
    });

    test('preserves original error type and stack trace', () async {
      final originalError = StateError('Original error');

      try {
        await cache.get(
          key: 'test',
          fetch: (_) async {
            throw originalError;
          },
          retry: RetryConfig(
            maxAttempts: 2,
            delay: (_) => Duration.zero,
          ),
        );
        fail('Should have thrown');
      } catch (e, st) {
        expect(e, isA<StateError>());
        expect((e as StateError).message, equals('Original error'));
        expect(st.toString(), contains('retry_test.dart'));
      }
    });
  });

  group('Syncache retry observer notifications', () {
    late Syncache<String> cache;
    late MemoryStore<String> store;
    late _RecordingObserver observer;

    setUp(() {
      store = MemoryStore<String>();
      observer = _RecordingObserver();
      cache = Syncache<String>(store: store, observers: [observer]);
    });

    test('notifies onRetry for each retry attempt', () async {
      var fetchCount = 0;

      final result = await cache.get(
        key: 'test',
        fetch: (_) async {
          fetchCount++;
          if (fetchCount < 3) {
            throw Exception('Error $fetchCount');
          }
          return 'data';
        },
        retry: RetryConfig(
          maxAttempts: 3,
          delay: (_) => Duration(milliseconds: 100),
        ),
      );

      expect(result, equals('data'));

      final retryEvents =
          observer.events.where((e) => e.startsWith('onRetry:')).toList();
      expect(retryEvents.length, equals(2));
      expect(retryEvents[0], contains('attempt=0'));
      expect(retryEvents[1], contains('attempt=1'));
    });

    test('notifies onRetryExhausted when all retries fail', () async {
      await expectLater(
        cache.get(
          key: 'test',
          fetch: (_) async {
            throw Exception('Persistent error');
          },
          retry: RetryConfig(
            maxAttempts: 2,
            delay: (_) => Duration.zero,
          ),
        ),
        throwsA(isA<Exception>()),
      );

      final exhaustedEvents = observer.events
          .where((e) => e.startsWith('onRetryExhausted:'))
          .toList();
      expect(exhaustedEvents.length, equals(1));
      expect(exhaustedEvents[0], contains('totalAttempts=3'));
    });

    test('does not notify onRetryExhausted when retries succeed', () async {
      var fetchCount = 0;

      await cache.get(
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

      final exhaustedEvents = observer.events
          .where((e) => e.startsWith('onRetryExhausted:'))
          .toList();
      expect(exhaustedEvents, isEmpty);
    });

    test('does not notify onRetryExhausted when retries disabled', () async {
      await expectLater(
        cache.get(
          key: 'test',
          fetch: (_) async {
            throw Exception('Error');
          },
          retry: RetryConfig.none,
        ),
        throwsA(isA<Exception>()),
      );

      final exhaustedEvents = observer.events
          .where((e) => e.startsWith('onRetryExhausted:'))
          .toList();
      expect(exhaustedEvents, isEmpty);
    });

    test('notifies onFetchStart for each attempt', () async {
      var fetchCount = 0;

      await cache.get(
        key: 'test',
        fetch: (_) async {
          fetchCount++;
          if (fetchCount < 3) {
            throw Exception('Error');
          }
          return 'data';
        },
        retry: RetryConfig(
          maxAttempts: 3,
          delay: (_) => Duration.zero,
        ),
      );

      final fetchStartEvents =
          observer.events.where((e) => e.startsWith('onFetchStart:')).toList();
      expect(fetchStartEvents.length, equals(3));
    });

    test('notifies onFetchError for each failed attempt', () async {
      var fetchCount = 0;

      await cache.get(
        key: 'test',
        fetch: (_) async {
          fetchCount++;
          if (fetchCount < 3) {
            throw Exception('Error');
          }
          return 'data';
        },
        retry: RetryConfig(
          maxAttempts: 3,
          delay: (_) => Duration.zero,
        ),
      );

      final fetchErrorEvents =
          observer.events.where((e) => e.startsWith('onFetchError:')).toList();
      expect(fetchErrorEvents.length, equals(2));
    });

    test('notifies onFetchSuccess only once on success', () async {
      var fetchCount = 0;

      await cache.get(
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

      final fetchSuccessEvents = observer.events
          .where((e) => e.startsWith('onFetchSuccess:'))
          .toList();
      expect(fetchSuccessEvents.length, equals(1));
    });
  });

  group('Syncache retry with policies', () {
    late Syncache<String> cache;
    late MemoryStore<String> store;

    setUp(() {
      store = MemoryStore<String>();
      cache = Syncache<String>(store: store);
    });

    test('retry works with networkOnly policy', () async {
      var fetchCount = 0;

      final result = await cache.get(
        key: 'test',
        fetch: (_) async {
          fetchCount++;
          if (fetchCount < 2) {
            throw Exception('Error');
          }
          return 'data';
        },
        policy: Policy.networkOnly,
        retry: RetryConfig(
          maxAttempts: 3,
          delay: (_) => Duration.zero,
        ),
      );

      expect(result, equals('data'));
      expect(fetchCount, equals(2));
    });

    test('retry works with refresh policy', () async {
      var fetchCount = 0;

      final result = await cache.get(
        key: 'test',
        fetch: (_) async {
          fetchCount++;
          if (fetchCount < 2) {
            throw Exception('Error');
          }
          return 'data';
        },
        policy: Policy.refresh,
        retry: RetryConfig(
          maxAttempts: 3,
          delay: (_) => Duration.zero,
        ),
      );

      expect(result, equals('data'));
      expect(fetchCount, equals(2));
    });

    test('offlineFirst falls back to stale cache after retry exhaustion',
        () async {
      // Pre-populate cache with stale data
      await store.write(
        'test',
        Stored(
          value: 'cached',
          meta: Metadata(
            version: 1,
            storedAt: DateTime.now().subtract(Duration(hours: 1)),
            ttl: Duration(minutes: 1), // Expired
          ),
        ),
      );

      final result = await cache.get(
        key: 'test',
        fetch: (_) async {
          throw Exception('Network error');
        },
        policy: Policy.offlineFirst,
        retry: RetryConfig(
          maxAttempts: 2,
          delay: (_) => Duration.zero,
        ),
      );

      // Should fall back to stale cache after retries fail
      expect(result, equals('cached'));
    });
  });
}

/// A recording observer for testing that stores events as strings.
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
  void onRetry(String key, int attempt, Object error, Duration delay) {
    events.add(
        'onRetry: $key, attempt=$attempt, error=$error, delay=${delay.inMilliseconds}ms');
  }

  @override
  void onRetryExhausted(String key, int totalAttempts, Object finalError) {
    events.add(
        'onRetryExhausted: $key, totalAttempts=$totalAttempts, error=$finalError');
  }
}
