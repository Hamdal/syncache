import 'dart:async';

import 'package:flutter/material.dart';
import 'package:syncache/syncache.dart';

import '../models/todo.dart';
import '../services/cache.dart';
import '../services/fake_api.dart';

/// Demonstrates reactive streams with watch().
///
/// This screen shows how `watch()` works:
/// 1. Initial fetch populates the stream
/// 2. Any cache updates (from get(), mutate(), etc.) emit new values
/// 3. Multiple watchers receive the same updates
///
/// The demo includes:
/// - Periodic auto-refresh to show stream updates
/// - Manual refresh that triggers stream emission
/// - Cache TTL countdown display
class WatchDemoScreen extends StatefulWidget {
  const WatchDemoScreen({super.key});

  @override
  State<WatchDemoScreen> createState() => _WatchDemoScreenState();
}

class _WatchDemoScreenState extends State<WatchDemoScreen> {
  StreamSubscription<TodoList>? _subscription;
  TodoList? _todos;
  bool _isLoading = true;
  String? _error;
  List<String> _events = [];
  int _updateCount = 0;

  // Auto-refresh timer
  Timer? _autoRefreshTimer;
  bool _autoRefreshEnabled = false;
  int _secondsUntilRefresh = 0;

  static const _autoRefreshInterval = Duration(seconds: 15);
  static const _ttl = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    _startWatching();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  void _addEvent(String event) {
    setState(() {
      _events = [
        '${DateTime.now().toString().substring(11, 19)}: $event',
        ..._events.take(14), // Keep last 15 events
      ];
    });
  }

  void _startWatching() {
    _subscription?.cancel();

    setState(() {
      _isLoading = true;
      _error = null;
      _updateCount = 0;
    });

    _addEvent('Started watching todos...');

    _subscription = todoCache
        .watch(
          key: 'todos:watch-demo',
          fetch: (_) => fakeApi.fetchTodos(),
          policy: Policy.staleWhileRefresh,
          ttl: _ttl,
        )
        .listen(
          (todos) {
            _updateCount++;
            _addEvent(
              'Stream update #$_updateCount: ${todos.items.length} todos '
              '(fetched: ${_formatTime(todos.fetchedAt)})',
            );
            setState(() {
              _todos = todos;
              _isLoading = false;
              _error = null;
            });
          },
          onError: (Object error) {
            _addEvent('Stream error: $error');
            setState(() {
              _error = error.toString();
              _isLoading = false;
            });
          },
        );
  }

  void _toggleAutoRefresh() {
    setState(() {
      _autoRefreshEnabled = !_autoRefreshEnabled;
    });

    if (_autoRefreshEnabled) {
      _addEvent(
        'Auto-refresh enabled (every ${_autoRefreshInterval.inSeconds}s)',
      );
      _secondsUntilRefresh = _autoRefreshInterval.inSeconds;
      _autoRefreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _secondsUntilRefresh--;
        });

        if (_secondsUntilRefresh <= 0) {
          _triggerRefresh();
          _secondsUntilRefresh = _autoRefreshInterval.inSeconds;
        }
      });
    } else {
      _addEvent('Auto-refresh disabled');
      _autoRefreshTimer?.cancel();
      _autoRefreshTimer = null;
    }
  }

  Future<void> _triggerRefresh() async {
    _addEvent('Triggering refresh (Policy.refresh)...');

    try {
      // Using Policy.refresh forces a network fetch and updates the cache
      // This will trigger stream watchers to receive the new value
      await todoCache.get(
        key: 'todos:watch-demo',
        fetch: (_) => fakeApi.fetchTodos(),
        policy: Policy.refresh,
        ttl: _ttl,
      );
      // Note: The stream listener above will log when it receives the update
    } catch (e) {
      _addEvent('Refresh failed: $e');
    }
  }

  Future<void> _simulateMutation() async {
    if (_todos == null) {
      _addEvent('Cannot mutate: no cached data');
      return;
    }

    _addEvent('Applying mutation...');

    try {
      await todoCache.mutate(
        key: 'todos:watch-demo',
        mutation: Mutation<TodoList>(
          apply: (current) {
            // Toggle the first incomplete todo
            final firstIncomplete = current.items.indexWhere(
              (t) => !t.completed,
            );
            if (firstIncomplete == -1) return current;
            return current.toggleTodo(current.items[firstIncomplete].id);
          },
          send: (optimistic) async {
            // Simulate server delay
            await Future.delayed(const Duration(milliseconds: 500));
            return optimistic;
          },
        ),
      );
      // The stream listener will log the update
    } catch (e) {
      _addEvent('Mutation failed: $e');
    }
  }

  Future<void> _invalidateAndRewatch() async {
    _addEvent('Invalidating cache...');
    await todoCache.invalidate('todos:watch-demo');
    _addEvent('Cache invalidated - restarting watch');
    _startWatching();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reactive Streams (watch)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _triggerRefresh,
            tooltip: 'Manual Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Event log
          Container(
            height: 150,
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
                        'Event Log',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Updates: $_updateCount',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                              ),
                        ),
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
                      final isUpdate = event.contains('Stream update');
                      return Text(
                        event,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: isUpdate
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: isUpdate
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Controls
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _simulateMutation,
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Mutate'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _triggerRefresh,
                    icon: const Icon(Icons.cloud_download, size: 18),
                    label: const Text('Refresh'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _toggleAutoRefresh,
                    icon: Icon(
                      _autoRefreshEnabled ? Icons.stop : Icons.play_arrow,
                      size: 18,
                    ),
                    label: Text(
                      _autoRefreshEnabled
                          ? 'Stop (${_secondsUntilRefresh}s)'
                          : 'Auto',
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(child: _buildContent()),

          // Bottom actions
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: OutlinedButton.icon(
              onPressed: _invalidateAndRewatch,
              icon: const Icon(Icons.delete_sweep),
              label: const Text('Invalidate & Restart Watch'),
            ),
          ),

          // Info card
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                          'How watch() Works',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'The stream emits values whenever the cache is updated:\n'
                      '- Mutate: applies optimistic update, stream emits\n'
                      '- Refresh: fetches new data, stream emits\n'
                      '- Auto: periodically refreshes to show live updates\n\n'
                      'Watch the "Stream update #N" events in the log!',
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

  Widget _buildContent() {
    if (_isLoading && _todos == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _todos == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: $_error'),
            const SizedBox(height: 16),
            FilledButton(onPressed: _startWatching, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_todos == null || _todos!.items.isEmpty) {
      return const Center(child: Text('No todos'));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _todos!.items.length,
      itemBuilder: (context, index) {
        final todo = _todos!.items[index];
        return ListTile(
          leading: Icon(
            todo.completed ? Icons.check_circle : Icons.radio_button_unchecked,
            color: todo.completed
                ? Colors.green
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          title: Text(
            todo.title,
            style: TextStyle(
              decoration: todo.completed ? TextDecoration.lineThrough : null,
            ),
          ),
          subtitle: Text(
            'Created: ${_formatTime(todo.createdAt)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inSeconds > 5) {
      return '${diff.inSeconds}s ago';
    } else {
      return 'just now';
    }
  }
}
