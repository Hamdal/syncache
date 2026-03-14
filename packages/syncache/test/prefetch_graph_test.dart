import 'dart:async';

import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

void main() {
  group('PrefetchNode', () {
    test('has correct default values', () {
      final node = PrefetchNode<String>(
        key: 'test',
        fetch: (_) async => 'value',
      );

      expect(node.key, equals('test'));
      expect(node.ttl, isNull);
      expect(node.policy, equals(Policy.refresh));
      expect(node.retry, isNull);
      expect(node.dependsOn, isEmpty);
    });

    test('accepts all parameters', () {
      final node = PrefetchNode<String>(
        key: 'test',
        fetch: (_) async => 'value',
        ttl: const Duration(hours: 1),
        policy: Policy.offlineFirst,
        retry: RetryConfig.none,
        dependsOn: ['dep1', 'dep2'],
      );

      expect(node.key, equals('test'));
      expect(node.ttl, equals(const Duration(hours: 1)));
      expect(node.policy, equals(Policy.offlineFirst));
      expect(node.retry, equals(RetryConfig.none));
      expect(node.dependsOn, equals(['dep1', 'dep2']));
    });
  });

  group('PrefetchGraphOptions', () {
    test('has correct default values', () {
      const options = PrefetchGraphOptions();
      expect(options.failFast, isFalse);
      expect(options.skipOnDependencyFailure, isTrue);
    });

    test('defaults constant has correct values', () {
      expect(PrefetchGraphOptions.defaults.failFast, isFalse);
      expect(PrefetchGraphOptions.defaults.skipOnDependencyFailure, isTrue);
    });
  });

  group('PrefetchNodeResult', () {
    test('success result has correct properties', () {
      final result = PrefetchNodeResult.success(
        'test-key',
        const Duration(milliseconds: 100),
      );

      expect(result.key, equals('test-key'));
      expect(result.status, equals(PrefetchNodeStatus.success));
      expect(result.success, isTrue);
      expect(result.skipped, isFalse);
      expect(result.duration, equals(const Duration(milliseconds: 100)));
      expect(result.error, isNull);
      expect(result.stackTrace, isNull);
    });

    test('failure result has correct properties', () {
      final error = Exception('Test error');
      final stackTrace = StackTrace.current;
      final result = PrefetchNodeResult.failure(
        'test-key',
        error,
        stackTrace,
        const Duration(milliseconds: 50),
      );

      expect(result.key, equals('test-key'));
      expect(result.status, equals(PrefetchNodeStatus.failed));
      expect(result.success, isFalse);
      expect(result.skipped, isFalse);
      expect(result.duration, equals(const Duration(milliseconds: 50)));
      expect(result.error, equals(error));
      expect(result.stackTrace, equals(stackTrace));
    });

    test('skipped result has correct properties', () {
      final result = PrefetchNodeResult.skipped(
        'test-key',
        'Dependency failed',
      );

      expect(result.key, equals('test-key'));
      expect(result.status, equals(PrefetchNodeStatus.skipped));
      expect(result.success, isFalse);
      expect(result.skipped, isTrue);
      expect(result.duration, isNull);
      expect(result.error, equals('Dependency failed'));
    });
  });

  group('PrefetchGraphResult', () {
    test('allSucceeded returns true when all nodes succeed', () {
      final result = PrefetchGraphResult(
        results: {
          'a':
              PrefetchNodeResult.success('a', const Duration(milliseconds: 10)),
          'b':
              PrefetchNodeResult.success('b', const Duration(milliseconds: 20)),
        },
        totalDuration: const Duration(milliseconds: 30),
      );

      expect(result.allSucceeded, isTrue);
      expect(result.anySucceeded, isTrue);
      expect(result.failedKeys, isEmpty);
      expect(result.skippedKeys, isEmpty);
      expect(result.succeededKeys, equals(['a', 'b']));
    });

    test('allSucceeded returns false when any node fails', () {
      final result = PrefetchGraphResult(
        results: {
          'a':
              PrefetchNodeResult.success('a', const Duration(milliseconds: 10)),
          'b': PrefetchNodeResult.failure(
            'b',
            Exception('error'),
            StackTrace.empty,
            const Duration(milliseconds: 20),
          ),
        },
        totalDuration: const Duration(milliseconds: 30),
      );

      expect(result.allSucceeded, isFalse);
      expect(result.anySucceeded, isTrue);
      expect(result.failedKeys, equals(['b']));
      expect(result.succeededKeys, equals(['a']));
    });

    test('skippedKeys returns skipped nodes', () {
      final result = PrefetchGraphResult(
        results: {
          'a': PrefetchNodeResult.failure(
            'a',
            Exception('error'),
            StackTrace.empty,
            const Duration(milliseconds: 10),
          ),
          'b': PrefetchNodeResult.skipped('b', 'Dependency "a" failed'),
        },
        totalDuration: const Duration(milliseconds: 30),
      );

      expect(result.skippedKeys, equals(['b']));
      expect(result.failedKeys, equals(['a']));
    });

    test('operator[] returns correct result', () {
      final result = PrefetchGraphResult(
        results: {
          'a':
              PrefetchNodeResult.success('a', const Duration(milliseconds: 10)),
        },
        totalDuration: const Duration(milliseconds: 10),
      );

      expect(result['a']?.success, isTrue);
      expect(result['nonexistent'], isNull);
    });
  });

  group('Syncache.prefetchGraph', () {
    late Syncache<String> cache;
    late MemoryStore<String> store;

    setUp(() {
      store = MemoryStore<String>();
      cache = Syncache<String>(store: store);
    });

    tearDown(() {
      cache.dispose();
    });

    test('returns empty result for empty node list', () async {
      final result = await cache.prefetchGraph([]);

      expect(result.results, isEmpty);
      expect(result.totalDuration, equals(Duration.zero));
      expect(result.allSucceeded, isTrue);
    });

    test('executes single node successfully', () async {
      var fetchCalled = false;
      final result = await cache.prefetchGraph([
        PrefetchNode<String>(
          key: 'test',
          fetch: (_) async {
            fetchCalled = true;
            return 'value';
          },
        ),
      ]);

      expect(fetchCalled, isTrue);
      expect(result.allSucceeded, isTrue);
      expect(result.results['test']?.success, isTrue);

      // Verify data was cached
      final cached = await store.read('test');
      expect(cached?.value, equals('value'));
    });

    test('executes independent nodes in parallel', () async {
      final executionOrder = <String>[];
      final completer1 = Completer<void>();
      final completer2 = Completer<void>();

      final resultFuture = cache.prefetchGraph([
        PrefetchNode<String>(
          key: 'a',
          fetch: (_) async {
            executionOrder.add('a-start');
            completer1.complete();
            await Future.delayed(const Duration(milliseconds: 50));
            executionOrder.add('a-end');
            return 'value-a';
          },
        ),
        PrefetchNode<String>(
          key: 'b',
          fetch: (_) async {
            executionOrder.add('b-start');
            completer2.complete();
            await Future.delayed(const Duration(milliseconds: 50));
            executionOrder.add('b-end');
            return 'value-b';
          },
        ),
      ]);

      // Wait for both to start
      await Future.wait([completer1.future, completer2.future]);

      // Both should have started before either finished
      expect(executionOrder, containsAll(['a-start', 'b-start']));
      expect(executionOrder.indexOf('a-end'), equals(-1));
      expect(executionOrder.indexOf('b-end'), equals(-1));

      final result = await resultFuture;
      expect(result.allSucceeded, isTrue);
    });

    test('executes nodes in dependency order', () async {
      final executionOrder = <String>[];

      final result = await cache.prefetchGraph([
        PrefetchNode<String>(
          key: 'child',
          fetch: (_) async {
            executionOrder.add('child');
            return 'child-value';
          },
          dependsOn: ['parent'],
        ),
        PrefetchNode<String>(
          key: 'parent',
          fetch: (_) async {
            executionOrder.add('parent');
            return 'parent-value';
          },
        ),
      ]);

      expect(result.allSucceeded, isTrue);
      expect(executionOrder, equals(['parent', 'child']));
    });

    test('executes complex dependency graph correctly', () async {
      // Graph:
      //   a (no deps)
      //   b (depends on a)
      //   c (no deps, parallel with a)
      //   d (depends on b and c)
      final executionOrder = <String>[];
      final timestamps = <String, int>{};
      var time = 0;

      Future<String> timedFetch(String key) async {
        timestamps['$key-start'] = time++;
        executionOrder.add(key);
        await Future.delayed(const Duration(milliseconds: 10));
        timestamps['$key-end'] = time++;
        return 'value-$key';
      }

      final result = await cache.prefetchGraph([
        PrefetchNode<String>(key: 'a', fetch: (_) => timedFetch('a')),
        PrefetchNode<String>(
          key: 'b',
          fetch: (_) => timedFetch('b'),
          dependsOn: ['a'],
        ),
        PrefetchNode<String>(key: 'c', fetch: (_) => timedFetch('c')),
        PrefetchNode<String>(
          key: 'd',
          fetch: (_) => timedFetch('d'),
          dependsOn: ['b', 'c'],
        ),
      ]);

      expect(result.allSucceeded, isTrue);

      // a must come before b
      expect(
          executionOrder.indexOf('a'), lessThan(executionOrder.indexOf('b')));
      // b must come before d
      expect(
          executionOrder.indexOf('b'), lessThan(executionOrder.indexOf('d')));
      // c must come before d
      expect(
          executionOrder.indexOf('c'), lessThan(executionOrder.indexOf('d')));
    });

    test('throws on duplicate keys', () async {
      expect(
        () => cache.prefetchGraph([
          PrefetchNode<String>(key: 'a', fetch: (_) async => 'value'),
          PrefetchNode<String>(key: 'a', fetch: (_) async => 'value'),
        ]),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Duplicate key'),
        )),
      );
    });

    test('throws on missing dependency', () async {
      expect(
        () => cache.prefetchGraph([
          PrefetchNode<String>(
            key: 'a',
            fetch: (_) async => 'value',
            dependsOn: ['nonexistent'],
          ),
        ]),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('not in the graph'),
        )),
      );
    });

    test('throws on circular dependency', () async {
      expect(
        () => cache.prefetchGraph([
          PrefetchNode<String>(
            key: 'a',
            fetch: (_) async => 'value',
            dependsOn: ['b'],
          ),
          PrefetchNode<String>(
            key: 'b',
            fetch: (_) async => 'value',
            dependsOn: ['a'],
          ),
        ]),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Circular dependency'),
        )),
      );
    });

    test('throws on complex circular dependency', () async {
      expect(
        () => cache.prefetchGraph([
          PrefetchNode<String>(
            key: 'a',
            fetch: (_) async => 'value',
            dependsOn: ['c'],
          ),
          PrefetchNode<String>(
            key: 'b',
            fetch: (_) async => 'value',
            dependsOn: ['a'],
          ),
          PrefetchNode<String>(
            key: 'c',
            fetch: (_) async => 'value',
            dependsOn: ['b'],
          ),
        ]),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Circular dependency'),
        )),
      );
    });

    test('handles node failure gracefully', () async {
      final result = await cache.prefetchGraph([
        PrefetchNode<String>(
          key: 'a',
          fetch: (_) async => throw Exception('Test error'),
        ),
        PrefetchNode<String>(
          key: 'b',
          fetch: (_) async => 'value-b',
        ),
      ]);

      expect(result.allSucceeded, isFalse);
      expect(result.anySucceeded, isTrue);
      expect(result.results['a']?.success, isFalse);
      expect(result.results['b']?.success, isTrue);
    });

    group('skipOnDependencyFailure', () {
      test('skips dependent nodes when dependency fails (default)', () async {
        final executionOrder = <String>[];

        final result = await cache.prefetchGraph([
          PrefetchNode<String>(
            key: 'parent',
            fetch: (_) async {
              executionOrder.add('parent');
              throw Exception('Parent failed');
            },
          ),
          PrefetchNode<String>(
            key: 'child',
            fetch: (_) async {
              executionOrder.add('child');
              return 'child-value';
            },
            dependsOn: ['parent'],
          ),
        ]);

        expect(executionOrder, equals(['parent']));
        expect(result.results['parent']?.success, isFalse);
        expect(result.results['child']?.skipped, isTrue);
        expect(result.skippedKeys, equals(['child']));
      });

      test('executes dependent nodes when skipOnDependencyFailure is false',
          () async {
        final executionOrder = <String>[];

        final result = await cache.prefetchGraph(
          [
            PrefetchNode<String>(
              key: 'parent',
              fetch: (_) async {
                executionOrder.add('parent');
                throw Exception('Parent failed');
              },
            ),
            PrefetchNode<String>(
              key: 'child',
              fetch: (_) async {
                executionOrder.add('child');
                return 'child-value';
              },
              dependsOn: ['parent'],
            ),
          ],
          options: const PrefetchGraphOptions(skipOnDependencyFailure: false),
        );

        expect(executionOrder, equals(['parent', 'child']));
        expect(result.results['parent']?.success, isFalse);
        expect(result.results['child']?.success, isTrue);
      });
    });

    group('failFast', () {
      test('skips remaining nodes when failFast is enabled', () async {
        final executionOrder = <String>[];

        // Create a scenario where:
        // - 'a' depends on 'b'
        // - 'b' fails
        // - 'a' should be skipped due to fail-fast + dependency failure
        final result = await cache.prefetchGraph(
          [
            PrefetchNode<String>(
              key: 'b',
              fetch: (_) async {
                executionOrder.add('b');
                throw Exception('B failed');
              },
            ),
            PrefetchNode<String>(
              key: 'a',
              fetch: (_) async {
                executionOrder.add('a');
                return 'a-value';
              },
              dependsOn: ['b'],
            ),
          ],
          options: const PrefetchGraphOptions(failFast: true),
        );

        // b should have executed and failed
        expect(executionOrder, equals(['b']));
        expect(result.results['b']?.success, isFalse);
        // a should be skipped (dependency failed + fail-fast)
        expect(result.results['a']?.skipped, isTrue);
      });

      test('continues independent in-flight nodes when failFast is enabled',
          () async {
        final executionOrder = <String>[];

        // Both nodes are independent and start in parallel
        // Even with failFast, both should complete since they start together
        final result = await cache.prefetchGraph(
          [
            PrefetchNode<String>(
              key: 'fast-fail',
              fetch: (_) async {
                executionOrder.add('fast-fail');
                throw Exception('Fast failure');
              },
            ),
            PrefetchNode<String>(
              key: 'independent',
              fetch: (_) async {
                executionOrder.add('independent');
                return 'independent-value';
              },
            ),
          ],
          options: const PrefetchGraphOptions(failFast: true),
        );

        // Both should have executed since they're independent and start together
        expect(executionOrder, containsAll(['fast-fail', 'independent']));
        expect(result.results['fast-fail']?.success, isFalse);
        expect(result.results['independent']?.success, isTrue);
      });
    });

    test('respects node policy', () async {
      // Pre-populate cache
      await store.write(
        'cached',
        Stored(
          value: 'cached-value',
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
      );

      var fetchCalled = false;

      final result = await cache.prefetchGraph([
        PrefetchNode<String>(
          key: 'cached',
          fetch: (_) async {
            fetchCalled = true;
            return 'fresh-value';
          },
          policy: Policy.offlineFirst, // Should use cached value
        ),
      ]);

      expect(result.allSucceeded, isTrue);
      expect(fetchCalled, isFalse);
    });

    test('respects node TTL', () async {
      final result = await cache.prefetchGraph([
        PrefetchNode<String>(
          key: 'with-ttl',
          fetch: (_) async => 'value',
          ttl: const Duration(hours: 1),
        ),
      ]);

      expect(result.allSucceeded, isTrue);

      final cached = await store.read('with-ttl');
      expect(cached?.meta.ttl, equals(const Duration(hours: 1)));
    });

    test('measures individual node durations', () async {
      final result = await cache.prefetchGraph([
        PrefetchNode<String>(
          key: 'fast',
          fetch: (_) async {
            await Future.delayed(const Duration(milliseconds: 10));
            return 'fast-value';
          },
        ),
        PrefetchNode<String>(
          key: 'slow',
          fetch: (_) async {
            await Future.delayed(const Duration(milliseconds: 50));
            return 'slow-value';
          },
        ),
      ]);

      expect(result.results['fast']?.duration, isNotNull);
      expect(result.results['slow']?.duration, isNotNull);
      expect(
        result.results['slow']!.duration!,
        greaterThan(result.results['fast']!.duration!),
      );
    });

    test('measures total duration', () async {
      final result = await cache.prefetchGraph([
        PrefetchNode<String>(
          key: 'a',
          fetch: (_) async {
            await Future.delayed(const Duration(milliseconds: 20));
            return 'value';
          },
        ),
      ]);

      expect(result.totalDuration.inMilliseconds, greaterThanOrEqualTo(20));
    });

    test('throws after dispose', () async {
      cache.dispose();

      expect(
        () => cache.prefetchGraph([
          PrefetchNode<String>(key: 'test', fetch: (_) async => 'value'),
        ]),
        throwsStateError,
      );
    });
  });
}
