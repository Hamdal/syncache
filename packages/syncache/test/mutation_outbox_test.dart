import 'dart:async';

import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

/// A controllable [Network] for tests.
class FakeNetwork implements Network {
  FakeNetwork({this.online = true});
  bool online;

  @override
  bool get isOnline => online;
}

/// A user-supplied [MutationOutbox] test double backed by a plain map.
///
/// Deliberately written without any storage-package dependency to prove
/// core durability has no storage-package requirement.
class MapOutbox implements MutationOutbox {
  final Map<String, PendingMutationRecord> records = {};

  /// When non-null, save calls complete only after this completer fires.
  Completer<void>? gateSaves;

  final List<Exception> saveErrors = [];
  final List<Exception> deleteErrors = [];

  @override
  Future<void> save(PendingMutationRecord record) async {
    final gate = gateSaves;
    if (gate != null) await gate.future;
    if (saveErrors.isNotEmpty) throw saveErrors.removeAt(0);
    records[record.id] = record;
  }

  @override
  Future<void> delete(String id) async {
    if (deleteErrors.isNotEmpty) throw deleteErrors.removeAt(0);
    records.remove(id);
  }

  @override
  Future<void> clear() async => records.clear();

  @override
  Future<List<PendingMutationRecord>> loadAll() async {
    final all = records.values.toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
    return all;
  }
}

/// Collects outbox observer events.
class OutboxObserver extends SyncacheObserver {
  final List<Object> outboxErrors = [];
  final List<PendingMutationRecord> replayFailed = [];
  final List<Object> replayErrors = [];

  @override
  void onOutboxError(Object error) => outboxErrors.add(error);

  @override
  void onOutboxReplayFailed(PendingMutationRecord record, Object error) {
    replayFailed.add(record);
    replayErrors.add(error);
  }
}

void main() {
  /// Pumps the event loop until [condition] holds (or fails after a bound).
  ///
  /// Outbox saves and queue processing hop through several microtasks and
  /// futures; a single `Duration.zero` pump is not deterministic enough.
  Future<void> pumpUntil(bool Function() condition,
      {int maxPumps = 200}) async {
    for (var i = 0; i < maxPumps && !condition(); i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  group('MemoryMutationOutbox', () {
    test('loadAll returns records ordered by seq', () async {
      final outbox = MemoryMutationOutbox();
      await outbox.save(PendingMutationRecord(
          id: 'a', key: 'k', seq: 2, payload: {}, queuedAt: DateTime.now()));
      await outbox.save(PendingMutationRecord(
          id: 'b', key: 'k', seq: 1, payload: {}, queuedAt: DateTime.now()));
      final all = await outbox.loadAll();
      expect(all.map((r) => r.id), ['b', 'a']);
    });

    test('delete and clear remove records', () async {
      final outbox = MemoryMutationOutbox();
      await outbox.save(PendingMutationRecord(
          id: 'a', key: 'k', seq: 1, payload: {}, queuedAt: DateTime.now()));
      await outbox.delete('a');
      expect(await outbox.loadAll(), isEmpty);
      await outbox.save(PendingMutationRecord(
          id: 'b', key: 'k', seq: 2, payload: {}, queuedAt: DateTime.now()));
      await outbox.clear();
      expect(await outbox.loadAll(), isEmpty);
    });
  });

  group('mutate with outbox', () {
    late MemoryStore<String> store;
    late MapOutbox outbox;
    late OutboxObserver observer;
    late Syncache<String> cache;

    setUp(() {
      store = MemoryStore<String>();
      outbox = MapOutbox();
      observer = OutboxObserver();
      cache = Syncache<String>(
        store: store,
        network: FakeNetwork(online: false),
        observers: [observer],
        outbox: outbox,
        mutationRetry: MutationRetryConfig(maxAttempts: 0),
      );
    });

    tearDown(() {
      cache.dispose();
    });

    Future<void> seed(String key) => cache.set(key: key, value: 'initial');

    test('enqueue persists a record with the payload', () async {
      await seed('k');
      await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'optimistic',
          send: (_) async => 'server',
        ),
        payload: {'op': 'rename', 'name': 'optimistic'},
      );
      await pumpUntil(() => outbox.records.isNotEmpty);

      expect(outbox.records, hasLength(1));
      final record = outbox.records.values.single;
      expect(record.key, 'k');
      expect(record.payload, {'op': 'rename', 'name': 'optimistic'});
      expect(record.id, cache.pendingMutationsSnapshot.single.id);
    });

    test('flush after reconnect deletes the record', () async {
      await seed('k');
      await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'optimistic',
          send: (_) async => 'server',
        ),
        payload: {'op': 'rename'},
      );
      await pumpUntil(() => outbox.records.isNotEmpty);
      expect(outbox.records, hasLength(1));

      (cache.network as FakeNetwork).online = true;
      await cache.processPendingMutations();

      expect(outbox.records, isEmpty);
      expect((await store.read('k'))!.value, 'server');
    });

    test('pendingMutationsSnapshot exposes the payload', () async {
      await seed('k');
      await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'optimistic',
          send: (_) async => 'server',
        ),
        payload: {'op': 'rename'},
      );
      expect(cache.pendingMutationsSnapshot.single.payload,
          {'op': 'rename'});
    });

    test('removePendingMutation deletes the record', () async {
      await seed('k');
      await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'optimistic',
          send: (_) async => 'server',
        ),
        payload: {'op': 'rename'},
      );
      final id = cache.pendingMutationsSnapshot.single.id;

      expect(cache.removePendingMutation(id), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(outbox.records, isEmpty);
    });

    test('clearPendingMutations deletes records but keeps an in-flight one',
        () async {
      await seed('k');
      (cache.network as FakeNetwork).online = true;

      // First send hangs until we complete it; don't await mutate() since
      // the processing pass (and therefore mutate) blocks on the send.
      final sendCompleter = Completer<String>();
      final firstFuture = cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'first',
          send: (_) => sendCompleter.future,
        ),
        payload: {'op': 'first'},
      );
      await pumpUntil(() =>
          cache.pendingMutationsSnapshot.isNotEmpty &&
          cache.pendingMutationsSnapshot.first.status ==
              PendingMutationStatus.syncing);

      await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'second',
          send: (_) async => 'second-server',
        ),
        payload: {'op': 'second'},
      );
      expect(cache.pendingMutationsSnapshot, hasLength(2));

      // Clear keeps the in-flight (first) mutation, discards the queued
      // (second) one and deletes its record.
      cache.clearPendingMutations();
      expect(cache.pendingMutationsSnapshot, hasLength(1));
      await pumpUntil(() => outbox.records.length == 1);
      expect(outbox.records.values.single.payload, {'op': 'first'},
          reason: 'the in-flight record is kept until its send settles');

      sendCompleter.complete('first-server');
      await firstFuture;
      await pumpUntil(() => outbox.records.isEmpty);
    });

    test('retry exhaustion deletes the record', () async {
      await seed('k');
      (cache.network as FakeNetwork).online = true;
      final handle = await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'optimistic',
          send: (_) async => throw Exception('server down'),
        ),
        payload: {'op': 'rename'},
      );

      final outcome = await handle.outcome;
      expect(outcome, isA<MutationFailure<String>>());
      await Future<void>.delayed(Duration.zero);
      expect(outbox.records, isEmpty,
          reason: 'exhausted mutations must not be replayed');
    });

    test('outbox save failure does not block the optimistic apply',
        () async {
      outbox.saveErrors.add(Exception('disk full'));
      await seed('k');
      final storedBefore = await store.read('k');

      final handle = await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'optimistic',
          send: (_) async => 'server',
        ),
        payload: {'op': 'rename'},
      );

      // Optimistic value written, no exception escaped mutate().
      final stored = await store.read('k');
      expect(stored!.value, 'optimistic');
      expect(stored.value, isNot(storedBefore!.value));
      expect(handle, isNotNull);

      expect(observer.outboxErrors, hasLength(1));
    });

    test('records survive dispose (durability contract)', () async {
      await seed('k');
      await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'optimistic',
          send: (_) async => 'server',
        ),
        payload: {'op': 'rename'},
      );
      expect(outbox.records, hasLength(1));

      cache.dispose();

      expect(outbox.records, hasLength(1),
          reason: 'dispose must preserve outbox records');
    });
  });

  group('mutate payload guard', () {
    test('throws StateError when payload is given without an outbox',
        () async {
      final cache = Syncache<String>(store: MemoryStore<String>());
      addTearDown(cache.dispose);
      await cache.set(key: 'k', value: 'initial');

      expect(
        () => cache.mutate(
          key: 'k',
          mutation: Mutation<String>(
            apply: (_) => 'x',
            send: (_) async => 'y',
          ),
          payload: {'op': 'rename'},
        ),
        throwsStateError,
      );
    });

    test('allows payload when an outbox is configured', () async {
      final cache = Syncache<String>(
        store: MemoryStore<String>(),
        network: FakeNetwork(online: false),
        outbox: MapOutbox(),
      );
      addTearDown(cache.dispose);
      await cache.set(key: 'k', value: 'initial');

      await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'x',
          send: (_) async => 'y',
        ),
        payload: {'op': 'rename'},
      );
      expect(cache.pendingMutationsSnapshot, hasLength(1));
    });
  });

  group('recoverPendingMutations', () {
    test('returns 0 when no outbox is configured', () async {
      final cache = Syncache<String>(store: MemoryStore<String>());
      addTearDown(cache.dispose);

      expect(await cache.recoverPendingMutations((_) async => throw UnimplementedError()), 0);
    });

    test('simulated restart: replays in seq order and flushes when online',
        () async {
      final store = MemoryStore<String>();
      final outbox = MapOutbox();
      final offline = Syncache<String>(
        store: store,
        network: FakeNetwork(online: false),
        outbox: outbox,
      );
      await offline.set(key: 'a', value: 'a0');
      await offline.set(key: 'b', value: 'b0');
      await offline.mutate(
        key: 'a',
        mutation: Mutation<String>(
          apply: (_) => 'a1',
          send: (_) async => 'a1-server',
        ),
        payload: {'op': 'a', 'n': 1},
      );
      await offline.mutate(
        key: 'b',
        mutation: Mutation<String>(
          apply: (_) => 'b1',
          send: (_) async => 'b1-server',
        ),
        payload: {'op': 'b', 'n': 2},
      );
      expect(outbox.records, hasLength(2));

      // "Process death": dispose without draining.
      offline.dispose();

      // Fresh process: new cache over the same store + outbox, now online.
      final sends = <String>[];
      final online = Syncache<String>(
        store: store,
        network: FakeNetwork(online: true),
        outbox: outbox,
      );
      addTearDown(online.dispose);

      final restored = await online.recoverPendingMutations((record) async {
        return Mutation<String>(
          apply: (current) =>
              current.replaceFirst('0', record.payload['n'].toString()),
          send: (value) async {
            sends.add(value);
            return '$value-server';
          },
        );
      });

      expect(restored, 2);
      // Both sends happened with no new mutate() call, in enqueue order.
      await Future<void>.delayed(Duration.zero);
      expect(sends, ['a1', 'b1']);
      expect(outbox.records, isEmpty,
          reason: 'successful replay deletes records');
    });

    test('replay re-derives the value via apply instead of double-applying',
        () async {
      final store = MemoryStore<String>();
      final outbox = MapOutbox();
      final offline = Syncache<String>(
        store: store,
        network: FakeNetwork(online: false),
        outbox: outbox,
      );
      await offline.set(key: 'k', value: 'count:0');
      await offline.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (current) =>
              'count:${int.parse(current.split(':')[1]) + 1}',
          send: (_) async => 'server',
        ),
        payload: {'op': 'increment'},
      );
      // The store holds the optimistic value written before the "kill".
      expect((await store.read('k'))!.value, 'count:1');
      offline.dispose();

      final online = Syncache<String>(
        store: store,
        network: FakeNetwork(online: true),
        outbox: outbox,
      );
      addTearDown(online.dispose);

      var applyCalls = 0;
      await online.recoverPendingMutations((record) async {
        return Mutation<String>(
          apply: (current) {
            applyCalls++;
            return 'count:${int.parse(current.split(':')[1]) + 1}';
          },
          send: (value) async => value,
        );
      });
      await pumpUntil(() => outbox.records.isEmpty);

      // apply was re-derived exactly once to compute the value to send...
      expect(applyCalls, 1);
      // ...and the send carried the re-derived value ('count:1' -> 'count:2'),
      // not a stale base.
      expect((await store.read('k'))!.value, 'count:2');
    });

    test('resolver failure is reported and the record stays', () async {
      final store = MemoryStore<String>();
      final outbox = MapOutbox();
      final offline = Syncache<String>(
        store: store,
        network: FakeNetwork(online: false),
        outbox: outbox,
      );
      await offline.set(key: 'k', value: 'v0');
      await offline.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'v1',
          send: (_) async => 'server',
        ),
        payload: {'op': 'unknown'},
      );
      offline.dispose();

      final observer = OutboxObserver();
      final online = Syncache<String>(
        store: store,
        network: FakeNetwork(online: true),
        outbox: outbox,
        observers: [observer],
      );
      addTearDown(online.dispose);

      final restored = await online.recoverPendingMutations((record) async {
        throw StateError('unknown op ${record.payload['op']}');
      });

      expect(restored, 0);
      expect(observer.replayFailed, hasLength(1));
      expect(observer.replayFailed.single.key, 'k');
      expect(observer.replayErrors.single, isA<StateError>());
      expect(outbox.records, hasLength(1),
          reason: 'failed records are never dropped silently');
    });

    test('missing cache entry is reported, not replayed', () async {
      final outbox = MapOutbox();
      // Store without the key the record refers to.
      final store = MemoryStore<String>();
      final offline = Syncache<String>(
        store: store,
        network: FakeNetwork(online: false),
        outbox: outbox,
      );
      await offline.set(key: 'k', value: 'v0');
      await offline.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'v1',
          send: (_) async => 'server',
        ),
        payload: {'op': 'x'},
      );
      offline.dispose();
      await store.delete('k'); // entry evicted while "app was dead"

      final observer = OutboxObserver();
      final online = Syncache<String>(
        store: store,
        network: FakeNetwork(online: true),
        outbox: outbox,
        observers: [observer],
      );
      addTearDown(online.dispose);

      final restored = await online.recoverPendingMutations((_) async =>
          Mutation<String>(apply: (_) => 'v', send: (_) async => 's'));

      expect(restored, 0);
      expect(observer.replayFailed, hasLength(1));
      expect(observer.replayErrors.single, isA<StateError>());
    });

    test('recovered ids never collide with newly generated ids', () async {
      final store = MemoryStore<String>();
      final outbox = MapOutbox();
      final offline = Syncache<String>(
        store: store,
        network: FakeNetwork(online: false),
        outbox: outbox,
      );
      await offline.set(key: 'k', value: 'v0');
      await offline.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'v1',
          send: (_) async => 'server',
        ),
        payload: {'op': 'x'},
      );
      final replayedId = outbox.records.values.single.id;
      offline.dispose();

      final online = Syncache<String>(
        store: store,
        network: FakeNetwork(online: false),
        outbox: outbox,
      );
      addTearDown(online.dispose);
      await online.recoverPendingMutations((_) async => Mutation<String>(
            apply: (_) => 'replayed',
            send: (_) async => 'server',
          ));

      // Enqueue a brand-new mutation in the new process.
      await online.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'fresh',
          send: (_) async => 'server',
        ),
        payload: {'op': 'y'},
      );

      final ids = online.pendingMutationsSnapshot.map((m) => m.id).toList();
      expect(ids.toSet().length, ids.length,
          reason: 'ids must be unique after recovery');
      expect(ids, contains(replayedId));
    });

    test('seq of new mutations orders after replayed records', () async {
      final outbox = MapOutbox();
      final store = MemoryStore<String>();
      final offline = Syncache<String>(
        store: store,
        network: FakeNetwork(online: false),
        outbox: outbox,
      );
      await offline.set(key: 'k', value: 'v0');
      await offline.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'v1',
          send: (_) async => 'server',
        ),
        payload: {'op': 'x'},
      );
      expect(outbox.records, hasLength(1));
      final replayedSeq = outbox.records.values.single.seq;
      expect(replayedSeq, greaterThan(0));
      offline.dispose();

      final online = Syncache<String>(
        store: store,
        network: FakeNetwork(online: false),
        outbox: outbox,
      );
      addTearDown(online.dispose);
      await online.recoverPendingMutations((_) async => Mutation<String>(
            apply: (_) => 'replayed',
            send: (_) async => 'server',
          ));
      await online.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'fresh',
          send: (_) async => 'server',
        ),
        payload: {'op': 'y'},
      );

      // Fresh records persist with a seq strictly greater than replayed ones.
      final fresh = online.pendingMutationsSnapshot;
      expect(fresh, hasLength(2));
    });

    test('outbox delete failure during drain is reported via onOutboxError',
        () async {
      final outbox = MapOutbox();
      final store = MemoryStore<String>();
      final offline = Syncache<String>(
        store: store,
        network: FakeNetwork(online: false),
        outbox: outbox,
      );
      await offline.set(key: 'k', value: 'v0');
      await offline.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'v1',
          send: (_) async => 'server',
        ),
        payload: {'op': 'x'},
      );
      offline.dispose();

      final observer = OutboxObserver();
      final online = Syncache<String>(
        store: store,
        network: FakeNetwork(online: true),
        outbox: outbox,
        observers: [observer],
      );
      addTearDown(online.dispose);
      outbox.deleteErrors.add(Exception('io error'));

      await online.recoverPendingMutations((_) async => Mutation<String>(
            apply: (_) => 'v1',
            send: (_) async => 'server',
          ));
      await Future<void>.delayed(Duration.zero);

      expect(observer.outboxErrors, hasLength(1));
      expect(outbox.records, hasLength(1),
          reason: 'record lingers after a failed delete');
    });

    test('mutation discarded while its save is in flight leaves no record',
        () async {
      final outbox = MapOutbox();
      outbox.gateSaves = Completer<void>();
      final cache = Syncache<String>(
        store: MemoryStore<String>(),
        network: FakeNetwork(online: false),
        outbox: outbox,
      );
      addTearDown(cache.dispose);
      await cache.set(key: 'k', value: 'v0');

      // Not awaited: the save is gated, so mutate() cannot complete yet.
      final handleFuture = cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'v1',
          send: (_) async => 'server',
        ),
        payload: {'op': 'x'},
      );
      // The queue registers the mutation after mutate()'s internal store
      // round-trips; wait for it.
      await pumpUntil(() => cache.pendingMutationsSnapshot.isNotEmpty);
      final id = cache.pendingMutationsSnapshot.single.id;
      expect(cache.removePendingMutation(id), isTrue);

      // Release the save; it lands after the discard, and the outbox must
      // self-correct by deleting the freshly written record.
      outbox.gateSaves!.complete();
      final handle = await handleFuture;
      expect(await handle.outcome, isA<MutationDiscarded<String>>());
      await pumpUntil(() => outbox.records.isEmpty);
      expect(outbox.records, isEmpty);
    });
  });
}
