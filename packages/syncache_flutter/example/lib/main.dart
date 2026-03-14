import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:syncache/syncache.dart';
import 'package:syncache_flutter/syncache_flutter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final FlutterNetwork _network;
  late final Syncache<User> _userCache;
  late final Syncache<List<Post>> _postsCache;

  @override
  void initState() {
    super.initState();
    _network = FlutterNetwork();
    _userCache = Syncache(store: MemoryStore<User>(), network: _network);
    _postsCache = Syncache(store: MemoryStore<List<Post>>(), network: _network);

    // Initialize network connectivity detection
    _network.initialize();
  }

  @override
  void dispose() {
    _userCache.dispose();
    _postsCache.dispose();
    _network.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use MultiSyncacheScope to provide multiple cache types
    return MultiSyncacheScope(
      network: _network,
      // Use a short duration for demo purposes (5 seconds instead of default 30)
      lifecycleConfig: const LifecycleConfig(
        refetchOnResume: true,
        refetchOnResumeMinDuration: Duration(seconds: 5),
        refetchOnReconnect: true,
      ),
      configs: [
        SyncacheScopeConfig<User>(_userCache),
        SyncacheScopeConfig<List<Post>>(_postsCache),
      ],
      child: MaterialApp(
        title: 'Syncache Flutter Demo',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const HomePage(),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Syncache Flutter Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(
            context,
            title: 'CacheBuilder Example',
            description: 'Reactive widget that rebuilds when cache updates',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CacheBuilderExample()),
            ),
          ),
          _buildSection(
            context,
            title: 'CacheConsumer Example',
            description: 'Listener + builder pattern for side effects',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CacheConsumerExample()),
            ),
          ),
          _buildSection(
            context,
            title: 'Multiple Caches Example',
            description: 'Using different cache types together',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MultipleCachesExample()),
            ),
          ),
          _buildSection(
            context,
            title: 'Lifecycle Demo',
            description: 'Refetch on resume and connectivity changes',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LifecycleDemo()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(title),
        subtitle: Text(description),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

// =============================================================================
// CacheBuilder Example
// =============================================================================

class CacheBuilderExample extends StatelessWidget {
  const CacheBuilderExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CacheBuilder Example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'CacheBuilder automatically subscribes to the cache and rebuilds '
              'when the value changes.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: CacheBuilder<User>(
                cacheKey: 'user:1',
                fetch: (_) => FakeApi.fetchUser(1),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _ErrorCard(error: snapshot.error!);
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return UserCard(user: snapshot.data!);
                },
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                final cache = SyncacheScope.of<User>(context);
                await cache.get(
                  key: 'user:1',
                  fetch: (_) => FakeApi.fetchUser(1),
                  policy: Policy.refresh,
                );
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Force Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// CacheConsumer Example
// =============================================================================

class CacheConsumerExample extends StatelessWidget {
  const CacheConsumerExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CacheConsumer Example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'CacheConsumer separates listener (for side effects) from builder. '
              'The listener is called before rebuild.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: CacheConsumer<User>(
                cacheKey: 'user:2',
                fetch: (_) => FakeApi.fetchUser(2),
                listener: (context, snapshot) {
                  // Show a snackbar when data arrives
                  if (snapshot.hasData) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Loaded: ${snapshot.data!.name}'),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  }
                },
                listenWhen: (previous, current) {
                  // Only notify on name changes
                  return previous?.name != current.name;
                },
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _ErrorCard(error: snapshot.error!);
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return UserCard(user: snapshot.data!);
                },
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                final cache = SyncacheScope.of<User>(context);
                // Simulate updating with random data
                await cache.get(
                  key: 'user:2',
                  fetch: (_) => FakeApi.fetchUser(2, randomize: true),
                  policy: Policy.refresh,
                );
              },
              icon: const Icon(Icons.shuffle),
              label: const Text('Fetch Random User'),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Multiple Caches Example
// =============================================================================

class MultipleCachesExample extends StatelessWidget {
  const MultipleCachesExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Multiple Caches')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Using multiple cache types (User and Posts) in the same widget tree.',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 24),

          // User cache
          const Text('User:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: CacheBuilder<User>(
              cacheKey: 'user:3',
              fetch: (_) => FakeApi.fetchUser(3),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return UserCard(user: snapshot.data!, compact: true);
              },
            ),
          ),

          const SizedBox(height: 24),

          // Posts cache
          const Text('Posts:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          CacheBuilder<List<Post>>(
            cacheKey: 'posts:user:3',
            fetch: (_) => FakeApi.fetchPosts(userId: 3),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              return Column(
                children:
                    snapshot.data!.map((post) => PostCard(post: post)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Lifecycle Demo
// =============================================================================

class LifecycleDemo extends StatefulWidget {
  const LifecycleDemo({super.key});

  @override
  State<LifecycleDemo> createState() => _LifecycleDemoState();
}

class _LifecycleDemoState extends State<LifecycleDemo>
    with WidgetsBindingObserver {
  final List<String> _events = [];
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _pausedAt = DateTime.now();
        _addEvent('[LIFECYCLE] App paused - timer started');
      case AppLifecycleState.inactive:
        _addEvent('[LIFECYCLE] App inactive (transitional)');
      case AppLifecycleState.resumed:
        if (_pausedAt != null) {
          final duration = DateTime.now().difference(_pausedAt!);
          final willRefetch = duration.inSeconds >= 5;
          _addEvent(
            '[LIFECYCLE] App resumed after ${duration.inSeconds}s '
            '(refetch: ${willRefetch ? "YES" : "NO, need 5s+"})',
          );
        } else {
          _addEvent('[LIFECYCLE] App resumed');
        }
        _pausedAt = null;
      case AppLifecycleState.hidden:
        _addEvent('[LIFECYCLE] App hidden');
      case AppLifecycleState.detached:
        _addEvent('[LIFECYCLE] App detached');
    }
  }

  void _addEvent(String event) {
    setState(() {
      final time = DateTime.now();
      final timeStr = '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}:'
          '${time.second.toString().padLeft(2, '0')}';
      _events.insert(0, '$timeStr $event');
      if (_events.length > 30) _events.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lifecycle Demo')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'SyncacheScope automatically refetches watched data when:',
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 8),
                Text('  - App resumes after 5+ seconds in background'),
                Text('  - Network connectivity is restored'),
                SizedBox(height: 16),
                Text(
                  'Try: Put app in background for 5+ seconds, then return. '
                  'Or toggle airplane mode.',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CacheConsumer<User>(
              cacheKey: 'user:lifecycle',
              fetch: (_) => FakeApi.fetchUser(99),
              listener: (context, snapshot) {
                if (snapshot.hasData) {
                  _addEvent('[DATA] User received: ${snapshot.data!.name}');
                }
              },
              builder: (context, snapshot) {
                return ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(snapshot.data?.name ?? 'Loading...'),
                  subtitle: Text(snapshot.data?.email ?? ''),
                  trailing: snapshot.connectionState == ConnectionState.waiting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                );
              },
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text(
                  'Event Log',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _events.clear()),
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: Colors.grey[100],
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _events.length,
                itemBuilder: (context, index) {
                  final event = _events[index];
                  final isLifecycle = event.contains('[LIFECYCLE]');
                  final isData = event.contains('[DATA]');
                  return Text(
                    event,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: isLifecycle
                          ? Colors.blue[700]
                          : isData
                              ? Colors.green[700]
                              : Colors.black87,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Models
// =============================================================================

class User {
  final int id;
  final String name;
  final String email;
  final String avatarUrl;

  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.avatarUrl,
  });
}

class Post {
  final int id;
  final int userId;
  final String title;
  final String body;

  const Post({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
  });
}

// =============================================================================
// Fake API (simulates network requests)
// =============================================================================

class FakeApi {
  static final _random = Random();

  static final _names = [
    'Alice Johnson',
    'Bob Smith',
    'Carol Williams',
    'David Brown',
    'Eve Davis',
  ];

  static Future<User> fetchUser(int id, {bool randomize = false}) async {
    // Simulate network delay
    await Future.delayed(Duration(milliseconds: 500 + _random.nextInt(500)));

    final name =
        randomize ? _names[_random.nextInt(_names.length)] : 'User $id';

    return User(
      id: id,
      name: name,
      email: '${name.toLowerCase().replaceAll(' ', '.')}@example.com',
      avatarUrl: 'https://i.pravatar.cc/150?u=$id',
    );
  }

  static Future<List<Post>> fetchPosts({required int userId}) async {
    // Simulate network delay
    await Future.delayed(Duration(milliseconds: 700 + _random.nextInt(300)));

    return List.generate(
      3,
      (index) => Post(
        id: userId * 100 + index,
        userId: userId,
        title: 'Post ${index + 1} by User $userId',
        body: 'This is the content of post ${index + 1}. '
            'Lorem ipsum dolor sit amet, consectetur adipiscing elit.',
      ),
    );
  }
}

// =============================================================================
// Widgets
// =============================================================================

class UserCard extends StatelessWidget {
  final User user;
  final bool compact;

  const UserCard({super.key, required this.user, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundImage: NetworkImage(user.avatarUrl),
          ),
          title: Text(user.name),
          subtitle: Text(user.email),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 50,
              backgroundImage: NetworkImage(user.avatarUrl),
            ),
            const SizedBox(height: 16),
            Text(
              user.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              user.email,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'ID: ${user.id}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class PostCard extends StatelessWidget {
  final Post post;

  const PostCard({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              post.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              post.body,
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final Object error;

  const _ErrorCard({required this.error});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 8),
            Text(
              'Error',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              error.toString(),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
