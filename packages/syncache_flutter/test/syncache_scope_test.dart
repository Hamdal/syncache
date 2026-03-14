import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:syncache/syncache.dart';
import 'package:syncache_flutter/syncache_flutter.dart';

class MockSyncache<T> extends Mock implements Syncache<T> {}

class MockStore<T> extends Mock implements Store<T> {}

class MockFlutterNetwork extends Mock implements FlutterNetwork {}

class FakeStored<T> extends Fake implements Stored<T> {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeStored<String>());
  });

  group('SyncacheScope', () {
    late MockSyncache<String> mockCache;
    late MockStore<String> mockStore;

    setUp(() {
      mockCache = MockSyncache<String>();
      mockStore = MockStore<String>();

      when(() => mockCache.store).thenReturn(mockStore);
    });

    testWidgets('provides cache to descendants', (tester) async {
      Syncache<String>? retrievedCache;

      await tester.pumpWidget(
        SyncacheScope<String>(
          cache: mockCache,
          child: Builder(
            builder: (context) {
              retrievedCache = SyncacheScope.of<String>(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(retrievedCache, same(mockCache));
    });

    testWidgets('maybeOf returns null when no scope found', (tester) async {
      Syncache<String>? retrievedCache;

      await tester.pumpWidget(
        Builder(
          builder: (context) {
            retrievedCache = SyncacheScope.maybeOf<String>(context);
            return const SizedBox();
          },
        ),
      );

      expect(retrievedCache, isNull);
    });

    testWidgets('maybeOf returns cache when scope exists', (tester) async {
      Syncache<String>? retrievedCache;

      await tester.pumpWidget(
        SyncacheScope<String>(
          cache: mockCache,
          child: Builder(
            builder: (context) {
              retrievedCache = SyncacheScope.maybeOf<String>(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(retrievedCache, same(mockCache));
    });

    testWidgets('of throws when no scope found', (tester) async {
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            expect(
              () => SyncacheScope.of<String>(context),
              throwsAssertionError,
            );
            return const SizedBox();
          },
        ),
      );
    });

    testWidgets('observerOf returns observer when scope exists',
        (tester) async {
      SyncacheLifecycleObserver<String>? observer;

      await tester.pumpWidget(
        SyncacheScope<String>(
          cache: mockCache,
          child: Builder(
            builder: (context) {
              observer = SyncacheScope.observerOf<String>(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(observer, isNotNull);
      expect(observer!.cache, same(mockCache));
    });

    testWidgets('observer is attached on init', (tester) async {
      SyncacheLifecycleObserver<String>? observer;

      await tester.pumpWidget(
        SyncacheScope<String>(
          cache: mockCache,
          child: Builder(
            builder: (context) {
              observer = SyncacheScope.observerOf<String>(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(observer!.isAttached, isTrue);
    });

    testWidgets('observer is detached on dispose', (tester) async {
      SyncacheLifecycleObserver<String>? observer;

      await tester.pumpWidget(
        SyncacheScope<String>(
          cache: mockCache,
          child: Builder(
            builder: (context) {
              observer = SyncacheScope.observerOf<String>(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(observer!.isAttached, isTrue);

      // Remove the widget from the tree
      await tester.pumpWidget(const SizedBox());

      expect(observer!.isAttached, isFalse);
    });

    testWidgets('uses default config when not specified', (tester) async {
      SyncacheLifecycleObserver<String>? observer;

      await tester.pumpWidget(
        SyncacheScope<String>(
          cache: mockCache,
          child: Builder(
            builder: (context) {
              observer = SyncacheScope.observerOf<String>(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(observer!.config.refetchOnResume, isTrue);
      expect(observer!.config.refetchOnReconnect, isTrue);
    });

    testWidgets('uses custom config when specified', (tester) async {
      SyncacheLifecycleObserver<String>? observer;

      await tester.pumpWidget(
        SyncacheScope<String>(
          cache: mockCache,
          config: const LifecycleConfig(
            refetchOnResume: false,
            refetchOnReconnect: false,
          ),
          child: Builder(
            builder: (context) {
              observer = SyncacheScope.observerOf<String>(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(observer!.config.refetchOnResume, isFalse);
      expect(observer!.config.refetchOnReconnect, isFalse);
    });

    testWidgets('recreates observer when cache changes', (tester) async {
      final cache1 = MockSyncache<String>();
      final cache2 = MockSyncache<String>();
      when(() => cache1.store).thenReturn(mockStore);
      when(() => cache2.store).thenReturn(mockStore);

      SyncacheLifecycleObserver<String>? observer1;
      SyncacheLifecycleObserver<String>? observer2;

      await tester.pumpWidget(
        SyncacheScope<String>(
          cache: cache1,
          child: Builder(
            builder: (context) {
              observer1 = SyncacheScope.observerOf<String>(context);
              return const SizedBox();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        SyncacheScope<String>(
          cache: cache2,
          child: Builder(
            builder: (context) {
              observer2 = SyncacheScope.observerOf<String>(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(observer1!.isAttached, isFalse);
      expect(observer2!.isAttached, isTrue);
      expect(observer2!.cache, same(cache2));
    });

    group('nested scopes', () {
      testWidgets('inner scope shadows outer scope', (tester) async {
        final outerCache = MockSyncache<String>();
        final innerCache = MockSyncache<String>();
        when(() => outerCache.store).thenReturn(mockStore);
        when(() => innerCache.store).thenReturn(mockStore);

        Syncache<String>? retrievedCache;

        await tester.pumpWidget(
          SyncacheScope<String>(
            cache: outerCache,
            child: SyncacheScope<String>(
              cache: innerCache,
              child: Builder(
                builder: (context) {
                  retrievedCache = SyncacheScope.of<String>(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        );

        expect(retrievedCache, same(innerCache));
      });

      testWidgets('different types coexist', (tester) async {
        final stringCache = MockSyncache<String>();
        final intCache = MockSyncache<int>();
        final stringStore = MockStore<String>();
        final intStore = MockStore<int>();

        when(() => stringCache.store).thenReturn(stringStore);
        when(() => intCache.store).thenReturn(intStore);

        Syncache<String>? retrievedStringCache;
        Syncache<int>? retrievedIntCache;

        await tester.pumpWidget(
          SyncacheScope<String>(
            cache: stringCache,
            child: SyncacheScope<int>(
              cache: intCache,
              child: Builder(
                builder: (context) {
                  retrievedStringCache = SyncacheScope.of<String>(context);
                  retrievedIntCache = SyncacheScope.of<int>(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        );

        expect(retrievedStringCache, same(stringCache));
        expect(retrievedIntCache, same(intCache));
      });
    });
  });

  group('LifecycleConfig', () {
    test('defaults has expected values', () {
      const config = LifecycleConfig.defaults;
      expect(config.refetchOnResume, isTrue);
      expect(config.refetchOnReconnect, isTrue);
      expect(config.refetchOnResumeMinDuration, const Duration(seconds: 30));
    });

    test('disabled has all features off', () {
      const config = LifecycleConfig.disabled;
      expect(config.refetchOnResume, isFalse);
      expect(config.refetchOnReconnect, isFalse);
    });
  });
}
