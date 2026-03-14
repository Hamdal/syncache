import 'dart:async';

import 'package:flutter/material.dart';
import 'package:syncache/syncache.dart';

/// A simple item for demonstrating list operations.
class Item {
  final String id;
  final String title;
  final bool favorite;

  const Item({required this.id, required this.title, this.favorite = false});

  Item copyWith({String? id, String? title, bool? favorite}) {
    return Item(
      id: id ?? this.id,
      title: title ?? this.title,
      favorite: favorite ?? this.favorite,
    );
  }
}

/// Demonstrates ListOperation for type-safe list mutations.
///
/// This screen shows how to:
/// 1. Use ListOperation.append, prepend, insert
/// 2. Use ListOperation.updateWhere to modify items
/// 3. Use ListOperation.removeWhere to delete items
/// 4. Use mutateList and mutateListItem extensions
class ListOperationDemoScreen extends StatefulWidget {
  const ListOperationDemoScreen({super.key});

  @override
  State<ListOperationDemoScreen> createState() =>
      _ListOperationDemoScreenState();
}

class _ListOperationDemoScreenState extends State<ListOperationDemoScreen> {
  // Cache for list of items
  final _cache = Syncache<List<Item>>(
    store: MemoryStore<List<Item>>(),
    observers: [LoggingObserver()],
  );

  List<Item>? _items;
  StreamSubscription<List<Item>>? _subscription;
  List<String> _events = [];
  bool _isLoading = false;
  int _itemCounter = 0;

  @override
  void initState() {
    super.initState();
    _startWatching();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _cache.dispose();
    super.dispose();
  }

  void _addEvent(String event) {
    setState(() {
      _events = [
        '${DateTime.now().toString().substring(11, 19)}: $event',
        ..._events.take(14),
      ];
    });
  }

  void _startWatching() {
    _subscription?.cancel();
    _subscription = _cache
        .watch(
          key: 'items',
          fetch: (_) async {
            await Future.delayed(const Duration(milliseconds: 300));
            return [
              const Item(id: '1', title: 'First Item'),
              const Item(id: '2', title: 'Second Item'),
              const Item(id: '3', title: 'Third Item', favorite: true),
            ];
          },
          policy: Policy.offlineFirst,
        )
        .listen((items) {
          setState(() {
            _items = items;
            _isLoading = false;
          });
          _addEvent('List updated: ${items.length} items');
        });

    setState(() {
      _isLoading = true;
    });
  }

  Future<void> _appendItem() async {
    _itemCounter++;
    final newItem = Item(
      id: 'new-$_itemCounter',
      title: 'Appended Item $_itemCounter',
    );

    _addEvent('Appending: ${newItem.title}');

    await _cache.mutateList(
      key: 'items',
      operation: ListOperation.append(newItem),
      send: () async {
        await Future.delayed(const Duration(milliseconds: 300));
        _addEvent('  Append synced to server');
      },
    );
  }

  Future<void> _prependItem() async {
    _itemCounter++;
    final newItem = Item(
      id: 'new-$_itemCounter',
      title: 'Prepended Item $_itemCounter',
    );

    _addEvent('Prepending: ${newItem.title}');

    await _cache.mutateList(
      key: 'items',
      operation: ListOperation.prepend(newItem),
      send: () async {
        await Future.delayed(const Duration(milliseconds: 300));
        _addEvent('  Prepend synced to server');
      },
    );
  }

  Future<void> _insertAtIndex(int index) async {
    _itemCounter++;
    final newItem = Item(
      id: 'new-$_itemCounter',
      title: 'Inserted Item $_itemCounter',
    );

    _addEvent('Inserting at index $index: ${newItem.title}');

    await _cache.mutateList(
      key: 'items',
      operation: ListOperation.insert(index, newItem),
      send: () async {
        await Future.delayed(const Duration(milliseconds: 300));
        _addEvent('  Insert synced to server');
      },
    );
  }

  Future<void> _toggleFavorite(Item item) async {
    final newFavorite = !item.favorite;
    _addEvent('Toggling favorite for ${item.title}: $newFavorite');

    await _cache.mutateList(
      key: 'items',
      operation: ListOperation.updateWhere(
        (i) => i.id == item.id,
        (i) => i.copyWith(favorite: newFavorite),
      ),
      send: () async {
        await Future.delayed(const Duration(milliseconds: 300));
        _addEvent('  Favorite toggle synced');
      },
    );
  }

  Future<void> _updateAllTitles() async {
    _addEvent('Updating all non-favorite titles...');

    await _cache.mutateList(
      key: 'items',
      operation: ListOperation.updateWhere(
        (i) => !i.favorite,
        (i) => i.copyWith(title: '${i.title} (updated)'),
      ),
      send: () async {
        await Future.delayed(const Duration(milliseconds: 300));
        _addEvent('  Bulk update synced');
      },
    );
  }

  Future<void> _removeItem(Item item) async {
    _addEvent('Removing: ${item.title}');

    await _cache.mutateList(
      key: 'items',
      operation: ListOperation.removeWhere((i) => i.id == item.id),
      send: () async {
        await Future.delayed(const Duration(milliseconds: 300));
        _addEvent('  Remove synced to server');
      },
    );
  }

  Future<void> _removeAllFavorites() async {
    _addEvent('Removing all favorites...');

    await _cache.mutateList(
      key: 'items',
      operation: ListOperation.removeWhere((i) => i.favorite),
      send: () async {
        await Future.delayed(const Duration(milliseconds: 300));
        _addEvent('  Bulk remove synced');
      },
    );
  }

  Future<void> _appendWithServerResponse() async {
    _itemCounter++;
    final tempItem = Item(
      id: 'temp-$_itemCounter',
      title: 'New Item (temp ID)',
    );

    _addEvent('Appending with server ID assignment...');
    _addEvent('  Temp ID: ${tempItem.id}');

    await _cache.mutateListItem(
      key: 'items',
      operation: ListOperation.append(tempItem),
      send: (item) async {
        await Future.delayed(const Duration(milliseconds: 500));
        // Server assigns a real ID
        final serverItem = item.copyWith(
          id: 'server-${DateTime.now().millisecondsSinceEpoch}',
          title: '${item.title.replaceAll(' (temp ID)', '')} (server)',
        );
        _addEvent('  Server assigned ID: ${serverItem.id}');
        return serverItem;
      },
      idSelector: (item) => item.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('List Operations')),
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
                        'Operations Log',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const Spacer(),
                      if (_items != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_items!.length} items',
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
                      final isSynced =
                          event.contains('synced') || event.contains('Server');
                      final isOperation =
                          event.contains('Appending') ||
                          event.contains('Prepending') ||
                          event.contains('Inserting') ||
                          event.contains('Toggling') ||
                          event.contains('Removing') ||
                          event.contains('Updating');

                      Color? textColor;
                      if (isSynced) {
                        textColor = Colors.green;
                      } else if (isOperation) {
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

          // Action buttons row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                FilledButton.icon(
                  onPressed: _appendItem,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Append'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _prependItem,
                  icon: const Icon(Icons.vertical_align_top, size: 18),
                  label: const Text('Prepend'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _insertAtIndex(1),
                  icon: const Icon(Icons.add_box, size: 18),
                  label: const Text('Insert @1'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _appendWithServerResponse,
                  icon: const Icon(Icons.cloud_upload, size: 18),
                  label: const Text('+ Server ID'),
                ),
              ],
            ),
          ),

          // Bulk actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _updateAllTitles,
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Update Non-Favorites'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _removeAllFavorites,
                    icon: const Icon(Icons.delete_sweep, size: 18),
                    label: const Text('Remove Favorites'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Items list
          Expanded(child: _buildItemsList()),

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
                          'ListOperation',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '- append/prepend/insert: Add items\n'
                      '- updateWhere: Modify matching items\n'
                      '- removeWhere: Delete matching items\n'
                      '- mutateListItem: Update with server response',
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

  Widget _buildItemsList() {
    if (_isLoading && _items == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_items == null || _items!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('No items'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _appendItem,
              child: const Text('Add First Item'),
            ),
          ],
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _items!.length,
      onReorder: (oldIndex, newIndex) {
        // Could implement reorder via ListOperation
      },
      itemBuilder: (context, index) {
        final item = _items![index];
        return Dismissible(
          key: ValueKey(item.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            color: Colors.red,
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) => _removeItem(item),
          child: ListTile(
            leading: IconButton(
              icon: Icon(
                item.favorite ? Icons.star : Icons.star_border,
                color: item.favorite ? Colors.amber : null,
              ),
              onPressed: () => _toggleFavorite(item),
            ),
            title: Text(item.title),
            subtitle: Text('ID: ${item.id}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '#$index',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.drag_handle),
              ],
            ),
          ),
        );
      },
    );
  }
}
