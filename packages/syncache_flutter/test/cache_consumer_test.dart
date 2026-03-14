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

  group('CacheConsumer', () {
    late MockSyncache<String> mockCache;
    late MockStore<String> mockStore;
    late StreamController<String> watchController;

    setUp(() {
      mockCache = MockSyncache<String>();
      mockStore = MockStore<String>();
      // Use sync: true to ensure events are delivered synchronously in tests
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

    testWidgets('builds with initial nothing state', (tester) async {
      ConnectionState? capturedState;

      await tester.pumpWidget(
        SyncacheScope<String>(
          cache: mockCache,
          child: CacheConsumer<String>(
            cacheKey: 'test-key',
            fetch: (req) async => 'value',
            builder: (context, snapshot) {
              capturedState = snapshot.connectionState;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedState, ConnectionState.waiting);
    });

    testWidgets('calls listener when data emits', (tester) async {
      final listenerCalls = <String>[];

      await tester.pumpWidget(
        testableWidget(
          SyncacheScope<String>(
            cache: mockCache,
            child: CacheConsumer<String>(
              cacheKey: 'test-key',
              fetch: (req) async => 'value',
              listener: (context, snapshot) {
                if (snapshot.hasData) {
                  listenerCalls.add(snapshot.data!);
                }
              },
              builder: (context, snapshot) {
                return Text(snapshot.data ?? 'loading');
              },
            ),
          ),
        ),
      );

      watchController.add('first-data');
      await tester.pump();

      expect(listenerCalls, ['first-data']);

      watchController.add('second-data');
      await tester.pump();

      expect(listenerCalls, ['first-data', 'second-data']);
    });

    testWidgets('calls listener on error', (tester) async {
      Object? capturedError;

      await tester.pumpWidget(
        SyncacheScope<String>(
          cache: mockCache,
          child: CacheConsumer<String>(
            cacheKey: 'test-key',
            fetch: (req) async => 'value',
            listener: (context, snapshot) {
              if (snapshot.hasError) {
                capturedError = snapshot.error;
              }
            },
            builder: (context, snapshot) {
              return const SizedBox();
            },
          ),
        ),
      );

      watchController.addError(Exception('Test error'));
      await tester.pump();

      expect(capturedError, isA<Exception>());
    });

    testWidgets('listenWhen controls listener calls', (tester) async {
      final listenerCalls = <String>[];

      await tester.pumpWidget(
        SyncacheScope<String>(
          cache: mockCache,
          child: CacheConsumer<String>(
            cacheKey: 'test-key',
            fetch: (req) async => 'value',
            listenWhen: (previous, current) {
              // Only listen when value contains 'important'
              return current.contains('important');
            },
            listener: (context, snapshot) {
              if (snapshot.hasData) {
                listenerCalls.add(snapshot.data!);
              }
            },
            builder: (context, snapshot) {
              return const SizedBox();
            },
          ),
        ),
      );

      // Should NOT trigger listener
      watchController.add('skip-this');
      await tester.pump();
      expect(listenerCalls, isEmpty);

      // SHOULD trigger listener
      watchController.add('important-update');
      await tester.pump();
      expect(listenerCalls, ['important-update']);
    });

    testWidgets('buildWhen controls rebuilds', (tester) async {
      var buildCount = 0;

      await tester.pumpWidget(
        testableWidget(
          SyncacheScope<String>(
            cache: mockCache,
            child: CacheConsumer<String>(
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

      // Should NOT trigger rebuild
      watchController.add('skip-this');
      await tester.pump();
      expect(buildCount, initialBuildCount);

      // SHOULD trigger rebuild
      watchController.add('please-rebuild-now');
      await tester.pump();
      expect(buildCount, initialBuildCount + 1);
      expect(find.text('please-rebuild-now'), findsOneWidget);
    });

    testWidgets('listener called before rebuild', (tester) async {
      final events = <String>[];

      await tester.pumpWidget(
        SyncacheScope<String>(
          cache: mockCache,
          child: CacheConsumer<String>(
            cacheKey: 'test-key',
            fetch: (req) async => 'value',
            listener: (context, snapshot) {
              events.add('listener');
            },
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                events.add('build');
              }
              return const SizedBox();
            },
          ),
        ),
      );

      events.clear();
      watchController.add('data');
      await tester.pump();

      // Listener should be called before rebuild
      expect(events, ['listener', 'build']);
    });

    testWidgets('listener and buildWhen work independently', (tester) async {
      final listenerCalls = <String>[];
      var buildCount = 0;

      await tester.pumpWidget(
        SyncacheScope<String>(
          cache: mockCache,
          child: CacheConsumer<String>(
            cacheKey: 'test-key',
            fetch: (req) async => 'value',
            listenWhen: (previous, current) => current.contains('listen'),
            buildWhen: (previous, current) => current.contains('build'),
            listener: (context, snapshot) {
              if (snapshot.hasData) {
                listenerCalls.add(snapshot.data!);
              }
            },
            builder: (context, snapshot) {
              buildCount++;
              return const SizedBox();
            },
          ),
        ),
      );

      final initialBuildCount = buildCount;
      listenerCalls.clear();

      // Should trigger listener only
      watchController.add('listen-only');
      await tester.pump();
      expect(listenerCalls, ['listen-only']);
      expect(buildCount, initialBuildCount);

      listenerCalls.clear();

      // Should trigger build only
      watchController.add('build-only');
      await tester.pump();
      expect(listenerCalls, isEmpty);
      expect(buildCount, initialBuildCount + 1);

      listenerCalls.clear();

      // Should trigger both
      watchController.add('listen-and-build');
      await tester.pump();
      expect(listenerCalls, ['listen-and-build']);
      expect(buildCount, initialBuildCount + 2);
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

      await tester.pumpWidget(
        testableWidget(
          SyncacheScope<String>(
            cache: mockCache,
            child: CacheConsumer<String>(
              key: const ValueKey('key-1'),
              cacheKey: 'key-1',
              fetch: (req) async => 'value',
              builder: (context, snapshot) {
                return Text(snapshot.data ?? 'loading');
              },
            ),
          ),
        ),
      );

      controller1.add('data-from-key-1');
      await tester.pump();
      expect(find.text('data-from-key-1'), findsOneWidget);

      // Change the key
      await tester.pumpWidget(
        testableWidget(
          SyncacheScope<String>(
            cache: mockCache,
            child: CacheConsumer<String>(
              key: const ValueKey('key-2'),
              cacheKey: 'key-2',
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

      final providedController = StreamController<String>.broadcast(sync: true);

      when(
        () => providedCache.watch(
          key: any(named: 'key'),
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      ).thenAnswer((_) => providedController.stream);

      await tester.pumpWidget(
        SyncacheScope<String>(
          cache: scopeCache,
          child: CacheConsumer<String>(
            cacheKey: 'test-key',
            cache: providedCache,
            fetch: (req) async => 'value',
            builder: (context, snapshot) {
              return const SizedBox();
            },
          ),
        ),
      );

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

      providedController.close();
    });

    testWidgets('passes policy and ttl to watch', (tester) async {
      await tester.pumpWidget(
        SyncacheScope<String>(
          cache: mockCache,
          child: CacheConsumer<String>(
            cacheKey: 'test-key',
            fetch: (req) async => 'value',
            policy: Policy.cacheOnly,
            ttl: const Duration(hours: 1),
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
          policy: Policy.cacheOnly,
          ttl: const Duration(hours: 1),
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
              return CacheConsumer<String>(
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
              return CacheConsumer<String>(
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

      // Remove the CacheConsumer
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
