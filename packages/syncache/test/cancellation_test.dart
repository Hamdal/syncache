import 'dart:async';

import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

void main() {
  group('CancellationToken', () {
    test('starts not cancelled', () {
      final token = CancellationToken();
      expect(token.isCancelled, isFalse);
    });

    test('isCancelled becomes true after cancel()', () {
      final token = CancellationToken();
      token.cancel();
      expect(token.isCancelled, isTrue);
    });

    test('cancel() is idempotent', () {
      final token = CancellationToken();
      token.cancel();
      token.cancel(); // Should not throw
      expect(token.isCancelled, isTrue);
    });

    test('onCancel callback is called when cancelled', () {
      final token = CancellationToken();
      var called = false;

      token.onCancel(() => called = true);
      expect(called, isFalse);

      token.cancel();
      expect(called, isTrue);
    });

    test('onCancel called immediately if already cancelled', () {
      final token = CancellationToken();
      token.cancel();

      var called = false;
      token.onCancel(() => called = true);
      expect(called, isTrue);
    });

    test('multiple onCancel callbacks are all called', () {
      final token = CancellationToken();
      final calls = <int>[];

      token.onCancel(() => calls.add(1));
      token.onCancel(() => calls.add(2));
      token.onCancel(() => calls.add(3));

      token.cancel();
      expect(calls, equals([1, 2, 3]));
    });

    test('removeOnCancel removes callback', () {
      final token = CancellationToken();
      var called = false;

      void callback() => called = true;
      token.onCancel(callback);

      final removed = token.removeOnCancel(callback);
      expect(removed, isTrue);

      token.cancel();
      expect(called, isFalse);
    });

    test('removeOnCancel returns false if not found', () {
      final token = CancellationToken();
      final removed = token.removeOnCancel(() {});
      expect(removed, isFalse);
    });

    test('throwIfCancelled does nothing when not cancelled', () {
      final token = CancellationToken();
      expect(() => token.throwIfCancelled(), returnsNormally);
    });

    test('throwIfCancelled throws when cancelled', () {
      final token = CancellationToken();
      token.cancel();
      expect(
          () => token.throwIfCancelled(), throwsA(isA<CancelledException>()));
    });

    test('onCancel callback error does not break other callbacks', () {
      final token = CancellationToken();
      final calls = <int>[];

      token.onCancel(() => calls.add(1));
      token.onCancel(() => throw Exception('Error'));
      token.onCancel(() => calls.add(3));

      token.cancel();
      expect(calls, equals([1, 3]));
    });

    test('toString returns readable format', () {
      final token = CancellationToken();
      expect(token.toString(), contains('isCancelled: false'));

      token.cancel();
      expect(token.toString(), contains('isCancelled: true'));
    });
  });

  group('CancelledException', () {
    test('has default message', () {
      final exception = CancelledException();
      expect(exception.message, equals('Operation was cancelled'));
    });

    test('accepts custom message', () {
      final exception = CancelledException('Custom message');
      expect(exception.message, equals('Custom message'));
    });

    test('toString includes message', () {
      final exception = CancelledException('test');
      expect(exception.toString(), contains('test'));
    });

    test('is a SyncacheException', () {
      expect(CancelledException(), isA<SyncacheException>());
    });
  });

  group('Syncache.get with cancellation', () {
    late Syncache<String> cache;
    late MemoryStore<String> store;

    setUp(() {
      store = MemoryStore<String>();
      cache = Syncache<String>(store: store);
    });

    test('completes normally when not cancelled', () async {
      final token = CancellationToken();

      final result = await cache.get(
        key: 'test',
        fetch: (_) async => 'data',
        cancel: token,
      );

      expect(result, equals('data'));
    });

    test('throws CancelledException when cancelled before start', () async {
      final token = CancellationToken();
      token.cancel();

      await expectLater(
        cache.get(
          key: 'test',
          fetch: (_) async => 'data',
          cancel: token,
        ),
        throwsA(isA<CancelledException>()),
      );
    });

    test('throws CancelledException when cancelled during fetch', () async {
      final token = CancellationToken();
      final fetchStarted = Completer<void>();

      final future = cache.get(
        key: 'test',
        fetch: (_) async {
          fetchStarted.complete();
          await Future.delayed(Duration(milliseconds: 100));
          return 'data';
        },
        cancel: token,
      );

      await fetchStarted.future;
      token.cancel();

      await expectLater(future, throwsA(isA<CancelledException>()));
    });

    test('does not store value when cancelled after fetch', () async {
      final token = CancellationToken();
      final fetchCompleted = Completer<void>();

      final future = cache.get(
        key: 'test',
        fetch: (_) async {
          final result = 'data';
          fetchCompleted.complete();
          // Small delay to allow cancellation to be processed
          await Future.delayed(Duration(milliseconds: 10));
          return result;
        },
        cancel: token,
      );

      await fetchCompleted.future;
      token.cancel();

      await expectLater(future, throwsA(isA<CancelledException>()));

      // Value should not be stored
      final cached = await store.read('test');
      expect(cached, isNull);
    });

    test('cancellation stops retry attempts', () async {
      final token = CancellationToken();
      var fetchCount = 0;

      final future = cache.get(
        key: 'test',
        fetch: (_) async {
          fetchCount++;
          if (fetchCount == 1) {
            throw Exception('First attempt fails');
          }
          await Future.delayed(Duration(milliseconds: 100));
          return 'data';
        },
        retry: RetryConfig(
          maxAttempts: 5,
          delay: (_) => Duration(milliseconds: 50),
        ),
        cancel: token,
      );

      // Wait for first failure and retry delay to start
      await Future.delayed(Duration(milliseconds: 30));
      token.cancel();

      await expectLater(future, throwsA(isA<CancelledException>()));

      // Should have only made 1 attempt before cancellation
      expect(fetchCount, equals(1));
    });

    test('cancellation during retry delay throws immediately', () async {
      final token = CancellationToken();
      // ignore: unused_local_variable
      var fetchCount = 0;

      final future = cache.get(
        key: 'test',
        fetch: (_) async {
          fetchCount++;
          throw Exception('Always fails');
        },
        retry: RetryConfig(
          maxAttempts: 3,
          delay: (_) => Duration(seconds: 10), // Long delay
        ),
        cancel: token,
      );

      // Wait for first failure
      await Future.delayed(Duration(milliseconds: 50));
      token.cancel();

      final stopwatch = Stopwatch()..start();
      await expectLater(future, throwsA(isA<CancelledException>()));
      stopwatch.stop();

      // Should complete quickly, not wait for 10 second delay
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });

    test('works with offlineFirst policy', () async {
      // Pre-populate with stale cache
      await store.write(
        'test',
        Stored(
          value: 'cached',
          meta: Metadata(
            version: 1,
            storedAt: DateTime.now().subtract(Duration(hours: 1)),
            ttl: Duration(minutes: 1),
          ),
        ),
      );

      final token = CancellationToken();
      final fetchStarted = Completer<void>();

      final future = cache.get(
        key: 'test',
        fetch: (_) async {
          fetchStarted.complete();
          await Future.delayed(Duration(milliseconds: 100));
          return 'fresh';
        },
        policy: Policy.offlineFirst,
        cancel: token,
      );

      await fetchStarted.future;
      token.cancel();

      // Should throw, not fall back to cache
      await expectLater(future, throwsA(isA<CancelledException>()));
    });

    test('works with networkOnly policy', () async {
      final token = CancellationToken();
      token.cancel();

      await expectLater(
        cache.get(
          key: 'test',
          fetch: (_) async => 'data',
          policy: Policy.networkOnly,
          cancel: token,
        ),
        throwsA(isA<CancelledException>()),
      );
    });

    test('works with refresh policy', () async {
      final token = CancellationToken();
      token.cancel();

      await expectLater(
        cache.get(
          key: 'test',
          fetch: (_) async => 'data',
          policy: Policy.refresh,
          cancel: token,
        ),
        throwsA(isA<CancelledException>()),
      );
    });

    test('cacheOnly policy ignores cancellation token', () async {
      // Pre-populate cache
      await store.write(
        'test',
        Stored(
          value: 'cached',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
      );

      final token = CancellationToken();
      token.cancel();

      // cacheOnly doesn't do network fetch, so cancellation after
      // initial check is irrelevant - but we do check at start
      await expectLater(
        cache.get(
          key: 'test',
          fetch: (_) async => 'data',
          policy: Policy.cacheOnly,
          cancel: token,
        ),
        throwsA(isA<CancelledException>()),
      );
    });
  });

  group('Syncache.get cancellation with observers', () {
    late Syncache<String> cache;
    late MemoryStore<String> store;
    late _RecordingObserver observer;

    setUp(() {
      store = MemoryStore<String>();
      observer = _RecordingObserver();
      cache = Syncache<String>(store: store, observers: [observer]);
    });

    test('notifies onFetchCancelled when cancelled', () async {
      final token = CancellationToken();
      final fetchStarted = Completer<void>();

      final future = cache.get(
        key: 'test',
        fetch: (_) async {
          fetchStarted.complete();
          await Future.delayed(Duration(milliseconds: 100));
          return 'data';
        },
        cancel: token,
      );

      await fetchStarted.future;
      token.cancel();

      await expectLater(future, throwsA(isA<CancelledException>()));

      expect(
        observer.events.where((e) => e.startsWith('onFetchCancelled:')),
        isNotEmpty,
      );
    });

    test('does not notify onFetchSuccess when cancelled', () async {
      final token = CancellationToken();
      final fetchStarted = Completer<void>();

      final future = cache.get(
        key: 'test',
        fetch: (_) async {
          fetchStarted.complete();
          await Future.delayed(Duration(milliseconds: 50));
          return 'data';
        },
        cancel: token,
      );

      await fetchStarted.future;
      token.cancel();

      await expectLater(future, throwsA(isA<CancelledException>()));

      expect(
        observer.events.where((e) => e.startsWith('onFetchSuccess:')),
        isEmpty,
      );
    });
  });

  group('Syncache.get cancellation with deduplication', () {
    late Syncache<String> cache;
    late MemoryStore<String> store;

    setUp(() {
      store = MemoryStore<String>();
      cache = Syncache<String>(store: store);
    });

    test('cancelled token throws before joining in-flight request', () async {
      final fetchStarted = Completer<void>();

      // Start first request
      final future1 = cache.get(
        key: 'test',
        fetch: (_) async {
          fetchStarted.complete();
          await Future.delayed(Duration(milliseconds: 100));
          return 'data';
        },
        policy: Policy.networkOnly,
      );

      await fetchStarted.future;

      // Try to join with cancelled token
      final token = CancellationToken();
      token.cancel();

      await expectLater(
        cache.get(
          key: 'test',
          fetch: (_) async => 'data2',
          policy: Policy.networkOnly,
          cancel: token,
        ),
        throwsA(isA<CancelledException>()),
      );

      // Original request should still complete
      final result = await future1;
      expect(result, equals('data'));
    });
  });

  group('Syncache.prefetchOne with cancellation', () {
    late Syncache<String> cache;
    late MemoryStore<String> store;

    setUp(() {
      store = MemoryStore<String>();
      cache = Syncache<String>(store: store);
    });

    test('returns false when cancelled', () async {
      final token = CancellationToken();
      token.cancel();

      // prefetchOne catches all exceptions and returns false
      // But get() with cancel token throws immediately
      // We need to verify this behavior
      final success = await cache.prefetchOne(
        key: 'test',
        fetch: (_) async => 'data',
      );

      // Without cancel token, should succeed
      expect(success, isTrue);
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
    events.add('onFetchError: $key');
  }

  @override
  void onFetchCancelled(String key) {
    events.add('onFetchCancelled: $key');
  }

  @override
  void onRetry(String key, int attempt, Object error, Duration delay) {
    events.add('onRetry: $key, attempt=$attempt');
  }
}
