import 'dart:async';

import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

/// Records mutation conflict/resolution events.
class ConflictObserver extends SyncacheObserver {
  final List<String> conflicts = [];
  final List<Object> conflictErrors = [];
  final List<String> resolved = [];
  final List<String> errors = [];
  final List<String> retryExhausted = [];

  @override
  void onMutationConflict(String key, Object error) {
    conflicts.add(key);
    conflictErrors.add(error);
  }

  @override
  void onMutationResolved(String key) => resolved.add(key);

  @override
  void onMutationError(String key, Object error, StackTrace stackTrace) =>
      errors.add(key);

  @override
  void onMutationRetryExhausted(
          String key, int totalAttempts, Object finalError) =>
      retryExhausted.add(key);
}

/// A capture-all resolver recording what it was handed.
class RecordingResolver implements ConflictResolver<String> {
  final String Function(
      String optimistic, String server, Map<String, Object?>? payload) merge;
  String? seenOptimistic;
  String? seenServer;
  Map<String, Object?>? seenPayload;
  int calls = 0;

  RecordingResolver(this.merge);

  @override
  Future<String> resolve({
    required String optimisticValue,
    required String serverValue,
    required Map<String, Object?>? payload,
  }) async {
    calls++;
    seenOptimistic = optimisticValue;
    seenServer = serverValue;
    seenPayload = payload;
    return merge(optimisticValue, serverValue, payload);
  }
}

/// A resolver that always throws.
class ThrowingResolver implements ConflictResolver<String> {
  @override
  Future<String> resolve({
    required String optimisticValue,
    required String serverValue,
    required Map<String, Object?>? payload,
  }) async {
    throw StateError('resolver exploded');
  }
}

void main() {
  /// Pumps the event loop until [condition] holds (or fails after a bound).
  ///
  /// Queue processing hops through several microtasks and futures; a single
  /// `Duration.zero` pump is not deterministic enough.
  Future<void> pumpUntil(bool Function() condition,
      {int maxPumps = 200}) async {
    for (var i = 0; i < maxPumps && !condition(); i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> seed(Syncache<String> cache, String key,
          [String value = 'initial']) =>
      cache.set(key: key, value: value);

  group('conflict resolution', () {
    test('consults the cache-wide resolver and settles MutationResolved',
        () async {
      final cache = Syncache<String>(
        store: MemoryStore<String>(),
        conflictResolver: serverWins<String>(),
      );
      addTearDown(cache.dispose);
      await seed(cache, 'k');

      var sendCount = 0;
      final handle = await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'optimistic',
          send: (_) async {
            sendCount++;
            throw SyncacheConflictException<String>('server-state');
          },
        ),
      );

      final outcome = await handle.outcome;

      expect(outcome, isA<MutationResolved<String>>());
      final resolved = outcome as MutationResolved<String>;
      expect(resolved.resolvedValue, 'server-state');
      expect(resolved.wasConflict, isTrue);
      expect(handle.isSettled, isTrue);
      expect(sendCount, 1,
          reason: 'conflicts are never retried — the resolver settles them');
      expect(cache.pendingMutationCount, 0,
          reason: 'resolved mutations leave the queue');

      final stored = await cache.store.read('k');
      expect(stored!.value, 'server-state',
          reason: 'serverWins stores the server value');
    });

    test('clientWins keeps the optimistic value', () async {
      final cache = Syncache<String>(
        store: MemoryStore<String>(),
        conflictResolver: clientWins<String>(),
      );
      addTearDown(cache.dispose);
      await seed(cache, 'k');

      final handle = await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'optimistic',
          send: (_) async =>
              throw SyncacheConflictException<String>('server-state'),
        ),
      );

      final outcome = await handle.outcome;
      expect((outcome as MutationResolved<String>).resolvedValue, 'optimistic');

      final stored = await cache.store.read('k');
      expect(stored!.value, 'optimistic');
    });

    test('the per-call resolver overrides the cache-wide default', () async {
      final cache = Syncache<String>(
        store: MemoryStore<String>(),
        conflictResolver: serverWins<String>(),
      );
      addTearDown(cache.dispose);
      await seed(cache, 'k');

      final handle = await cache.mutate(
        key: 'k',
        conflictResolver: clientWins<String>(),
        mutation: Mutation<String>(
          apply: (_) => 'optimistic',
          send: (_) async =>
              throw SyncacheConflictException<String>('server-state'),
        ),
      );

      final outcome = await handle.outcome;
      expect((outcome as MutationResolved<String>).resolvedValue, 'optimistic');
    });

    test('the resolver receives optimistic value, server value and payload',
        () async {
      final resolver = RecordingResolver(
          (optimistic, server, payload) => '$optimistic+$server');
      final cache = Syncache<String>(
        store: MemoryStore<String>(),
        outbox: MemoryMutationOutbox(),
        conflictResolver: resolver,
      );
      addTearDown(cache.dispose);
      await seed(cache, 'k');

      final handle = await cache.mutate(
        key: 'k',
        payload: {'op': 'rename', 'name': 'optimistic'},
        mutation: Mutation<String>(
          apply: (_) => 'optimistic',
          send: (_) async =>
              throw SyncacheConflictException<String>('server-state'),
        ),
      );
      await handle.outcome;

      await pumpUntil(() => resolver.calls == 1);

      expect(resolver.seenOptimistic, 'optimistic');
      expect(resolver.seenServer, 'server-state');
      expect(resolver.seenPayload, {'op': 'rename', 'name': 'optimistic'});
    });

    test('a custom merge resolver produces the merged value', () async {
      final cache = Syncache<String>(
        store: MemoryStore<String>(),
        conflictResolver: RecordingResolver(
            (optimistic, server, payload) => '$server-then-$optimistic'),
      );
      addTearDown(cache.dispose);
      await seed(cache, 'k');

      final handle = await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'mine',
          send: (_) async => throw SyncacheConflictException<String>('theirs'),
        ),
      );

      final outcome = await handle.outcome;
      expect((outcome as MutationResolved<String>).resolvedValue,
          'theirs-then-mine');

      final stored = await cache.store.read('k');
      expect(stored!.value, 'theirs-then-mine');
    });

    test('a throwing resolver fails the mutation terminally', () async {
      final cache = Syncache<String>(
        store: MemoryStore<String>(),
        mutationRetry: MutationRetryConfig(maxAttempts: 3),
        conflictResolver: ThrowingResolver(),
      );
      addTearDown(cache.dispose);
      await seed(cache, 'k');

      var sendCount = 0;
      final handle = await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'optimistic',
          send: (_) async {
            sendCount++;
            throw SyncacheConflictException<String>('server-state');
          },
        ),
      );

      final outcome = await handle.outcome;

      expect(outcome, isA<MutationFailure<String>>());
      final failure = outcome as MutationFailure<String>;
      expect(failure.error, isA<StateError>());
      expect(failure.error.toString(), contains('resolver exploded'));
      expect(sendCount, 1, reason: 'a throwing resolver is not re-consulted');
      expect(cache.pendingMutationCount, 0);
    });

    test('without any resolver a conflict fails terminally instead of retrying',
        () async {
      final cache = Syncache<String>(
        store: MemoryStore<String>(),
        mutationRetry: MutationRetryConfig(maxAttempts: 5),
      );
      addTearDown(cache.dispose);
      await seed(cache, 'k');

      var sendCount = 0;
      final handle = await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'optimistic',
          send: (_) async {
            sendCount++;
            throw SyncacheConflictException<String>('server-state');
          },
        ),
      );

      final outcome = await handle.outcome;

      expect(outcome, isA<MutationFailure<String>>());
      expect((outcome as MutationFailure<String>).error,
          isA<SyncacheConflictException<String>>());
      expect(sendCount, 1,
          reason: 'no retry: the same send would only conflict again');
      expect(cache.pendingMutationCount, 0);
    });

    test('conflict resolution deletes the outbox record instead of keeping it',
        () async {
      final outbox = MemoryMutationOutbox();
      final cache = Syncache<String>(
        store: MemoryStore<String>(),
        outbox: outbox,
        conflictResolver: serverWins<String>(),
      );
      addTearDown(cache.dispose);
      await seed(cache, 'k');

      final handle = await cache.mutate(
        key: 'k',
        payload: {'op': 'rename'},
        mutation: Mutation<String>(
          apply: (_) => 'optimistic',
          send: (_) async =>
              throw SyncacheConflictException<String>('server-state'),
        ),
      );
      await handle.outcome;

      var remaining = await outbox.loadAll();
      for (var i = 0; i < 200 && remaining.isNotEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
        remaining = await outbox.loadAll();
      }

      expect(remaining, isEmpty,
          reason: 'the conflict is settled — the record must not replay');
    });

    test('fires onMutationConflict then onMutationResolved', () async {
      final observer = ConflictObserver();
      final cache = Syncache<String>(
        store: MemoryStore<String>(),
        observers: [observer],
        conflictResolver: serverWins<String>(),
      );
      addTearDown(cache.dispose);
      await seed(cache, 'k');

      final handle = await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'optimistic',
          send: (_) async =>
              throw SyncacheConflictException<String>('server-state'),
        ),
      );
      await handle.outcome;

      expect(observer.conflicts, ['k']);
      expect(observer.conflictErrors.single,
          isA<SyncacheConflictException<String>>());
      expect(observer.resolved, ['k']);
      expect(observer.retryExhausted, isEmpty,
          reason: 'a resolved conflict is not a retry exhaustion');
    });

    test('an unresolved conflict also fires onMutationError + retryExhausted',
        () async {
      final observer = ConflictObserver();
      final cache = Syncache<String>(
        store: MemoryStore<String>(),
        observers: [observer],
      );
      addTearDown(cache.dispose);
      await seed(cache, 'k');

      final handle = await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'optimistic',
          send: (_) async =>
              throw SyncacheConflictException<String>('server-state'),
        ),
      );
      await handle.outcome;

      expect(observer.conflicts, ['k']);
      expect(observer.errors, ['k']);
      expect(observer.retryExhausted, ['k']);
      expect(observer.resolved, isEmpty);
    });

    test(
        'mutations queued behind the conflict are re-applied on the resolved '
        'value', () async {
      final cache = Syncache<String>(
        store: MemoryStore<String>(),
        conflictResolver: serverWins<String>(),
      );
      addTearDown(cache.dispose);
      await seed(cache, 'k');

      // First mutation hangs in flight; second queues behind it.
      final gate = Completer<void>();
      String? m2Received;
      final handle1 = await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'm1',
          send: (_) => gate.future.then(
              (_) => throw SyncacheConflictException<String>('server-state')),
        ),
      );
      final handle2 = await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (current) => '$current+m2',
          send: (value) async {
            m2Received = value;
            return 'server-2';
          },
        ),
      );

      gate.complete();

      expect((await handle1.outcome as MutationResolved<String>).resolvedValue,
          'server-state');
      expect(await handle2.outcome, isA<MutationSuccess<String>>());

      expect(m2Received, 'server-state+m2',
          reason:
              'm2 was re-applied on top of the resolved value before its send');
      final stored = await cache.store.read('k');
      expect(stored!.value, 'server-2',
          reason: 'm2 then synced and its server value won');
    });

    test('a differently-typed conflict exception is an ordinary send failure',
        () async {
      final resolver = RecordingResolver(
          (optimistic, server, payload) => 'should-not-happen');
      final cache = Syncache<String>(
        store: MemoryStore<String>(),
        conflictResolver: resolver,
      );
      addTearDown(cache.dispose);
      await seed(cache, 'k');

      final handle = await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'optimistic',
          send: (_) async => throw SyncacheConflictException<int>(409),
        ),
      );

      final outcome = await handle.outcome;
      expect(outcome, isA<MutationFailure<String>>());
      expect(resolver.calls, 0,
          reason: "type mismatch: not recognized as this cache's conflict");
    });

    test('works through ScopedSyncache with a per-call resolver', () async {
      final cache = Syncache<String>(store: MemoryStore<String>());
      addTearDown(cache.dispose);
      final scoped = cache.scoped('s');
      await scoped.set(key: 'k', value: 'initial');

      final handle = await scoped.mutate(
        key: 'k',
        conflictResolver: clientWins<String>(),
        mutation: Mutation<String>(
          apply: (_) => 'scoped-optimistic',
          send: (_) async =>
              throw SyncacheConflictException<String>('server-state'),
        ),
      );

      final outcome = await handle.outcome;
      expect((outcome as MutationResolved<String>).resolvedValue,
          'scoped-optimistic');

      final stored = await cache.store.read('s:k');
      expect(stored!.value, 'scoped-optimistic');
    });
  });
}
