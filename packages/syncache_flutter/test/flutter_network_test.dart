import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:syncache_flutter/syncache_flutter.dart';

class MockConnectivity extends Mock implements Connectivity {}

void main() {
  group('FlutterNetwork', () {
    late MockConnectivity mockConnectivity;
    late StreamController<List<ConnectivityResult>> connectivityController;

    setUp(() {
      mockConnectivity = MockConnectivity();
      connectivityController =
          StreamController<List<ConnectivityResult>>.broadcast();

      when(() => mockConnectivity.onConnectivityChanged)
          .thenAnswer((_) => connectivityController.stream);
    });

    tearDown(() {
      connectivityController.close();
    });

    test('defaults to online before initialization', () {
      final network = FlutterNetwork(connectivity: mockConnectivity);
      expect(network.isOnline, isTrue);
      expect(network.isInitialized, isFalse);
    });

    test('initialize checks current connectivity', () async {
      when(() => mockConnectivity.checkConnectivity()).thenAnswer(
        (_) async => [ConnectivityResult.wifi],
      );

      final network = FlutterNetwork(connectivity: mockConnectivity);
      await network.initialize();

      expect(network.isOnline, isTrue);
      expect(network.isInitialized, isTrue);
      verify(() => mockConnectivity.checkConnectivity()).called(1);

      network.dispose();
    });

    test('initialize reports offline when no connectivity', () async {
      when(() => mockConnectivity.checkConnectivity()).thenAnswer(
        (_) async => [ConnectivityResult.none],
      );

      final network = FlutterNetwork(connectivity: mockConnectivity);
      await network.initialize();

      expect(network.isOnline, isFalse);
      expect(network.isInitialized, isTrue);

      network.dispose();
    });

    test('initialize is idempotent', () async {
      when(() => mockConnectivity.checkConnectivity()).thenAnswer(
        (_) async => [ConnectivityResult.wifi],
      );

      final network = FlutterNetwork(connectivity: mockConnectivity);
      await network.initialize();
      await network.initialize();
      await network.initialize();

      verify(() => mockConnectivity.checkConnectivity()).called(1);

      network.dispose();
    });

    test('concurrent initialize calls wait for first to complete', () async {
      final completer = Completer<List<ConnectivityResult>>();
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) => completer.future);

      final network = FlutterNetwork(connectivity: mockConnectivity);

      // Start multiple concurrent initializations
      final futures = [
        network.initialize(),
        network.initialize(),
        network.initialize(),
      ];

      // None should be complete yet
      expect(network.isInitialized, isFalse);

      // Complete the connectivity check
      completer.complete([ConnectivityResult.wifi]);

      // All futures should complete
      await Future.wait(futures);

      expect(network.isInitialized, isTrue);
      expect(network.isOnline, isTrue);

      // Should only call checkConnectivity once
      verify(() => mockConnectivity.checkConnectivity()).called(1);

      network.dispose();
    });

    test('initialize can retry after error', () async {
      // Create a fresh mock for this test to avoid interference
      final freshMockConnectivity = MockConnectivity();
      final freshController =
          StreamController<List<ConnectivityResult>>.broadcast();
      when(() => freshMockConnectivity.onConnectivityChanged)
          .thenAnswer((_) => freshController.stream);

      var callCount = 0;
      when(() => freshMockConnectivity.checkConnectivity()).thenAnswer(
        (_) async {
          callCount++;
          if (callCount == 1) {
            throw Exception('Network error');
          }
          return [ConnectivityResult.wifi];
        },
      );

      final network = FlutterNetwork(connectivity: freshMockConnectivity);

      // First call should fail
      Object? caughtError;
      try {
        await network.initialize();
      } catch (e) {
        caughtError = e;
      }
      expect(caughtError, isA<Exception>());
      expect(network.isInitialized, isFalse);

      // Second call should succeed
      await network.initialize();
      expect(network.isInitialized, isTrue);

      network.dispose();
      freshController.close();
    });

    test('handles multiple connectivity types (wifi + mobile)', () async {
      when(() => mockConnectivity.checkConnectivity()).thenAnswer(
        (_) async => [ConnectivityResult.wifi, ConnectivityResult.mobile],
      );

      final network = FlutterNetwork(connectivity: mockConnectivity);
      await network.initialize();

      expect(network.isOnline, isTrue);

      network.dispose();
    });

    test('handles connectivity with none included (edge case)', () async {
      // Some devices might report [wifi, none] which should still be online
      when(() => mockConnectivity.checkConnectivity()).thenAnswer(
        (_) async => [ConnectivityResult.wifi, ConnectivityResult.none],
      );

      final network = FlutterNetwork(connectivity: mockConnectivity);
      await network.initialize();

      expect(network.isOnline, isTrue);

      network.dispose();
    });

    group('connectivity changes', () {
      test('emits connectivity change after debounce', () async {
        when(() => mockConnectivity.checkConnectivity()).thenAnswer(
          (_) async => [ConnectivityResult.wifi],
        );

        final network = FlutterNetwork(
          connectivity: mockConnectivity,
          debounceDuration: const Duration(milliseconds: 50),
        );
        await network.initialize();

        final changes = <bool>[];
        final subscription = network.onConnectivityChanged.listen(changes.add);

        // Go offline
        connectivityController.add([ConnectivityResult.none]);

        // Wait for debounce
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(changes, [false]);
        expect(network.isOnline, isFalse);

        await subscription.cancel();
        network.dispose();
      });

      test('emits reconnection event after debounce', () async {
        when(() => mockConnectivity.checkConnectivity()).thenAnswer(
          (_) async => [ConnectivityResult.none],
        );

        final network = FlutterNetwork(
          connectivity: mockConnectivity,
          debounceDuration: const Duration(milliseconds: 50),
        );
        await network.initialize();
        expect(network.isOnline, isFalse);

        final changes = <bool>[];
        final subscription = network.onConnectivityChanged.listen(changes.add);

        // Go online
        connectivityController.add([ConnectivityResult.wifi]);

        // Wait for debounce
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(changes, [true]);
        expect(network.isOnline, isTrue);

        await subscription.cancel();
        network.dispose();
      });

      test('debounces rapid connectivity changes', () async {
        when(() => mockConnectivity.checkConnectivity()).thenAnswer(
          (_) async => [ConnectivityResult.wifi],
        );

        final network = FlutterNetwork(
          connectivity: mockConnectivity,
          debounceDuration: const Duration(milliseconds: 100),
        );
        await network.initialize();

        final changes = <bool>[];
        final subscription = network.onConnectivityChanged.listen(changes.add);

        // Rapid changes within debounce window
        connectivityController.add([ConnectivityResult.none]);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        connectivityController.add([ConnectivityResult.wifi]);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        connectivityController.add([ConnectivityResult.none]);

        // Wait for debounce
        await Future<void>.delayed(const Duration(milliseconds: 150));

        // Only the final state should be emitted
        expect(changes, [false]);

        await subscription.cancel();
        network.dispose();
      });

      test('does not emit when state unchanged', () async {
        when(() => mockConnectivity.checkConnectivity()).thenAnswer(
          (_) async => [ConnectivityResult.wifi],
        );

        final network = FlutterNetwork(
          connectivity: mockConnectivity,
          debounceDuration: const Duration(milliseconds: 50),
        );
        await network.initialize();

        final changes = <bool>[];
        final subscription = network.onConnectivityChanged.listen(changes.add);

        // Same state (still online, just different type)
        connectivityController.add([ConnectivityResult.mobile]);

        await Future<void>.delayed(const Duration(milliseconds: 100));

        // No change should be emitted
        expect(changes, isEmpty);

        await subscription.cancel();
        network.dispose();
      });
    });

    group('dispose', () {
      test('cancels subscription and closes controller', () async {
        when(() => mockConnectivity.checkConnectivity()).thenAnswer(
          (_) async => [ConnectivityResult.wifi],
        );

        final network = FlutterNetwork(connectivity: mockConnectivity);
        await network.initialize();

        var streamClosed = false;
        network.onConnectivityChanged.listen(
          (_) {},
          onDone: () => streamClosed = true,
        );

        network.dispose();

        // Give time for the stream to close
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(streamClosed, isTrue);
      });

      test('is safe to call multiple times', () async {
        when(() => mockConnectivity.checkConnectivity()).thenAnswer(
          (_) async => [ConnectivityResult.wifi],
        );

        final network = FlutterNetwork(connectivity: mockConnectivity);
        await network.initialize();

        // Should not throw
        network.dispose();
        network.dispose();
        network.dispose();
      });
    });

    group('edge cases', () {
      test('handles ethernet connectivity', () async {
        when(() => mockConnectivity.checkConnectivity()).thenAnswer(
          (_) async => [ConnectivityResult.ethernet],
        );

        final network = FlutterNetwork(connectivity: mockConnectivity);
        await network.initialize();

        expect(network.isOnline, isTrue);

        network.dispose();
      });

      test('handles vpn connectivity', () async {
        when(() => mockConnectivity.checkConnectivity()).thenAnswer(
          (_) async => [ConnectivityResult.vpn],
        );

        final network = FlutterNetwork(connectivity: mockConnectivity);
        await network.initialize();

        expect(network.isOnline, isTrue);

        network.dispose();
      });

      test('handles bluetooth connectivity', () async {
        when(() => mockConnectivity.checkConnectivity()).thenAnswer(
          (_) async => [ConnectivityResult.bluetooth],
        );

        final network = FlutterNetwork(connectivity: mockConnectivity);
        await network.initialize();

        expect(network.isOnline, isTrue);

        network.dispose();
      });

      test('custom debounce duration works', () async {
        when(() => mockConnectivity.checkConnectivity()).thenAnswer(
          (_) async => [ConnectivityResult.wifi],
        );

        final network = FlutterNetwork(
          connectivity: mockConnectivity,
          debounceDuration: const Duration(milliseconds: 200),
        );
        await network.initialize();

        final changes = <bool>[];
        final subscription = network.onConnectivityChanged.listen(changes.add);

        connectivityController.add([ConnectivityResult.none]);

        // Before debounce
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(changes, isEmpty);

        // After debounce
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(changes, [false]);

        await subscription.cancel();
        network.dispose();
      });
    });
  });
}
