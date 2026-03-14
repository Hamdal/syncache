import 'dart:async';

import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

/// A Network implementation that is always offline.
class _OfflineNetwork implements Network {
  @override
  bool get isOnline => false;
}

void main() {
  group('Syncache', () {
    late Syncache<String> cache;
    late MemoryStore<String> store;

    setUp(() {
      store = MemoryStore<String>();
      cache = Syncache<String>(store: store);
    });

    group('get', () {
      test('fetches and caches value on cache miss', () async {
        var fetchCount = 0;

        final result = await cache.get(
          key: 'test-key',
          fetch: (_) async {
            fetchCount++;
            return 'fetched-value';
          },
        );

        expect(result, equals('fetched-value'));
        expect(fetchCount, equals(1));

        // Verify it was cached
        final cached = await store.read('test-key');
        expect(cached, isNotNull);
        expect(cached!.value, equals('fetched-value'));
      });

      test('returns cached value without fetching when not expired', () async {
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

        var fetchCount = 0;
        final result = await cache.get(
          key: 'test-key',
          fetch: (_) async {
            fetchCount++;
            return 'fetched-value';
          },
        );

        expect(result, equals('cached-value'));
        expect(fetchCount, equals(0));
      });

      test('fetches when cached value is expired', () async {
        // Pre-populate cache with expired value
        await store.write(
          'test-key',
          Stored(
            value: 'expired-value',
            meta: Metadata(
              version: 1,
              storedAt: DateTime.now().subtract(const Duration(hours: 2)),
              ttl: const Duration(hours: 1),
            ),
          ),
        );

        var fetchCount = 0;
        final result = await cache.get(
          key: 'test-key',
          fetch: (_) async {
            fetchCount++;
            return 'fresh-value';
          },
        );

        expect(result, equals('fresh-value'));
        expect(fetchCount, equals(1));
      });

      test('throws CacheMissException with cacheOnly policy', () async {
        expect(
          () => cache.get(
            key: 'nonexistent',
            fetch: (_) async => 'value',
            policy: Policy.cacheOnly,
          ),
          throwsA(isA<CacheMissException>()),
        );
      });

      test('always fetches with networkOnly policy', () async {
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

        var fetchCount = 0;
        final result = await cache.get(
          key: 'test-key',
          fetch: (_) async {
            fetchCount++;
            return 'network-value';
          },
          policy: Policy.networkOnly,
        );

        expect(result, equals('network-value'));
        expect(fetchCount, equals(1));
      });
    });

    group('request deduplication', () {
      test('deduplicates concurrent requests for same key', () async {
        var fetchCount = 0;
        final completer = Completer<String>();

        Future<String> fetcher(SyncacheRequest _) async {
          fetchCount++;
          return completer.future;
        }

        // Start 3 concurrent requests
        final futures = [
          cache.get(
              key: 'dedup-key', fetch: fetcher, policy: Policy.networkOnly),
          cache.get(
              key: 'dedup-key', fetch: fetcher, policy: Policy.networkOnly),
          cache.get(
              key: 'dedup-key', fetch: fetcher, policy: Policy.networkOnly),
        ];

        // Complete the fetch
        completer.complete('shared-value');

        final results = await Future.wait(futures);

        // Only one fetch should have occurred
        expect(fetchCount, equals(1));
        // All results should be the same
        expect(
            results, equals(['shared-value', 'shared-value', 'shared-value']));
      });

      test('does not deduplicate requests for different keys', () async {
        var fetchCount = 0;

        final result1 = cache.get(
          key: 'key-1',
          fetch: (_) async {
            fetchCount++;
            await Future.delayed(const Duration(milliseconds: 10));
            return 'value-1';
          },
          policy: Policy.networkOnly,
        );

        final result2 = cache.get(
          key: 'key-2',
          fetch: (_) async {
            fetchCount++;
            await Future.delayed(const Duration(milliseconds: 10));
            return 'value-2';
          },
          policy: Policy.networkOnly,
        );

        final results = await Future.wait([result1, result2]);

        expect(fetchCount, equals(2));
        expect(results, equals(['value-1', 'value-2']));
      });

      test('clears in-flight tracking after request completes', () async {
        var fetchCount = 0;

        // First request
        await cache.get(
          key: 'clear-key',
          fetch: (_) async {
            fetchCount++;
            return 'first-value';
          },
          policy: Policy.networkOnly,
        );

        expect(fetchCount, equals(1));

        // Second request after first completes - should fetch again
        await cache.get(
          key: 'clear-key',
          fetch: (_) async {
            fetchCount++;
            return 'second-value';
          },
          policy: Policy.networkOnly,
        );

        expect(fetchCount, equals(2));
      });

      test('clears in-flight tracking on fetch error', () async {
        var fetchCount = 0;
        var shouldFail = true;

        Future<String> fetcher(SyncacheRequest _) async {
          fetchCount++;
          if (shouldFail) {
            throw Exception('Fetch failed');
          }
          return 'success';
        }

        // First request fails
        expect(
          () => cache.get(
              key: 'error-key', fetch: fetcher, policy: Policy.networkOnly),
          throwsA(isA<Exception>()),
        );

        await Future.delayed(const Duration(milliseconds: 10));
        expect(fetchCount, equals(1));

        // Second request should be able to fetch (not blocked by first failure)
        shouldFail = false;
        final result = await cache.get(
          key: 'error-key',
          fetch: fetcher,
          policy: Policy.networkOnly,
        );

        expect(fetchCount, equals(2));
        expect(result, equals('success'));
      });

      test('propagates error to all waiting callers', () async {
        final completer = Completer<String>();

        Future<String> fetcher(SyncacheRequest _) async {
          return completer.future;
        }

        // Start 3 concurrent requests
        final futures = [
          cache.get(
              key: 'error-prop-key',
              fetch: fetcher,
              policy: Policy.networkOnly),
          cache.get(
              key: 'error-prop-key',
              fetch: fetcher,
              policy: Policy.networkOnly),
          cache.get(
              key: 'error-prop-key',
              fetch: fetcher,
              policy: Policy.networkOnly),
        ];

        // Complete with error
        completer.completeError(Exception('Shared error'));

        // All futures should fail with the same error
        for (final future in futures) {
          expect(future, throwsA(isA<Exception>()));
        }
      });

      test('deduplicates with staleWhileRefresh policy', () async {
        // Pre-populate cache with expired value
        await store.write(
          'swr-key',
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

        Future<String> fetcher(SyncacheRequest _) async {
          fetchCount++;
          return completer.future;
        }

        // Start concurrent requests - they should return stale value immediately
        final result1 = await cache.get(
          key: 'swr-key',
          fetch: fetcher,
          policy: Policy.staleWhileRefresh,
        );
        final result2 = await cache.get(
          key: 'swr-key',
          fetch: fetcher,
          policy: Policy.staleWhileRefresh,
        );

        // Both should get stale value immediately
        expect(result1, equals('stale-value'));
        expect(result2, equals('stale-value'));

        // Complete background refresh
        completer.complete('fresh-value');
        await Future.delayed(const Duration(milliseconds: 50));

        // Should have only triggered one background fetch
        expect(fetchCount, equals(1));

        // Cache should now have fresh value
        final cached = await store.read('swr-key');
        expect(cached!.value, equals('fresh-value'));
      });
    });

    group('watch', () {
      test('emits initial value', () async {
        final stream = cache.watch(
          key: 'watch-key',
          fetch: (_) async => 'watched-value',
        );

        expect(stream, emits('watched-value'));
      });

      test('emits updates when cache changes', () async {
        final stream = cache.watch(
          key: 'watch-update-key',
          fetch: (_) async => 'initial',
        );

        // Collect emitted values
        final values = <String>[];
        final subscription = stream.listen(values.add);

        // Wait for initial emission
        await Future.delayed(const Duration(milliseconds: 50));

        // Update cache directly via another get with networkOnly
        await cache.get(
          key: 'watch-update-key',
          fetch: (_) async => 'updated',
          policy: Policy.networkOnly,
        );

        await Future.delayed(const Duration(milliseconds: 50));
        await subscription.cancel();

        expect(values, contains('initial'));
        expect(values, contains('updated'));
      });
    });

    group('invalidate', () {
      test('removes cached value', () async {
        await store.write(
          'invalidate-key',
          Stored(
            value: 'to-remove',
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        await cache.invalidate('invalidate-key');

        final cached = await store.read('invalidate-key');
        expect(cached, isNull);
      });
    });

    group('clear', () {
      test('removes all cached values', () async {
        await store.write(
          'key-1',
          Stored(
              value: 'value-1',
              meta: Metadata(version: 1, storedAt: DateTime.now())),
        );
        await store.write(
          'key-2',
          Stored(
              value: 'value-2',
              meta: Metadata(version: 1, storedAt: DateTime.now())),
        );

        await cache.clear();

        expect(await store.read('key-1'), isNull);
        expect(await store.read('key-2'), isNull);
      });
    });

    group('mutate', () {
      test('applies optimistic update immediately', () async {
        await store.write(
          'mutate-key',
          Stored(
            value: 'original',
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        final sendCompleter = Completer<String>();

        // Start mutation but don't complete send yet
        unawaited(cache.mutate(
          key: 'mutate-key',
          mutation: Mutation<String>(
            apply: (value) => 'optimistic-$value',
            send: (value) => sendCompleter.future,
          ),
        ));

        // Allow the mutation to apply optimistically
        await Future.delayed(const Duration(milliseconds: 10));

        // Value should be optimistically updated
        final cached = await store.read('mutate-key');
        expect(cached!.value, equals('optimistic-original'));

        // Complete the mutation
        sendCompleter.complete('server-value');
      });

      test('throws CacheMissException if key not cached', () async {
        expect(
          () => cache.mutate(
            key: 'nonexistent',
            mutation: Mutation<String>(
              apply: (v) => v,
              send: (v) async => v,
            ),
          ),
          throwsA(isA<CacheMissException>()),
        );
      });
    });

    group('concurrent mutations', () {
      test('preserves later optimistic updates when earlier send completes',
          () async {
        // Setup: initial value is "A"
        await store.write(
          'concurrent-key',
          Stored(
            value: 'A',
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        final sendCompleter1 = Completer<String>();
        final sendCompleter2 = Completer<String>();

        // Mutation 1: A -> B (will complete second)
        unawaited(cache.mutate(
          key: 'concurrent-key',
          mutation: Mutation<String>(
            apply: (value) => 'B', // optimistic: A -> B
            send: (value) => sendCompleter1.future,
          ),
        ));

        await Future.delayed(const Duration(milliseconds: 10));

        // Cache should now be "B"
        var cached = await store.read('concurrent-key');
        expect(cached!.value, equals('B'));

        // Mutation 2: B -> C (applied on top of B)
        unawaited(cache.mutate(
          key: 'concurrent-key',
          mutation: Mutation<String>(
            apply: (value) => '${value}C', // optimistic: B -> BC
            send: (value) => sendCompleter2.future,
          ),
        ));

        await Future.delayed(const Duration(milliseconds: 10));

        // Cache should now be "BC"
        cached = await store.read('concurrent-key');
        expect(cached!.value, equals('BC'));

        // Mutation 1 completes with server value "B_server"
        // The fix should re-apply Mutation 2's apply on top of this
        sendCompleter1.complete('B_server');

        await Future.delayed(const Duration(milliseconds: 50));

        // Cache should be "B_serverC" (server value + mutation 2 re-applied)
        cached = await store.read('concurrent-key');
        expect(cached!.value, equals('B_serverC'));

        // Mutation 2 completes
        sendCompleter2.complete('final_server');

        await Future.delayed(const Duration(milliseconds: 50));

        // Cache should be the final server value
        cached = await store.read('concurrent-key');
        expect(cached!.value, equals('final_server'));
      });

      test('rapid toggle preserves final state', () async {
        // Setup: initial value is "OFF"
        await store.write(
          'toggle-key',
          Stored(
            value: 'OFF',
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        final completers = <Completer<String>>[];

        // Rapid toggles: OFF -> ON -> OFF -> ON
        for (var i = 0; i < 3; i++) {
          final completer = Completer<String>();
          completers.add(completer);

          unawaited(cache.mutate(
            key: 'toggle-key',
            mutation: Mutation<String>(
              apply: (value) => value == 'ON' ? 'OFF' : 'ON',
              send: (value) => completer.future,
            ),
          ));

          await Future.delayed(const Duration(milliseconds: 5));
        }

        // After 3 toggles from OFF: ON -> OFF -> ON
        // Final optimistic state should be ON
        var cached = await store.read('toggle-key');
        expect(cached!.value, equals('ON'));

        // Complete first toggle (OFF -> ON) with server value "ON"
        completers[0].complete('ON');
        await Future.delayed(const Duration(milliseconds: 50));

        // After first send completes, re-apply remaining toggles:
        // ON (server) -> OFF (toggle 2) -> ON (toggle 3) = ON
        cached = await store.read('toggle-key');
        expect(cached!.value, equals('ON'));

        // Complete second toggle
        completers[1].complete('OFF');
        await Future.delayed(const Duration(milliseconds: 50));

        // After second send completes, re-apply remaining toggle:
        // OFF (server) -> ON (toggle 3) = ON
        cached = await store.read('toggle-key');
        expect(cached!.value, equals('ON'));

        // Complete third toggle
        completers[2].complete('ON');
        await Future.delayed(const Duration(milliseconds: 50));

        // Final state should be ON
        cached = await store.read('toggle-key');
        expect(cached!.value, equals('ON'));
      });

      test('multiple keys do not interfere with each other', () async {
        // Setup: two keys with different values
        await store.write(
          'key-1',
          Stored(
            value: 'A1',
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );
        await store.write(
          'key-2',
          Stored(
            value: 'A2',
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        final completer1 = Completer<String>();
        final completer2 = Completer<String>();

        // Mutate key-1
        unawaited(cache.mutate(
          key: 'key-1',
          mutation: Mutation<String>(
            apply: (value) => 'B1',
            send: (value) => completer1.future,
          ),
        ));

        await Future.delayed(const Duration(milliseconds: 10));

        // Mutate key-2
        unawaited(cache.mutate(
          key: 'key-2',
          mutation: Mutation<String>(
            apply: (value) => 'B2',
            send: (value) => completer2.future,
          ),
        ));

        await Future.delayed(const Duration(milliseconds: 10));

        // Both should have optimistic values
        expect((await store.read('key-1'))!.value, equals('B1'));
        expect((await store.read('key-2'))!.value, equals('B2'));

        // Complete key-1 mutation
        completer1.complete('C1');
        await Future.delayed(const Duration(milliseconds: 50));

        // key-1 should have server value, key-2 should be unchanged
        expect((await store.read('key-1'))!.value, equals('C1'));
        expect((await store.read('key-2'))!.value, equals('B2'));

        // Complete key-2 mutation
        completer2.complete('C2');
        await Future.delayed(const Duration(milliseconds: 50));

        // Both should have final server values
        expect((await store.read('key-1'))!.value, equals('C1'));
        expect((await store.read('key-2'))!.value, equals('C2'));
      });

      test('failed mutation does not block remaining mutations', () async {
        // Setup
        await store.write(
          'fail-key',
          Stored(
            value: 'A',
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        // Use cache with no retries for predictable behavior
        final noRetryCache = Syncache<String>(
          store: store,
          mutationRetry: const MutationRetryConfig(maxAttempts: 0),
        );

        final failCompleter = Completer<String>();
        final successCompleter = Completer<String>();

        // Mutation 1: will fail
        unawaited(noRetryCache.mutate(
          key: 'fail-key',
          mutation: Mutation<String>(
            apply: (value) => 'B',
            send: (value) => failCompleter.future,
          ),
        ));

        await Future.delayed(const Duration(milliseconds: 10));

        // Mutation 2: will succeed
        unawaited(noRetryCache.mutate(
          key: 'fail-key',
          mutation: Mutation<String>(
            apply: (value) => '${value}C',
            send: (value) => successCompleter.future,
          ),
        ));

        await Future.delayed(const Duration(milliseconds: 10));

        // Optimistic state should be "BC"
        var cached = await store.read('fail-key');
        expect(cached!.value, equals('BC'));

        // Fail mutation 1 - it gets removed but cache keeps optimistic value
        failCompleter.completeError(Exception('Network error'));
        await Future.delayed(const Duration(milliseconds: 50));

        // Cache still has "BC" (optimistic values are not rolled back on failure)
        // Mutation 2 will still try to send its optimistic value
        cached = await store.read('fail-key');
        expect(cached!.value, equals('BC'));

        // Mutation 2 completes - this is the first successful sync
        // After mutation 1's send completes (even with failure), mutation 2's
        // optimisticValue was rebased on top of the server state. But since
        // mutation 1 failed, there's no server state update. Mutation 2
        // sends its current optimisticValue and the server returns 'final'.
        successCompleter.complete('final');
        await Future.delayed(const Duration(milliseconds: 50));

        // Final state from server
        cached = await store.read('fail-key');
        expect(cached!.value, equals('final'));
      });

      test('watch stream receives all intermediate states', () async {
        await store.write(
          'watch-concurrent-key',
          Stored(
            value: 'initial',
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        final values = <String>[];
        final subscription = cache
            .watch(
              key: 'watch-concurrent-key',
              fetch: (_) async => 'initial',
            )
            .listen(values.add);

        await Future.delayed(const Duration(milliseconds: 50));

        final completer1 = Completer<String>();
        final completer2 = Completer<String>();

        // Mutation 1
        unawaited(cache.mutate(
          key: 'watch-concurrent-key',
          mutation: Mutation<String>(
            apply: (value) => 'optimistic1',
            send: (value) => completer1.future,
          ),
        ));

        await Future.delayed(const Duration(milliseconds: 20));

        // Mutation 2
        unawaited(cache.mutate(
          key: 'watch-concurrent-key',
          mutation: Mutation<String>(
            apply: (value) => 'optimistic2',
            send: (value) => completer2.future,
          ),
        ));

        await Future.delayed(const Duration(milliseconds: 20));

        // Complete both mutations
        completer1.complete('server1');
        await Future.delayed(const Duration(milliseconds: 50));

        completer2.complete('server2');
        await Future.delayed(const Duration(milliseconds: 50));

        await subscription.cancel();

        // Stream should have received initial, optimistic1, optimistic2,
        // and server updates
        expect(values, contains('initial'));
        expect(values, contains('optimistic1'));
        expect(values, contains('optimistic2'));
        expect(values, contains('server2'));
      });

      test('mutations added during send are rebased correctly', () async {
        // Setup
        await store.write(
          'rebase-key',
          Stored(
            value: 'A',
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        final sendCompleter = Completer<String>();
        var mutationAddedDuringSend = false;

        // Mutation 1: will add mutation 2 during its send
        unawaited(cache.mutate(
          key: 'rebase-key',
          mutation: Mutation<String>(
            apply: (value) => 'B',
            send: (value) async {
              // During send, add another mutation
              if (!mutationAddedDuringSend) {
                mutationAddedDuringSend = true;
                unawaited(cache.mutate(
                  key: 'rebase-key',
                  mutation: Mutation<String>(
                    apply: (v) => '${v}C',
                    send: (v) async => v, // Just echo the value
                  ),
                ));
              }
              return sendCompleter.future;
            },
          ),
        ));

        // Wait for mutation 1's send to start (which adds mutation 2)
        await Future.delayed(const Duration(milliseconds: 50));

        // At this point:
        // - Mutation 1's send is awaiting sendCompleter
        // - Mutation 2 was added and applied: B -> BC
        var cached = await store.read('rebase-key');
        expect(cached!.value, equals('BC'));

        // Complete mutation 1
        sendCompleter.complete('B_server');
        await Future.delayed(const Duration(milliseconds: 100));

        // After mutation 1 completes:
        // - Server value is B_server
        // - Mutation 2 should be rebased: B_server -> B_serverC
        cached = await store.read('rebase-key');
        expect(cached!.value, equals('B_serverC'));
      });
    });

    group('dispose', () {
      test('throws StateError when calling get after dispose', () async {
        cache.dispose();

        expect(
          () => cache.get(
            key: 'test',
            fetch: (_) async => 'value',
          ),
          throwsA(isA<StateError>()),
        );
      });

      test('throws StateError when calling watch after dispose', () {
        cache.dispose();

        expect(
          () => cache.watch(
            key: 'test',
            fetch: (_) async => 'value',
          ),
          throwsA(isA<StateError>()),
        );
      });

      test('throws StateError when calling mutate after dispose', () async {
        await store.write(
          'test',
          Stored(
            value: 'value',
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        cache.dispose();

        expect(
          () => cache.mutate(
            key: 'test',
            mutation: Mutation<String>(
              apply: (v) => v,
              send: (v) async => v,
            ),
          ),
          throwsA(isA<StateError>()),
        );
      });

      test('throws StateError when calling invalidate after dispose', () {
        cache.dispose();

        expect(
          () => cache.invalidate('test'),
          throwsA(isA<StateError>()),
        );
      });

      test('throws StateError when calling clear after dispose', () {
        cache.dispose();

        expect(
          () => cache.clear(),
          throwsA(isA<StateError>()),
        );
      });

      test('throws StateError when calling pendingMutationCount after dispose',
          () {
        cache.dispose();

        expect(
          () => cache.pendingMutationCount,
          throwsA(isA<StateError>()),
        );
      });

      test('calling dispose twice is safe', () {
        cache.dispose();
        cache.dispose(); // Should not throw
      });
    });

    group('clearPendingMutations', () {
      test('clears all mutations when queue is not processing', () async {
        await store.write(
          'clear-test',
          Stored(
            value: 'value',
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        // Use offline network to prevent processing
        final offlineCache = Syncache<String>(
          store: store,
          network: _OfflineNetwork(),
        );

        // Add mutations (they won't process because offline)
        unawaited(offlineCache.mutate(
          key: 'clear-test',
          mutation: Mutation<String>(
            apply: (v) => 'A',
            send: (v) async => v,
          ),
        ));
        unawaited(offlineCache.mutate(
          key: 'clear-test',
          mutation: Mutation<String>(
            apply: (v) => 'B',
            send: (v) async => v,
          ),
        ));

        await Future.delayed(const Duration(milliseconds: 20));
        expect(offlineCache.pendingMutationCount, equals(2));

        offlineCache.clearPendingMutations();
        expect(offlineCache.pendingMutationCount, equals(0));
      });
    });
  });
}
