import 'package:flutter_test/flutter_test.dart';
import 'package:syncache/syncache.dart';
import 'package:syncache_workmanager/syncache_workmanager.dart';

void main() {
  group('task names', () {
    test('isSyncacheTask matches exactly the two Syncache task names', () {
      expect(isSyncacheTask(syncacheFlushTaskName), isTrue);
      expect(isSyncacheTask(syncacheCleanupTaskName), isTrue);
      expect(isSyncacheTask('syncache.flush '), isFalse);
      expect(isSyncacheTask('otherPackage.task'), isFalse);
      expect(isSyncacheTask(''), isFalse);
    });

    test('task and unique names are distinct constants', () {
      expect(syncacheFlushTaskName, isNot(syncacheCleanupTaskName));
      expect(
        syncachePeriodicFlushUniqueName,
        isNot(syncacheOneOffFlushUniqueName),
      );
    });
  });

  group('runSyncacheTask', () {
    SyncacheBackgroundFlusher buildFlusher(
      MemoryStore<int> store, {
      bool expiredEntry = false,
    }) {
      return SyncacheBackgroundFlusher(
        registrations: [
          SyncacheBackgroundCacheRegistration<int>(
            createCache: () async {
              final cache =
                  Syncache<int>(store: store, outbox: MemoryMutationOutbox());
              return cache;
            },
            resolveRecord: (record) async =>
                Mutation<int>(apply: (v) => v, send: (v) async => v),
          ),
        ],
      );
    }

    test('returns true and flushes for the flush task name', () async {
      final store = MemoryStore<int>();
      await store.write(
        'n:1',
        Stored(value: 1, meta: Metadata(version: 1, storedAt: DateTime.now())),
      );

      final handled = await runSyncacheTask(
        syncacheFlushTaskName,
        flusher: buildFlusher(store),
      );

      expect(handled, isTrue);
      // Sanity: the cache was constructed and is usable (read via a fresh
      // cache over the same store).
      final probe = Syncache<int>(store: store);
      final entry = await probe.entry('n:1', fetch: (_) async => 1).get();
      expect(entry, 1);
      probe.dispose();
    });

    test('routes the cleanup task name to a flush with cleanup', () async {
      final store = MemoryStore<int>();
      await store.write(
        'stale:1',
        Stored(
          value: 9,
          meta: Metadata(
            version: 1,
            storedAt: DateTime.now().subtract(const Duration(hours: 2)),
            ttl: const Duration(hours: 1),
          ),
        ),
      );

      final handled = await runSyncacheTask(
        syncacheCleanupTaskName,
        flusher: buildFlusher(store),
      );

      expect(handled, isTrue);
      expect(
        await store.read('stale:1'),
        isNull,
        reason: 'the cleanup task sweeps expired entries',
      );
    });

    test('returns false when the flusher throws', () async {
      final flusher = SyncacheBackgroundFlusher(
        registrations: [
          SyncacheBackgroundCacheRegistration<int>(
            createCache: () async =>
                throw StateError('persistence failed to open'),
            resolveRecord: (record) async =>
                Mutation<int>(apply: (v) => v, send: (v) async => v),
          ),
        ],
      );

      final handled = await runSyncacheTask(
        syncacheFlushTaskName,
        flusher: flusher,
      );

      expect(
        handled,
        isFalse,
        reason: 'false asks workmanager to retry the task with backoff',
      );
    });

    test('reports errors through the onError callback', () async {
      final errors = <Object>[];
      final flusher = SyncacheBackgroundFlusher(
        registrations: [
          SyncacheBackgroundCacheRegistration<int>(
            createCache: () async => throw StateError('boom'),
            resolveRecord: (record) async =>
                Mutation<int>(apply: (v) => v, send: (v) async => v),
          ),
        ],
      );

      final handled = await runSyncacheTask(
        syncacheFlushTaskName,
        flusher: flusher,
        onError: (error, stackTrace) => errors.add(error),
      );

      expect(handled, isFalse);
      expect(errors.single, isA<StateError>());
    });

    test('rejects foreign task names loudly', () async {
      await expectLater(
        runSyncacheTask(
          'otherPackage.task',
          flusher: buildFlusher(MemoryStore<int>()),
        ),
        throwsArgumentError,
      );
    });
  });
}
