import 'dart:async';

import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

/// A controllable network for testing online/offline transitions.
class _ControllableNetwork implements Network {
  bool _isOnline = true;

  @override
  bool get isOnline => _isOnline;

  void goOnline() => _isOnline = true;
  void goOffline() => _isOnline = false;
}

/// A network that is always offline for testing mutation queuing.
class _OfflineNetwork implements Network {
  @override
  bool get isOnline => false;
}

void main() {
  group('CacheResult and Metadata', () {
    late Syncache<String> cache;
    late MemoryStore<String> store;

    setUp(() {
      store = MemoryStore<String>();
      cache = Syncache<String>(store: store);
    });

    group('getWithMeta', () {
      test('returns CacheResult with isFromCache=false on fresh fetch',
          () async {
        final result = await cache.getWithMeta(
          key: 'test-key',
          fetch: (_) async => 'fetched-value',
        );

        expect(result.value, equals('fetched-value'));
        expect(result.meta.isFromCache, isFalse);
        expect(result.meta.isStale, isFalse);
        expect(result.meta.storedAt, isNotNull);
        expect(result.meta.version, equals(1));
      });

      test('returns CacheResult with isFromCache=true from cache', () async {
        // Pre-populate cache
        await store.write(
          'test-key',
          Stored(
            value: 'cached-value',
            meta: Metadata(
              version: 5,
              storedAt: DateTime.now().subtract(const Duration(minutes: 10)),
              ttl: const Duration(hours: 1),
            ),
          ),
        );

        final result = await cache.getWithMeta(
          key: 'test-key',
          fetch: (_) async => 'fetched-value',
        );

        expect(result.value, equals('cached-value'));
        expect(result.meta.isFromCache, isTrue);
        expect(result.meta.isStale, isFalse);
        expect(result.meta.version, equals(5));
      });

      test('returns isStale=true for expired cached data', () async {
        // Pre-populate cache with expired value
        await store.write(
          'test-key',
          Stored(
            value: 'stale-value',
            meta: Metadata(
              version: 3,
              storedAt: DateTime.now().subtract(const Duration(hours: 2)),
              ttl: const Duration(hours: 1),
            ),
          ),
        );

        // Use cacheOnly to get the stale value
        final result = await cache.getWithMeta(
          key: 'test-key',
          fetch: (_) async => 'fetched-value',
          policy: Policy.cacheOnly,
        );

        expect(result.value, equals('stale-value'));
        expect(result.meta.isFromCache, isTrue);
        expect(result.meta.isStale, isTrue);
      });

      test('age returns correct duration', () async {
        final storedAt = DateTime.now().subtract(const Duration(minutes: 30));
        await store.write(
          'test-key',
          Stored(
            value: 'cached-value',
            meta: Metadata(
              version: 1,
              storedAt: storedAt,
              ttl: const Duration(hours: 1),
            ),
          ),
        );

        final result = await cache.getWithMeta(
          key: 'test-key',
          fetch: (_) async => 'fetched-value',
        );

        expect(result.meta.age, isNotNull);
        // Age should be approximately 30 minutes (allow some tolerance)
        expect(result.meta.age!.inMinutes, greaterThanOrEqualTo(29));
        expect(result.meta.age!.inMinutes, lessThanOrEqualTo(31));
      });
    });

    group('watchWithMeta', () {
      test('emits CacheResult with metadata on each update', () async {
        final results = <CacheResult<String>>[];

        final stream = cache.watchWithMeta(
          key: 'test-key',
          fetch: (_) async => 'initial-value',
        );

        final sub = stream.listen(results.add);

        // Wait for initial fetch
        await Future.delayed(const Duration(milliseconds: 50));
        expect(results.isNotEmpty, isTrue);
        expect(results.last.value, equals('initial-value'));
        // Initial fetch should have isFromCache: false (fresh from network)
        expect(
          results.any((r) => r.meta.isFromCache == false),
          isTrue,
        );

        final initialCount = results.length;

        // Trigger an update via mutation
        await cache.mutate(
          key: 'test-key',
          mutation: Mutation(
            apply: (v) => 'mutated-value',
            send: (v) async => v,
          ),
        );

        await Future.delayed(const Duration(milliseconds: 50));
        expect(results.length, greaterThan(initialCount));
        expect(results.last.value, equals('mutated-value'));
        // After mutation sync, value is fresh from server (not from cache)
        expect(results.last.meta.isFromCache, isFalse);

        await sub.cancel();
      });
    });
  });

  group('Pending Mutations Observability', () {
    late Syncache<String> cache;
    late MemoryStore<String> store;
    late _ControllableNetwork network;

    setUp(() {
      store = MemoryStore<String>();
      network = _ControllableNetwork();
      cache = Syncache<String>(store: store, network: network);
    });

    test('pendingMutationsStream emits when mutations are queued', () async {
      // Pre-populate cache
      await store.write(
        'test-key',
        Stored(
          value: 'initial',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
      );

      final snapshots = <List<PendingMutationInfo>>[];
      final sub = cache.pendingMutationsStream.listen(snapshots.add);

      // Go offline to prevent sync
      network.goOffline();

      await cache.mutate(
        key: 'test-key',
        mutation: Mutation(
          apply: (v) => 'mutated',
          send: (v) async => v,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 50));

      expect(snapshots.isNotEmpty, isTrue);
      expect(snapshots.last.length, equals(1));
      expect(snapshots.last.first.key, equals('test-key'));
      expect(
          snapshots.last.first.status, equals(PendingMutationStatus.pending));

      await sub.cancel();
    });

    test('hasPendingMutations returns true when mutations exist', () async {
      await store.write(
        'test-key',
        Stored(
          value: 'initial',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
      );

      network.goOffline();

      expect(cache.hasPendingMutations, isFalse);

      await cache.mutate(
        key: 'test-key',
        mutation: Mutation(
          apply: (v) => 'mutated',
          send: (v) async => v,
        ),
      );

      expect(cache.hasPendingMutations, isTrue);
    });

    test('pendingMutationsSnapshot returns current state', () async {
      await store.write(
        'test-key',
        Stored(
          value: 'initial',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
      );

      network.goOffline();

      await cache.mutate(
        key: 'test-key',
        mutation: Mutation(
          apply: (v) => 'mutated',
          send: (v) async => v,
        ),
      );

      final snapshot = cache.pendingMutationsSnapshot;
      expect(snapshot.length, equals(1));
      expect(snapshot.first.key, equals('test-key'));
    });

    test('isSyncedStream emits true when all mutations are synced', () async {
      await store.write(
        'test-key',
        Stored(
          value: 'initial',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
      );

      final syncStates = <bool>[];
      final sub = cache.isSyncedStream.listen(syncStates.add);

      // Start online, mutate, should sync immediately
      await cache.mutate(
        key: 'test-key',
        mutation: Mutation(
          apply: (v) => 'mutated',
          send: (v) async {
            await Future.delayed(const Duration(milliseconds: 20));
            return v;
          },
        ),
      );

      await Future.delayed(const Duration(milliseconds: 100));

      // Should have emitted both false (has pending) and true (all synced)
      expect(syncStates, contains(false));
      expect(syncStates.last, isTrue);

      await sub.cancel();
    });

    test('mutation status transitions from pending to syncing to removed',
        () async {
      await store.write(
        'test-key',
        Stored(
          value: 'initial',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
      );

      final statuses = <PendingMutationStatus>[];
      final completer = Completer<void>();

      cache.pendingMutationsStream.listen((mutations) {
        if (mutations.isNotEmpty) {
          statuses.add(mutations.first.status);
        }
        if (mutations.isEmpty && statuses.isNotEmpty) {
          completer.complete();
        }
      });

      await cache.mutate(
        key: 'test-key',
        mutation: Mutation(
          apply: (v) => 'mutated',
          send: (v) async {
            await Future.delayed(const Duration(milliseconds: 20));
            return v;
          },
        ),
      );

      await completer.future.timeout(const Duration(seconds: 1));

      expect(statuses, contains(PendingMutationStatus.pending));
      expect(statuses, contains(PendingMutationStatus.syncing));
    });
  });

  group('QueryKey', () {
    test('encoded returns base when no params', () {
      final key = QueryKey('users');
      expect(key.encoded, equals('users'));
    });

    test('encoded includes sorted params', () {
      final key = QueryKey('users', {'workspace': 123, 'active': true});
      expect(key.encoded, equals('users?active=true&workspace=123'));
    });

    test('params are sorted alphabetically', () {
      final key = QueryKey('events', {'z': 1, 'a': 2, 'm': 3});
      expect(key.encoded, equals('events?a=2&m=3&z=1'));
    });

    test('pattern returns wildcard pattern', () {
      final key = QueryKey('calendar/events', {'month': '2024-03'});
      expect(key.pattern, equals('calendar/events?*'));
    });

    test('toString returns encoded', () {
      final key = QueryKey('test', {'x': 1});
      expect(key.toString(), equals(key.encoded));
    });

    test('equality works correctly', () {
      final key1 = QueryKey('users', {'a': 1, 'b': 2});
      final key2 = QueryKey('users', {'b': 2, 'a': 1});
      final key3 = QueryKey('users', {'a': 1});

      expect(key1, equals(key2));
      expect(key1, isNot(equals(key3)));
    });

    test('hashCode is consistent', () {
      final key1 = QueryKey('users', {'a': 1, 'b': 2});
      final key2 = QueryKey('users', {'b': 2, 'a': 1});

      expect(key1.hashCode, equals(key2.hashCode));
    });
  });

  group('Tag-Based Invalidation', () {
    late Syncache<String> cache;
    late MemoryStore<String> store;

    setUp(() {
      store = MemoryStore<String>();
      cache = Syncache<String>(store: store);
    });

    group('get with tags', () {
      test('stores entry with tags', () async {
        await cache.get(
          key: 'event:123',
          fetch: (_) async => 'event-data',
          tags: ['events', 'calendar', 'workspace:456'],
        );

        final tags = await store.getTags('event:123');
        expect(tags, containsAll(['events', 'calendar', 'workspace:456']));
      });

      test('tags are preserved on update', () async {
        await cache.get(
          key: 'event:123',
          fetch: (_) async => 'event-data-v1',
          tags: ['events', 'calendar'],
        );

        // Force refresh
        await cache.get(
          key: 'event:123',
          fetch: (_) async => 'event-data-v2',
          policy: Policy.refresh,
          tags: ['events', 'calendar'],
        );

        final tags = await store.getTags('event:123');
        expect(tags, containsAll(['events', 'calendar']));

        final stored = await store.read('event:123');
        expect(stored?.value, equals('event-data-v2'));
      });
    });

    group('invalidateTag', () {
      test('deletes all entries with the tag', () async {
        // Store multiple entries with the same tag
        await cache.get(
          key: 'event:1',
          fetch: (_) async => 'event-1',
          tags: ['events', 'workspace:100'],
        );
        await cache.get(
          key: 'event:2',
          fetch: (_) async => 'event-2',
          tags: ['events', 'workspace:100'],
        );
        await cache.get(
          key: 'user:1',
          fetch: (_) async => 'user-1',
          tags: ['users', 'workspace:100'],
        );

        await cache.invalidateTag('events');

        expect(await store.read('event:1'), isNull);
        expect(await store.read('event:2'), isNull);
        expect(await store.read('user:1'), isNotNull);
      });

      test('closes watchers for invalidated entries', () async {
        await cache.get(
          key: 'event:1',
          fetch: (_) async => 'event-1',
          tags: ['events'],
        );

        var streamClosed = false;
        final stream = cache.watch(
          key: 'event:1',
          fetch: (_) async => 'event-1',
        );

        stream.listen(
          (_) {},
          onDone: () => streamClosed = true,
        );

        await Future.delayed(const Duration(milliseconds: 50));

        await cache.invalidateTag('events');

        await Future.delayed(const Duration(milliseconds: 50));
        expect(streamClosed, isTrue);
      });
    });

    group('invalidateTags', () {
      test('deletes entries matching any tag by default', () async {
        await cache.get(
          key: 'event:1',
          fetch: (_) async => 'event-1',
          tags: ['events'],
        );
        await cache.get(
          key: 'user:1',
          fetch: (_) async => 'user-1',
          tags: ['users'],
        );
        await cache.get(
          key: 'other:1',
          fetch: (_) async => 'other-1',
          tags: ['other'],
        );

        await cache.invalidateTags(['events', 'users']);

        expect(await store.read('event:1'), isNull);
        expect(await store.read('user:1'), isNull);
        expect(await store.read('other:1'), isNotNull);
      });

      test('with matchAll=true only deletes entries with all tags', () async {
        await cache.get(
          key: 'event:1',
          fetch: (_) async => 'event-1',
          tags: ['events', 'workspace:100'],
        );
        await cache.get(
          key: 'event:2',
          fetch: (_) async => 'event-2',
          tags: ['events', 'workspace:200'],
        );
        await cache.get(
          key: 'event:3',
          fetch: (_) async => 'event-3',
          tags: ['events', 'workspace:100', 'important'],
        );

        await cache.invalidateTags(['events', 'workspace:100'], matchAll: true);

        // Only event:1 and event:3 should be deleted (they have both tags)
        expect(await store.read('event:1'), isNull);
        expect(await store.read('event:2'), isNotNull);
        expect(await store.read('event:3'), isNull);
      });

      test('does nothing with empty tags list', () async {
        await cache.get(
          key: 'event:1',
          fetch: (_) async => 'event-1',
          tags: ['events'],
        );

        await cache.invalidateTags([]);

        expect(await store.read('event:1'), isNotNull);
      });
    });

    group('invalidatePattern', () {
      test('deletes entries matching glob pattern', () async {
        await cache.get(
          key: 'user:1',
          fetch: (_) async => 'user-1',
        );
        await cache.get(
          key: 'user:2',
          fetch: (_) async => 'user-2',
        );
        await cache.get(
          key: 'event:1',
          fetch: (_) async => 'event-1',
        );

        await cache.invalidatePattern('user:*');

        expect(await store.read('user:1'), isNull);
        expect(await store.read('user:2'), isNull);
        expect(await store.read('event:1'), isNotNull);
      });

      test('supports ? wildcard for single character', () async {
        await cache.get(
          key: 'log-a',
          fetch: (_) async => 'log-a',
        );
        await cache.get(
          key: 'log-b',
          fetch: (_) async => 'log-b',
        );
        await cache.get(
          key: 'log-ab',
          fetch: (_) async => 'log-ab',
        );

        await cache.invalidatePattern('log-?');

        expect(await store.read('log-a'), isNull);
        expect(await store.read('log-b'), isNull);
        expect(await store.read('log-ab'), isNotNull);
      });

      test('works with QueryKey patterns', () async {
        final key1 = QueryKey('calendar/events', {'month': '2024-03'});
        final key2 = QueryKey('calendar/events', {'month': '2024-04'});
        final key3 = QueryKey('calendar/tasks', {'month': '2024-03'});

        await cache.get(
          key: key1.encoded,
          fetch: (_) async => 'events-march',
        );
        await cache.get(
          key: key2.encoded,
          fetch: (_) async => 'events-april',
        );
        await cache.get(
          key: key3.encoded,
          fetch: (_) async => 'tasks-march',
        );

        await cache.invalidatePattern('calendar/events?*');

        expect(await store.read(key1.encoded), isNull);
        expect(await store.read(key2.encoded), isNull);
        expect(await store.read(key3.encoded), isNotNull);
      });
    });
  });

  group('Mutation Invalidation', () {
    late Syncache<String> cache;
    late MemoryStore<String> store;

    setUp(() {
      store = MemoryStore<String>();
      cache = Syncache<String>(store: store);
    });

    test('invalidates keys by pattern after successful sync', () async {
      // Populate cache with related entries
      await cache.get(
        key: 'event:456',
        fetch: (_) async => 'event-456',
      );
      await cache.get(
        key: 'calendar:events:2024-03',
        fetch: (_) async => 'march-events',
      );
      await cache.get(
        key: 'calendar:events:2024-04',
        fetch: (_) async => 'april-events',
      );
      await cache.get(
        key: 'dashboard:stats',
        fetch: (_) async => 'stats',
      );

      // Mutate with invalidation patterns
      await cache.mutate(
        key: 'event:456',
        mutation: Mutation(
          apply: (v) => 'updated-event',
          send: (v) async => v,
        ),
        invalidates: ['calendar:*'],
      );

      // Wait for sync to complete
      await Future.delayed(const Duration(milliseconds: 100));

      // Mutated entry should still exist (updated)
      expect(await store.read('event:456'), isNotNull);
      expect((await store.read('event:456'))!.value, equals('updated-event'));

      // Pattern-matched entries should be invalidated
      expect(await store.read('calendar:events:2024-03'), isNull);
      expect(await store.read('calendar:events:2024-04'), isNull);

      // Unrelated entries should still exist
      expect(await store.read('dashboard:stats'), isNotNull);
    });

    test('invalidates keys by tags after successful sync', () async {
      // Populate cache with tagged entries
      await cache.get(
        key: 'event:456',
        fetch: (_) async => 'event-456',
        tags: ['events'],
      );
      await cache.get(
        key: 'calendar-view',
        fetch: (_) async => 'calendar-data',
        tags: ['calendar', 'events'],
      );
      await cache.get(
        key: 'dashboard',
        fetch: (_) async => 'dashboard-data',
        tags: ['dashboard'],
      );

      // Mutate with tag invalidation
      await cache.mutate(
        key: 'event:456',
        mutation: Mutation(
          apply: (v) => 'updated-event',
          send: (v) async => v,
        ),
        invalidateTags: ['calendar'],
      );

      // Wait for sync
      await Future.delayed(const Duration(milliseconds: 100));

      // Mutated entry should still exist
      expect(await store.read('event:456'), isNotNull);

      // Tag-matched entries should be invalidated
      expect(await store.read('calendar-view'), isNull);

      // Unrelated entries should still exist
      expect(await store.read('dashboard'), isNotNull);
    });

    test('invalidates both patterns and tags', () async {
      await cache.get(
        key: 'event:456',
        fetch: (_) async => 'event-456',
      );
      await cache.get(
        key: 'list:events',
        fetch: (_) async => 'event-list',
      );
      await cache.get(
        key: 'dashboard',
        fetch: (_) async => 'dashboard',
        tags: ['dashboard'],
      );
      await cache.get(
        key: 'stats',
        fetch: (_) async => 'stats',
        tags: ['other'],
      );

      await cache.mutate(
        key: 'event:456',
        mutation: Mutation(
          apply: (v) => 'updated',
          send: (v) async => v,
        ),
        invalidates: ['list:*'],
        invalidateTags: ['dashboard'],
      );

      await Future.delayed(const Duration(milliseconds: 100));

      expect(await store.read('event:456'), isNotNull);
      expect(await store.read('list:events'), isNull);
      expect(await store.read('dashboard'), isNull);
      expect(await store.read('stats'), isNotNull);
    });

    test('does not invalidate on failed mutation', () async {
      await cache.get(
        key: 'event:456',
        fetch: (_) async => 'event-456',
      );
      await cache.get(
        key: 'calendar-view',
        fetch: (_) async => 'calendar-data',
        tags: ['calendar'],
      );

      try {
        await cache.mutate(
          key: 'event:456',
          mutation: Mutation(
            apply: (v) => 'updated',
            send: (v) async => throw Exception('Sync failed'),
          ),
          invalidateTags: ['calendar'],
        );
      } catch (_) {}

      // Wait for mutation to fail
      await Future.delayed(const Duration(milliseconds: 200));

      // Related entries should NOT be invalidated since sync failed
      expect(await store.read('calendar-view'), isNotNull);
    });
  });

  group('MemoryStore TaggableStore', () {
    late MemoryStore<String> store;

    setUp(() {
      store = MemoryStore<String>();
    });

    test('implements TaggableStore', () {
      expect(store, isA<TaggableStore<String>>());
    });

    test('writeWithTags stores entry with tags', () async {
      await store.writeWithTags(
        'key1',
        Stored(
          value: 'value1',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
        ['tag1', 'tag2'],
      );

      final tags = await store.getTags('key1');
      expect(tags, containsAll(['tag1', 'tag2']));
    });

    test('getTags returns empty list for non-existent key', () async {
      final tags = await store.getTags('nonexistent');
      expect(tags, isEmpty);
    });

    test('getKeysByTag returns all keys with tag', () async {
      await store.writeWithTags(
        'key1',
        Stored(
          value: 'value1',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
        ['shared-tag'],
      );
      await store.writeWithTags(
        'key2',
        Stored(
          value: 'value2',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
        ['shared-tag', 'other-tag'],
      );
      await store.writeWithTags(
        'key3',
        Stored(
          value: 'value3',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
        ['different-tag'],
      );

      final keys = await store.getKeysByTag('shared-tag');
      expect(keys, containsAll(['key1', 'key2']));
      expect(keys, isNot(contains('key3')));
    });

    test('deleteByTag removes all entries with tag', () async {
      await store.writeWithTags(
        'key1',
        Stored(
          value: 'value1',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
        ['delete-me'],
      );
      await store.writeWithTags(
        'key2',
        Stored(
          value: 'value2',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
        ['delete-me'],
      );
      await store.writeWithTags(
        'key3',
        Stored(
          value: 'value3',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
        ['keep-me'],
      );

      await store.deleteByTag('delete-me');

      expect(await store.read('key1'), isNull);
      expect(await store.read('key2'), isNull);
      expect(await store.read('key3'), isNotNull);
    });

    test('deleteByTags with matchAll=false removes entries with any tag',
        () async {
      await store.writeWithTags(
        'key1',
        Stored(
          value: 'value1',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
        ['tag-a'],
      );
      await store.writeWithTags(
        'key2',
        Stored(
          value: 'value2',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
        ['tag-b'],
      );
      await store.writeWithTags(
        'key3',
        Stored(
          value: 'value3',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
        ['tag-c'],
      );

      await store.deleteByTags(['tag-a', 'tag-b'], matchAll: false);

      expect(await store.read('key1'), isNull);
      expect(await store.read('key2'), isNull);
      expect(await store.read('key3'), isNotNull);
    });

    test('deleteByTags with matchAll=true removes entries with all tags',
        () async {
      await store.writeWithTags(
        'key1',
        Stored(
          value: 'value1',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
        ['tag-a', 'tag-b'],
      );
      await store.writeWithTags(
        'key2',
        Stored(
          value: 'value2',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
        ['tag-a'],
      );
      await store.writeWithTags(
        'key3',
        Stored(
          value: 'value3',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
        ['tag-b'],
      );

      await store.deleteByTags(['tag-a', 'tag-b'], matchAll: true);

      expect(await store.read('key1'), isNull);
      expect(await store.read('key2'), isNotNull);
      expect(await store.read('key3'), isNotNull);
    });

    test('getKeysByPattern matches glob patterns', () async {
      await store.write(
        'user:1',
        Stored(
          value: 'user-1',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
      );
      await store.write(
        'user:2',
        Stored(
          value: 'user-2',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
      );
      await store.write(
        'event:1',
        Stored(
          value: 'event-1',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
      );

      final keys = await store.getKeysByPattern('user:*');
      expect(keys, containsAll(['user:1', 'user:2']));
      expect(keys, isNot(contains('event:1')));
    });

    test('deleteByPattern removes matching entries', () async {
      await store.write(
        'temp:a',
        Stored(
          value: 'temp-a',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
      );
      await store.write(
        'temp:b',
        Stored(
          value: 'temp-b',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
      );
      await store.write(
        'perm:a',
        Stored(
          value: 'perm-a',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
      );

      await store.deleteByPattern('temp:*');

      expect(await store.read('temp:a'), isNull);
      expect(await store.read('temp:b'), isNull);
      expect(await store.read('perm:a'), isNotNull);
    });

    test('delete also removes associated tags', () async {
      await store.writeWithTags(
        'key1',
        Stored(
          value: 'value1',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
        ['tag1', 'tag2'],
      );

      await store.delete('key1');

      final tags = await store.getTags('key1');
      expect(tags, isEmpty);

      final keys = await store.getKeysByTag('tag1');
      expect(keys, isNot(contains('key1')));
    });

    test('clear removes all tags', () async {
      await store.writeWithTags(
        'key1',
        Stored(
          value: 'value1',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
        ['tag1'],
      );
      await store.writeWithTags(
        'key2',
        Stored(
          value: 'value2',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
        ['tag2'],
      );

      await store.clear();

      expect(await store.getKeysByTag('tag1'), isEmpty);
      expect(await store.getKeysByTag('tag2'), isEmpty);
    });
  });

  group('Store without TaggableStore', () {
    late Syncache<String> cache;
    late _NonTaggableStore store;

    setUp(() {
      store = _NonTaggableStore();
      cache = Syncache<String>(store: store);
    });

    test('invalidateTag does nothing silently', () async {
      await cache.get(
        key: 'test-key',
        fetch: (_) async => 'value',
      );

      // Should not throw
      await cache.invalidateTag('some-tag');

      // Entry should still exist
      expect(await store.read('test-key'), isNotNull);
    });

    test('invalidateTags does nothing silently', () async {
      await cache.get(
        key: 'test-key',
        fetch: (_) async => 'value',
      );

      await cache.invalidateTags(['tag1', 'tag2']);

      expect(await store.read('test-key'), isNotNull);
    });

    test('invalidatePattern does nothing silently', () async {
      await cache.get(
        key: 'test-key',
        fetch: (_) async => 'value',
      );

      await cache.invalidatePattern('test:*');

      expect(await store.read('test-key'), isNotNull);
    });

    test('tags parameter in get is ignored', () async {
      // Should not throw even though store doesn't support tags
      await cache.get(
        key: 'test-key',
        fetch: (_) async => 'value',
        tags: ['ignored-tag'],
      );

      expect(await store.read('test-key'), isNotNull);
    });
  });

  group('Cache Scoping', () {
    late Syncache<String> cache;
    late MemoryStore<String> store;

    setUp(() {
      store = MemoryStore<String>();
      cache = Syncache<String>(store: store);
    });

    group('scoped()', () {
      test('returns a ScopedSyncache instance', () {
        final scoped = cache.scoped('workspace:123');
        expect(scoped, isA<ScopedSyncache<String>>());
        expect(scoped.scope, equals('workspace:123'));
      });

      test('scoped cache has access to underlying cache', () {
        final scoped = cache.scoped('workspace:123');
        expect(scoped.cache, same(cache));
      });
    });

    group('ScopedSyncache.get()', () {
      test('prefixes key with scope', () async {
        final scoped = cache.scoped('workspace:123');

        await scoped.get(
          key: 'users',
          fetch: (_) async => 'user-data',
        );

        // Check the store has the scoped key
        expect(await store.read('workspace:123:users'), isNotNull);
        expect((await store.read('workspace:123:users'))!.value,
            equals('user-data'));

        // Original key should not exist
        expect(await store.read('users'), isNull);
      });

      test('different scopes are isolated', () async {
        final scope1 = cache.scoped('workspace:1');
        final scope2 = cache.scoped('workspace:2');

        await scope1.get(
          key: 'data',
          fetch: (_) async => 'scope1-value',
        );

        await scope2.get(
          key: 'data',
          fetch: (_) async => 'scope2-value',
        );

        expect(
          (await store.read('workspace:1:data'))!.value,
          equals('scope1-value'),
        );
        expect(
          (await store.read('workspace:2:data'))!.value,
          equals('scope2-value'),
        );
      });

      test('passes tags to underlying cache', () async {
        final scoped = cache.scoped('workspace:123');

        await scoped.get(
          key: 'events',
          fetch: (_) async => 'events-data',
          tags: ['events', 'calendar'],
        );

        final tags = await store.getTags('workspace:123:events');
        expect(tags, containsAll(['events', 'calendar']));
      });
    });

    group('ScopedSyncache.getWithMeta()', () {
      test('returns metadata with scoped key', () async {
        final scoped = cache.scoped('workspace:123');

        final result = await scoped.getWithMeta(
          key: 'data',
          fetch: (_) async => 'value',
        );

        expect(result.value, equals('value'));
        expect(result.meta.isFromCache, isFalse);
      });
    });

    group('ScopedSyncache.watch()', () {
      test('watches scoped key', () async {
        final scoped = cache.scoped('workspace:123');
        final values = <String>[];

        final stream = scoped.watch(
          key: 'data',
          fetch: (_) async => 'initial',
        );

        final sub = stream.listen(values.add);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(values.isNotEmpty, isTrue);
        expect(values.last, equals('initial'));

        // Mutate via scoped cache
        await scoped.mutate(
          key: 'data',
          mutation: Mutation(
            apply: (v) => 'mutated',
            send: (v) async => v,
          ),
        );

        await Future.delayed(const Duration(milliseconds: 50));
        expect(values.last, equals('mutated'));

        await sub.cancel();
      });
    });

    group('ScopedSyncache.mutate()', () {
      test('mutates scoped key', () async {
        final scoped = cache.scoped('workspace:123');

        // First populate the cache
        await scoped.get(
          key: 'item',
          fetch: (_) async => 'original',
        );

        await scoped.mutate(
          key: 'item',
          mutation: Mutation(
            apply: (v) => 'updated',
            send: (v) async => v,
          ),
        );

        await Future.delayed(const Duration(milliseconds: 50));

        expect(
          (await store.read('workspace:123:item'))!.value,
          equals('updated'),
        );
      });

      test('scopes invalidation patterns', () async {
        final scoped = cache.scoped('workspace:123');

        // Populate entries
        await scoped.get(key: 'item', fetch: (_) async => 'item-data');
        await scoped.get(key: 'list:items', fetch: (_) async => 'list-data');
        await scoped.get(key: 'other', fetch: (_) async => 'other-data');

        // Mutate with invalidation pattern (should be scoped)
        await scoped.mutate(
          key: 'item',
          mutation: Mutation(
            apply: (v) => 'updated',
            send: (v) async => v,
          ),
          invalidates: ['list:*'],
        );

        await Future.delayed(const Duration(milliseconds: 100));

        // Scoped list entry should be invalidated
        expect(await store.read('workspace:123:list:items'), isNull);
        // Other scoped entry should remain
        expect(await store.read('workspace:123:other'), isNotNull);
      });
    });

    group('ScopedSyncache.invalidate()', () {
      test('invalidates scoped key', () async {
        final scoped = cache.scoped('workspace:123');

        await scoped.get(
          key: 'data',
          fetch: (_) async => 'value',
        );

        expect(await store.read('workspace:123:data'), isNotNull);

        await scoped.invalidate('data');

        expect(await store.read('workspace:123:data'), isNull);
      });
    });

    group('ScopedSyncache.invalidatePattern()', () {
      test('invalidates patterns within scope', () async {
        final scoped = cache.scoped('workspace:123');

        await scoped.get(key: 'user:1', fetch: (_) async => 'user1');
        await scoped.get(key: 'user:2', fetch: (_) async => 'user2');
        await scoped.get(key: 'event:1', fetch: (_) async => 'event1');

        await scoped.invalidatePattern('user:*');

        expect(await store.read('workspace:123:user:1'), isNull);
        expect(await store.read('workspace:123:user:2'), isNull);
        expect(await store.read('workspace:123:event:1'), isNotNull);
      });
    });

    group('ScopedSyncache.clear()', () {
      test('clears all entries in scope', () async {
        final scope1 = cache.scoped('workspace:1');
        final scope2 = cache.scoped('workspace:2');

        await scope1.get(key: 'data1', fetch: (_) async => 'value1');
        await scope1.get(key: 'data2', fetch: (_) async => 'value2');
        await scope2.get(key: 'data1', fetch: (_) async => 'value3');

        // Clear scope1
        await scope1.clear();

        // Scope1 entries should be gone
        expect(await store.read('workspace:1:data1'), isNull);
        expect(await store.read('workspace:1:data2'), isNull);

        // Scope2 entries should remain
        expect(await store.read('workspace:2:data1'), isNotNull);
      });
    });

    group('ScopedSyncache.invalidateTag()', () {
      test('tags are NOT scoped (shared across scopes)', () async {
        final scope1 = cache.scoped('workspace:1');
        final scope2 = cache.scoped('workspace:2');

        await scope1.get(
          key: 'events',
          fetch: (_) async => 'events1',
          tags: ['calendar'],
        );
        await scope2.get(
          key: 'events',
          fetch: (_) async => 'events2',
          tags: ['calendar'],
        );

        // Invalidate tag from scope1 - should affect both scopes
        await scope1.invalidateTag('calendar');

        expect(await store.read('workspace:1:events'), isNull);
        expect(await store.read('workspace:2:events'), isNull);
      });
    });

    group('Syncache.clearScope()', () {
      test('clears all entries in specified scope', () async {
        final scope1 = cache.scoped('workspace:1');
        final scope2 = cache.scoped('workspace:2');

        await scope1.get(key: 'a', fetch: (_) async => 'a1');
        await scope1.get(key: 'b', fetch: (_) async => 'b1');
        await scope2.get(key: 'a', fetch: (_) async => 'a2');

        // Clear via main cache
        await cache.clearScope('workspace:1');

        expect(await store.read('workspace:1:a'), isNull);
        expect(await store.read('workspace:1:b'), isNull);
        expect(await store.read('workspace:2:a'), isNotNull);
      });
    });

    group('Syncache.invalidateInScope()', () {
      test('invalidates pattern within specified scope', () async {
        final scope1 = cache.scoped('workspace:1');
        final scope2 = cache.scoped('workspace:2');

        await scope1.get(key: 'user:1', fetch: (_) async => 'u1-s1');
        await scope1.get(key: 'user:2', fetch: (_) async => 'u2-s1');
        await scope1.get(key: 'event:1', fetch: (_) async => 'e1-s1');
        await scope2.get(key: 'user:1', fetch: (_) async => 'u1-s2');

        // Invalidate users in scope1 only
        await cache.invalidateInScope('workspace:1', 'user:*');

        expect(await store.read('workspace:1:user:1'), isNull);
        expect(await store.read('workspace:1:user:2'), isNull);
        expect(await store.read('workspace:1:event:1'), isNotNull);
        expect(await store.read('workspace:2:user:1'), isNotNull);
      });
    });

    group('ScopedSyncache.prefetch()', () {
      test('prefetches with scoped keys', () async {
        final scoped = cache.scoped('workspace:123');

        final results = await scoped.prefetch([
          PrefetchRequest(key: 'data1', fetch: (_) async => 'value1'),
          PrefetchRequest(key: 'data2', fetch: (_) async => 'value2'),
        ]);

        expect(results.length, equals(2));
        expect(results.every((r) => r.success), isTrue);

        expect(await store.read('workspace:123:data1'), isNotNull);
        expect(await store.read('workspace:123:data2'), isNotNull);
      });
    });

    group('ScopedSyncache.prefetchOne()', () {
      test('prefetches single key with scope', () async {
        final scoped = cache.scoped('workspace:123');

        final success = await scoped.prefetchOne(
          key: 'single',
          fetch: (_) async => 'single-value',
        );

        expect(success, isTrue);
        expect(await store.read('workspace:123:single'), isNotNull);
      });
    });

    group('Global mutation operations are not scoped', () {
      test('pendingMutationCount is global', () async {
        // Pre-populate
        await store.write(
          'workspace:1:data',
          Stored(
            value: 'value1',
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );
        await store.write(
          'workspace:2:data',
          Stored(
            value: 'value2',
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        // Create a network that's offline to queue mutations
        final offlineCache = Syncache<String>(
          store: store,
          network: _OfflineNetwork(),
        );
        final offlineScope1 = offlineCache.scoped('workspace:1');
        final offlineScope2 = offlineCache.scoped('workspace:2');

        await offlineScope1.mutate(
          key: 'data',
          mutation: Mutation(
            apply: (v) => 'updated1',
            send: (v) async => v,
          ),
        );

        await offlineScope2.mutate(
          key: 'data',
          mutation: Mutation(
            apply: (v) => 'updated2',
            send: (v) async => v,
          ),
        );

        // Both scopes should see the global count
        expect(offlineScope1.pendingMutationCount, equals(2));
        expect(offlineScope2.pendingMutationCount, equals(2));
        expect(offlineCache.pendingMutationCount, equals(2));
      });

      test('hasPendingMutations is global', () async {
        await store.write(
          'workspace:1:data',
          Stored(
            value: 'value',
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );

        final offlineCache = Syncache<String>(
          store: store,
          network: _OfflineNetwork(),
        );
        final scoped = offlineCache.scoped('workspace:1');

        expect(scoped.hasPendingMutations, isFalse);

        await scoped.mutate(
          key: 'data',
          mutation: Mutation(
            apply: (v) => 'updated',
            send: (v) async => v,
          ),
        );

        expect(scoped.hasPendingMutations, isTrue);
      });
    });
  });
}

/// A simple store that does NOT implement TaggableStore
class _NonTaggableStore implements Store<String> {
  final _data = <String, Stored<String>>{};

  @override
  Future<void> write(String key, Stored<String> entry) async {
    _data[key] = entry;
  }

  @override
  Future<Stored<String>?> read(String key) async {
    return _data[key];
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }

  @override
  Future<void> clear() async {
    _data.clear();
  }
}
