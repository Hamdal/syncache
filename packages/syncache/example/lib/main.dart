import 'package:flutter/material.dart';

import 'screens/cache_meta_demo.dart';
import 'screens/cancellation_demo.dart';
import 'screens/list_operation_demo.dart';
import 'screens/mutation_demo.dart';
import 'screens/offline_first_demo.dart';
import 'screens/prefetch_demo.dart';
import 'screens/retry_demo.dart';
import 'screens/scoped_demo.dart';
import 'screens/tags_demo.dart';
import 'screens/watch_demo.dart';
import 'services/network.dart';

void main() {
  runApp(const SyncacheExampleApp());
}

/// Example app demonstrating syncache package features.
class SyncacheExampleApp extends StatelessWidget {
  const SyncacheExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Syncache Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

/// Home page with navigation to different demos and network toggle.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    simulatedNetwork.addListener(_onNetworkChange);
  }

  @override
  void dispose() {
    simulatedNetwork.removeListener(_onNetworkChange);
    super.dispose();
  }

  void _onNetworkChange() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Syncache Example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Network status toggle
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    simulatedNetwork.isOnline ? Icons.wifi : Icons.wifi_off,
                    color: simulatedNetwork.isOnline
                        ? Colors.green
                        : Colors.red,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Network Status',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          simulatedNetwork.isOnline ? 'Online' : 'Offline',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: simulatedNetwork.isOnline
                                    ? Colors.green
                                    : Colors.red,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: simulatedNetwork.isOnline,
                    onChanged: (value) {
                      simulatedNetwork.setOnline(value);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Core Features Section
          Text('Core Features', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Explore the fundamental syncache capabilities.'),
          const SizedBox(height: 16),

          // Offline-first demo
          _DemoCard(
            icon: Icons.cloud_download,
            title: 'Offline-First Caching',
            description:
                'Cache policies: offlineFirst, cacheOnly, networkOnly, '
                'and cache invalidation.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const OfflineFirstDemoScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // Watch demo
          _DemoCard(
            icon: Icons.stream,
            title: 'Reactive Streams (watch)',
            description:
                'Real-time updates via watch() with staleWhileRefresh policy.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const WatchDemoScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // Mutations demo
          _DemoCard(
            icon: Icons.edit,
            title: 'Optimistic Mutations',
            description:
                'Instant UI updates with background sync via mutate().',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MutationDemoScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          // Advanced Features Section
          Text(
            'Advanced Features',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text('Explore advanced capabilities for production apps.'),
          const SizedBox(height: 16),

          // Cancellation demo
          _DemoCard(
            icon: Icons.cancel,
            title: 'Cancellation Token',
            description: 'Cancel in-flight requests with CancellationToken.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CancellationDemoScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // Retry demo
          _DemoCard(
            icon: Icons.refresh,
            title: 'Retry Config',
            description:
                'Automatic retry with exponential backoff and custom filters.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const RetryDemoScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // Prefetch demo
          _DemoCard(
            icon: Icons.bolt,
            title: 'Prefetch & Graph',
            description:
                'Batch prefetching with parallel execution and dependencies.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PrefetchDemoScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // Cache metadata demo
          _DemoCard(
            icon: Icons.info,
            title: 'Cache Metadata',
            description:
                'Access staleness, age, and version via getWithMeta/watchWithMeta.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CacheMetaDemoScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          // Organization Features Section
          Text('Organization', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Tools for organizing and managing cached data.'),
          const SizedBox(height: 16),

          // Scoped caches demo
          _DemoCard(
            icon: Icons.folder,
            title: 'Scoped Caches',
            description:
                'Namespace isolation for multi-tenant or multi-workspace apps.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ScopedDemoScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // Tags demo
          _DemoCard(
            icon: Icons.label,
            title: 'Tag-Based Invalidation',
            description: 'Group cache entries by tags for bulk invalidation.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const TagsDemoScreen()),
              );
            },
          ),
          const SizedBox(height: 12),

          // List operations demo
          _DemoCard(
            icon: Icons.list,
            title: 'List Operations',
            description:
                'Type-safe list mutations: append, prepend, updateWhere, removeWhere.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ListOperationDemoScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          // Info section
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'About Syncache',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Syncache is an offline-first cache and sync engine for '
                    'Dart applications. It provides:\n\n'
                    '- Multiple caching policies\n'
                    '- Optimistic mutations with auto sync\n'
                    '- Reactive streams via watch()\n'
                    '- Pluggable storage backends\n'
                    '- Cancellation & retry support\n'
                    '- Prefetch with dependency graphs\n'
                    '- Scoped caches & tag-based invalidation\n'
                    '- List operation helpers',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A card widget for demo navigation.
class _DemoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _DemoCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
