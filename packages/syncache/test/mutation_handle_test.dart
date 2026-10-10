import 'dart:async';

import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

/// A [Network] that never reports connectivity, so mutations stay queued.
class AlwaysOffline implements Network {
  const AlwaysOffline();

  @override
  bool get isOnline => false;
}

/// Tests for the per-mutation result handle returned by `mutate()`.
void main() {
  group('MutationHandle', () {
    late MemoryStore<String> store;
    late Syncache<String> cache;

    setUp(() {
      store = MemoryStore<String>();
      cache = Syncache<String>(store: store);
    });

    tearDown(() {
      cache.dispose();
    });

    Future<void> seedValue(String key) async {
      await cache.set(key: key, value: 'initial');
    }

    test('resolves with the server value on success', () async {
      await seedValue('k');

      final handle = await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (v) => 'optimistic',
          send: (_) async => 'server-confirmed',
        ),
      );
      expect(handle.isSettled, isFalse,
          reason: 'still awaiting the server right after mutate');

      final outcome = await handle.outcome;

      expect(handle.isSettled, isTrue);
      expect(outcome, isA<MutationSuccess<String>>());
      expect(
          (outcome as MutationSuccess<String>).serverValue, 'server-confirmed');

      // The cache holds the server-confirmed value.
      final stored = await store.read('k');
      expect(stored!.value, 'server-confirmed');
    });

    test('resolves with success after a retry-then-success', () async {
      await seedValue('k');

      var sendCount = 0;
      final handle = await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (v) => 'optimistic',
          send: (_) async {
            sendCount++;
            if (sendCount == 1) {
              throw Exception('flaky network');
            }
            return 'confirmed-after-retry';
          },
        ),
      );

      final outcome = await handle.outcome;

      expect(sendCount, 2, reason: 'one retry after the first failure');
      expect(outcome, isA<MutationSuccess<String>>());
      expect((outcome as MutationSuccess<String>).serverValue,
          'confirmed-after-retry');
    });

    test('resolves with failure when retries are exhausted', () async {
      await seedValue('k');
      final failingCache = Syncache<String>(
        store: store,
        mutationRetry: MutationRetryConfig(
          maxAttempts: 2,
          delay: (_) => Duration.zero,
        ),
      );
      addTearDown(failingCache.dispose);
      await failingCache.set(key: 'k', value: 'initial');

      final handle = await failingCache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (v) => 'optimistic',
          send: (_) async => throw StateError('server down'),
        ),
      );

      final outcome = await handle.outcome;

      expect(outcome, isA<MutationFailure<String>>());
      final failure = outcome as MutationFailure<String>;
      expect(failure.error, isA<StateError>());
      expect(failure.retried, 2, reason: 'maxAttempts retries were performed');
      expect(failure.stackTrace, isA<StackTrace>());
      expect(handle.isSettled, isTrue);
      expect(failingCache.pendingMutationCount, 0,
          reason: 'exhausted mutation is removed from the queue');
    });

    test('resolves with failure when the error is not retryable', () async {
      await seedValue('k');
      final failingCache = Syncache<String>(
        store: store,
        mutationRetry: MutationRetryConfig(
          maxAttempts: 3,
          retryIf: (e) => e is FormatException,
        ),
      );
      addTearDown(failingCache.dispose);
      await failingCache.set(key: 'k', value: 'initial');

      final handle = await failingCache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (v) => 'optimistic',
          send: (_) async => throw StateError('permanent'),
        ),
      );

      final outcome = await handle.outcome;

      expect(outcome, isA<MutationFailure<String>>());
      expect((outcome as MutationFailure<String>).retried, 0,
          reason: 'the first failure already ended the mutation');
    });

    test('resolves with discarded after clearPendingMutations', () async {
      final offlineCache = Syncache<String>(
        store: store,
        network: const AlwaysOffline(),
      );
      addTearDown(offlineCache.dispose);
      await offlineCache.set(key: 'k', value: 'initial');

      final handle = await offlineCache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (v) => 'optimistic',
          send: (_) async => 'server',
        ),
      );
      expect(offlineCache.pendingMutationCount, 1);

      offlineCache.clearPendingMutations();

      final outcome = await handle.outcome;
      expect(outcome, isA<MutationDiscarded<String>>());
      expect(handle.isSettled, isTrue);
    });

    test('resolves with discarded on dispose', () async {
      final offlineCache = Syncache<String>(
        store: store,
        network: const AlwaysOffline(),
      );
      await offlineCache.set(key: 'k', value: 'initial');

      final handle = await offlineCache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (v) => 'optimistic',
          send: (_) async => 'server',
        ),
      );
      expect(offlineCache.pendingMutationCount, 1);

      offlineCache.dispose();

      final outcome = await handle.outcome;
      expect(outcome, isA<MutationDiscarded<String>>());
      expect(handle.isSettled, isTrue);
    });

    test('each mutation gets its own handle', () async {
      await seedValue('k');

      final gate1 = Completer<String>();
      final handle1 = await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (v) => 'm1',
          send: (_) => gate1.future,
        ),
      );
      final handle2 = await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (v) => 'm2',
          send: (_) async => 'server-2',
        ),
      );

      expect(identical(handle1, handle2), isFalse);
      expect(handle1.isSettled, isFalse);
      expect(handle2.isSettled, isFalse);

      gate1.complete('server-1');

      expect((await handle1.outcome as MutationSuccess<String>).serverValue,
          'server-1');
      expect((await handle2.outcome as MutationSuccess<String>).serverValue,
          'server-2');
    });

    test('works through ScopedSyncache', () async {
      await seedValue('s:k');
      final scoped = cache.scoped('s');

      final handle = await scoped.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (v) => 'optimistic',
          send: (_) async => 'scoped-server',
        ),
      );

      final outcome = await handle.outcome;
      expect((outcome as MutationSuccess<String>).serverValue, 'scoped-server');
    });

    test('outcome future does not error on failure', () async {
      await seedValue('k');
      final failingCache = Syncache<String>(
        store: store,
        mutationRetry: MutationRetryConfig(maxAttempts: 0),
      );
      addTearDown(failingCache.dispose);
      await failingCache.set(key: 'k', value: 'initial');

      final handle = await failingCache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (v) => 'optimistic',
          send: (_) async => throw Exception('boom'),
        ),
      );

      // Must complete with a value, never with an error.
      await expectLater(handle.outcome, completes);
      expect(await handle.outcome, isA<MutationFailure<String>>());
    });
  });
}
