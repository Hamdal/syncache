import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncache/syncache.dart';
import 'package:syncache_flutter/syncache_flutter.dart';

/// A Network implementation that is always offline — keeps mutations in the
/// queue so the inspector has something to render.
class _OfflineNetwork implements Network {
  @override
  bool get isOnline => false;
}

void main() {
  group('SyncacheInspectorScreen', () {
    late Syncache<String> cache;
    late MemoryStore<String> store;

    setUp(() {
      store = MemoryStore<String>();
      cache = Syncache<String>(store: store, network: _OfflineNetwork());
    });

    Future<void> pumpScreen(WidgetTester tester) {
      return tester.pumpWidget(
        MaterialApp(home: SyncacheInspectorScreen<String>(cache: cache)),
      );
    }

    testWidgets('renders stats, entries, and the raw dump', (tester) async {
      await cache.set(key: 'user:1', value: 'alice');
      await cache.get(key: 'user:1', fetch: (_) async => 'alice');

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      expect(find.text('Stats'), findsOneWidget);
      expect(find.text('Entries (1)'), findsOneWidget);
      expect(find.text('version 1'), findsOneWidget);
      expect(find.text('Raw dump'), findsOneWidget);
      expect(find.textContaining('"user:1"'), findsOneWidget);
      expect(find.text('Pending mutations (0)'), findsOneWidget);
    });

    testWidgets('renders pending mutations from the live queue',
        (tester) async {
      await cache.set(key: 'k', value: 'v');
      await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (v) => '$v!',
          send: (v) async => v,
        ),
      );
      final live = cache.pendingMutationsSnapshot.single;

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      expect(find.text('Pending mutations (1)'), findsOneWidget);
      expect(find.byKey(ValueKey('mutation-${live.id}')), findsOneWidget);
    });

    testWidgets('discard removes exactly one mutation', (tester) async {
      await cache.set(key: 'k1', value: 'v1');
      await cache.set(key: 'k2', value: 'v2');
      await cache.mutate(
        key: 'k1',
        mutation: Mutation<String>(apply: (v) => v, send: (v) async => v),
      );
      await cache.mutate(
        key: 'k2',
        mutation: Mutation<String>(apply: (v) => v, send: (v) async => v),
      );
      final firstId = cache.pendingMutationsSnapshot.first.id;
      expect(cache.pendingMutationCount, equals(2));

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ValueKey('discard-$firstId')));
      await tester.pumpAndSettle();

      expect(cache.pendingMutationCount, equals(1));
      expect(
        cache.removePendingMutation(firstId),
        isFalse,
        reason: 'the discarded id must be gone',
      );
    });

    testWidgets('clear cache button wipes entries', (tester) async {
      await cache.set(key: 'k', value: 'v');

      await pumpScreen(tester);
      await tester.pumpAndSettle();
      expect(find.text('Entries (1)'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('inspector_clear_cache')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('inspector_clear_cache')));
      await tester.pumpAndSettle();

      expect(await store.read('k'), isNull);
      expect(find.text('Entries (0)'), findsOneWidget);
    });

    testWidgets('retry-all button is enabled only with pending mutations',
        (tester) async {
      await pumpScreen(tester);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('inspector_retry_all')),
            )
            .onPressed,
        isNull,
      );

      await cache.set(key: 'k', value: 'v');
      await cache.mutate(
        key: 'k',
        mutation: Mutation<String>(apply: (v) => v, send: (v) async => v),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('inspector_retry_all')),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('refresh button rebuilds data sections', (tester) async {
      await pumpScreen(tester);
      await tester.pumpAndSettle();
      expect(find.text('Entries (0)'), findsOneWidget);

      await cache.set(key: 'late', value: 'v');
      await tester.tap(find.byKey(const ValueKey('inspector_refresh')));
      await tester.pumpAndSettle();

      expect(find.text('Entries (1)'), findsOneWidget);
    });
  });
}
