import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncache/syncache.dart';
import 'package:syncache_flutter/syncache_flutter.dart';

void main() {
  testWidgets('PaginatedCacheBuilder renders state and forwards loadMore',
      (tester) async {
    var callCount = 0;
    Future<PageResult<String>> fetchPage(Object? pageKey) async {
      callCount++;
      if (pageKey == null) {
        return const PageResult<String>(['a', 'b'], nextPageKey: 'p2');
      }
      return const PageResult<String>(['c'], nextPageKey: null);
    }

    final cache = Syncache<List<String>>(store: MemoryStore<List<String>>());
    addTearDown(cache.dispose);
    final paginated = PaginatedCache<String>(
      cache: cache,
      key: 'items',
      fetchPage: fetchPage,
    );
    addTearDown(paginated.dispose);

    final capturedStates = <PagedViewState<String>>[];
    late VoidCallback capturedLoadMore;

    await tester.pumpWidget(
      MaterialApp(
        home: PaginatedCacheBuilder<String>(
          paginated: paginated,
          builder: (context, state, loadMore) {
            capturedStates.add(state);
            capturedLoadMore = loadMore;
            return Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                children: [
                  Text('items: ${state.items.length}'),
                  Text('hasMore: ${state.hasMore}'),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Seeded empty, then rehydrated (still empty — nothing stored yet).
    expect(find.text('items: 0'), findsOneWidget);
    expect(find.text('hasMore: true'), findsOneWidget);
    expect(callCount, 0, reason: 'no fetch until loadMore is called');

    // The app owns the scroll wiring; here we just invoke the callback.
    capturedLoadMore();
    await tester.pumpAndSettle();

    expect(callCount, 1);
    expect(find.text('items: 2'), findsOneWidget);

    capturedLoadMore();
    await tester.pumpAndSettle();

    expect(callCount, 2);
    expect(find.text('items: 3'), findsOneWidget);
    expect(find.text('hasMore: false'), findsOneWidget);
    expect(capturedStates.last.items, ['a', 'b', 'c']);
  });

  testWidgets('PaginatedCacheBuilder rebuilds on external window mutations',
      (tester) async {
    Future<PageResult<String>> fetchPage(Object? pageKey) async =>
        const PageResult<String>(['a'], nextPageKey: null);

    final cache = Syncache<List<String>>(store: MemoryStore<List<String>>());
    addTearDown(cache.dispose);
    final paginated = PaginatedCache<String>(
      cache: cache,
      key: 'items',
      fetchPage: fetchPage,
    );
    addTearDown(paginated.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: PaginatedCacheBuilder<String>(
          paginated: paginated,
          builder: (context, state, loadMore) =>
              Text('items: ${state.items.join(",")}'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await paginated.loadMore();
    await tester.pumpAndSettle();
    expect(find.text('items: a'), findsOneWidget);

    // A mutation on the window (outside PaginatedCache) is picked up.
    await cache.mutateList(
      key: 'items',
      operation: const ListOperation.append('b'),
      send: () async {},
    );
    await tester.pumpAndSettle();
    expect(find.text('items: a,b'), findsOneWidget);
  });

  testWidgets('resubscribes when the paginated instance changes',
      (tester) async {
    Future<PageResult<String>> fetchPage(Object? pageKey) async =>
        PageResult<String>(['${pageKey ?? 'first'}'], nextPageKey: null);

    final cache = Syncache<List<String>>(store: MemoryStore<List<String>>());
    addTearDown(cache.dispose);
    final first = PaginatedCache<String>(
      cache: cache,
      key: 'items',
      fetchPage: fetchPage,
    );
    final second = PaginatedCache<String>(
      cache: cache,
      key: 'other',
      fetchPage: fetchPage,
    );
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: PaginatedCacheBuilder<String>(
          paginated: first,
          builder: (context, state, loadMore) =>
              Text('items: ${state.items.length}'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('items: 0'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: PaginatedCacheBuilder<String>(
          paginated: second,
          builder: (context, state, loadMore) =>
              Text('items: ${state.items.length}'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Old subscription must be silent; new instance drives the widget.
    await first.loadMore();
    await tester.pumpAndSettle();
    expect(
      find.text('items: 0'),
      findsOneWidget,
      reason: 'the detached instance no longer rebuilds the widget',
    );

    await second.loadMore();
    await tester.pumpAndSettle();
    expect(find.text('items: 1'), findsOneWidget);
  });
}
