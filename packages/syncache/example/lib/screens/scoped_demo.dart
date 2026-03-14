import 'package:flutter/material.dart';
import 'package:syncache/syncache.dart';

import '../models/todo.dart';

/// Demonstrates ScopedSyncache for namespace isolation.
///
/// This screen shows how to:
/// 1. Create scoped caches for different contexts (workspaces, tenants)
/// 2. Isolate data between scopes
/// 3. Clear data for a specific scope
class ScopedDemoScreen extends StatefulWidget {
  const ScopedDemoScreen({super.key});

  @override
  State<ScopedDemoScreen> createState() => _ScopedDemoScreenState();
}

class _ScopedDemoScreenState extends State<ScopedDemoScreen> {
  // Base cache that stores all data
  final _baseCache = Syncache<TodoList>(
    store: MemoryStore<TodoList>(),
    observers: [LoggingObserver()],
  );

  // Scoped views for different workspaces
  late final ScopedSyncache<TodoList> _workspace1;
  late final ScopedSyncache<TodoList> _workspace2;
  late final ScopedSyncache<TodoList> _workspace3;

  String _selectedWorkspace = 'workspace:1';
  TodoList? _todos;
  bool _isLoading = false;
  List<String> _events = [];
  final Map<String, int> _todoCountByScope = {};

  @override
  void initState() {
    super.initState();
    _workspace1 = _baseCache.scoped('workspace:1');
    _workspace2 = _baseCache.scoped('workspace:2');
    _workspace3 = _baseCache.scoped('workspace:3');
  }

  @override
  void dispose() {
    _baseCache.dispose();
    super.dispose();
  }

  ScopedSyncache<TodoList> get _currentScope {
    switch (_selectedWorkspace) {
      case 'workspace:1':
        return _workspace1;
      case 'workspace:2':
        return _workspace2;
      case 'workspace:3':
        return _workspace3;
      default:
        return _workspace1;
    }
  }

  void _addEvent(String event) {
    setState(() {
      _events = [
        '${DateTime.now().toString().substring(11, 19)}: $event',
        ..._events.take(14),
      ];
    });
  }

  Future<void> _loadTodos() async {
    setState(() {
      _isLoading = true;
    });

    _addEvent('Loading todos for $_selectedWorkspace...');

    try {
      final todos = await _currentScope.get(
        key: 'todos',
        fetch: (_) => _fetchWorkspaceTodos(_selectedWorkspace),
        policy: Policy.offlineFirst,
        ttl: const Duration(minutes: 5),
      );

      setState(() {
        _todos = todos;
        _todoCountByScope[_selectedWorkspace] = todos.items.length;
        _isLoading = false;
      });

      _addEvent('Loaded ${todos.items.length} todos for $_selectedWorkspace');
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _addEvent('Error: $e');
    }
  }

  Future<TodoList> _fetchWorkspaceTodos(String workspace) async {
    await Future.delayed(const Duration(milliseconds: 500));

    // Return different todos for each workspace
    final now = DateTime.now();
    final workspaceNum = int.parse(workspace.split(':').last);

    return TodoList(
      fetchedAt: now,
      items: List.generate(
        3 + workspaceNum,
        (i) => Todo(
          id: workspaceNum * 100 + i,
          title: 'Workspace $workspaceNum - Task ${i + 1}',
          completed: i.isEven,
          createdAt: now.subtract(Duration(hours: i)),
        ),
      ),
    );
  }

  Future<void> _addTodoToCurrentScope() async {
    if (_todos == null) {
      _addEvent('Load todos first');
      return;
    }

    _addEvent('Adding todo to $_selectedWorkspace...');

    await _currentScope.mutate(
      key: 'todos',
      mutation: Mutation<TodoList>(
        apply: (current) {
          final newTodo = Todo(
            id: DateTime.now().millisecondsSinceEpoch,
            title: '$_selectedWorkspace - New Task',
            completed: false,
            createdAt: DateTime.now(),
          );
          return current.addTodo(newTodo);
        },
        send: (optimistic) async {
          await Future.delayed(const Duration(milliseconds: 300));
          return optimistic;
        },
      ),
    );

    // Refresh display
    await _loadTodos();
  }

  Future<void> _clearCurrentScope() async {
    _addEvent('Clearing $_selectedWorkspace...');

    await _currentScope.clear();

    setState(() {
      _todos = null;
      _todoCountByScope.remove(_selectedWorkspace);
    });

    _addEvent('$_selectedWorkspace cleared');
  }

  Future<void> _clearAllScopes() async {
    _addEvent('Clearing all workspaces...');

    await _baseCache.clear();

    setState(() {
      _todos = null;
      _todoCountByScope.clear();
    });

    _addEvent('All workspaces cleared');
  }

  Future<void> _loadAllScopes() async {
    _addEvent('Loading all workspaces...');

    setState(() {
      _isLoading = true;
    });

    // Load all three workspaces
    final results = await Future.wait([
      _workspace1.get(
        key: 'todos',
        fetch: (_) => _fetchWorkspaceTodos('workspace:1'),
        policy: Policy.offlineFirst,
      ),
      _workspace2.get(
        key: 'todos',
        fetch: (_) => _fetchWorkspaceTodos('workspace:2'),
        policy: Policy.offlineFirst,
      ),
      _workspace3.get(
        key: 'todos',
        fetch: (_) => _fetchWorkspaceTodos('workspace:3'),
        policy: Policy.offlineFirst,
      ),
    ]);

    setState(() {
      _todoCountByScope['workspace:1'] = results[0].items.length;
      _todoCountByScope['workspace:2'] = results[1].items.length;
      _todoCountByScope['workspace:3'] = results[2].items.length;
      _isLoading = false;
    });

    _addEvent('All workspaces loaded');
    _addEvent('  workspace:1: ${results[0].items.length} todos');
    _addEvent('  workspace:2: ${results[1].items.length} todos');
    _addEvent('  workspace:3: ${results[2].items.length} todos');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scoped Caches')),
      body: Column(
        children: [
          // Workspace selector
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Workspace',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _WorkspaceChip(
                      label: 'Workspace 1',
                      scope: 'workspace:1',
                      isSelected: _selectedWorkspace == 'workspace:1',
                      todoCount: _todoCountByScope['workspace:1'],
                      onTap: () {
                        setState(() {
                          _selectedWorkspace = 'workspace:1';
                          _todos = null;
                        });
                        _loadTodos();
                      },
                    ),
                    const SizedBox(width: 8),
                    _WorkspaceChip(
                      label: 'Workspace 2',
                      scope: 'workspace:2',
                      isSelected: _selectedWorkspace == 'workspace:2',
                      todoCount: _todoCountByScope['workspace:2'],
                      onTap: () {
                        setState(() {
                          _selectedWorkspace = 'workspace:2';
                          _todos = null;
                        });
                        _loadTodos();
                      },
                    ),
                    const SizedBox(width: 8),
                    _WorkspaceChip(
                      label: 'Workspace 3',
                      scope: 'workspace:3',
                      isSelected: _selectedWorkspace == 'workspace:3',
                      todoCount: _todoCountByScope['workspace:3'],
                      onTap: () {
                        setState(() {
                          _selectedWorkspace = 'workspace:3';
                          _todos = null;
                        });
                        _loadTodos();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Event log
          Container(
            height: 120,
            color: Theme.of(context).colorScheme.surfaceContainer,
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
                        'Scope Log',
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
                      return Text(
                        _events[index],
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Todos list
          Expanded(child: _buildTodosList()),

          // Action buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isLoading ? null : _loadTodos,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Load'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _addTodoToCurrentScope,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Todo'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _clearCurrentScope,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Clear Scope'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _loadAllScopes,
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('Load All'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _isLoading ? null : _clearAllScopes,
                  icon: const Icon(Icons.delete_forever, size: 18),
                  label: const Text('Clear All Workspaces'),
                ),
              ],
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
                          'ScopedSyncache',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Keys are auto-prefixed with scope:\n'
                      '"todos" becomes "workspace:1:todos"\n\n'
                      'Great for multi-tenant apps or user sessions.',
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

  Widget _buildTodosList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_todos == null) {
      return Center(
        child: Text(
          'Select a workspace and load todos',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    if (_todos!.items.isEmpty) {
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
          title: Text(todo.title),
          subtitle: Text('ID: ${todo.id}'),
        );
      },
    );
  }
}

class _WorkspaceChip extends StatelessWidget {
  final String label;
  final String scope;
  final bool isSelected;
  final int? todoCount;
  final VoidCallback onTap;

  const _WorkspaceChip({
    required this.label,
    required this.scope,
    required this.isSelected,
    required this.todoCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            if (todoCount != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  todoCount.toString(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isSelected
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
