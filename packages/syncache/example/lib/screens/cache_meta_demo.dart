import 'dart:async';

import 'package:flutter/material.dart';
import 'package:syncache/syncache.dart';

import '../models/user.dart';
import '../services/cache.dart';
import '../services/fake_api.dart';
import '../services/network.dart';

/// Demonstrates getWithMeta and watchWithMeta for cache metadata.
///
/// This screen shows how to:
/// 1. Access CacheResult with isFromCache, isStale, storedAt, version
/// 2. Display staleness indicators in UI
/// 3. Show data age to users
class CacheMetaDemoScreen extends StatefulWidget {
  const CacheMetaDemoScreen({super.key});

  @override
  State<CacheMetaDemoScreen> createState() => _CacheMetaDemoScreenState();
}

class _CacheMetaDemoScreenState extends State<CacheMetaDemoScreen> {
  CacheResult<User>? _result;
  StreamSubscription<CacheResult<User>>? _subscription;
  bool _isLoading = false;
  String? _error;
  List<String> _events = [];
  Timer? _ageTimer;

  @override
  void initState() {
    super.initState();
    // Update age display every second
    _ageTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_result != null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _ageTimer?.cancel();
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

  Future<void> _loadWithMeta() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    _addEvent('Calling getWithMeta...');

    try {
      final result = await userCache.getWithMeta(
        key: 'user:meta-demo',
        fetch: (_) => fakeApi.fetchUser(),
        policy: Policy.offlineFirst,
        ttl: const Duration(seconds: 10), // Short TTL for demo
      );

      setState(() {
        _result = result;
        _isLoading = false;
      });

      _addEvent('Result received:');
      _addEvent('  isFromCache: ${result.meta.isFromCache}');
      _addEvent('  isStale: ${result.meta.isStale}');
      _addEvent('  version: ${result.meta.version}');
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      _addEvent('Error: $e');
    }
  }

  void _startWatchWithMeta() {
    _subscription?.cancel();

    setState(() {
      _isLoading = true;
      _error = null;
    });

    _addEvent('Starting watchWithMeta stream...');

    _subscription = userCache
        .watchWithMeta(
          key: 'user:meta-watch',
          fetch: (_) => fakeApi.fetchUser(),
          policy: Policy.staleWhileRefresh,
          ttl: const Duration(seconds: 10),
        )
        .listen(
          (result) {
            setState(() {
              _result = result;
              _isLoading = false;
            });

            _addEvent('Stream update:');
            _addEvent('  isFromCache: ${result.meta.isFromCache}');
            _addEvent('  isStale: ${result.meta.isStale}');
            _addEvent('  version: ${result.meta.version}');
          },
          onError: (Object error) {
            setState(() {
              _error = error.toString();
              _isLoading = false;
            });
            _addEvent('Stream error: $error');
          },
        );
  }

  Future<void> _forceRefresh() async {
    setState(() {
      _isLoading = true;
    });

    _addEvent('Force refreshing with Policy.refresh...');

    try {
      final result = await userCache.getWithMeta(
        key: 'user:meta-demo',
        fetch: (_) => fakeApi.fetchUser(),
        policy: Policy.refresh,
        ttl: const Duration(seconds: 10),
      );

      setState(() {
        _result = result;
        _isLoading = false;
      });

      _addEvent('Fresh data received:');
      _addEvent('  isFromCache: ${result.meta.isFromCache}');
      _addEvent('  version: ${result.meta.version}');
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      _addEvent('Error: $e');
    }
  }

  Future<void> _invalidateAndLoad() async {
    _addEvent('Invalidating cache...');
    await userCache.invalidate('user:meta-demo');
    await _loadWithMeta();
  }

  String _formatAge(Duration? age) {
    if (age == null) return 'N/A';
    if (age.inSeconds < 60) {
      return '${age.inSeconds}s ago';
    } else if (age.inMinutes < 60) {
      return '${age.inMinutes}m ${age.inSeconds % 60}s ago';
    } else {
      return '${age.inHours}h ${age.inMinutes % 60}m ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cache Metadata')),
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
                        'Metadata Log',
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
                      final isMeta =
                          event.contains('isFromCache') ||
                          event.contains('isStale') ||
                          event.contains('version');
                      final isUpdate =
                          event.contains('update') ||
                          event.contains('received');

                      Color? textColor;
                      if (isMeta) {
                        textColor = Colors.blue;
                      } else if (isUpdate) {
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

          // Metadata display card
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildMetadataCard(),
              ),
            ),
          ),

          // User data card
          if (_result != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        child: Text(
                          _result!.value.name[0],
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                              ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _result!.value.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              _result!.value.email,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      // Stale indicator
                      if (_result!.meta.isStale)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.access_time,
                                size: 14,
                                color: Colors.orange,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Stale',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: Colors.orange),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

          const Spacer(),

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
                        onPressed: _isLoading ? null : _loadWithMeta,
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('getWithMeta'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _startWatchWithMeta,
                        icon: const Icon(Icons.stream, size: 18),
                        label: const Text('watchWithMeta'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _forceRefresh,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Force Refresh'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _invalidateAndLoad,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Invalidate'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Network toggle for testing
                Card(
                  child: SwitchListTile(
                    title: const Text('Network Status'),
                    subtitle: Text(
                      simulatedNetwork.isOnline ? 'Online' : 'Offline',
                    ),
                    secondary: Icon(
                      simulatedNetwork.isOnline ? Icons.wifi : Icons.wifi_off,
                      color: simulatedNetwork.isOnline
                          ? Colors.green
                          : Colors.red,
                    ),
                    value: simulatedNetwork.isOnline,
                    onChanged: (value) {
                      simulatedNetwork.setOnline(value);
                      setState(() {});
                    },
                  ),
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
                          'CacheResult Metadata',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '- isFromCache: Was data from cache vs network?\n'
                      '- isStale: Has TTL expired?\n'
                      '- age: Time since data was stored\n'
                      '- version: Cache entry update count',
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

  Widget _buildMetadataCard() {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Column(
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
      );
    }

    if (_result == null) {
      return Center(
        child: Text(
          'Load data to see metadata',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final meta = _result!.meta;
    final age = meta.age;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetadataItem(
                label: 'Source',
                value: meta.isFromCache ? 'Cache' : 'Network',
                icon: meta.isFromCache ? Icons.storage : Icons.cloud_download,
                color: meta.isFromCache ? Colors.blue : Colors.green,
              ),
            ),
            Expanded(
              child: _MetadataItem(
                label: 'Freshness',
                value: meta.isStale ? 'Stale' : 'Fresh',
                icon: meta.isStale ? Icons.access_time : Icons.check_circle,
                color: meta.isStale ? Colors.orange : Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetadataItem(
                label: 'Age',
                value: _formatAge(age),
                icon: Icons.schedule,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            Expanded(
              child: _MetadataItem(
                label: 'Version',
                value: 'v${meta.version}',
                icon: Icons.tag,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        if (meta.storedAt != null) ...[
          const SizedBox(height: 8),
          Text(
            'Stored at: ${meta.storedAt!.toLocal().toString().substring(0, 19)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _MetadataItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetadataItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
