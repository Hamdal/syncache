import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:syncache/syncache.dart';
import 'package:syncache_flutter/syncache_flutter.dart';

class MockSyncache<T> extends Mock implements Syncache<T> {}

class FakeSyncacheRequest extends Fake implements SyncacheRequest {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeSyncacheRequest());
    registerFallbackValue(Policy.offlineFirst);
  });

  group('SyncacheFlutterExtensions', () {
    late MockSyncache<String> mockCache;
    late StreamController<String> watchController;

    setUp(() {
      mockCache = MockSyncache<String>();
      watchController = StreamController<String>.broadcast(sync: true);

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

    test('toValueListenable creates SyncacheValueListenable', () {
      final listenable = mockCache.toValueListenable(
        key: 'test-key',
        fetch: (req) async => 'value',
      );

      expect(listenable, isA<SyncacheValueListenable<String>>());
      expect(listenable.key, 'test-key');
      expect(listenable.cache, mockCache);
      expect(listenable.policy, Policy.offlineFirst);
      expect(listenable.ttl, isNull);

      listenable.dispose();
    });

    test('toValueListenable passes all parameters', () {
      final listenable = mockCache.toValueListenable(
        key: 'test-key',
        fetch: (req) async => 'value',
        policy: Policy.refresh,
        ttl: const Duration(minutes: 5),
      );

      expect(listenable.policy, Policy.refresh);
      expect(listenable.ttl, const Duration(minutes: 5));

      listenable.dispose();
    });
  });

  group('SyncacheValueListenable', () {
    late MockSyncache<String> mockCache;
    late StreamController<String> watchController;

    setUp(() {
      mockCache = MockSyncache<String>();
      watchController = StreamController<String>.broadcast(sync: true);

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

    test('starts with waiting state', () {
      final listenable = SyncacheValueListenable<String>(
        cache: mockCache,
        key: 'test-key',
        fetch: (req) async => 'value',
      );

      expect(listenable.value.connectionState, ConnectionState.waiting);
      expect(listenable.value.data, isNull);

      listenable.dispose();
    });

    test('updates value when stream emits data', () {
      final listenable = SyncacheValueListenable<String>(
        cache: mockCache,
        key: 'test-key',
        fetch: (req) async => 'value',
      );

      watchController.add('test-data');

      expect(listenable.value.connectionState, ConnectionState.active);
      expect(listenable.value.data, 'test-data');
      expect(listenable.value.hasData, true);

      listenable.dispose();
    });

    test('updates value when stream emits error', () {
      final listenable = SyncacheValueListenable<String>(
        cache: mockCache,
        key: 'test-key',
        fetch: (req) async => 'value',
      );

      final error = Exception('Test error');
      watchController.addError(error);

      expect(listenable.value.connectionState, ConnectionState.active);
      expect(listenable.value.error, error);
      expect(listenable.value.hasError, true);

      listenable.dispose();
    });

    test('updates state to done when stream completes', () async {
      final controller = StreamController<String>(sync: true);

      when(
        () => mockCache.watch(
          key: any(named: 'key'),
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      ).thenAnswer((_) => controller.stream);

      final listenable = SyncacheValueListenable<String>(
        cache: mockCache,
        key: 'test-key',
        fetch: (req) async => 'value',
      );

      controller.add('data');
      expect(listenable.value.data, 'data');

      await controller.close();

      expect(listenable.value.connectionState, ConnectionState.done);

      listenable.dispose();
    });

    test('notifies listeners on data changes', () {
      final listenable = SyncacheValueListenable<String>(
        cache: mockCache,
        key: 'test-key',
        fetch: (req) async => 'value',
      );

      var notifyCount = 0;
      listenable.addListener(() {
        notifyCount++;
      });

      watchController.add('data-1');
      expect(notifyCount, 1);

      watchController.add('data-2');
      expect(notifyCount, 2);

      listenable.dispose();
    });

    test('isDisposed returns correct state', () {
      final listenable = SyncacheValueListenable<String>(
        cache: mockCache,
        key: 'test-key',
        fetch: (req) async => 'value',
      );

      expect(listenable.isDisposed, false);

      listenable.dispose();

      expect(listenable.isDisposed, true);
    });

    test('does not update value after dispose', () {
      final listenable = SyncacheValueListenable<String>(
        cache: mockCache,
        key: 'test-key',
        fetch: (req) async => 'value',
      );

      listenable.dispose();

      // Should not throw or update
      watchController.add('data-after-dispose');
      expect(listenable.value.data, isNull);
    });

    test('dispose can be called multiple times safely', () {
      final listenable = SyncacheValueListenable<String>(
        cache: mockCache,
        key: 'test-key',
        fetch: (req) async => 'value',
      );

      listenable.dispose();
      listenable.dispose(); // Should not throw
    });

    test('resubscribe restarts the stream', () {
      var watchCallCount = 0;

      when(
        () => mockCache.watch(
          key: any(named: 'key'),
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      ).thenAnswer((_) {
        watchCallCount++;
        return watchController.stream;
      });

      final listenable = SyncacheValueListenable<String>(
        cache: mockCache,
        key: 'test-key',
        fetch: (req) async => 'value',
      );

      expect(watchCallCount, 1);

      listenable.resubscribe();

      expect(watchCallCount, 2);
      expect(listenable.value.connectionState, ConnectionState.waiting);

      listenable.dispose();
    });

    test('resubscribe throws when disposed', () {
      final listenable = SyncacheValueListenable<String>(
        cache: mockCache,
        key: 'test-key',
        fetch: (req) async => 'value',
      );

      listenable.dispose();

      expect(
        () => listenable.resubscribe(),
        throwsA(isA<StateError>()),
      );
    });

    test('refresh calls cache.get with refresh policy', () async {
      when(
        () => mockCache.get(
          key: any(named: 'key'),
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      ).thenAnswer((_) async => 'refreshed');

      final listenable = SyncacheValueListenable<String>(
        cache: mockCache,
        key: 'test-key',
        fetch: (req) async => 'value',
        ttl: const Duration(minutes: 10),
      );

      await listenable.refresh();

      verify(
        () => mockCache.get(
          key: 'test-key',
          fetch: any(named: 'fetch'),
          policy: Policy.refresh,
          ttl: const Duration(minutes: 10),
        ),
      ).called(1);

      listenable.dispose();
    });

    test('refresh does nothing when disposed', () async {
      when(
        () => mockCache.get(
          key: any(named: 'key'),
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      ).thenAnswer((_) async => 'refreshed');

      final listenable = SyncacheValueListenable<String>(
        cache: mockCache,
        key: 'test-key',
        fetch: (req) async => 'value',
      );

      listenable.dispose();

      await listenable.refresh();

      verifyNever(
        () => mockCache.get(
          key: any(named: 'key'),
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      );
    });

    test('refresh silently handles errors', () async {
      when(
        () => mockCache.get(
          key: any(named: 'key'),
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      ).thenThrow(Exception('Refresh failed'));

      final listenable = SyncacheValueListenable<String>(
        cache: mockCache,
        key: 'test-key',
        fetch: (req) async => 'value',
      );

      // Should not throw
      await listenable.refresh();

      listenable.dispose();
    });

    testWidgets('works with ValueListenableBuilder', (tester) async {
      final listenable = SyncacheValueListenable<String>(
        cache: mockCache,
        key: 'test-key',
        fetch: (req) async => 'value',
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ValueListenableBuilder<AsyncSnapshot<String>>(
            valueListenable: listenable,
            builder: (context, snapshot, child) {
              if (snapshot.hasData) {
                return Text(snapshot.data!);
              }
              return const Text('loading');
            },
          ),
        ),
      );

      expect(find.text('loading'), findsOneWidget);

      watchController.add('test-data');
      await tester.pump();

      expect(find.text('test-data'), findsOneWidget);

      listenable.dispose();
    });

    test('passes correct parameters to watch', () {
      final listenable = SyncacheValueListenable<String>(
        cache: mockCache,
        key: 'my-key',
        fetch: (req) async => 'value',
        policy: Policy.cacheOnly,
        ttl: const Duration(hours: 1),
      );

      verify(
        () => mockCache.watch(
          key: 'my-key',
          fetch: any(named: 'fetch'),
          policy: Policy.cacheOnly,
          ttl: const Duration(hours: 1),
        ),
      ).called(1);

      listenable.dispose();
    });
  });
}
