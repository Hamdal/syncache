import 'dart:async';

import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

/// Simulates being offline (a failed page fetch).
class OfflineException implements Exception {
  const OfflineException();
  @override
  String toString() => 'OfflineException';
}

/// Controllable page fetcher: scripted responses per page key, call
/// recording, optional gating (to hold a fetch in flight) and failures.
class PageFetcher {
  final responses = <Object?, PageResult<String>>{};
  final List<Object?> requested = [];
  Completer<void>? gate;
  Exception? Function(Object? pageKey)? thrower;

  Future<PageResult<String>> fetch(Object? pageKey) async {
    requested.add(pageKey);
    final hold = gate;
    if (hold != null) await hold.future;
    final error = thrower?.call(pageKey);
    if (error != null) throw error;
    return responses[pageKey] ??
        PageResult<String>(const <String>[], nextPageKey: null);
  }
}

/// Records store events to verify dynamic observer registration.
class RecordingObserver extends SyncacheObserver {
  final List<String> stores = [];
  @override
  void onStore(String key) => stores.add(key);
}

void main() {
  /// Pumps the event loop until [condition] holds (or fails after a bound).
  ///
  /// External store events are coalesced on microtasks; a single pump is
  /// not deterministic enough.
  Future<void> pumpUntil(bool Function() condition,
      {int maxPumps = 200}) async {
    for (var i = 0; i < maxPumps && !condition(); i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  const windowKey = 'posts?feed=home';
  const firstKey = null;

  group('PaginatedCache', () {
    late Syncache<List<String>> cache;
    late PageFetcher fetcher;
    late PaginatedCache<String> paginated;

    setUp(() {
      cache = Syncache<List<String>>(store: MemoryStore<List<String>>());
      fetcher = PageFetcher();
      fetcher.responses[firstKey] =
          const PageResult<String>(['a', 'b', 'c'], nextPageKey: 'p2');
      fetcher.responses['p2'] =
          const PageResult<String>(['d', 'e'], nextPageKey: null);
      paginated = PaginatedCache<String>(
        cache: cache,
        key: windowKey,
        fetchPage: fetcher.fetch,
      );
    });

    tearDown(() {
      paginated.dispose();
      cache.dispose();
    });

    test('loadMore appends pages in order and closes at the last page',
        () async {
      await paginated.loadMore();
      expect(paginated.state.items, ['a', 'b', 'c']);
      expect(paginated.state.hasMore, isTrue);
      expect(paginated.state.isLoadingMore, isFalse);

      await paginated.loadMore();
      expect(paginated.state.items, ['a', 'b', 'c', 'd', 'e']);
      expect(paginated.state.hasMore, isFalse);

      final callsAfterEnd = fetcher.requested.length;
      await paginated.loadMore();
      expect(fetcher.requested.length, callsAfterEnd,
          reason: 'loadMore past the end does not fetch');
      expect(paginated.state.items, ['a', 'b', 'c', 'd', 'e']);
    });

    test('the watch stream is seeded and emits on changes', () async {
      final events = <PagedViewState<String>>[];
      final sub = paginated.watch.listen(events.add);
      addTearDown(sub.cancel);

      await paginated.loadMore();
      await pumpUntil(() => events.any((s) => s.items.isNotEmpty));

      expect(events.first.items, isEmpty, reason: 'seeded with current state');
      expect(events.last.items, ['a', 'b', 'c']);
    });

    test('maxItems trims from the front and leaves the cursor alone', () async {
      final trimmed = PaginatedCache<String>(
        cache: cache,
        key: windowKey,
        fetchPage: fetcher.fetch,
        maxItems: 2,
      );
      addTearDown(trimmed.dispose);

      // p1: a,b,c (next p2) — trimmed to [b,c]
      // p2: d (next p3)    — trimmed to [c,d]
      fetcher.responses['p2'] =
          const PageResult<String>(['d'], nextPageKey: 'p3');
      fetcher.responses['p3'] =
          const PageResult<String>(['x'], nextPageKey: null);

      await trimmed.loadMore();
      expect(trimmed.state.items, ['b', 'c']);

      await trimmed.loadMore();
      expect(trimmed.state.items, ['c', 'd'],
          reason: 'trim keeps the last maxItems, not the newest pages');

      await trimmed.loadMore();
      expect(fetcher.requested, [firstKey, 'p2', 'p3'],
          reason: 'the cursor advances regardless of trimming');
      expect(trimmed.state.items, ['d', 'x']);
    });

    test('external invalidation drops the tail and refetches page 1', () async {
      await paginated.loadMore(); // window [a,b,c]
      fetcher.responses[firstKey] =
          const PageResult<String>(['z'], nextPageKey: null);

      await cache.invalidatePattern('posts?*');
      await pumpUntil(() =>
          paginated.state.items.isEmpty &&
          paginated.state.hasMore &&
          fetcher.requested.length == 2);

      expect(paginated.state.items, ['z'],
          reason: 'the fresh first page replaces the window; tail is gone');
      expect(paginated.state.hasMore, isFalse);
      expect(fetcher.requested, [firstKey, firstKey]);
    });

    test(
        'autoRefreshOnInvalidation=false resets state without fetching, '
        'and the next loadMore appends page 1 to the emptied window', () async {
      // One instance per key: the setUp instance (auto-refresh) must not
      // observe this key while `manual` is under test.
      paginated.dispose();

      final manual = PaginatedCache<String>(
        cache: cache,
        key: windowKey,
        fetchPage: fetcher.fetch,
        autoRefreshOnInvalidation: false,
      );
      addTearDown(manual.dispose);

      await manual.loadMore(); // [a,b,c]
      expect(manual.state.items, ['a', 'b', 'c']);

      await cache.invalidatePattern('posts?*');
      await pumpUntil(() => manual.state.items.isEmpty);

      expect(fetcher.requested.length, 1, reason: 'no automatic refetch');
      expect(manual.state.hasMore, isTrue, reason: 'paging state reset');
      expect(manual.state.error, isNull);

      fetcher.responses[firstKey] =
          const PageResult<String>(['z'], nextPageKey: null);
      await manual.loadMore();
      expect(manual.state.items, ['z']);
      expect(fetcher.requested.length, 2);
    });

    test('eviction resets the paging state but never refetches', () async {
      final smallCache = Syncache<List<String>>(
        store: MemoryStore<List<String>>(maxLength: 2),
      );
      addTearDown(smallCache.dispose);
      final paged = PaginatedCache<String>(
        cache: smallCache,
        key: windowKey,
        fetchPage: fetcher.fetch,
      );
      addTearDown(paged.dispose);

      await paged.loadMore(); // window stored under windowKey
      expect(paged.state.items, ['a', 'b', 'c']);
      final callsBefore = fetcher.requested.length;

      // Overflow the bounded store: our window is the LRU entry.
      await smallCache.set(key: 'o1', value: <String>['1']);
      await smallCache.set(key: 'o2', value: <String>['2']);
      await pumpUntil(() => paged.state.items.isEmpty);

      expect(fetcher.requested.length, callsBefore,
          reason: 'eviction is a capacity event — no refill');
      expect(paged.state.hasMore, isTrue);
      expect(await smallCache.store.read(windowKey), isNull);
    });

    test('refresh merges the fresh page at the front and dedupes the tail',
        () async {
      await paginated.loadMore();
      await paginated.loadMore(); // [a,b,c,d,e], hasMore false

      // Refreshed page 1: 'c' still present (equal item), 'x' new.
      fetcher.responses[firstKey] =
          const PageResult<String>(['c', 'x'], nextPageKey: 'p2');

      await paginated.refresh();
      expect(paginated.state.items, ['c', 'x', 'a', 'b', 'd', 'e'],
          reason: 'fresh wins at the front; equal tail item dropped, '
              'tail order preserved');
      expect(paginated.state.hasMore, isTrue,
          reason: 'hasMore re-opens per the fresh page');

      // Appends still do not dedupe.
      await paginated.loadMore();
      expect(paginated.state.items, ['c', 'x', 'a', 'b', 'd', 'e', 'd', 'e']);
    });

    test('optimistic list mutations are visible in state and store', () async {
      await paginated.loadMore(); // [a,b,c]

      await cache.mutateList(
        key: windowKey,
        operation: ListOperation.append('new'),
        send: () async {},
      );
      await pumpUntil(() => paginated.state.items.contains('new'));

      expect(paginated.state.items, ['a', 'b', 'c', 'new']);
      final stored = await cache.store.read(windowKey);
      expect(stored!.value, ['a', 'b', 'c', 'new']);

      await cache.mutateList(
        key: windowKey,
        operation: ListOperation.removeWhere((item) => item == 'b'),
        send: () async {},
      );
      await pumpUntil(() => !paginated.state.items.contains('b'));
      expect(paginated.state.items, ['a', 'c', 'new']);
    });

    test('restart rule: rehydrated window + loadMore refresh-merges', () async {
      await paginated.loadMore(); // [a,b,c] persisted
      paginated.dispose();

      // "Process restart": a fresh instance over the same cache + key.
      final revived = PaginatedCache<String>(
        cache: cache,
        key: windowKey,
        fetchPage: fetcher.fetch,
      );
      addTearDown(revived.dispose);
      await pumpUntil(() => revived.state.items.isNotEmpty);
      expect(revived.state.items, ['a', 'b', 'c']);
      expect(revived.state.hasMore, isTrue, reason: 'cursor was in-memory');

      fetcher.responses[firstKey] =
          const PageResult<String>(['z'], nextPageKey: 'p2');
      await revived.loadMore();

      expect(fetcher.requested, [firstKey, firstKey],
          reason: 'cursor reset to the first page key');
      expect(revived.state.items, ['z', 'a', 'b', 'c'],
          reason: 'refresh-merge, never a duplicate append');
    });

    test('failed loadMore keeps window + cursor, never throws, and retries',
        () async {
      await paginated.loadMore(); // [a,b,c]
      fetcher.thrower =
          (pageKey) => pageKey == 'p2' ? const OfflineException() : null;

      await expectLater(paginated.loadMore(), completes,
          reason: 'fetch failures surface in state, never as errors');
      expect(paginated.state.error, isA<OfflineException>());
      expect(paginated.state.items, ['a', 'b', 'c']);
      expect(paginated.state.hasMore, isTrue);

      // Cursor unchanged → the retry re-fetches the same page.
      fetcher.thrower = null;
      fetcher.responses['p2'] =
          const PageResult<String>(['d'], nextPageKey: null);
      await paginated.loadMore();
      expect(fetcher.requested, [firstKey, 'p2', 'p2']);
      expect(paginated.state.items, ['a', 'b', 'c', 'd']);
      expect(paginated.state.error, isNull);
    });

    test('concurrent loadMore calls coalesce into one fetch', () async {
      fetcher.gate = Completer<void>();
      final f1 = paginated.loadMore();
      final f2 = paginated.loadMore();
      expect(identical(f1, f2), isTrue, reason: 'same in-flight future');
      await pumpUntil(() => fetcher.requested.length == 1);
      expect(fetcher.requested.length, 1);

      fetcher.gate!.complete();
      await Future.wait([f1, f2]);
      expect(fetcher.requested.length, 1);
      expect(paginated.state.items, ['a', 'b', 'c']);
    });

    test('invalidation during an in-flight fetch discards the stale result',
        () async {
      fetcher.gate = Completer<void>();
      final load = paginated.loadMore(); // hangs on the gate
      await pumpUntil(() => fetcher.requested.length == 1);
      expect(fetcher.requested.length, 1);

      // Invalidate while the fetch is in flight; auto-refresh enqueues a
      // second fetch (also gated).
      fetcher.responses[firstKey] =
          const PageResult<String>(['z'], nextPageKey: null);
      final invalidateDone = cache.invalidatePattern('posts?*');
      await pumpUntil(() => fetcher.requested.length == 2);
      fetcher.gate!.complete();

      await load;
      await invalidateDone;
      await pumpUntil(() =>
          paginated.state.items.length == 1 && !paginated.state.isRefreshing);

      expect(paginated.state.items, ['z'],
          reason: 'the pre-invalidation page result was discarded');
    });

    test('dispose keeps the stored window, closes the stream, stops fetches',
        () async {
      await paginated.loadMore();

      final done = Completer<void>();
      paginated.watch.listen((_) {}, onDone: done.complete);

      paginated.dispose();
      await done.future;

      final stored = await cache.store.read(windowKey);
      expect(stored!.value, ['a', 'b', 'c'], reason: 'window survives');

      await paginated.loadMore();
      expect(fetcher.requested.length, 1, reason: 'no fetches after dispose');
      expect(paginated.watch, emitsDone);
    });

    test(
        'one instance per key is the caller\'s contract — two instances '
        'each seed/fetch independently (documented, not guarded)', () async {
      final second = PaginatedCache<String>(
        cache: cache,
        key: 'other',
        fetchPage: fetcher.fetch,
      );
      addTearDown(second.dispose);
      await second.loadMore();
      // Just proves a second key works alongside the first.
      expect(second.state.items, ['a', 'b', 'c']);
      expect(paginated.state.items, isEmpty,
          reason: 'instances over different keys are independent');
    });
  });

  group('Syncache.addObserver / removeObserver', () {
    test('dynamic observers receive events until removed', () async {
      final cache = Syncache<String>(store: MemoryStore<String>());
      addTearDown(cache.dispose);
      final observer = RecordingObserver();

      cache.addObserver(observer);
      await cache.set(key: 'k', value: 'v1');
      expect(observer.stores, ['k']);

      cache.removeObserver(observer);
      await cache.set(key: 'k', value: 'v2');
      expect(observer.stores, ['k'],
          reason: 'removed observers receive no further events');
    });

    test('dynamic observers see PaginatedCache-relevant invalidation events',
        () async {
      final cache = Syncache<String>(store: MemoryStore<String>());
      addTearDown(cache.dispose);
      final observer = RecordingObserver();
      cache.addObserver(observer);

      await cache.set(key: 'user:1', value: 'a');
      await cache.invalidatePattern('user:*');
      expect(observer.stores, ['user:1']);
    });

    test('removeObserver of an unknown observer is a no-op', () {
      final cache = Syncache<String>(store: MemoryStore<String>());
      addTearDown(cache.dispose);
      cache.removeObserver(RecordingObserver());
    });
  });
}
