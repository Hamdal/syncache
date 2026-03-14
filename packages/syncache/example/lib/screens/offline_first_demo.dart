import 'package:flutter/material.dart';
import 'package:syncache/syncache.dart';

import '../models/user.dart';
import '../services/cache.dart';
import '../services/fake_api.dart';

/// Demonstrates the offline-first caching policy.
///
/// This screen shows how `Policy.offlineFirst` works:
/// 1. First load fetches from network and caches the result
/// 2. Subsequent loads return cached data instantly (if not expired)
/// 3. When offline, cached data is returned
/// 4. When cache expires, fresh data is fetched
class OfflineFirstDemoScreen extends StatefulWidget {
  const OfflineFirstDemoScreen({super.key});

  @override
  State<OfflineFirstDemoScreen> createState() => _OfflineFirstDemoScreenState();
}

class _OfflineFirstDemoScreenState extends State<OfflineFirstDemoScreen> {
  User? _user;
  bool _isLoading = false;
  String? _error;
  String _lastAction = '';

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _lastAction = 'Loading with Policy.offlineFirst...';
    });

    final stopwatch = Stopwatch()..start();

    try {
      final user = await userCache.get(
        key: 'user:profile',
        fetch: (_) => fakeApi.fetchUser(),
        policy: Policy.offlineFirst,
        ttl: const Duration(seconds: 30), // Short TTL for demo
      );

      stopwatch.stop();

      setState(() {
        _user = user;
        _isLoading = false;
        _lastAction =
            'Loaded in ${stopwatch.elapsedMilliseconds}ms '
            '(${stopwatch.elapsedMilliseconds < 100 ? "from cache" : "from network"})';
      });
    } catch (e) {
      stopwatch.stop();
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _lastAction = 'Error after ${stopwatch.elapsedMilliseconds}ms';
      });
    }
  }

  Future<void> _loadCacheOnly() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _lastAction = 'Loading with Policy.cacheOnly...';
    });

    try {
      final user = await userCache.get(
        key: 'user:profile',
        fetch: (_) => fakeApi.fetchUser(),
        policy: Policy.cacheOnly,
      );

      setState(() {
        _user = user;
        _isLoading = false;
        _lastAction = 'Loaded from cache only';
      });
    } on CacheMissException {
      setState(() {
        _error = 'No cached data available';
        _isLoading = false;
        _lastAction = 'Cache miss (no data in cache)';
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _lastAction = 'Error';
      });
    }
  }

  Future<void> _loadNetworkOnly() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _lastAction = 'Loading with Policy.networkOnly...';
    });

    final stopwatch = Stopwatch()..start();

    try {
      final user = await userCache.get(
        key: 'user:profile',
        fetch: (_) => fakeApi.fetchUser(),
        policy: Policy.networkOnly,
        ttl: const Duration(seconds: 30),
      );

      stopwatch.stop();

      setState(() {
        _user = user;
        _isLoading = false;
        _lastAction =
            'Fetched from network in ${stopwatch.elapsedMilliseconds}ms';
      });
    } catch (e) {
      stopwatch.stop();
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _lastAction = 'Network error after ${stopwatch.elapsedMilliseconds}ms';
      });
    }
  }

  Future<void> _invalidateCache() async {
    await userCache.invalidate('user:profile');
    setState(() {
      _lastAction = 'Cache invalidated - next load will fetch from network';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offline-First Demo')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last Action',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _lastAction.isEmpty ? 'None' : _lastAction,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // User info card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildUserContent(),
              ),
            ),
            const SizedBox(height: 24),

            // Action buttons
            Text(
              'Cache Policies',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Try different policies and observe the loading times. '
              'Cached responses are nearly instant.',
            ),
            const SizedBox(height: 16),

            FilledButton.icon(
              onPressed: _isLoading ? null : _loadUser,
              icon: const Icon(Icons.cloud_download),
              label: const Text('Offline First'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _loadCacheOnly,
              icon: const Icon(Icons.storage),
              label: const Text('Cache Only'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _loadNetworkOnly,
              icon: const Icon(Icons.wifi),
              label: const Text('Network Only'),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _isLoading ? null : _invalidateCache,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Invalidate Cache'),
            ),
            const SizedBox(height: 24),

            // Info card
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
                          'How It Works',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '- Offline First: Returns cached data if valid, '
                      'otherwise fetches from network\n'
                      '- Cache Only: Only returns cached data, never makes '
                      'network requests\n'
                      '- Network Only: Always fetches from network, ignoring cache\n\n'
                      'Toggle the network status from the home screen to see '
                      'offline behavior.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserContent() {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Column(
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 8),
          Text('Error', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }

    if (_user == null) {
      return const Center(child: Text('No user data'));
    }

    return Row(
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            _user!.name[0],
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_user!.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                _user!.email,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
