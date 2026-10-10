import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

/// Tests for the Milestone 2 invalidation semantics: invalidation must NOT
/// close watch streams. Instead, active watchers are refetched with their
/// own fetch/policy/ttl and the stream stays open in every outcome.
void main() {
  group('Invalidation refetch semantics', () {
    late MemoryStore<String> store;
    late Syncache<String> cache;

    setUp(() {
      store = MemoryStore<String>();
      cache = Syncache<String>(store: store);
    });

    tearDown(() {
      cache.dispose();
    });

    group('invalidate', () {
      test('keeps the stream open and emits the refetched value', () async {
        var serverValue = 'v1';
        final values = <String>[];
        var done = false;

        final sub = cache.watch(
          key: 'user:1',
          fetch: (_) async => serverValue,
        ).listen(
          values.add,
          onDone: () => done = true,
        );

        // Wait for the initial fetch.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(values, ['v1']);

        serverValue = 'v2';
        await cache.invalidate('user:1');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(values, ['v1', 'v2']);
        expect(done, isFalse, reason: 'stream must survive invalidation');

        await sub.cancel();
      });

      test('emits the refetch error and remains usable afterwards',
          () async {
        var shouldFail = false;
        var fetchCount = 0;
        final values = <String>[];
        final errors = <Object>[];
        var done = false;

        final sub = cache.watch(
          key: 'user:1',
          fetch: (_) async {
            fetchCount++;
            if (shouldFail) throw Exception('network down');
            return 'v$fetchCount';
          },
        ).listen(
          values.add,
          onError: errors.add,
          onDone: () => done = true,
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(values, ['v1']);

        shouldFail = true;
        await cache.invalidate('user:1');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(errors, hasLength(1));
        expect(done, isFalse, reason: 'failed refetch must not close stream');

        // The stream must still deliver updates after the failed refetch.
        shouldFail = false;
        await cache.set(key: 'user:1', value: 'recovered');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(values, ['v1', 'recovered']);
        expect(done, isFalse);

        await sub.cancel();
      });

      test('cacheOnly watcher receives CacheMissException and stays open',
          () async {
        await cache.get(
          key: 'user:1',
          fetch: (_) async => 'v1',
        );

        final errors = <Object>[];
        var done = false;

        final sub = cache.watch(
          key: 'user:1',
          fetch: (_) async => 'v1',
          policy: Policy.cacheOnly,
        ).listen(
          (_) {},
          onError: errors.add,
          onDone: () => done = true,
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(errors, isEmpty);

        await cache.invalidate('user:1');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(errors, hasLength(1));
        expect(errors.first, isA<CacheMissException>());
        expect(done, isFalse, reason: 'cacheOnly stream must stay open');

        await sub.cancel();
      });

      test('does not refetch unsubscribed watchers', () async {
        var fetchCount = 0;
        final sub = cache.watch(
          key: 'user:1',
          fetch: (_) async {
            fetchCount++;
            return 'v$fetchCount';
          },
        ).listen((_) {});

        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(fetchCount, 1);

        await sub.cancel();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        await cache.invalidate('user:1');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(fetchCount, 1,
            reason: 'cancelled watchers must not be refetched');
      });

      test('watchWithMeta receives the refetched CacheResult', () async {
        var serverValue = 'v1';
        final results = <CacheResult<String>>[];
        var done = false;

        final sub = cache.watchWithMeta(
          key: 'user:1',
          fetch: (_) async => serverValue,
        ).listen(
          results.add,
          onDone: () => done = true,
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(results, hasLength(1));

        serverValue = 'v2';
        await cache.invalidate('user:1');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(results, hasLength(2));
        expect(results.last.value, 'v2');
        expect(done, isFalse);

        await sub.cancel();
      });
    });

    group('invalidateTag', () {
      test('refetches affected watchers and keeps streams open', () async {
        await cache.get(
          key: 'event:1',
          fetch: (_) async => 'event-1',
          tags: ['events'],
        );

        var serverValue = 'event-1-fresh';
        final values = <String>[];
        var done = false;

        final sub = cache.watch(
          key: 'event:1',
          fetch: (_) async => serverValue,
        ).listen(
          values.add,
          onDone: () => done = true,
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
        final initialCount = values.length;

        await cache.invalidateTag('events');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(values.length, greaterThan(initialCount));
        expect(values.last, 'event-1-fresh');
        expect(done, isFalse);

        await sub.cancel();
      });
    });

    group('invalidatePattern', () {
      test('refetches affected watchers and keeps streams open', () async {
        await cache.get(
          key: 'user:1',
          fetch: (_) async => 'u1',
          tags: ['users'],
        );
        await cache.get(
          key: 'user:2',
          fetch: (_) async => 'u2',
          tags: ['users'],
        );

        var serverValue = 'fresh';
        final user1Values = <String>[];
        final user2Values = <String>[];

        final sub1 = cache.watch(
          key: 'user:1',
          fetch: (_) async => serverValue,
        ).listen(user1Values.add);
        final sub2 = cache.watch(
          key: 'user:2',
          fetch: (_) async => serverValue,
        ).listen(user2Values.add);

        await Future<void>.delayed(const Duration(milliseconds: 20));

        serverValue = 'refreshed';
        await cache.invalidatePattern('user:*');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(user1Values.last, 'refreshed');
        expect(user2Values.last, 'refreshed');

        await sub1.cancel();
        await sub2.cancel();
      });
    });

    group('clear', () {
      test('refetches all watchers by default', () async {
        await cache.get(
          key: 'user:1',
          fetch: (_) async => 'u1',
        );

        var serverValue = 'u1';
        final values = <String>[];
        var done = false;

        final sub = cache.watch(
          key: 'user:1',
          fetch: (_) async => serverValue,
        ).listen(
          values.add,
          onDone: () => done = true,
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));

        serverValue = 'after-clear';
        await cache.clear();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(values.last, 'after-clear');
        expect(done, isFalse);

        await sub.cancel();
      });

      test('with refetchWatchers=false keeps streams open and silent',
          () async {
        await cache.get(
          key: 'user:1',
          fetch: (_) async => 'u1',
        );

        var fetchCount = 0;
        final values = <String>[];
        final errors = <Object>[];
        var done = false;

        final sub = cache.watch(
          key: 'user:1',
          fetch: (_) async {
            fetchCount++;
            return 'u$fetchCount';
          },
          // networkOnly so the initial load performs a real fetch; the test
          // then proves that clear(refetchWatchers: false) causes no further
          // fetches.
          policy: Policy.networkOnly,
        ).listen(
          values.add,
          onError: errors.add,
          onDone: () => done = true,
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
        final valuesAfterInitial = values.length;
        final fetchCountAfterInitial = fetchCount;

        await cache.clear(refetchWatchers: false);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(values.length, valuesAfterInitial,
            reason: 'no refetch, no events');
        expect(errors, isEmpty);
        expect(done, isFalse, reason: 'stream must not close on clear');
        expect(fetchCount, fetchCountAfterInitial,
            reason: 'cancelled watchers must not be refetched');

        await sub.cancel();
      });
    });

    group('watchWithDependencies', () {
      test('is refetched when its own key is invalidated', () async {
        var serverValue = 'events-v1';
        final values = <String>[];
        var done = false;

        final sub = cache.watchWithDependencies(
          key: 'events',
          fetch: (_) async => serverValue,
          refetchWhen: ['workspace:current'],
        ).listen(
          values.add,
          onDone: () => done = true,
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(values, ['events-v1']);

        serverValue = 'events-v2';
        await cache.invalidate('events');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(values.last, 'events-v2');
        expect(done, isFalse);

        await sub.cancel();
      });
    });
  });
}
