import 'package:flutter/material.dart';
import 'package:syncache/syncache.dart';

import '../models/user.dart';
import '../services/fake_api.dart';

/// Demonstrates Prefetch and PrefetchGraph for batch data loading.
///
/// This screen shows how to:
/// 1. Prefetch multiple items in parallel
/// 2. Use PrefetchGraph with dependencies
/// 3. Handle prefetch results and errors
class PrefetchDemoScreen extends StatefulWidget {
  const PrefetchDemoScreen({super.key});

  @override
  State<PrefetchDemoScreen> createState() => _PrefetchDemoScreenState();
}

class _PrefetchDemoScreenState extends State<PrefetchDemoScreen> {
  // Separate cache for this demo
  final _cache = Syncache<User>(
    store: MemoryStore<User>(),
    observers: [LoggingObserver()],
  );

  List<String> _events = [];
  bool _isLoading = false;
  Map<String, bool> _prefetchResults = {};

  @override
  void dispose() {
    _cache.dispose();
    super.dispose();
  }

  void _addEvent(String event) {
    setState(() {
      _events = [
        '${DateTime.now().toString().substring(11, 19)}: $event',
        ..._events.take(19),
      ];
    });
  }

  Future<void> _prefetchParallel() async {
    setState(() {
      _isLoading = true;
      _prefetchResults.clear();
    });

    _addEvent('Starting parallel prefetch of 4 users...');

    final stopwatch = Stopwatch()..start();

    final results = await _cache.prefetch([
      PrefetchRequest(
        key: 'user:1',
        fetch: (_) => _simulateFetch('User 1', 500),
      ),
      PrefetchRequest(
        key: 'user:2',
        fetch: (_) => _simulateFetch('User 2', 800),
      ),
      PrefetchRequest(
        key: 'user:3',
        fetch: (_) => _simulateFetch('User 3', 300),
      ),
      PrefetchRequest(
        key: 'user:4',
        fetch: (_) => _simulateFetch('User 4', 600),
      ),
    ]);

    stopwatch.stop();

    final succeeded = results.where((r) => r.success).length;
    final failed = results.where((r) => !r.success).length;

    setState(() {
      _prefetchResults = {for (final r in results) r.key: r.success};
    });

    _addEvent(
      'Parallel prefetch completed in ${stopwatch.elapsedMilliseconds}ms: '
      '$succeeded succeeded, $failed failed',
    );

    for (final result in results) {
      _addEvent(
        '  ${result.key}: ${result.success ? "✓" : "✗ ${result.error}"}',
      );
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _prefetchGraph() async {
    setState(() {
      _isLoading = true;
      _prefetchResults.clear();
    });

    _addEvent('Starting graph prefetch with dependencies...');
    _addEvent('  profile → settings → notifications (sequential)');
    _addEvent('  dashboard runs in parallel');

    final stopwatch = Stopwatch()..start();

    final result = await _cache.prefetchGraph(
      [
        // Profile must load first
        PrefetchNode(
          key: 'profile',
          fetch: (_) => _simulateFetch('Profile', 400),
        ),
        // Settings depends on profile
        PrefetchNode(
          key: 'settings',
          fetch: (_) => _simulateFetch('Settings', 300),
          dependsOn: ['profile'],
        ),
        // Notifications depends on settings
        PrefetchNode(
          key: 'notifications',
          fetch: (_) => _simulateFetch('Notifications', 200),
          dependsOn: ['settings'],
        ),
        // Dashboard runs in parallel (no dependencies)
        PrefetchNode(
          key: 'dashboard',
          fetch: (_) => _simulateFetch('Dashboard', 500),
        ),
      ],
      options: const PrefetchGraphOptions(
        failFast: false,
        skipOnDependencyFailure: true,
      ),
    );

    stopwatch.stop();

    setState(() {
      _prefetchResults = {
        for (final entry in result.results.entries)
          entry.key: entry.value.success,
      };
    });

    _addEvent(
      'Graph prefetch completed in ${result.totalDuration.inMilliseconds}ms',
    );
    _addEvent('  Succeeded: ${result.succeededKeys.join(", ")}');

    if (result.failedKeys.isNotEmpty) {
      _addEvent('  Failed: ${result.failedKeys.join(", ")}');
    }

    if (result.skippedKeys.isNotEmpty) {
      _addEvent('  Skipped: ${result.skippedKeys.join(", ")}');
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _prefetchGraphWithFailure() async {
    setState(() {
      _isLoading = true;
      _prefetchResults.clear();
    });

    _addEvent('Starting graph prefetch with simulated failure...');
    _addEvent('  settings will fail → notifications should be skipped');

    final stopwatch = Stopwatch()..start();

    final result = await _cache.prefetchGraph([
      PrefetchNode(
        key: 'profile',
        fetch: (_) => _simulateFetch('Profile', 300),
      ),
      PrefetchNode(
        key: 'settings',
        fetch: (_) async {
          await Future.delayed(const Duration(milliseconds: 200));
          throw Exception('Settings fetch failed');
        },
        dependsOn: ['profile'],
      ),
      PrefetchNode(
        key: 'notifications',
        fetch: (_) => _simulateFetch('Notifications', 200),
        dependsOn: ['settings'],
      ),
      PrefetchNode(
        key: 'dashboard',
        fetch: (_) => _simulateFetch('Dashboard', 400),
      ),
    ], options: const PrefetchGraphOptions(skipOnDependencyFailure: true));

    stopwatch.stop();

    setState(() {
      _prefetchResults = {
        for (final entry in result.results.entries)
          entry.key: entry.value.success,
      };
    });

    _addEvent('Graph completed in ${result.totalDuration.inMilliseconds}ms');

    for (final entry in result.results.entries) {
      final status = entry.value.status;
      final icon = status == PrefetchNodeStatus.success
          ? '✓'
          : status == PrefetchNodeStatus.skipped
          ? '⊘'
          : '✗';
      _addEvent('  ${entry.key}: $icon ${status.name}');
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _prefetchOne() async {
    setState(() {
      _isLoading = true;
      _prefetchResults.clear();
    });

    _addEvent('Prefetching single item...');

    final success = await _cache.prefetchOne(
      key: 'single-user',
      fetch: (_) => _simulateFetch('Single User', 600),
    );

    setState(() {
      _prefetchResults = {'single-user': success};
    });

    _addEvent('prefetchOne result: ${success ? "success" : "failed"}');

    // Now demonstrate that the data is cached
    final stopwatch = Stopwatch()..start();
    final user = await _cache.get(
      key: 'single-user',
      fetch: (_) => fakeApi.fetchUser(),
      policy: Policy.cacheOnly,
    );
    stopwatch.stop();

    _addEvent(
      'Subsequent cache read: ${user.name} in ${stopwatch.elapsedMilliseconds}ms',
    );

    setState(() {
      _isLoading = false;
    });
  }

  Future<User> _simulateFetch(String name, int delayMs) async {
    _addEvent('  Fetching $name...');
    await Future.delayed(Duration(milliseconds: delayMs));
    _addEvent('  $name fetched in ${delayMs}ms');
    return User(
      id: name.hashCode,
      name: name,
      email: '${name.toLowerCase().replaceAll(' ', '')}@example.com',
      avatarUrl: '',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Prefetch')),
      body: Column(
        children: [
          // Event log
          Container(
            height: 200,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.terminal,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Prefetch Log',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _events.length,
                    itemBuilder: (context, index) {
                      final event = _events[index];
                      final isFetch = event.contains('Fetching');
                      final isComplete =
                          event.contains('completed') ||
                          event.contains('fetched');
                      final isFailed =
                          event.contains('failed') || event.contains('✗');
                      final isSkipped =
                          event.contains('skipped') || event.contains('⊘');

                      Color? textColor;
                      if (isFetch) {
                        textColor = Colors.blue;
                      } else if (isComplete) {
                        textColor = Colors.green;
                      } else if (isFailed) {
                        textColor = Colors.red;
                      } else if (isSkipped) {
                        textColor = Colors.orange;
                      }

                      return Text(
                        event,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color:
                              textColor ??
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Results visualization
          if (_prefetchResults.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Prefetch Results',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _prefetchResults.entries.map((entry) {
                          return Chip(
                            avatar: Icon(
                              entry.value ? Icons.check_circle : Icons.error,
                              size: 18,
                              color: entry.value ? Colors.green : Colors.red,
                            ),
                            label: Text(entry.key),
                            backgroundColor: entry.value
                                ? Colors.green.withValues(alpha: 0.1)
                                : Colors.red.withValues(alpha: 0.1),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: _isLoading ? null : _prefetchParallel,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bolt),
                  label: const Text('Parallel Prefetch (4 items)'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _prefetchGraph,
                  icon: const Icon(Icons.account_tree),
                  label: const Text('Graph Prefetch (with dependencies)'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _prefetchGraphWithFailure,
                  icon: const Icon(Icons.warning),
                  label: const Text(
                    'Graph with Failure (skipOnDependencyFailure)',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _prefetchOne,
                  icon: const Icon(Icons.person),
                  label: const Text('Prefetch One'),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Info card
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Prefetch API',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '- prefetch(): Fetch multiple items in parallel\n'
                      '- prefetchGraph(): Fetch with dependency ordering\n'
                      '- prefetchOne(): Fetch a single item\n\n'
                      'Great for preloading data on app startup or navigation.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
