import 'package:flutter/widgets.dart';
import 'package:syncache/syncache.dart';

import 'flutter_network.dart';
import 'lifecycle_observer.dart';
import 'syncache_scope.dart';

/// Convenience widget to provide multiple caches without deep nesting.
///
/// Instead of nesting multiple [SyncacheScope] widgets, use this to
/// provide all caches in a flat structure:
///
/// ```dart
/// MultiSyncacheScope(
///   network: flutterNetwork,
///   configs: [
///     SyncacheScopeConfig<User>(userCache),
///     SyncacheScopeConfig<Post>(postCache),
///     SyncacheScopeConfig<Settings>(settingsCache),
///   ],
///   child: MyApp(),
/// )
/// ```
///
/// This is equivalent to:
///
/// ```dart
/// SyncacheScope<User>(
///   cache: userCache,
///   network: flutterNetwork,
///   child: SyncacheScope<Post>(
///     cache: postCache,
///     network: flutterNetwork,
///     child: SyncacheScope<Settings>(
///       cache: settingsCache,
///       network: flutterNetwork,
///       child: MyApp(),
///     ),
///   ),
/// )
/// ```
class MultiSyncacheScope extends StatelessWidget {
  /// The cache configurations to provide.
  final List<SyncacheScopeConfig<dynamic>> configs;

  /// Optional network instance shared by all scopes.
  final FlutterNetwork? network;

  /// Configuration for lifecycle behavior, shared by all scopes.
  final LifecycleConfig lifecycleConfig;

  /// The widget below this in the tree.
  final Widget child;

  /// Creates a [MultiSyncacheScope].
  const MultiSyncacheScope({
    super.key,
    required this.configs,
    required this.child,
    this.network,
    this.lifecycleConfig = LifecycleConfig.defaults,
  });

  @override
  Widget build(BuildContext context) {
    Widget result = child;

    // Build from inside out (last config wraps closest to child)
    for (final config in configs.reversed) {
      result = config._buildScope(
        network: network,
        lifecycleConfig: lifecycleConfig,
        child: result,
      );
    }

    return result;
  }
}

/// Type-safe configuration for a single cache scope.
///
/// Used with [MultiSyncacheScope] to configure each cache instance.
///
/// ```dart
/// final config = SyncacheScopeConfig<User>(userCache);
/// ```
class SyncacheScopeConfig<T> {
  /// The cache instance to provide.
  final Syncache<T> cache;

  /// Creates a [SyncacheScopeConfig].
  const SyncacheScopeConfig(this.cache);

  /// Builds a [SyncacheScope] widget with the given configuration.
  Widget _buildScope({
    FlutterNetwork? network,
    LifecycleConfig lifecycleConfig = LifecycleConfig.defaults,
    required Widget child,
  }) {
    return SyncacheScope<T>(
      cache: cache,
      network: network,
      config: lifecycleConfig,
      child: child,
    );
  }
}
