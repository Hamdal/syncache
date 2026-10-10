import 'dart:async';

import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

/// Tests for the seeded mutation-queue streams: `pendingMutationsStream`
/// and `isSyncedStream` must emit their current state to every new
/// listener before any live updates, so late subscribers (e.g. a sync
/// indicator built after the mutations were queued) see the present state
/// immediately.
void main() {
  group('Mutation queue streams', () {
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

    group('pendingMutationsStream', () {
      test('late subscriber sees the current pending list immediately',
          () async {
        await seedValue('k');

        // Hold the in-flight send so the queue stays occupied.
        final gate = Completer<String>();
        await cache.mutate(
          key: 'k',
          mutation: Mutation<String>(
            apply: (v) => 'm1',
            send: (_) => gate.future,
          ),
        );
        await cache.mutate(
          key: 'k',
          mutation: Mutation<String>(
            apply: (v) => 'm2',
            send: (_) async => 'done',
          ),
        );
        expect(cache.pendingMutationCount, 2);

        final emissions = <List<PendingMutationInfo>>[];
        final sub = cache.pendingMutationsStream.listen(emissions.add);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(emissions, isNotEmpty,
            reason: 'late subscriber must be seeded');
        expect(emissions.first, hasLength(2));
        expect(
          emissions.first.map((m) => m.key),
          everyElement('k'),
        );

        gate.complete('server');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(cache.pendingMutationCount, 0);

        await sub.cancel();
      });

      test('late subscriber sees an empty list when queue is drained',
          () async {
        await seedValue('k');
        await cache.mutate(
          key: 'k',
          mutation: Mutation<String>(
            apply: (v) => 'm1',
            send: (_) async => 'server',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(cache.pendingMutationCount, 0);

        final emissions = <List<PendingMutationInfo>>[];
        final sub = cache.pendingMutationsStream.listen(emissions.add);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(emissions.first, isEmpty);

        await sub.cancel();
      });

      test('live updates still arrive after the seed', () async {
        await seedValue('k');

        final emissions = <List<PendingMutationInfo>>[];
        final sub = cache.pendingMutationsStream.listen(emissions.add);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final seededLength = emissions.first.length;

        await cache.mutate(
          key: 'k',
          mutation: Mutation<String>(
            apply: (v) => 'm1',
            send: (_) async => 'server',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Seed (empty), then pending during processing, then drained. The
        // queue was seeded empty, so subsequent emissions must exist.
        expect(emissions.length, greaterThan(seededLength));
        expect(emissions.last, isEmpty);

        await sub.cancel();
      });

      test('multiple subscribers are each seeded independently', () async {
        await seedValue('k');

        final gate = Completer<String>();
        await cache.mutate(
          key: 'k',
          mutation: Mutation<String>(
            apply: (v) => 'm1',
            send: (_) => gate.future,
          ),
        );

        final emissions1 = <List<PendingMutationInfo>>[];
        final emissions2 = <List<PendingMutationInfo>>[];
        final sub1 = cache.pendingMutationsStream.listen(emissions1.add);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final sub2 = cache.pendingMutationsStream.listen(emissions2.add);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(emissions1.first, hasLength(1));
        expect(emissions2.first, hasLength(1),
            reason: 'second late subscriber must also be seeded');

        gate.complete('server');
        await sub1.cancel();
        await sub2.cancel();
      });
    });

    group('isSyncedStream', () {
      test('emits false immediately when there are pending mutations',
          () async {
        await seedValue('k');

        final gate = Completer<String>();
        await cache.mutate(
          key: 'k',
          mutation: Mutation<String>(
            apply: (v) => 'm1',
            send: (_) => gate.future,
          ),
        );

        final emissions = <bool>[];
        final sub = cache.isSyncedStream.listen(emissions.add);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(emissions.first, isFalse,
            reason: 'seeded state must be false while mutations are pending');

        gate.complete('server');
        await sub.cancel();
      });

      test('emits true after the queue drains', () async {
        await seedValue('k');

        final gate = Completer<String>();
        await cache.mutate(
          key: 'k',
          mutation: Mutation<String>(
            apply: (v) => 'm1',
            send: (_) => gate.future,
          ),
        );

        final emissions = <bool>[];
        final sub = cache.isSyncedStream.listen(emissions.add);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(emissions.first, isFalse);

        gate.complete('server');
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(emissions, contains(true));
        expect(emissions.last, isTrue);

        await sub.cancel();
      });

      test('late subscriber is seeded true when nothing is pending',
          () async {
        await seedValue('k');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final emissions = <bool>[];
        final sub = cache.isSyncedStream.listen(emissions.add);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(emissions, [true]);

        await sub.cancel();
      });
    });
  });
}
