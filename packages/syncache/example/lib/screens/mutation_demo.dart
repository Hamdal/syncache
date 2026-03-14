import 'dart:async';

import 'package:flutter/material.dart';
import 'package:syncache/syncache.dart';

import '../models/todo.dart';
import '../services/cache.dart';
import '../services/fake_api.dart';

/// Demonstrates optimistic mutations.
///
/// This screen shows how `mutate()` works:
/// 1. Local cache is updated immediately (optimistic update)
/// 2. UI reflects changes instantly
/// 3. Background sync sends changes to server
/// 4. Server response is merged with pending optimistic updates
///
/// Syncache handles concurrent mutations correctly - when a mutation's
/// `send` completes, any pending mutations are re-applied on top of
/// the server response, preserving all optimistic updates.
class MutationDemoScreen extends StatefulWidget {
  const MutationDemoScreen({super.key});

  @override
  State<MutationDemoScreen> createState() => _MutationDemoScreenState();
}

class _MutationDemoScreenState extends State<MutationDemoScreen> {
  StreamSubscription<TodoList>? _subscription;
  TodoList? _todos;
  bool _isLoading = true;
  String? _error;
  List<String> _events = [];
  final TextEditingController _textController = TextEditingController();

  // Track in-flight mutations to show sync status
  final Set<int> _mutatingTodoIds = {};

  @override
  void initState() {
    super.initState();
    _loadTodos();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _textController.dispose();
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

  void _loadTodos() {
    _subscription?.cancel();

    setState(() {
      _isLoading = true;
      _error = null;
      _mutatingTodoIds.clear();
    });

    _addEvent('Loading todos...');

    _subscription = todoCache
        .watch(
          key: 'todos:mutations',
          fetch: (_) => fakeApi.fetchTodos(),
          policy: Policy.offlineFirst,
          ttl: const Duration(minutes: 5),
        )
        .listen(
          (todos) {
            _addEvent('Cache updated: ${_summarizeTodos(todos)}');
            setState(() {
              _todos = todos;
              _isLoading = false;
              _error = null;
            });
          },
          onError: (Object error) {
            _addEvent('Error: $error');
            setState(() {
              _error = error.toString();
              _isLoading = false;
            });
          },
        );
  }

  String _summarizeTodos(TodoList todos) {
    final completed = todos.items.where((t) => t.completed).length;
    return '$completed/${todos.items.length} completed';
  }

  Future<void> _toggleTodo(Todo todo) async {
    // Track that this todo is being mutated
    setState(() {
      _mutatingTodoIds.add(todo.id);
    });

    final newState = !todo.completed ? 'completed' : 'incomplete';
    _addEvent('Toggle #${todo.id} → $newState (optimistic)');

    try {
      await todoCache.mutate(
        key: 'todos:mutations',
        mutation: Mutation<TodoList>(
          // Optimistic update - runs immediately
          apply: (current) => current.toggleTodo(todo.id),
          // Sync to server - runs in background
          send: (optimistic) => fakeApi.updateTodos(optimistic),
        ),
      );
      _addEvent('Toggle #${todo.id} synced to server');
    } catch (e) {
      _addEvent('Toggle #${todo.id} failed: $e');
    } finally {
      setState(() {
        _mutatingTodoIds.remove(todo.id);
      });
    }
  }

  Future<void> _addTodo() async {
    final title = _textController.text.trim();
    if (title.isEmpty) return;

    _textController.clear();

    if (_todos == null) {
      _addEvent('Cannot add: no cached data');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Load todos first before adding new ones'),
        ),
      );
      return;
    }

    _addEvent('Adding "$title" (optimistic)');

    try {
      await todoCache.mutate(
        key: 'todos:mutations',
        mutation: Mutation<TodoList>(
          apply: (current) {
            final newTodo = Todo(
              id: DateTime.now().millisecondsSinceEpoch, // Unique temp ID
              title: title,
              completed: false,
              createdAt: DateTime.now(),
            );
            return current.addTodo(newTodo);
          },
          send: (optimistic) => fakeApi.addTodo(_todos!, title),
        ),
      );
      _addEvent('Add "$title" synced to server');
    } catch (e) {
      _addEvent('Add "$title" failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPendingMutations = todoCache.pendingMutationCount > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Optimistic Mutations'),
        actions: [
          if (hasPendingMutations)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${todoCache.pendingMutationCount} pending',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              todoCache.invalidate('todos:mutations');
              _loadTodos();
            },
            tooltip: 'Reload',
          ),
        ],
      ),
      body: Column(
        children: [
          // Event log
          Container(
            height: 130,
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
                        'Mutation Log',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const Spacer(),
                      if (_mutatingTodoIds.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Syncing ${_mutatingTodoIds.length}...',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: Colors.orange),
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
                      final isOptimistic = event.contains('optimistic');
                      final isSynced = event.contains('synced');
                      final isError = event.contains('failed');

                      Color? textColor;
                      if (isOptimistic) {
                        textColor = Colors.orange;
                      } else if (isSynced) {
                        textColor = Colors.green;
                      } else if (isError) {
                        textColor = Colors.red;
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

          // Add todo input
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'Add a new todo...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _addTodo(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(onPressed: _addTodo, child: const Text('Add')),
              ],
            ),
          ),

          // Content
          Expanded(child: _buildContent()),

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
                        const SizedBox(width: 12),
                        Text(
                          'Optimistic Mutations',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tap todos rapidly to test concurrent mutations. '
                      'Changes appear instantly (orange), then sync to server (green). '
                      'Pending mutations are preserved when earlier syncs complete. '
                      'Go offline to queue mutations.',
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
            FilledButton(onPressed: _loadTodos, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_todos == null || _todos!.items.isEmpty) {
      return const Center(child: Text('No todos - add one above!'));
    }

    return ListView.builder(
      itemCount: _todos!.items.length,
      itemBuilder: (context, index) {
        final todo = _todos!.items[index];
        final isMutating = _mutatingTodoIds.contains(todo.id);

        return ListTile(
          onTap: () => _toggleTodo(todo),
          leading: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  todo.completed
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  key: ValueKey(todo.completed),
                  color: todo.completed
                      ? Colors.green
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (isMutating)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.orange,
                  ),
                ),
            ],
          ),
          title: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              decoration: todo.completed ? TextDecoration.lineThrough : null,
              color: todo.completed
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : Theme.of(context).colorScheme.onSurface,
            ),
            child: Text(todo.title),
          ),
          subtitle: Text(
            'ID: ${todo.id}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: const Icon(Icons.chevron_right),
        );
      },
    );
  }
}
