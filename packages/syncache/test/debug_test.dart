import 'dart:async';
import 'dart:convert';

import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

/// A Network implementation that is always offline.
class _OfflineNetwork implements Network {
  @override
  bool get isOnline => false;
}

void main() {
  group('debugSnapshot / SyncacheDebug', () {
    late Syncache<String> cache;
    late MemoryStore<String> store;

    setUp(() {
      store = MemoryStore<String>();
      cache = Syncache<String>(store: store);
    });

    test('lists registered watchers with policy and ttl', () async {
      cache.watch(
        key: 'w1',
        fetch: (_) async => 'v',
        policy: Policy.staleWhileRefresh,
        ttl: const Duration(minutes: 3),
      );
      cache.watchWithMeta(key: 'w2', fetch: (_) async => 'v');

      final dump = await cache.debugSnapshot();
      final watchers = dump['watchers']! as List<Map<String, Object?>>;

      final w1 = watchers.firstWhere((w) => w['key'] == 'w1');
      expect(w1['kind'], equals('value'));
      expect(w1['policy'], equals('staleWhileRefresh'));
      expect(w1['ttlMs'], equals(const Duration(minutes: 3).inMilliseconds));

      final w2 = watchers.firstWhere((w) => w['key'] == 'w2');
      expect(w2['kind'], equals('meta'));
    });

    test('lists in-flight fetch keys while a fetch is pending', () async {
      final gate = Completer<void>();
      final fetchDone = cache.get(
        key: 'slow',
        fetch: (_) async {
          await gate.future;
          return 'v';
        },
      );

      // Let the fetch start.
      await Future<void>.delayed(Duration.zero);

      final dump = await cache.debugSnapshot();
      expect(dump['inFlightFetches'], contains('slow'));

      gate.complete();
      await fetchDone;

      final after = await cache.debugSnapshot();
      expect(after['inFlightFetches'], isNot(contains('slow')));
    });

    test('lists pending mutations with id, key, status, retries and error',
        () async {
      final offline = Syncache<String>(
        store: store,
        network: _OfflineNetwork(),
      );
      await offline.set(key: 'k', value: 'v');
      await offline.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (v) => '$v!',
          send: (v) async => v,
        ),
      );

      // Offline: the process pass bails out immediately, so the mutation
      // stays queued — and the dump must reflect exactly that live state.
      final live = offline.pendingMutationsSnapshot.single;
      final dump = await offline.debugSnapshot();
      final pending = dump['pendingMutations']! as List<Map<String, Object?>>;
      expect(pending, hasLength(1));
      expect(pending.first['key'], equals('k'));
      expect(pending.first['id'], equals(live.id));
      expect(pending.first['status'], equals('pending'));
      expect(pending.first['retryCount'], equals(0));
      expect(pending.first['lastError'], isNull);

      offline.dispose();
    });

    test('includes stats counters', () async {
      await cache.get(key: 'k', fetch: (_) async => 'v');
      final dump = await cache.debugSnapshot();
      final stats = dump['stats']! as Map<String, Object?>;

      expect(stats['stores'], equals(1));
      expect(stats['entryCount'], equals(1));
      expect(stats['hits'], equals(0));
    });

    test('includes store entry count and sample keys', () async {
      for (var i = 0; i < 25; i++) {
        await cache.set(key: 'k$i', value: 'v$i');
      }

      final dump = await cache.debugSnapshot();
      final storeInfo = dump['store']! as Map<String, Object?>;
      expect(storeInfo['entryCount'], equals(25));
      expect((storeInfo['sampleKeys']! as List).length, equals(20),
          reason: 'sample keys are capped at the default limit');

      final limited = await cache.debugSnapshot(sampleKeyLimit: 5);
      expect(
        ((limited['store']! as Map<String, Object?>)['sampleKeys']! as List)
            .length,
        equals(5),
      );
    });

    test('dump is fully JSON-encodable', () async {
      final offline = Syncache<String>(
        store: store,
        network: _OfflineNetwork(),
      );
      await offline.set(key: 'k', value: 'v');
      await offline.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (v) => '$v!',
          send: (v) async => v,
        ),
      );
      offline.watch(
        key: 'w',
        fetch: (_) async => 'v',
        policy: Policy.refresh,
        ttl: const Duration(seconds: 30),
      );

      final json = await SyncacheDebug.dumpJson(offline);
      expect(json, isA<String>());
      final decoded = jsonDecode(json) as Map<String, Object?>;
      expect(
          decoded.keys,
          containsAll([
            'watchers',
            'inFlightFetches',
            'pendingMutations',
            'stats',
            'store'
          ]));

      offline.dispose();
    });

    test('SyncacheDebug instance facade delegates to the cache', () async {
      await cache.set(key: 'k', value: 'v');

      final debug = SyncacheDebug(cache);
      final dump = await debug.dump();
      expect(
        (dump['store']! as Map<String, Object?>)['entryCount'],
        equals(1),
      );

      final viaStatic = await SyncacheDebug.dumpOf(cache);
      expect(viaStatic['store'], equals(dump['store']));
    });

    test('throws StateError after dispose', () async {
      cache.dispose();
      expect(cache.debugSnapshot(), throwsStateError);
    });
  });
}
