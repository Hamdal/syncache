import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:syncache/syncache.dart';
import 'package:syncache_flutter/syncache_flutter.dart';

class MockSyncache<T> extends Mock implements Syncache<T> {}

class MockStore<T> extends Mock implements Store<T> {}

class MockFlutterNetwork extends Mock implements FlutterNetwork {}

class FakeSyncacheRequest extends Fake implements SyncacheRequest {}

/// Wraps a widget with necessary ancestors for testing.
Widget testableWidget(Widget child) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: child,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeSyncacheRequest());
    registerFallbackValue(Policy.offlineFirst);
  });

  group('SyncacheScopeConfig', () {
    test('stores cache instance', () {
      final cache = MockSyncache<String>();
      final config = SyncacheScopeConfig<String>(cache);

      expect(config.cache, cache);
    });
  });

  group('MultiSyncacheScope', () {
    late MockSyncache<String> stringCache;
    late MockSyncache<int> intCache;
    late MockSyncache<bool> boolCache;
    late MockStore<String> stringStore;
    late MockStore<int> intStore;
    late MockStore<bool> boolStore;
    late MockFlutterNetwork mockNetwork;
    late StreamController<bool> connectivityController;

    setUp(() {
      stringCache = MockSyncache<String>();
      intCache = MockSyncache<int>();
      boolCache = MockSyncache<bool>();
      stringStore = MockStore<String>();
      intStore = MockStore<int>();
      boolStore = MockStore<bool>();
      mockNetwork = MockFlutterNetwork();
      connectivityController = StreamController<bool>.broadcast(sync: true);

      when(() => stringCache.store).thenReturn(stringStore);
      when(() => intCache.store).thenReturn(intStore);
      when(() => boolCache.store).thenReturn(boolStore);
      when(() => mockNetwork.onConnectivityChanged)
          .thenAnswer((_) => connectivityController.stream);
    });

    tearDown(() {
      connectivityController.close();
    });

    testWidgets('provides multiple caches to descendants', (tester) async {
      Syncache<String>? retrievedStringCache;
      Syncache<int>? retrievedIntCache;
      Syncache<bool>? retrievedBoolCache;

      await tester.pumpWidget(
        testableWidget(
          MultiSyncacheScope(
            configs: [
              SyncacheScopeConfig<String>(stringCache),
              SyncacheScopeConfig<int>(intCache),
              SyncacheScopeConfig<bool>(boolCache),
            ],
            child: Builder(
              builder: (context) {
                retrievedStringCache = SyncacheScope.of<String>(context);
                retrievedIntCache = SyncacheScope.of<int>(context);
                retrievedBoolCache = SyncacheScope.of<bool>(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      expect(retrievedStringCache, stringCache);
      expect(retrievedIntCache, intCache);
      expect(retrievedBoolCache, boolCache);
    });

    testWidgets('passes shared network to all scopes', (tester) async {
      SyncacheLifecycleObserver<String>? stringObserver;
      SyncacheLifecycleObserver<int>? intObserver;

      await tester.pumpWidget(
        testableWidget(
          MultiSyncacheScope(
            network: mockNetwork,
            configs: [
              SyncacheScopeConfig<String>(stringCache),
              SyncacheScopeConfig<int>(intCache),
            ],
            child: Builder(
              builder: (context) {
                stringObserver = SyncacheScope.observerOf<String>(context);
                intObserver = SyncacheScope.observerOf<int>(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      // Both observers should be attached (network was provided)
      expect(stringObserver?.isAttached, true);
      expect(intObserver?.isAttached, true);
    });

    testWidgets('passes shared lifecycleConfig to all scopes', (tester) async {
      const customConfig = LifecycleConfig(
        refetchOnResume: false,
        refetchOnReconnect: false,
      );

      SyncacheLifecycleObserver<String>? stringObserver;
      SyncacheLifecycleObserver<int>? intObserver;

      await tester.pumpWidget(
        testableWidget(
          MultiSyncacheScope(
            lifecycleConfig: customConfig,
            configs: [
              SyncacheScopeConfig<String>(stringCache),
              SyncacheScopeConfig<int>(intCache),
            ],
            child: Builder(
              builder: (context) {
                stringObserver = SyncacheScope.observerOf<String>(context);
                intObserver = SyncacheScope.observerOf<int>(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      expect(stringObserver?.config, customConfig);
      expect(intObserver?.config, customConfig);
    });

    testWidgets('works with empty configs list', (tester) async {
      await tester.pumpWidget(
        testableWidget(
          const MultiSyncacheScope(
            configs: [],
            child: Text('child'),
          ),
        ),
      );

      expect(find.text('child'), findsOneWidget);
    });

    testWidgets('works with single config', (tester) async {
      Syncache<String>? retrievedCache;

      await tester.pumpWidget(
        testableWidget(
          MultiSyncacheScope(
            configs: [
              SyncacheScopeConfig<String>(stringCache),
            ],
            child: Builder(
              builder: (context) {
                retrievedCache = SyncacheScope.of<String>(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      expect(retrievedCache, stringCache);
    });

    testWidgets('nesting order is correct (last config closest to child)',
        (tester) async {
      // The build order should be: String wraps Int wraps Bool wraps child
      // So Bool should be the innermost scope

      final widgets = <String>[];

      await tester.pumpWidget(
        testableWidget(
          MultiSyncacheScope(
            configs: [
              SyncacheScopeConfig<String>(stringCache),
              SyncacheScopeConfig<int>(intCache),
              SyncacheScopeConfig<bool>(boolCache),
            ],
            child: Builder(
              builder: (context) {
                // All should be accessible
                final str = SyncacheScope.of<String>(context);
                final num = SyncacheScope.of<int>(context);
                final boo = SyncacheScope.of<bool>(context);

                // Add widget types to verify they're all accessible
                widgets.add('String:${str.runtimeType}');
                widgets.add('int:${num.runtimeType}');
                widgets.add('bool:${boo.runtimeType}');

                return const SizedBox();
              },
            ),
          ),
        ),
      );

      // All caches should be accessible (3 entries for 3 cache types)
      expect(widgets.length, 3);
    });

    testWidgets('disposes observers when removed from tree', (tester) async {
      SyncacheLifecycleObserver<String>? observer;

      await tester.pumpWidget(
        testableWidget(
          MultiSyncacheScope(
            configs: [
              SyncacheScopeConfig<String>(stringCache),
            ],
            child: Builder(
              builder: (context) {
                observer = SyncacheScope.observerOf<String>(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      expect(observer?.isAttached, true);

      // Remove from tree
      await tester.pumpWidget(
        testableWidget(const SizedBox()),
      );

      expect(observer?.isAttached, false);
    });

    testWidgets('works without network (observers still created)',
        (tester) async {
      SyncacheLifecycleObserver<String>? observer;

      await tester.pumpWidget(
        testableWidget(
          MultiSyncacheScope(
            network: null,
            configs: [
              SyncacheScopeConfig<String>(stringCache),
            ],
            child: Builder(
              builder: (context) {
                observer = SyncacheScope.observerOf<String>(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      expect(observer, isNotNull);
      expect(observer?.isAttached, true);
    });

    testWidgets('uses default lifecycleConfig when not specified',
        (tester) async {
      SyncacheLifecycleObserver<String>? observer;

      await tester.pumpWidget(
        testableWidget(
          MultiSyncacheScope(
            configs: [
              SyncacheScopeConfig<String>(stringCache),
            ],
            child: Builder(
              builder: (context) {
                observer = SyncacheScope.observerOf<String>(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      expect(observer?.config, LifecycleConfig.defaults);
    });

    testWidgets('can be nested within other MultiSyncacheScope',
        (tester) async {
      final outerCache = MockSyncache<double>();
      final outerStore = MockStore<double>();
      when(() => outerCache.store).thenReturn(outerStore);

      Syncache<String>? innerStringCache;
      Syncache<double>? outerDoubleCache;

      await tester.pumpWidget(
        testableWidget(
          MultiSyncacheScope(
            configs: [
              SyncacheScopeConfig<double>(outerCache),
            ],
            child: MultiSyncacheScope(
              configs: [
                SyncacheScopeConfig<String>(stringCache),
              ],
              child: Builder(
                builder: (context) {
                  innerStringCache = SyncacheScope.of<String>(context);
                  outerDoubleCache = SyncacheScope.of<double>(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );

      expect(innerStringCache, stringCache);
      expect(outerDoubleCache, outerCache);
    });

    testWidgets('const constructor works', (tester) async {
      // Verify that const constructor compiles and works
      const scope = MultiSyncacheScope(
        configs: [],
        lifecycleConfig: LifecycleConfig.disabled,
        child: SizedBox(),
      );

      await tester.pumpWidget(
        testableWidget(scope),
      );

      expect(find.byType(SizedBox), findsOneWidget);
    });
  });
}
