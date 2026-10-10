import 'dart:async';

import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

/// A [ReactiveNetwork] that lets tests control connectivity and emit
/// transition events synchronously (deterministic, no delays needed).
class FakeReactiveNetwork implements ReactiveNetwork {
  final StreamController<bool> _changes =
      StreamController<bool>.broadcast(sync: true);

  @override
  bool isOnline = true;

  @override
  Stream<bool> get onConnectivityChanged => _changes.stream;

  void goOffline() {
    isOnline = false;
    _changes.add(false);
  }

  void goOnline() {
    isOnline = true;
    _changes.add(true);
  }
}

/// Tests for the reconnect-driven mutation flush and the public queue
/// control API.
void main() {
  group('Reactive network mutation flush', () {
    late MemoryStore<String> store;
    late FakeReactiveNetwork network;
    late Syncache<String> cache;

    setUp(() {
      store = MemoryStore<String>();
      network = FakeReactiveNetwork();
      cache = Syncache<String>(store: store, network: network);
    });

    tearDown(() {
      cache.dispose();
    });

    Future<void> seedValue(String key) async {
      await cache.set(key: key, value: 'initial');
    }

    test(
        'queued mutations sync when the network comes back online, '
        'without any new mutate() call', () async {
      await seedValue('k');

      network.goOffline();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      var sendCount = 0;
      final handle = await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (v) => 'optimistic',
          send: (_) async {
            sendCount++;
            return 'server';
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(sendCount, 0, reason: 'offline: nothing is sent yet');
      expect(cache.pendingMutationCount, 1);
      expect(handle.isSettled, isFalse);

      // Back online — the queue must flush on its own.
      network.goOnline();
      await handle.outcome;

      expect(sendCount, 1, reason: 'the queued mutation was sent exactly once');
      expect(cache.pendingMutationCount, 0);
      expect(handle.isSettled, isTrue);
      expect((await handle.outcome as MutationSuccess<String>).serverValue,
          'server');

      final stored = await store.read('k');
      expect(stored!.value, 'server');
    });

    test('offline to online with an empty queue does nothing', () async {
      await seedValue('k');

      network.goOffline();
      network.goOnline();

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(cache.pendingMutationCount, 0);
    });

    test('double-flap does not double-process', () async {
      await seedValue('k');

      network.goOffline();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Gate the send so the first processing pass is still in flight when
      // the flapping continues.
      final gate = Completer<String>();
      var sendCount = 0;
      final handle = await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (v) => 'optimistic',
          send: (_) {
            sendCount++;
            return gate.future;
          },
        ),
      );

      network.goOnline(); // starts processing (awaiting the gated send)
      network.goOffline();
      network.goOnline(); // must be a no-op thanks to the processing guard

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(sendCount, 1, reason: 'only one send attempt while gated');

      gate.complete('server');
      await handle.outcome;
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(sendCount, 1);
      expect(cache.pendingMutationCount, 0);
    });

    test('multiple queued mutations all flush on reconnect', () async {
      await seedValue('k');

      network.goOffline();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final handles = <MutationHandle<String>>[];
      for (var i = 1; i <= 3; i++) {
        handles.add(await cache.mutate(
          key: 'k',
          mutation: Mutation<String>(
            apply: (v) => 'm$i',
            send: (_) async => 'server-$i',
          ),
        ));
      }
      expect(cache.pendingMutationCount, 3);

      network.goOnline();

      final outcomes = await Future.wait(handles.map((h) => h.outcome));
      expect(cache.pendingMutationCount, 0);
      expect(
        outcomes.map((o) => (o as MutationSuccess<String>).serverValue),
        containsAll(['server-1', 'server-2', 'server-3']),
      );
    });

    test('dispose cancels the connectivity subscription safely', () async {
      await seedValue('k');
      network.goOffline();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (v) => 'optimistic',
          send: (_) async => 'server',
        ),
      );

      cache.dispose();

      // Emitting after dispose must not throw.
      expect(() => network.goOnline(), returnsNormally);
    });
  });

  group('processPendingMutations', () {
    late MemoryStore<String> store;
    late FakeReactiveNetwork network;
    late Syncache<String> cache;

    setUp(() {
      store = MemoryStore<String>();
      network = FakeReactiveNetwork();
      cache = Syncache<String>(store: store, network: network);
    });

    tearDown(() {
      cache.dispose();
    });

    test('flushes queued mutations manually without a connectivity event',
        () async {
      await cache.set(key: 'k', value: 'initial');

      network.goOffline();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      var sendCount = 0;
      await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (v) => 'optimistic',
          send: (_) async {
            sendCount++;
            return 'server';
          },
        ),
      );
      expect(cache.pendingMutationCount, 1);

      // Still offline: a manual pass must not send anything.
      await cache.processPendingMutations();
      expect(sendCount, 0);

      // Simulate connectivity returning without the transition event
      // (e.g. a Network implementation that never emits events).
      network.isOnline = true;
      await cache.processPendingMutations();

      expect(sendCount, 1);
      expect(cache.pendingMutationCount, 0);
    });

    test('is idempotent while a pass is already running', () async {
      await cache.set(key: 'k', value: 'initial');
      final gate = Completer<String>();
      var sendCount = 0;

      network.goOffline();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final handle = await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (v) => 'optimistic',
          send: (_) {
            sendCount++;
            return gate.future;
          },
        ),
      );

      network.isOnline = true;
      final pass1 = cache.processPendingMutations();
      final pass2 = cache.processPendingMutations();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(sendCount, 1, reason: 'concurrent passes must be collapsed');

      gate.complete('server');
      await Future.wait([pass1, pass2, handle.outcome]);
      expect(sendCount, 1);
    });

    test('works through ScopedSyncache (queue is global)', () async {
      final scoped = cache.scoped('s');
      await cache.set(key: 's:k', value: 'initial');

      network.goOffline();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final handle = await scoped.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (v) => 'optimistic',
          send: (_) async => 'server',
        ),
      );
      expect(cache.pendingMutationCount, 1);

      network.isOnline = true;
      await scoped.processPendingMutations();
      expect(cache.pendingMutationCount, 0);
      await handle.outcome;
    });
  });

  group('removePendingMutation', () {
    late MemoryStore<String> store;
    late Syncache<String> cache;

    setUp(() {
      store = MemoryStore<String>();
      cache = Syncache<String>(
        store: store,
        network: const _AlwaysOffline(),
      );
    });

    tearDown(() {
      cache.dispose();
    });

    test('removes a queued mutation by id and discards its handle', () async {
      await cache.set(key: 'k', value: 'initial');
      final handle = await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (v) => 'optimistic',
          send: (_) async => 'server',
        ),
      );
      final id = cache.pendingMutationsSnapshot.single.id;

      expect(cache.removePendingMutation(id), isTrue);
      expect(cache.removePendingMutation(id), isFalse,
          reason: 'already removed');
      expect(cache.pendingMutationCount, 0);
      expect(await handle.outcome, isA<MutationDiscarded<String>>());
    });

    test('returns false for unknown ids', () async {
      expect(cache.removePendingMutation('mut_999'), isFalse);
    });

    test('deprecated removeFirstPendingMutation still discards the handle',
        () async {
      await cache.set(key: 'k', value: 'initial');
      final handle = await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (v) => 'optimistic',
          send: (_) async => 'server',
        ),
      );

      // ignore: deprecated_member_use_from_same_package
      final removed = cache.removeFirstPendingMutation();

      expect(removed, isTrue);
      expect(await handle.outcome, isA<MutationDiscarded<String>>());
    });
  });
}

class _AlwaysOffline implements Network {
  const _AlwaysOffline();

  @override
  bool get isOnline => false;
}
