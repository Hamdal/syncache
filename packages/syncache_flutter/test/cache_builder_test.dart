import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:syncache/syncache.dart';
import 'package:syncache_flutter/syncache_flutter.dart';

class MockSyncache<T> extends Mock implements Syncache<T> {}

class MockStore<T> extends Mock implements Store<T> {}

class FakeStored<T> extends Fake implements Stored<T> {}

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
    registerFallbackValue(FakeStored<String>());
    registerFallbackValue(FakeSyncacheRequest());
    registerFallbackValue(Policy.offlineFirst);
  });

  group('CacheBuilder', () {
    late MockSyncache<String> mockCache;
    late MockStore<String> mockStore;
    late StreamController<String> watchController;

    setUp(() {
      mockCache = MockSyncache<String>();
      mockStore = MockStore<String>();
      watchController = StreamController<String>.broadcast(sync: true);

      when(() => mockCache.store).thenReturn(mockStore);
      when(
        () => mockCache.watch(
          key: any(named: 'key'),
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      ).thenAnswer((_) => watchController.stream);
    });

    tearDown(() {
      watchController.close();
    });

    testWidgets('shows nothing state initially', (tester) async {
      ConnectionState? capturedState;

      await tester.pumpWidget(
        SyncacheScope<String>(
          cache: mockCache,
          child: CacheBuilder<String>(
            cacheKey: 'test-key',
            fetch: (req) async => 'value',
            builder: (context, snapshot) {
              capturedState = snapshot.connectionState;
              return const SizedBox();
            },
          ),
        ),
      );

      // First build should be waiting (nothing -> waiting after subscribe)
      expect(capturedState, ConnectionState.waiting);
    });

    testWidgets('shows data when stream emits', (tester) async {
      String? capturedData;

      await tester.pumpWidget(
        testableWidget(
          SyncacheScope<String>(
            cache: mockCache,
            child: CacheBuilder<String>(
              cacheKey: 'test-key',
              fetch: (req) async => 'value',
              builder: (context, snapshot) {
                capturedData = snapshot.data;
                return Text(snapshot.data ?? 'loading');
              },
            ),
          ),
        ),
      );

      watchController.add('test-data');
      await tester.pump();

      expect(capturedData, 'test-data');
      expect(find.text('test-data'), findsOneWidget);
    });

    testWidgets('shows error when stream errors', (tester) async {
      Object? capturedError;

      await tester.pumpWidget(
        testableWidget(
          SyncacheScope<String>(
            cache: mockCache,
            child: CacheBuilder<String>(
              cacheKey: 'test-key',
              fetch: (req) async => 'value',
              builder: (context, snapshot) {
                capturedError = snapshot.error;
                if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                }
                return const Text('loading');
              },
            ),
          ),
        ),
      );

      watchController.addError(Exception('Test error'));
      await tester.pump();

      expect(capturedError, isA<Exception>());
    });

    testWidgets('shows initialData while waiting', (tester) async {
      String? capturedData;
      ConnectionState? capturedState;

      await tester.pumpWidget(
        testableWidget(
          SyncacheScope<String>(
            cache: mockCache,
            child: CacheBuilder<String>(
              cacheKey: 'test-key',
              fetch: (req) async => 'value',
              initialData: 'initial-value',
              builder: (context, snapshot) {
                capturedData = snapshot.data;
                capturedState = snapshot.connectionState;
                return Text(snapshot.data ?? 'loading');
              },
            ),
          ),
        ),
      );

      expect(capturedData, 'initial-value');
      expect(capturedState, ConnectionState.waiting);
      expect(find.text('initial-value'), findsOneWidget);
    });

    testWidgets('buildWhen controls rebuilds', (tester) async {
      var buildCount = 0;

      await tester.pumpWidget(
        testableWidget(
          SyncacheScope<String>(
            cache: mockCache,
            child: CacheBuilder<String>(
              cacheKey: 'test-key',
              fetch: (req) async => 'value',
              buildWhen: (previous, current) {
                // Only rebuild when value contains 'rebuild'
                return current.contains('rebuild');
              },
              builder: (context, snapshot) {
                buildCount++;
                return Text(snapshot.data ?? 'loading');
              },
            ),
          ),
        ),
      );

      final initialBuildCount = buildCount;

      // This should NOT trigger rebuild (no 'rebuild' in value)
      watchController.add('skip-this');
      await tester.pump();
      expect(buildCount, initialBuildCount);

      // This SHOULD trigger rebuild
      watchController.add('please-rebuild-now');
      await tester.pump();
      expect(buildCount, initialBuildCount + 1);
      expect(find.text('please-rebuild-now'), findsOneWidget);
    });

    testWidgets('resubscribes when cache key changes', (tester) async {
      final controller1 = StreamController<String>.broadcast(sync: true);
      final controller2 = StreamController<String>.broadcast(sync: true);

      when(
        () => mockCache.watch(
          key: 'key-1',
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      ).thenAnswer((_) => controller1.stream);

      when(
        () => mockCache.watch(
          key: 'key-2',
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      ).thenAnswer((_) => controller2.stream);

      var currentKey = 'key-1';

      await tester.pumpWidget(
        testableWidget(
          SyncacheScope<String>(
            cache: mockCache,
            child: StatefulBuilder(
              builder: (context, setState) {
                return CacheBuilder<String>(
                  key: ValueKey(currentKey),
                  cacheKey: currentKey,
                  fetch: (req) async => 'value',
                  builder: (context, snapshot) {
                    return Text(snapshot.data ?? 'loading');
                  },
                );
              },
            ),
          ),
        ),
      );

      controller1.add('data-from-key-1');
      await tester.pump();
      expect(find.text('data-from-key-1'), findsOneWidget);

      // Change the key
      currentKey = 'key-2';
      await tester.pumpWidget(
        testableWidget(
          SyncacheScope<String>(
            cache: mockCache,
            child: CacheBuilder<String>(
              key: ValueKey(currentKey),
              cacheKey: currentKey,
              fetch: (req) async => 'value',
              builder: (context, snapshot) {
                return Text(snapshot.data ?? 'loading');
              },
            ),
          ),
        ),
      );

      controller2.add('data-from-key-2');
      await tester.pump();
      expect(find.text('data-from-key-2'), findsOneWidget);

      controller1.close();
      controller2.close();
    });

    testWidgets('uses provided cache over scope', (tester) async {
      final scopeCache = MockSyncache<String>();
      final providedCache = MockSyncache<String>();
      final scopeStore = MockStore<String>();
      final providedStore = MockStore<String>();

      when(() => scopeCache.store).thenReturn(scopeStore);
      when(() => providedCache.store).thenReturn(providedStore);

      final scopeController = StreamController<String>.broadcast(sync: true);
      final providedController = StreamController<String>.broadcast(sync: true);

      when(
        () => scopeCache.watch(
          key: any(named: 'key'),
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      ).thenAnswer((_) => scopeController.stream);

      when(
        () => providedCache.watch(
          key: any(named: 'key'),
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      ).thenAnswer((_) => providedController.stream);

      await tester.pumpWidget(
        testableWidget(
          SyncacheScope<String>(
            cache: scopeCache,
            child: CacheBuilder<String>(
              cacheKey: 'test-key',
              cache: providedCache,
              fetch: (req) async => 'value',
              builder: (context, snapshot) {
                return Text(snapshot.data ?? 'loading');
              },
            ),
          ),
        ),
      );

      // Only provided cache should receive watch call
      verify(
        () => providedCache.watch(
          key: 'test-key',
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      ).called(1);

      verifyNever(
        () => scopeCache.watch(
          key: any(named: 'key'),
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      );

      scopeController.close();
      providedController.close();
    });

    testWidgets('passes policy and ttl to watch', (tester) async {
      await tester.pumpWidget(
        SyncacheScope<String>(
          cache: mockCache,
          child: CacheBuilder<String>(
            cacheKey: 'test-key',
            fetch: (req) async => 'value',
            policy: Policy.refresh,
            ttl: const Duration(minutes: 5),
            builder: (context, snapshot) {
              return const SizedBox();
            },
          ),
        ),
      );

      verify(
        () => mockCache.watch(
          key: 'test-key',
          fetch: any(named: 'fetch'),
          policy: Policy.refresh,
          ttl: const Duration(minutes: 5),
        ),
      ).called(1);
    });

    testWidgets('registers with lifecycle observer', (tester) async {
      SyncacheLifecycleObserver<String>? observer;

      await tester.pumpWidget(
        SyncacheScope<String>(
          cache: mockCache,
          child: Builder(
            builder: (context) {
              return CacheBuilder<String>(
                cacheKey: 'test-key',
                fetch: (req) async => 'value',
                builder: (context, snapshot) {
                  observer = SyncacheScope.observerOf<String>(context);
                  return const SizedBox();
                },
              );
            },
          ),
        ),
      );

      expect(observer, isNotNull);
      expect(observer!.watcherCount, 1);
    });

    testWidgets('unregisters from lifecycle observer on dispose',
        (tester) async {
      SyncacheLifecycleObserver<String>? observer;

      await tester.pumpWidget(
        SyncacheScope<String>(
          cache: mockCache,
          child: Builder(
            builder: (context) {
              observer = SyncacheScope.observerOf<String>(context);
              return CacheBuilder<String>(
                cacheKey: 'test-key',
                fetch: (req) async => 'value',
                builder: (context, snapshot) {
                  return const SizedBox();
                },
              );
            },
          ),
        ),
      );

      expect(observer!.watcherCount, 1);

      // Remove the CacheBuilder
      await tester.pumpWidget(
        SyncacheScope<String>(
          cache: mockCache,
          child: const SizedBox(),
        ),
      );

      expect(observer!.watcherCount, 0);
    });
  });
}
