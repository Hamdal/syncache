import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncache/syncache.dart';
import 'package:syncache_workmanager/syncache_workmanager.dart';

/// A controllable [Network] so tests can simulate the device being
/// offline without touching platform channels.
class FakeNetwork implements Network {
  FakeNetwork({this.online = true});

  bool online;

  @override
  bool get isOnline => online;
}

/// A cache whose sends hang forever (simulates an unreachable server
/// holding the connection open).
Completer<int> _neverCompletes() => Completer<int>();

void main() {
  group('SyncacheBackgroundFlusher', () {
    test('empty outbox flushes nothing but reports success', () async {
      final store = MemoryStore<int>();
      final outbox = MemoryMutationOutbox();
      var created = 0;

      final flusher = SyncacheBackgroundFlusher(
        registrations: [
          SyncacheBackgroundCacheRegistration<int>(
            createCache: () async {
              created++;
              return Syncache<int>(store: store, outbox: outbox);
            },
            resolveRecord: (record) async =>
                Mutation<int>(apply: (v) => v, send: (v) async => v),
          ),
        ],
      );

      final report = await flusher.flush();

      expect(created, 1, reason: 'every pass builds a fresh cache');
      expect(report.recovered, 0);
      expect(report.remaining, 0);
      expect(report.swept, 0);
      expect(report.exhaustedBudget, isFalse);
      expect(report.duration, greaterThanOrEqualTo(Duration.zero));
    });

    test('recovers a record and sends the decoded optimistic snapshot',
        () async {
      final store = MemoryStore<int>();
      final outbox = MemoryMutationOutbox();

      // Foreground state as the app left it: cached value 1, an unsynced
      // write whose optimistic value (snapshot) was 41.
      await store.write(
        'n:1',
        Stored(value: 1, meta: Metadata(version: 1, storedAt: DateTime.now())),
      );
      await outbox.save(
        PendingMutationRecord(
          id: 'mut_1',
          key: 'n:1',
          seq: 1,
          payload: const {'op': 'add'},
          queuedAt: DateTime.now(),
          optimisticSnapshot: 41,
        ),
      );

      final sent = <int>[];
      final flusher = SyncacheBackgroundFlusher(
        registrations: [
          SyncacheBackgroundCacheRegistration<int>(
            createCache: () async => Syncache<int>(
              store: store,
              outbox: outbox,
              decodeOptimisticSnapshot: (snapshot) => snapshot as int,
              mutationRetry: MutationRetryConfig.none,
            ),
            resolveRecord: (record) async => Mutation<int>(
              apply: (v) => v,
              send: (v) async {
                sent.add(v);
                return v + 1;
              },
            ),
          ),
        ],
      );

      final report = await flusher.flush();

      expect(
        sent,
        [41],
        reason: 'replay sends the exact pre-death value, not a '
            're-derived apply(current)',
      );
      expect(report.recovered, 1);
      expect(report.remaining, 0);
      expect(report.exhaustedBudget, isFalse);

      // The record is deleted once the mutation settles…
      expect(await outbox.loadAll(), isEmpty);
      // …and the server-confirmed value replaced the cached one.
      final confirmed = await store.read('n:1');
      expect(confirmed!.value, 42);
    });

    test('records with no matching cache entry are left in the outbox',
        () async {
      final store = MemoryStore<int>();
      final outbox = MemoryMutationOutbox();
      await outbox.save(
        PendingMutationRecord(
          id: 'mut_1',
          key: 'missing-key',
          seq: 1,
          payload: const {'op': 'add'},
          queuedAt: DateTime.now(),
        ),
      );

      final flusher = SyncacheBackgroundFlusher(
        registrations: [
          SyncacheBackgroundCacheRegistration<int>(
            createCache: () async =>
                Syncache<int>(store: store, outbox: outbox),
            resolveRecord: (record) async =>
                Mutation<int>(apply: (v) => v, send: (v) async => v),
          ),
        ],
      );

      final report = await flusher.flush();

      expect(
        report.recovered,
        0,
        reason: 'replay-failed records are not '
            're-enqueued',
      );
      expect(report.remaining, 0);
      expect(
        (await outbox.loadAll()).map((r) => r.id),
        ['mut_1'],
        reason: 'records are never dropped silently',
      );
    });

    test('resolveRecord throwing keeps the record for the next run', () async {
      final store = MemoryStore<int>();
      final outbox = MemoryMutationOutbox();
      await store.write(
        'n:1',
        Stored(value: 1, meta: Metadata(version: 1, storedAt: DateTime.now())),
      );
      await outbox.save(
        PendingMutationRecord(
          id: 'mut_1',
          key: 'n:1',
          seq: 1,
          payload: const {'op': 'unknown'},
          queuedAt: DateTime.now(),
        ),
      );

      final flusher = SyncacheBackgroundFlusher(
        registrations: [
          SyncacheBackgroundCacheRegistration<int>(
            createCache: () async =>
                Syncache<int>(store: store, outbox: outbox),
            resolveRecord: (record) async =>
                throw UnimplementedError('unknown op ${record.payload['op']}'),
          ),
        ],
      );

      final report = await flusher.flush();

      expect(report.recovered, 0);
      expect((await outbox.loadAll()).map((r) => r.id), ['mut_1']);
    });

    test('retry exhaustion deletes the record and reports nothing pending',
        () async {
      final store = MemoryStore<int>();
      final outbox = MemoryMutationOutbox();
      await store.write(
        'n:1',
        Stored(value: 1, meta: Metadata(version: 1, storedAt: DateTime.now())),
      );
      await outbox.save(
        PendingMutationRecord(
          id: 'mut_1',
          key: 'n:1',
          seq: 1,
          payload: const {'op': 'add'},
          queuedAt: DateTime.now(),
        ),
      );

      final flusher = SyncacheBackgroundFlusher(
        registrations: [
          SyncacheBackgroundCacheRegistration<int>(
            createCache: () async => Syncache<int>(
              store: store,
              outbox: outbox,
              mutationRetry: MutationRetryConfig.none,
            ),
            resolveRecord: (record) async => Mutation<int>(
              apply: (v) => v,
              send: (v) async => throw Exception('server down'),
            ),
          ),
        ],
      );

      final report = await flusher.flush();

      expect(report.recovered, 1);
      expect(
        report.remaining,
        0,
        reason: 'exhausted mutations are dropped from the queue',
      );
      expect(
        await outbox.loadAll(),
        isEmpty,
        reason: 'exhausted records are deleted, not replayed forever',
      );
    });

    test('hanging sends stop at the time budget and keep the record', () async {
      final store = MemoryStore<int>();
      final outbox = MemoryMutationOutbox();
      await store.write(
        'n:1',
        Stored(value: 1, meta: Metadata(version: 1, storedAt: DateTime.now())),
      );
      await outbox.save(
        PendingMutationRecord(
          id: 'mut_1',
          key: 'n:1',
          seq: 1,
          payload: const {'op': 'add'},
          queuedAt: DateTime.now(),
        ),
      );

      final flusher = SyncacheBackgroundFlusher(
        registrations: [
          SyncacheBackgroundCacheRegistration<int>(
            createCache: () async => Syncache<int>(
              store: store,
              outbox: outbox,
              mutationRetry: MutationRetryConfig.none,
            ),
            resolveRecord: (record) async => Mutation<int>(
              apply: (v) => v,
              send: (v) => _neverCompletes().future,
            ),
          ),
        ],
      );

      final report =
          await flusher.flush(timeBudget: const Duration(milliseconds: 400));

      expect(report.recovered, 1);
      expect(report.remaining, 1);
      expect(report.exhaustedBudget, isTrue);
      expect(
        (await outbox.loadAll()).map((r) => r.id),
        ['mut_1'],
        reason: 'unsent mutations stay in the outbox for the next run',
      );
    });

    test('an offline background cache returns immediately, record intact',
        () async {
      final store = MemoryStore<int>();
      final outbox = MemoryMutationOutbox();
      await store.write(
        'n:1',
        Stored(value: 1, meta: Metadata(version: 1, storedAt: DateTime.now())),
      );
      await outbox.save(
        PendingMutationRecord(
          id: 'mut_1',
          key: 'n:1',
          seq: 1,
          payload: const {'op': 'add'},
          queuedAt: DateTime.now(),
        ),
      );

      final flusher = SyncacheBackgroundFlusher(
        registrations: [
          SyncacheBackgroundCacheRegistration<int>(
            createCache: () async => Syncache<int>(
              store: store,
              outbox: outbox,
              network: FakeNetwork(online: false),
            ),
            resolveRecord: (record) async =>
                Mutation<int>(apply: (v) => v, send: (v) async => v),
          ),
        ],
      );

      final report = await flusher.flush();

      expect(
        report.recovered,
        1,
        reason: 'recovery re-enqueues even while offline',
      );
      expect(report.remaining, 1);
      expect(
        report.exhaustedBudget,
        isFalse,
        reason: 'the wait ended because of the network, not the budget',
      );
      expect((await outbox.loadAll()).map((r) => r.id), ['mut_1']);
    });

    test('cleanup sweeps expired entries only when requested', () async {
      Future<SyncacheBackgroundFlusher> buildFlusher() async {
        final store = MemoryStore<int>();
        await store.write(
          'n:1',
          Stored(
            value: 1,
            meta: Metadata(version: 1, storedAt: DateTime.now()),
          ),
        );
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
        return SyncacheBackgroundFlusher(
          registrations: [
            SyncacheBackgroundCacheRegistration<int>(
              createCache: () async =>
                  Syncache<int>(store: store, outbox: MemoryMutationOutbox()),
              resolveRecord: (record) async =>
                  Mutation<int>(apply: (v) => v, send: (v) async => v),
            ),
          ],
        );
      }

      final withCleanup = await buildFlusher();
      final report = await withCleanup.flush(cleanup: true);
      expect(report.swept, 1);

      final withoutCleanup = await buildFlusher();
      final report2 = await withoutCleanup.flush();
      expect(report2.swept, 0);
    });

    test('flushes every registration across cache types', () async {
      final intStore = MemoryStore<int>();
      final intOutbox = MemoryMutationOutbox();
      final stringStore = MemoryStore<String>();
      final stringOutbox = MemoryMutationOutbox();

      await intStore.write(
        'n:1',
        Stored(value: 1, meta: Metadata(version: 1, storedAt: DateTime.now())),
      );
      await intOutbox.save(
        PendingMutationRecord(
          id: 'mut_int',
          key: 'n:1',
          seq: 1,
          payload: const {'op': 'add'},
          queuedAt: DateTime.now(),
          optimisticSnapshot: 7,
        ),
      );
      await stringStore.write(
        's:1',
        Stored(
          value: 'a',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
      );
      await stringOutbox.save(
        PendingMutationRecord(
          id: 'mut_str',
          key: 's:1',
          seq: 1,
          payload: const {'op': 'rename'},
          queuedAt: DateTime.now(),
          optimisticSnapshot: 'b',
        ),
      );

      final sentInts = <int>[];
      final sentStrings = <String>[];
      final flusher = SyncacheBackgroundFlusher(
        registrations: [
          SyncacheBackgroundCacheRegistration<int>(
            createCache: () async => Syncache<int>(
              store: intStore,
              outbox: intOutbox,
              decodeOptimisticSnapshot: (snapshot) => snapshot as int,
            ),
            resolveRecord: (record) async => Mutation<int>(
              apply: (v) => v,
              send: (v) async {
                sentInts.add(v);
                return v;
              },
            ),
          ),
          SyncacheBackgroundCacheRegistration<String>(
            createCache: () async => Syncache<String>(
              store: stringStore,
              outbox: stringOutbox,
              decodeOptimisticSnapshot: (snapshot) => snapshot as String,
            ),
            resolveRecord: (record) async => Mutation<String>(
              apply: (v) => v,
              send: (v) async {
                sentStrings.add(v);
                return v;
              },
            ),
          ),
        ],
      );

      final report = await flusher.flush();

      expect(sentInts, [7]);
      expect(sentStrings, ['b']);
      expect(report.recovered, 2);
      expect(report.remaining, 0);
      expect(await intOutbox.loadAll(), isEmpty);
      expect(await stringOutbox.loadAll(), isEmpty);
    });

    test('a registration failing to build fails the whole pass', () async {
      var secondCreated = 0;
      final flusher = SyncacheBackgroundFlusher(
        registrations: [
          SyncacheBackgroundCacheRegistration<int>(
            createCache: () async =>
                throw StateError('persistence failed to open'),
            resolveRecord: (record) async =>
                Mutation<int>(apply: (v) => v, send: (v) async => v),
          ),
          SyncacheBackgroundCacheRegistration<String>(
            createCache: () async {
              secondCreated++;
              return Syncache<String>(
                store: MemoryStore<String>(),
                outbox: MemoryMutationOutbox(),
              );
            },
            resolveRecord: (record) async =>
                Mutation<String>(apply: (v) => v, send: (v) async => v),
          ),
        ],
      );

      await expectLater(
        flusher.flush(),
        throwsStateError,
        reason: 'fail fast so workmanager retries the task with backoff; '
            'the next run replays every registration',
      );
      expect(
        secondCreated,
        0,
        reason: 'registrations after the failure are not attempted',
      );
    });
  });

  group('SyncacheFlushReport', () {
    test('has useful defaults and a readable toString', () {
      const report = SyncacheFlushReport();
      expect(report.recovered, 0);
      expect(report.remaining, 0);
      expect(report.swept, 0);
      expect(report.exhaustedBudget, isFalse);
      expect(report.duration, Duration.zero);
      expect(
        report.toString(),
        'SyncacheFlushReport(recovered: 0, remaining: 0, swept: 0, '
        'exhaustedBudget: false, duration: 0:00:00.000000)',
      );
    });
  });
}
