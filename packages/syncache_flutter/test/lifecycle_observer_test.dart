import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:syncache/syncache.dart';
import 'package:syncache_flutter/syncache_flutter.dart';

class MockSyncache<T> extends Mock implements Syncache<T> {}

class MockFlutterNetwork extends Mock implements FlutterNetwork {}

class FakeSyncacheRequest extends Fake implements SyncacheRequest {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeSyncacheRequest());
    registerFallbackValue(Policy.offlineFirst);
    registerFallbackValue(const Duration(seconds: 30));
  });

  group('LifecycleConfig', () {
    test('has correct default values', () {
      const config = LifecycleConfig();

      expect(config.refetchOnResume, true);
      expect(config.refetchOnResumeMinDuration, const Duration(seconds: 30));
      expect(config.refetchOnReconnect, true);
      expect(config.onRefetchError, isNull);
    });

    test('defaults constant has expected values', () {
      expect(LifecycleConfig.defaults.refetchOnResume, true);
      expect(LifecycleConfig.defaults.refetchOnReconnect, true);
    });

    test('disabled constant has expected values', () {
      expect(LifecycleConfig.disabled.refetchOnResume, false);
      expect(LifecycleConfig.disabled.refetchOnReconnect, false);
    });

    test('equality works correctly', () {
      const config1 = LifecycleConfig(
        refetchOnResume: true,
        refetchOnReconnect: false,
      );
      const config2 = LifecycleConfig(
        refetchOnResume: true,
        refetchOnReconnect: false,
      );
      const config3 = LifecycleConfig(
        refetchOnResume: false,
        refetchOnReconnect: false,
      );

      expect(config1, equals(config2));
      expect(config1, isNot(equals(config3)));
      expect(config1.hashCode, equals(config2.hashCode));
    });

    test('custom onRefetchError callback is stored', () {
      var errorCalled = false;
      final config = LifecycleConfig(
        onRefetchError: (key, error, stackTrace) {
          errorCalled = true;
        },
      );

      config.onRefetchError?.call('key', Exception('test'), StackTrace.current);
      expect(errorCalled, true);
    });
  });

  group('WatcherRegistration', () {
    test('stores key and fetch correctly', () {
      Future<String> fetcher(SyncacheRequest req) async => 'value';

      final registration = WatcherRegistration<String>(
        key: 'test-key',
        fetch: fetcher,
        ttl: const Duration(minutes: 5),
        policy: Policy.refresh,
      );

      expect(registration.key, 'test-key');
      expect(registration.fetch, fetcher);
      expect(registration.ttl, const Duration(minutes: 5));
      expect(registration.policy, Policy.refresh);
    });

    test('default policy is offlineFirst', () {
      final registration = WatcherRegistration<String>(
        key: 'test-key',
        fetch: (req) async => 'value',
      );

      expect(registration.policy, Policy.offlineFirst);
    });

    test('equality is based on key only', () {
      final reg1 = WatcherRegistration<String>(
        key: 'same-key',
        fetch: (req) async => 'value1',
        ttl: const Duration(minutes: 1),
      );
      final reg2 = WatcherRegistration<String>(
        key: 'same-key',
        fetch: (req) async => 'value2',
        ttl: const Duration(minutes: 5),
      );
      final reg3 = WatcherRegistration<String>(
        key: 'different-key',
        fetch: (req) async => 'value1',
      );

      expect(reg1, equals(reg2));
      expect(reg1, isNot(equals(reg3)));
      expect(reg1.hashCode, equals(reg2.hashCode));
    });
  });

  group('SyncacheLifecycleObserver', () {
    late MockSyncache<String> mockCache;
    late MockFlutterNetwork mockNetwork;
    late StreamController<bool> connectivityController;

    setUp(() {
      mockCache = MockSyncache<String>();
      mockNetwork = MockFlutterNetwork();
      connectivityController = StreamController<bool>.broadcast(sync: true);

      when(() => mockNetwork.onConnectivityChanged)
          .thenAnswer((_) => connectivityController.stream);
    });

    tearDown(() {
      connectivityController.close();
    });

    testWidgets('attach and detach lifecycle', (tester) async {
      final observer = SyncacheLifecycleObserver<String>(
        cache: mockCache,
        network: mockNetwork,
      );

      expect(observer.isAttached, false);

      observer.attach();
      expect(observer.isAttached, true);

      // Calling attach again should be a no-op
      observer.attach();
      expect(observer.isAttached, true);

      observer.detach();
      expect(observer.isAttached, false);

      // Calling detach again should be a no-op
      observer.detach();
      expect(observer.isAttached, false);
    });

    testWidgets('registers and unregisters watchers', (tester) async {
      final observer = SyncacheLifecycleObserver<String>(
        cache: mockCache,
      );

      expect(observer.watcherCount, 0);

      final reg1 = WatcherRegistration<String>(
        key: 'key-1',
        fetch: (req) async => 'value1',
      );
      final reg2 = WatcherRegistration<String>(
        key: 'key-2',
        fetch: (req) async => 'value2',
      );

      observer.registerWatcher(reg1);
      expect(observer.watcherCount, 1);

      observer.registerWatcher(reg2);
      expect(observer.watcherCount, 2);

      // Registering same key again should not increase count (Set behavior)
      observer.registerWatcher(reg1);
      expect(observer.watcherCount, 2);

      observer.unregisterWatcher('key-1');
      expect(observer.watcherCount, 1);

      observer.clearWatchers();
      expect(observer.watcherCount, 0);
    });

    testWidgets('copyWatchers returns a copy of active watchers',
        (tester) async {
      final observer = SyncacheLifecycleObserver<String>(
        cache: mockCache,
      );

      final reg1 = WatcherRegistration<String>(
        key: 'key-1',
        fetch: (req) async => 'value1',
      );
      final reg2 = WatcherRegistration<String>(
        key: 'key-2',
        fetch: (req) async => 'value2',
      );

      observer.registerWatcher(reg1);
      observer.registerWatcher(reg2);

      final copy = observer.copyWatchers();

      expect(copy.length, 2);
      expect(copy, contains(reg1));
      expect(copy, contains(reg2));

      // Modifying copy should not affect original
      copy.clear();
      expect(observer.watcherCount, 2);
    });

    testWidgets('restoreWatchers adds watchers from another set',
        (tester) async {
      final observer = SyncacheLifecycleObserver<String>(
        cache: mockCache,
      );

      final watchers = {
        WatcherRegistration<String>(
          key: 'key-1',
          fetch: (req) async => 'value1',
        ),
        WatcherRegistration<String>(
          key: 'key-2',
          fetch: (req) async => 'value2',
        ),
      };

      observer.restoreWatchers(watchers);

      expect(observer.watcherCount, 2);
    });

    testWidgets('refetches on connectivity restored when enabled',
        (tester) async {
      when(
        () => mockCache.get(
          key: any(named: 'key'),
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      ).thenAnswer((_) async => 'value');

      final observer = SyncacheLifecycleObserver<String>(
        cache: mockCache,
        network: mockNetwork,
        config: const LifecycleConfig(refetchOnReconnect: true),
      );

      observer.attach();
      observer.registerWatcher(
        WatcherRegistration<String>(
          key: 'test-key',
          fetch: (req) async => 'value',
        ),
      );

      // Simulate connectivity restored
      connectivityController.add(true);
      await tester.pump();

      verify(
        () => mockCache.get(
          key: 'test-key',
          fetch: any(named: 'fetch'),
          policy: Policy.refresh,
          ttl: any(named: 'ttl'),
        ),
      ).called(1);

      observer.detach();
    });

    testWidgets('does not refetch on connectivity when disabled',
        (tester) async {
      final observer = SyncacheLifecycleObserver<String>(
        cache: mockCache,
        network: mockNetwork,
        config: const LifecycleConfig(refetchOnReconnect: false),
      );

      observer.attach();
      observer.registerWatcher(
        WatcherRegistration<String>(
          key: 'test-key',
          fetch: (req) async => 'value',
        ),
      );

      // Simulate connectivity restored
      connectivityController.add(true);
      await tester.pump();

      verifyNever(
        () => mockCache.get(
          key: any(named: 'key'),
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      );

      observer.detach();
    });

    testWidgets('does not refetch when connectivity goes offline',
        (tester) async {
      when(
        () => mockCache.get(
          key: any(named: 'key'),
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      ).thenAnswer((_) async => 'value');

      final observer = SyncacheLifecycleObserver<String>(
        cache: mockCache,
        network: mockNetwork,
        config: const LifecycleConfig(refetchOnReconnect: true),
      );

      observer.attach();
      observer.registerWatcher(
        WatcherRegistration<String>(
          key: 'test-key',
          fetch: (req) async => 'value',
        ),
      );

      // Simulate going offline
      connectivityController.add(false);
      await tester.pump();

      verifyNever(
        () => mockCache.get(
          key: any(named: 'key'),
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      );

      observer.detach();
    });

    testWidgets('calls onRefetchError when refetch fails', (tester) async {
      final testError = Exception('Refetch failed');
      when(
        () => mockCache.get(
          key: any(named: 'key'),
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      ).thenThrow(testError);

      String? errorKey;
      Object? errorObject;

      final observer = SyncacheLifecycleObserver<String>(
        cache: mockCache,
        network: mockNetwork,
        config: LifecycleConfig(
          refetchOnReconnect: true,
          onRefetchError: (key, error, stackTrace) {
            errorKey = key;
            errorObject = error;
          },
        ),
      );

      observer.attach();
      observer.registerWatcher(
        WatcherRegistration<String>(
          key: 'test-key',
          fetch: (req) async => 'value',
        ),
      );

      // Simulate connectivity restored
      connectivityController.add(true);
      await tester.pump();

      expect(errorKey, 'test-key');
      expect(errorObject, testError);

      observer.detach();
    });

    testWidgets('silently ignores errors when onRefetchError is not provided',
        (tester) async {
      when(
        () => mockCache.get(
          key: any(named: 'key'),
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      ).thenThrow(Exception('Refetch failed'));

      final observer = SyncacheLifecycleObserver<String>(
        cache: mockCache,
        network: mockNetwork,
        config: const LifecycleConfig(refetchOnReconnect: true),
      );

      observer.attach();
      observer.registerWatcher(
        WatcherRegistration<String>(
          key: 'test-key',
          fetch: (req) async => 'value',
        ),
      );

      // Should not throw
      connectivityController.add(true);
      await tester.pump();

      observer.detach();
    });

    testWidgets('refetches all registered watchers', (tester) async {
      when(
        () => mockCache.get(
          key: any(named: 'key'),
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      ).thenAnswer((_) async => 'value');

      final observer = SyncacheLifecycleObserver<String>(
        cache: mockCache,
        network: mockNetwork,
        config: const LifecycleConfig(refetchOnReconnect: true),
      );

      observer.attach();
      observer.registerWatcher(
        WatcherRegistration<String>(
          key: 'key-1',
          fetch: (req) async => 'value1',
          ttl: const Duration(minutes: 1),
        ),
      );
      observer.registerWatcher(
        WatcherRegistration<String>(
          key: 'key-2',
          fetch: (req) async => 'value2',
          ttl: const Duration(minutes: 2),
        ),
      );

      connectivityController.add(true);
      await tester.pump();

      verify(
        () => mockCache.get(
          key: 'key-1',
          fetch: any(named: 'fetch'),
          policy: Policy.refresh,
          ttl: const Duration(minutes: 1),
        ),
      ).called(1);

      verify(
        () => mockCache.get(
          key: 'key-2',
          fetch: any(named: 'fetch'),
          policy: Policy.refresh,
          ttl: const Duration(minutes: 2),
        ),
      ).called(1);

      observer.detach();
    });

    testWidgets('handles app lifecycle - paused state', (tester) async {
      final observer = SyncacheLifecycleObserver<String>(
        cache: mockCache,
        config: const LifecycleConfig(refetchOnResume: true),
      );

      observer.attach();

      // Trigger paused state
      observer.didChangeAppLifecycleState(AppLifecycleState.paused);

      // No immediate action expected on pause
      verifyNever(
        () => mockCache.get(
          key: any(named: 'key'),
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      );

      observer.detach();
    });

    testWidgets(
        'does not refetch on resume if paused duration is less than minimum',
        (tester) async {
      when(
        () => mockCache.get(
          key: any(named: 'key'),
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      ).thenAnswer((_) async => 'value');

      final observer = SyncacheLifecycleObserver<String>(
        cache: mockCache,
        config: const LifecycleConfig(
          refetchOnResume: true,
          refetchOnResumeMinDuration: Duration(minutes: 5),
        ),
      );

      observer.attach();
      observer.registerWatcher(
        WatcherRegistration<String>(
          key: 'test-key',
          fetch: (req) async => 'value',
        ),
      );

      // Pause and immediately resume (less than 5 minutes)
      observer.didChangeAppLifecycleState(AppLifecycleState.paused);
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);

      verifyNever(
        () => mockCache.get(
          key: any(named: 'key'),
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      );

      observer.detach();
    });

    testWidgets('does not refetch on resume when refetchOnResume is disabled',
        (tester) async {
      final observer = SyncacheLifecycleObserver<String>(
        cache: mockCache,
        config: const LifecycleConfig(refetchOnResume: false),
      );

      observer.attach();
      observer.registerWatcher(
        WatcherRegistration<String>(
          key: 'test-key',
          fetch: (req) async => 'value',
        ),
      );

      observer.didChangeAppLifecycleState(AppLifecycleState.paused);
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);

      verifyNever(
        () => mockCache.get(
          key: any(named: 'key'),
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      );

      observer.detach();
    });

    testWidgets('inactive state does not start pause timer', (tester) async {
      when(
        () => mockCache.get(
          key: any(named: 'key'),
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      ).thenAnswer((_) async => 'value');

      final observer = SyncacheLifecycleObserver<String>(
        cache: mockCache,
        config: const LifecycleConfig(
          refetchOnResume: true,
          refetchOnResumeMinDuration: Duration.zero,
        ),
      );

      observer.attach();
      observer.registerWatcher(
        WatcherRegistration<String>(
          key: 'test-key',
          fetch: (req) async => 'value',
        ),
      );

      // Only inactive (no pause), then resume - should not refetch
      observer.didChangeAppLifecycleState(AppLifecycleState.inactive);
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);

      verifyNever(
        () => mockCache.get(
          key: any(named: 'key'),
          fetch: any(named: 'fetch'),
          policy: any(named: 'policy'),
          ttl: any(named: 'ttl'),
        ),
      );

      observer.detach();
    });

    testWidgets('hidden and detached states are handled gracefully',
        (tester) async {
      final observer = SyncacheLifecycleObserver<String>(
        cache: mockCache,
      );

      observer.attach();

      // These should not throw
      observer.didChangeAppLifecycleState(AppLifecycleState.hidden);
      observer.didChangeAppLifecycleState(AppLifecycleState.detached);

      observer.detach();
    });

    testWidgets('works without network instance', (tester) async {
      final observer = SyncacheLifecycleObserver<String>(
        cache: mockCache,
        network: null,
        config: const LifecycleConfig(refetchOnReconnect: true),
      );

      // Should not throw
      observer.attach();
      expect(observer.isAttached, true);
      observer.detach();
    });
  });
}
