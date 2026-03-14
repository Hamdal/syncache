import 'dart:async';

import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

void main() {
  group('Reactive Refetch', () {
    late Syncache<String> cache;
    late MemoryStore<String> store;

    setUp(() {
      store = MemoryStore<String>();
      cache = Syncache<String>(store: store);
    });

    tearDown(() {
      cache.dispose();
    });

    group('set()', () {
      test('stores value in cache', () async {
        await cache.set(key: 'test-key', value: 'test-value');

        final stored = await store.read('test-key');
        expect(stored, isNotNull);
        expect(stored!.value, equals('test-value'));
      });

      test('stores value with TTL', () async {
        await cache.set(
          key: 'test-key',
          value: 'test-value',
          ttl: Duration(hours: 1),
        );

        final stored = await store.read('test-key');
        expect(stored, isNotNull);
        expect(stored!.meta.ttl, equals(Duration(hours: 1)));
      });

      test('increments version on update', () async {
        await cache.set(key: 'test-key', value: 'value-1');
        final first = await store.read('test-key');
        expect(first!.meta.version, equals(1));

        await cache.set(key: 'test-key', value: 'value-2');
        final second = await store.read('test-key');
        expect(second!.meta.version, equals(2));
      });

      test('preserves TTL when updating existing entry', () async {
        await cache.set(
          key: 'test-key',
          value: 'value-1',
          ttl: Duration(hours: 2),
        );

        await cache.set(key: 'test-key', value: 'value-2');

        final stored = await store.read('test-key');
        expect(stored!.meta.ttl, equals(Duration(hours: 2)));
      });

      test('notifies watchers when value changes', () async {
        // Set initial value
        await cache.set(key: 'test-key', value: 'initial');

        final values = <String>[];
        final subscription = cache
            .watch(
              key: 'test-key',
              fetch: (_) async => 'fetched',
              policy: Policy.cacheOnly,
            )
            .listen(values.add);

        // Wait for initial emit
        await Future.delayed(Duration(milliseconds: 50));
        expect(values, equals(['initial']));

        // Update the value
        await cache.set(key: 'test-key', value: 'updated');
        await Future.delayed(Duration(milliseconds: 50));

        expect(values, equals(['initial', 'updated']));

        await subscription.cancel();
      });
    });

    group('watchWithDependencies()', () {
      test('emits exactly one initial value from fetch', () async {
        int fetchCount = 0;

        final stream = cache.watchWithDependencies(
          key: 'events',
          fetch: (_) async {
            fetchCount++;
            return 'events-$fetchCount';
          },
          refetchWhen: ['workspace'],
        );

        final values = <String>[];
        final subscription = stream.listen(values.add);

        await Future.delayed(Duration(milliseconds: 100));

        // Should emit exactly once
        expect(values, equals(['events-1']));
        expect(fetchCount, equals(1));

        await subscription.cancel();
      });

      test('refetches when dependency changes via set()', () async {
        int fetchCount = 0;

        final stream = cache.watchWithDependencies(
          key: 'events',
          fetch: (_) async {
            fetchCount++;
            return 'events-$fetchCount';
          },
          refetchWhen: ['workspace'],
        );

        final values = <String>[];
        final subscription = stream.listen(values.add);

        // Wait for initial fetch
        await Future.delayed(Duration(milliseconds: 100));
        expect(values, equals(['events-1']));

        // Change the dependency
        await cache.set(key: 'workspace', value: 'new-workspace');
        await Future.delayed(Duration(milliseconds: 100));

        // Should have refetched exactly once more
        expect(values, equals(['events-1', 'events-2']));
        expect(fetchCount, equals(2));

        await subscription.cancel();
      });

      test('refetches when dependency changes via mutate()', () async {
        // First set initial value for mutate to work
        await cache.set(key: 'workspace', value: 'initial');

        int fetchCount = 0;

        final stream = cache.watchWithDependencies(
          key: 'events',
          fetch: (_) async {
            fetchCount++;
            return 'events-$fetchCount';
          },
          refetchWhen: ['workspace'],
        );

        final values = <String>[];
        final subscription = stream.listen(values.add);

        // Wait for initial fetch
        await Future.delayed(Duration(milliseconds: 100));
        expect(values, equals(['events-1']));

        // Mutate the dependency
        await cache.mutate(
          key: 'workspace',
          mutation: Mutation(
            apply: (v) => 'mutated-workspace',
            send: (v) async => 'mutated-workspace',
          ),
        );
        await Future.delayed(Duration(milliseconds: 100));

        // Should have refetched exactly once more
        expect(values, equals(['events-1', 'events-2']));
        expect(fetchCount, equals(2));

        await subscription.cancel();
      });

      test('supports multiple dependencies', () async {
        int fetchCount = 0;

        final stream = cache.watchWithDependencies(
          key: 'dashboard',
          fetch: (_) async {
            fetchCount++;
            return 'dashboard-$fetchCount';
          },
          refetchWhen: ['user', 'workspace', 'settings'],
        );

        final values = <String>[];
        final subscription = stream.listen(values.add);

        // Wait for initial fetch
        await Future.delayed(Duration(milliseconds: 100));
        expect(values, equals(['dashboard-1']));

        // Change first dependency
        await cache.set(key: 'user', value: 'new-user');
        await Future.delayed(Duration(milliseconds: 100));
        expect(values.last, equals('dashboard-2'));

        // Change second dependency
        await cache.set(key: 'workspace', value: 'new-workspace');
        await Future.delayed(Duration(milliseconds: 100));
        expect(values.last, equals('dashboard-3'));

        // Change third dependency
        await cache.set(key: 'settings', value: 'new-settings');
        await Future.delayed(Duration(milliseconds: 100));
        expect(values.last, equals('dashboard-4'));

        expect(fetchCount, equals(4));

        await subscription.cancel();
      });

      test('multiple watchers can depend on same key', () async {
        int eventsFetchCount = 0;
        int tasksFetchCount = 0;

        final eventsStream = cache.watchWithDependencies(
          key: 'events',
          fetch: (_) async {
            eventsFetchCount++;
            return 'events-$eventsFetchCount';
          },
          refetchWhen: ['workspace'],
        );

        final tasksStream = cache.watchWithDependencies(
          key: 'tasks',
          fetch: (_) async {
            tasksFetchCount++;
            return 'tasks-$tasksFetchCount';
          },
          refetchWhen: ['workspace'],
        );

        final eventsValues = <String>[];
        final tasksValues = <String>[];

        final sub1 = eventsStream.listen(eventsValues.add);
        final sub2 = tasksStream.listen(tasksValues.add);

        // Wait for initial fetches
        await Future.delayed(Duration(milliseconds: 100));
        expect(eventsValues, equals(['events-1']));
        expect(tasksValues, equals(['tasks-1']));

        // Change the shared dependency
        await cache.set(key: 'workspace', value: 'new-workspace');
        await Future.delayed(Duration(milliseconds: 100));

        // Both should have refetched
        expect(eventsValues, equals(['events-1', 'events-2']));
        expect(tasksValues, equals(['tasks-1', 'tasks-2']));

        await sub1.cancel();
        await sub2.cancel();
      });

      test('cleans up dependency tracking on cancel', () async {
        int fetchCount = 0;

        final stream = cache.watchWithDependencies(
          key: 'events',
          fetch: (_) async {
            fetchCount++;
            return 'events-$fetchCount';
          },
          refetchWhen: ['workspace'],
        );

        final subscription = stream.listen((_) {});
        await Future.delayed(Duration(milliseconds: 100));
        final countAfterInit = fetchCount;

        // Cancel the subscription
        await subscription.cancel();
        await Future.delayed(Duration(milliseconds: 50));

        // Change the dependency after cancel
        await cache.set(key: 'workspace', value: 'changed');
        await Future.delayed(Duration(milliseconds: 100));

        // Should NOT have refetched (watcher was cancelled)
        expect(fetchCount, equals(countAfterInit));
      });

      test('falls back to regular watch when refetchWhen is empty', () async {
        int fetchCount = 0;

        final stream = cache.watchWithDependencies(
          key: 'events',
          fetch: (_) async {
            fetchCount++;
            return 'events-$fetchCount';
          },
          refetchWhen: [], // Empty list
        );

        final values = <String>[];
        final subscription = stream.listen(values.add);

        await Future.delayed(Duration(milliseconds: 100));
        expect(values, equals(['events-1']));
        final countAfterInit = fetchCount;

        // Even if we set a key, nothing should happen since no deps
        await cache.set(key: 'random', value: 'value');
        await Future.delayed(Duration(milliseconds: 100));

        // Should not have refetched
        expect(fetchCount, equals(countAfterInit));

        await subscription.cancel();
      });

      test('handles errors in dependent fetch', () async {
        bool shouldFail = false;

        final stream = cache.watchWithDependencies(
          key: 'events',
          fetch: (_) async {
            if (shouldFail) {
              throw Exception('Fetch failed');
            }
            return 'events';
          },
          refetchWhen: ['trigger'],
        );

        final values = <String>[];
        final errors = <Object>[];
        final subscription = stream.listen(
          values.add,
          onError: errors.add,
        );

        await Future.delayed(Duration(milliseconds: 100));
        expect(values, equals(['events']));

        // Now trigger an error
        shouldFail = true;
        await cache.set(key: 'trigger', value: 'change');
        await Future.delayed(Duration(milliseconds: 100));

        expect(errors, isNotEmpty);

        await subscription.cancel();
      });

      test('does not refetch when unrelated key changes', () async {
        int fetchCount = 0;

        final stream = cache.watchWithDependencies(
          key: 'events',
          fetch: (_) async {
            fetchCount++;
            return 'events-$fetchCount';
          },
          refetchWhen: ['workspace'],
        );

        final values = <String>[];
        final subscription = stream.listen(values.add);

        await Future.delayed(Duration(milliseconds: 100));
        expect(values, equals(['events-1']));
        final countAfterInit = fetchCount;

        // Set an unrelated key
        await cache.set(key: 'unrelated', value: 'value');
        await Future.delayed(Duration(milliseconds: 100));

        // Should not have refetched
        expect(fetchCount, equals(countAfterInit));
        expect(values, equals(['events-1']));

        await subscription.cancel();
      });

      test('handles rapid dependency changes', () async {
        int fetchCount = 0;

        final stream = cache.watchWithDependencies(
          key: 'events',
          fetch: (_) async {
            fetchCount++;
            // Simulate network delay
            await Future.delayed(Duration(milliseconds: 20));
            return 'events-$fetchCount';
          },
          refetchWhen: ['workspace'],
        );

        final values = <String>[];
        final subscription = stream.listen(values.add);

        await Future.delayed(Duration(milliseconds: 100));
        final countAfterInit = fetchCount;

        // Rapid changes
        await cache.set(key: 'workspace', value: 'ws-1');
        await cache.set(key: 'workspace', value: 'ws-2');
        await cache.set(key: 'workspace', value: 'ws-3');

        // Wait for all fetches to complete
        await Future.delayed(Duration(milliseconds: 300));

        // All changes should trigger refetches
        expect(fetchCount, greaterThan(countAfterInit));

        await subscription.cancel();
      });
    });

    group('dependency chain scenarios', () {
      test('changing a dependency while watcher is active', () async {
        // Set up a scenario: user -> events
        int fetchCount = 0;

        final stream = cache.watchWithDependencies(
          key: 'events',
          fetch: (_) async {
            fetchCount++;
            return 'events-$fetchCount';
          },
          refetchWhen: ['user'],
        );

        final values = <String>[];
        final subscription = stream.listen(values.add);

        await Future.delayed(Duration(milliseconds: 100));
        expect(values, equals(['events-1']));

        // Simulate user switching
        await cache.set(key: 'user', value: 'user-1');
        await Future.delayed(Duration(milliseconds: 100));
        expect(values, equals(['events-1', 'events-2']));

        await cache.set(key: 'user', value: 'user-2');
        await Future.delayed(Duration(milliseconds: 100));
        expect(values, equals(['events-1', 'events-2', 'events-3']));

        expect(fetchCount, equals(3));

        await subscription.cancel();
      });

      test('watcher survives dependency invalidation', () async {
        // Set up dependency
        await cache.set(key: 'config', value: 'initial-config');

        int fetchCount = 0;

        final stream = cache.watchWithDependencies(
          key: 'data',
          fetch: (_) async {
            fetchCount++;
            return 'data-$fetchCount';
          },
          refetchWhen: ['config'],
        );

        final values = <String>[];
        final subscription = stream.listen(values.add);

        await Future.delayed(Duration(milliseconds: 100));
        expect(values, equals(['data-1']));
        final countAfterInit = fetchCount;

        // Invalidate the dependency (this removes it from cache)
        await cache.invalidate('config');
        await Future.delayed(Duration(milliseconds: 100));

        // Setting the config again should still trigger refetch
        await cache.set(key: 'config', value: 'new-config');
        await Future.delayed(Duration(milliseconds: 100));

        expect(fetchCount, greaterThan(countAfterInit));

        await subscription.cancel();
      });
    });

    group('integration with other features', () {
      test('works with TaggableStore', () async {
        final taggableStore = MemoryStore<String>(); // Already supports tags
        final taggableCache = Syncache<String>(store: taggableStore);

        int fetchCount = 0;

        final stream = taggableCache.watchWithDependencies(
          key: 'events',
          fetch: (_) async {
            fetchCount++;
            return 'events-$fetchCount';
          },
          refetchWhen: ['workspace'],
        );

        final values = <String>[];
        final subscription = stream.listen(values.add);

        await Future.delayed(Duration(milliseconds: 100));
        expect(values, equals(['events-1']));

        await taggableCache.set(key: 'workspace', value: 'ws-1');
        await Future.delayed(Duration(milliseconds: 100));

        expect(values, equals(['events-1', 'events-2']));

        await subscription.cancel();
        taggableCache.dispose();
      });

      test('dependency refetch respects ttl parameter', () async {
        final stream = cache.watchWithDependencies(
          key: 'events',
          fetch: (_) async => 'events',
          refetchWhen: ['workspace'],
          ttl: Duration(hours: 2),
        );

        final subscription = stream.listen((_) {});
        await Future.delayed(Duration(milliseconds: 100));

        // Trigger refetch
        await cache.set(key: 'workspace', value: 'new');
        await Future.delayed(Duration(milliseconds: 100));

        // Check that TTL was applied
        final stored = await store.read('events');
        expect(stored!.meta.ttl, equals(Duration(hours: 2)));

        await subscription.cancel();
      });
    });

    group('edge cases', () {
      test('handles disposed cache gracefully', () async {
        cache.dispose();

        expect(
          () => cache.set(key: 'test', value: 'value'),
          throwsStateError,
        );

        expect(
          () => cache.watchWithDependencies(
            key: 'test',
            fetch: (_) async => 'value',
            refetchWhen: ['dep'],
          ),
          throwsStateError,
        );
      });

      test('handles same key in refetchWhen multiple times', () async {
        int fetchCount = 0;

        final stream = cache.watchWithDependencies(
          key: 'events',
          fetch: (_) async {
            fetchCount++;
            return 'events-$fetchCount';
          },
          // Duplicate dependency (shouldn't cause issues)
          refetchWhen: ['workspace', 'workspace'],
        );

        final values = <String>[];
        final subscription = stream.listen(values.add);

        await Future.delayed(Duration(milliseconds: 100));
        expect(values, equals(['events-1']));
        final countAfterInit = fetchCount;

        await cache.set(key: 'workspace', value: 'new');
        await Future.delayed(Duration(milliseconds: 100));

        // Should handle duplicates gracefully (refetch happens)
        expect(fetchCount, greaterThan(countAfterInit));

        await subscription.cancel();
      });

      test('watcher key same as dependency key', () async {
        // Edge case: watching a key that depends on itself
        int fetchCount = 0;

        final stream = cache.watchWithDependencies(
          key: 'self',
          fetch: (_) async {
            fetchCount++;
            return 'self-$fetchCount';
          },
          refetchWhen: ['self'],
        );

        final values = <String>[];
        final subscription = stream.listen(values.add);

        await Future.delayed(Duration(milliseconds: 100));
        expect(values, equals(['self-1']));
        final countAfterInit = fetchCount;

        // Setting the key should trigger refetch of itself
        await cache.set(key: 'self', value: 'external');
        await Future.delayed(Duration(milliseconds: 100));

        // This creates an interesting scenario - the set updates the value,
        // then triggers refetch which overwrites with fetched value
        expect(fetchCount, greaterThan(countAfterInit));

        await subscription.cancel();
      });

      test('watcher is not triggered by its own fetch result', () async {
        // This tests that when a dependency watcher refetches and stores,
        // it doesn't create an infinite loop
        int fetchCount = 0;

        final stream = cache.watchWithDependencies(
          key: 'data',
          fetch: (_) async {
            fetchCount++;
            return 'data-$fetchCount';
          },
          refetchWhen: ['trigger'],
        );

        final subscription = stream.listen((_) {});
        await Future.delayed(Duration(milliseconds: 100));

        // Initial fetch
        final initialCount = fetchCount;
        expect(initialCount, equals(1));

        // Wait a bit more to ensure no infinite loops
        await Future.delayed(Duration(milliseconds: 200));

        // Should not have fetched more times
        expect(fetchCount, equals(initialCount));

        await subscription.cancel();
      });
    });
  });
}
