import 'dart:async';

import 'package:flutter/material.dart';
import 'package:syncache/syncache.dart';

/// A simple product for demonstrating tag-based invalidation.
class Product {
  final String id;
  final String name;
  final String category;
  final double price;

  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
  });
}

/// Demonstrates tag-based cache invalidation.
///
/// This screen shows how to:
/// 1. Tag cache entries for grouped invalidation
/// 2. Invalidate by single tag or multiple tags
/// 3. Use pattern-based invalidation
class TagsDemoScreen extends StatefulWidget {
  const TagsDemoScreen({super.key});

  @override
  State<TagsDemoScreen> createState() => _TagsDemoScreenState();
}

class _TagsDemoScreenState extends State<TagsDemoScreen> {
  // Use TaggableStore for tag support (MemoryStore implements it)
  final _cache = Syncache<Product>(
    store: MemoryStore<Product>(),
    observers: [LoggingObserver()],
  );

  final Map<String, Product> _products = {};
  List<String> _events = [];
  bool _isLoading = false;

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

  Future<void> _loadAllProducts() async {
    setState(() {
      _isLoading = true;
      _products.clear();
    });

    _addEvent('Loading all products with tags...');

    // Load products with category tags
    final products = [
      const Product(
        id: '1',
        name: 'iPhone 15',
        category: 'electronics',
        price: 999,
      ),
      const Product(
        id: '2',
        name: 'MacBook Pro',
        category: 'electronics',
        price: 1999,
      ),
      const Product(
        id: '3',
        name: 'AirPods',
        category: 'electronics',
        price: 199,
      ),
      const Product(
        id: '4',
        name: 'Running Shoes',
        category: 'sports',
        price: 129,
      ),
      const Product(id: '5', name: 'Yoga Mat', category: 'sports', price: 49),
      const Product(id: '6', name: 'Novel Book', category: 'books', price: 19),
      const Product(id: '7', name: 'Cookbook', category: 'books', price: 29),
    ];

    for (final product in products) {
      await _cache.get(
        key: 'product:${product.id}',
        fetch: (_) async {
          await Future.delayed(const Duration(milliseconds: 50));
          return product;
        },
        policy: Policy.refresh,
        tags: [
          'category:${product.category}',
          'all-products',
          if (product.price > 100) 'expensive',
        ],
      );

      setState(() {
        _products[product.id] = product;
      });
    }

    _addEvent('Loaded ${products.length} products with tags');
    _addEvent('  Tags used: category:*, all-products, expensive');

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _invalidateTag(String tag) async {
    _addEvent('Invalidating tag: $tag');

    await _cache.invalidateTag(tag);

    // Remove products that match the tag from display
    setState(() {
      switch (tag) {
        case 'category:electronics':
          _products.removeWhere((_, p) => p.category == 'electronics');
          break;
        case 'category:sports':
          _products.removeWhere((_, p) => p.category == 'sports');
          break;
        case 'category:books':
          _products.removeWhere((_, p) => p.category == 'books');
          break;
        case 'expensive':
          _products.removeWhere((_, p) => p.price > 100);
          break;
        case 'all-products':
          _products.clear();
          break;
      }
    });

    _addEvent('  Invalidated all entries with tag: $tag');
    _addEvent('  Remaining products: ${_products.length}');
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'electronics':
        return Colors.blue;
      case 'sports':
        return Colors.green;
      case 'books':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tag-Based Invalidation')),
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
                        'Tag Operations Log',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const Spacer(),
                      if (_products.isNotEmpty)
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
                            '${_products.length} cached',
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
                      final isInvalidate = event.contains('Invalidat');
                      final isLoad =
                          event.contains('Loading') || event.contains('Loaded');

                      Color? textColor;
                      if (isInvalidate) {
                        textColor = Colors.orange;
                      } else if (isLoad) {
                        textColor = Colors.green;
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

          // Load button
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: _isLoading ? null : _loadAllProducts,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              label: const Text('Load Products with Tags'),
            ),
          ),

          // Tag buttons
          if (_products.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Invalidate by Category Tag',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _TagChip(
                        label: 'Electronics',
                        color: Colors.blue,
                        onTap: () => _invalidateTag('category:electronics'),
                      ),
                      _TagChip(
                        label: 'Sports',
                        color: Colors.green,
                        onTap: () => _invalidateTag('category:sports'),
                      ),
                      _TagChip(
                        label: 'Books',
                        color: Colors.orange,
                        onTap: () => _invalidateTag('category:books'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Invalidate by Other Tags',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _TagChip(
                        label: 'Expensive (>\$100)',
                        color: Colors.red,
                        onTap: () => _invalidateTag('expensive'),
                      ),
                      _TagChip(
                        label: 'All Products',
                        color: Colors.purple,
                        onTap: () => _invalidateTag('all-products'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // Products list
          Expanded(child: _buildProductsList()),

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
                          'Tag-Based Invalidation',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '- Add tags when caching: tags: ["category:x"]\n'
                      '- invalidateTag: Remove all entries with tag\n'
                      '- invalidateTags: Match any or all tags\n'
                      '- Requires TaggableStore (MemoryStore supports it)',
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

  Widget _buildProductsList() {
    if (_isLoading && _products.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_products.isEmpty) {
      return Center(
        child: Text(
          'Load products to see tag-based invalidation',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final productList = _products.values.toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: productList.length,
      itemBuilder: (context, index) {
        final product = productList[index];
        final categoryColor = _getCategoryColor(product.category);

        return ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: categoryColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getCategoryIcon(product.category),
              color: categoryColor,
            ),
          ),
          title: Text(product.name),
          subtitle: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  product.category,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: categoryColor),
                ),
              ),
              if (product.price > 100) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'expensive',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: Colors.red),
                  ),
                ),
              ],
            ],
          ),
          trailing: Text(
            '\$${product.price.toStringAsFixed(0)}',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        );
      },
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'electronics':
        return Icons.devices;
      case 'sports':
        return Icons.sports_soccer;
      case 'books':
        return Icons.book;
      default:
        return Icons.category;
    }
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _TagChip({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      avatar: Icon(Icons.cancel, size: 18, color: color),
      onPressed: onTap,
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
      labelStyle: TextStyle(color: color),
    );
  }
}
