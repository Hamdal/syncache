import 'dart:async';

import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

void main() {
  group('SyncacheEntry', () {
    late Syncache<String> cache;
    late MemoryStore<String> store;

    setUp(() {
      store = MemoryStore<String>();
      cache = Syncache<String>(store: store);
    });

    group('get', () {
      test('fetches, caches, and hits cache — parity with cache.get', () async {
        var fetchCount = 0;
        final entry = cache.entry(
          'user:1',
          fetch: (_) async => 'v-${++fetchCount}',
          ttl: const Duration(minutes: 5),
        );

        expect(await entry.get(), equals('v-1'));
        expect(fetchCount, equals(1));

        // Cached under the bound key with the bound TTL.
        final stored = await store.read('user:1');
        expect(stored, isNotNull);
        expect(stored!.value, equals('v-1'));
        expect(stored.meta.ttl, equals(const Duration(minutes: 5)));

        // Second read is served from cache (fresh, not expired).
        expect(await entry.get(), equals('v-1'));
        expect(fetchCount, equals(1));
      });

      test('bound ttl expires entries', () async {
        final entry = cache.entry(
          'k',
          fetch: (_) async => 'fresh',
          ttl: const Duration(milliseconds: 50),
        );

        await entry.get();
        await Future<void>.delayed(const Duration(milliseconds: 60));

        // Expired: offlineFirst refetches.
        expect(await entry.get(), equals('fresh'));
        expect((await store.read('k'))!.meta.version, equals(2));
      });

      test('per-call policy override does not mutate the bound policy',
          () async {
        var fetchCount = 0;
        final entry = cache.entry(
          'k',
          fetch: (_) async => 'v-${++fetchCount}',
        );

        await entry.get();
        expect(
          await entry.get(policy: Policy.networkOnly),
          equals('v-2'),
        );
        // Bound policy (offlineFirst) still applies on the next call.
        expect(await entry.get(), equals('v-2'));
        expect(fetchCount, equals(2));
      });

      test('bound tags are written on fetch', () async {
        final entry = cache.entry(
          'k',
          fetch: (_) async => 'v',
          tags: ['users'],
        );

        await entry.get();

        expect(await store.getKeysByTag('users'), contains('k'));
      });
    });

    group('getWithMeta', () {
      test('returns CacheResult with metadata — parity with getWithMeta',
          () async {
        final entry = cache.entry(
          'k',
          fetch: (_) async => 'v',
          ttl: const Duration(minutes: 1),
        );

        final result = await entry.getWithMeta();

        expect(result.value, equals('v'));
        expect(result.meta.isFromCache, isFalse);
        expect(result.meta.isStale, isFalse);

        final second = await entry.getWithMeta();
        expect(second.value, equals('v'));
        expect(second.meta.isFromCache, isTrue);
        expect(second.meta.version, equals(1));
      });
    });

    group('watch', () {
      test('emits initial value and updates — parity with cache.watch',
          () async {
        var fetchCount = 0;
        final entry = cache.entry(
          'k',
          fetch: (_) async => 'v-${++fetchCount}',
        );

        final values = <String>[];
        final sub = entry.watch().listen(values.add);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        await entry.set('direct');
        await Future<void>.delayed(Duration.zero);

        expect(values, contains('v-1'));
        expect(values, contains('direct'));

        await sub.cancel();
      });

      test('invalidation refetches the stream instead of closing it', () async {
        var fetchCount = 0;
        final entry = cache.entry(
          'k',
          fetch: (_) async => 'v-${++fetchCount}',
        );

        final values = <String>[];
        final errors = <Object>[];
        final done = Completer<void>();
        final sub = entry.watch().listen(
              values.add,
              onError: errors.add,
              onDone: done.complete,
            );
        await Future<void>.delayed(Duration.zero);

        await entry.invalidate();
        await Future<void>.delayed(Duration.zero);

        expect(values, contains('v-2'), reason: 'watcher should be refetched');
        expect(errors, isEmpty);
        expect(done.isCompleted, isFalse,
            reason: 'stream must stay open after invalidation');

        await sub.cancel();
      });

      test('watchWithMeta emits CacheResults — parity with watchWithMeta',
          () async {
        final entry = cache.entry(
          'k',
          fetch: (_) async => 'v',
          ttl: const Duration(minutes: 1),
        );

        final results = <CacheResult<String>>[];
        final sub = entry.watchWithMeta().listen(results.add);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(results, isNotEmpty);
        expect(results.first.value, equals('v'));
        expect(results.first.meta.version, equals(1));

        await entry.set('v2');
        await Future<void>.delayed(Duration.zero);

        expect(
          results.any((r) => r.value == 'v2' && r.meta.version == 2),
          isTrue,
        );

        await sub.cancel();
      });
    });

    group('refresh', () {
      test('forces a network fetch even when the cache is fresh', () async {
        var fetchCount = 0;
        final entry = cache.entry(
          'k',
          fetch: (_) async => 'v-${++fetchCount}',
        );

        await entry.get();
        expect(fetchCount, equals(1));

        expect(await entry.refresh(), equals('v-2'));
        expect(fetchCount, equals(2));
        expect((await store.read('k'))!.value, equals('v-2'));
      });

      test('falls back to cache when offline', () async {
        var fetchCount = 0;
        final offlineCache = Syncache<String>(
          store: store,
          network: _OfflineNetwork(),
        );
        final entry = offlineCache.entry(
          'k',
          fetch: (_) async => 'v-${++fetchCount}',
        );

        // Seed the cache without touching the network.
        await entry.set('seeded');

        expect(await entry.refresh(), equals('seeded'));
        expect(fetchCount, equals(0), reason: 'offline: no fetch attempted');
      });

      test('throws CacheMissException when offline with empty cache', () async {
        final offlineCache = Syncache<String>(
          store: MemoryStore<String>(),
          network: _OfflineNetwork(),
        );
        final entry = offlineCache.entry('k', fetch: (_) async => 'v');

        expect(
          entry.refresh(),
          throwsA(isA<CacheMissException>()),
        );
      });
    });

    group('set', () {
      test('writes the bound key and notifies watchers', () async {
        final entry = cache.entry('k', fetch: (_) async => 'fetched');

        final values = <String>[];
        final sub = entry.watch().listen(values.add);
        await Future<void>.delayed(Duration.zero);

        await entry.set('direct');
        await Future<void>.delayed(Duration.zero);

        expect((await store.read('k'))!.value, equals('direct'));
        expect(values, contains('direct'));

        await sub.cancel();
      });

      test('per-call ttl overrides the bound ttl', () async {
        final entry = cache.entry(
          'k',
          fetch: (_) async => 'v',
          ttl: const Duration(minutes: 5),
        );

        await entry.set('v', ttl: const Duration(hours: 1));

        expect(
          (await store.read('k'))!.meta.ttl,
          equals(const Duration(hours: 1)),
        );
      });

      test('bound ttl is used when no per-call ttl is given', () async {
        final entry = cache.entry(
          'k',
          fetch: (_) async => 'v',
          ttl: const Duration(minutes: 5),
        );

        await entry.set('v');

        expect(
          (await store.read('k'))!.meta.ttl,
          equals(const Duration(minutes: 5)),
        );
      });
    });

    group('invalidate', () {
      test('deletes the entry from the store', () async {
        final entry = cache.entry('k', fetch: (_) async => 'v');

        await entry.get();
        expect(await store.read('k'), isNotNull);

        await entry.invalidate();
        expect(await store.read('k'), isNull);
      });
    });

    group('lightweight view semantics', () {
      test('entries hold no state: two views of one key stay in sync',
          () async {
        final a = cache.entry('k', fetch: (_) async => 'a');
        final b = cache.entry('k', fetch: (_) async => 'b');

        await a.get();
        // Same underlying stored value despite different bound fetchers.
        expect(await b.get(), equals('a'));

        await b.set('from-b');
        expect(await a.get(), equals('from-b'));
      });

      test('entries are lazy: creation and writes start no fetches', () async {
        var fetchCount = 0;
        final entry = cache.entry('k', fetch: (_) async => 'v-${++fetchCount}');
        cache.entry('k2', fetch: (_) async => 'v-${++fetchCount}');

        // Creating entries and writing through them never fetches — entries
        // are passive views, all work happens on the underlying cache.
        await entry.set('x');
        await cache.set(key: 'k2', value: 'y');
        expect(fetchCount, equals(0));

        // A watch started afterwards still begins from the stored value,
        // served from cache (no fetch) by the bound policy.
        final values = <String>[];
        final sub = entry.watch().listen(values.add);
        while (!values.contains('x')) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(fetchCount, equals(0), reason: 'offlineFirst hit, no fetch');

        await sub.cancel();
      });

      test('entries remain usable after other entries are done (no dispose)',
          () async {
        final entry = cache.entry('k', fetch: (_) async => 'v');

        // Exercise every method once — none may require disposal afterwards.
        await entry.get();
        await entry.getWithMeta();
        final sub = entry.watch().listen((_) {});
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        await entry.set('v2');
        await entry.refresh();
        await entry.invalidate();

        // Entry still fully usable.
        expect(await entry.get(), equals('v'));
      });
    });

    group('scoped entries', () {
      test('ScopedSyncache.entry prefixes the key', () async {
        final scoped = cache.scoped('workspace:1');
        var fetchCount = 0;
        final entry = scoped.entry(
          'user:123',
          fetch: (_) async => 'v-${++fetchCount}',
          ttl: const Duration(minutes: 5),
        );

        await entry.get();

        // Stored under the prefixed key; nothing under the bare key.
        expect(
            (await store.read('workspace:1:user:123'))?.value, equals('v-1'));
        expect(await store.read('user:123'), isNull);
        expect(entry.key, equals('workspace:1:user:123'));
      });

      test('scoped entry operations are isolated per scope', () async {
        final ws1 = cache.scoped('workspace:1').entry(
              'k',
              fetch: (_) async => 'ws1',
            );
        final ws2 = cache.scoped('workspace:2').entry(
              'k',
              fetch: (_) async => 'ws2',
            );

        expect(await ws1.get(), equals('ws1'));
        expect(await ws2.get(), equals('ws2'));

        await ws1.set('updated');
        expect(await ws1.get(), equals('updated'));
        expect(await ws2.get(), equals('ws2'));
      });

      test('scoped entry invalidate only affects its own scope', () async {
        final ws1 = cache.scoped('workspace:1').entry(
              'k',
              fetch: (_) async => 'ws1',
            );
        final ws2 = cache.scoped('workspace:2').entry(
              'k',
              fetch: (_) async => 'ws2',
            );

        await ws1.get();
        await ws2.get();

        await ws1.invalidate();

        expect(await store.read('workspace:1:k'), isNull);
        expect(await store.read('workspace:2:k'), isNotNull);
      });

      test('scoped entry refresh/watch/set parity with root entries', () async {
        var fetchCount = 0;
        final scoped = cache.scoped('s');
        final entry = scoped.entry(
          'k',
          fetch: (_) async => 'v-${++fetchCount}',
        );

        await entry.get();
        expect(await entry.refresh(), equals('v-2'));

        final values = <String>[];
        final sub = entry.watch().listen(values.add);
        await Future<void>.delayed(Duration.zero);
        await scoped.set(key: 'k', value: 'via-scoped-cache');
        await Future<void>.delayed(Duration.zero);

        expect(values, contains('v-2'));
        expect(values, contains('via-scoped-cache'));

        await sub.cancel();
      });
    });

    group('lifecycle', () {
      test('entry methods throw StateError after cache disposal', () async {
        final entry = cache.entry('k', fetch: (_) async => 'v');
        cache.dispose();

        expect(entry.get, throwsStateError);
        expect(entry.getWithMeta, throwsStateError);
        expect(entry.watch, throwsStateError);
        expect(entry.watchWithMeta, throwsStateError);
        expect(entry.refresh(), throwsStateError);
        expect(entry.set('v'), throwsStateError);
        expect(entry.invalidate(), throwsStateError);
      });

      test('toString includes key and policy', () {
        final entry = cache.entry(
          'k',
          fetch: (_) async => 'v',
          policy: Policy.cacheOnly,
        );

        expect(entry.toString(), contains('k'));
        expect(entry.toString(), contains('Policy.cacheOnly'));
      });
    });
  });
}

/// A Network implementation that is always offline.
class _OfflineNetwork implements Network {
  @override
  bool get isOnline => false;
}
