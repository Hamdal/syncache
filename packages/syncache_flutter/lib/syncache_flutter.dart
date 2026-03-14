/// Flutter integration for Syncache - lifecycle management, widgets,
/// and connectivity detection.
///
/// This package provides Flutter-specific functionality for [Syncache],
/// including:
///
/// - [FlutterNetwork]: Real connectivity detection using `connectivity_plus`
/// - [SyncacheScope]: Dependency injection and lifecycle management
/// - [CacheBuilder]: StreamBuilder-style widget for cache data
/// - [CacheConsumer]: Consumer pattern widget with separate listener
/// - [MultiSyncacheScope]: Helper for providing multiple cache instances
///
/// ## Getting Started
///
/// 1. Create a [FlutterNetwork] instance and initialize it:
///
/// ```dart
/// final network = FlutterNetwork();
/// await network.initialize();
/// ```
///
/// 2. Create your cache instances:
///
/// ```dart
/// final userCache = Syncache<User>(
///   store: MemoryStore<User>(),
///   network: network,
/// );
/// ```
///
/// 3. Wrap your app with [SyncacheScope]:
///
/// ```dart
/// SyncacheScope<User>(
///   cache: userCache,
///   network: network,
///   child: MyApp(),
/// )
/// ```
///
/// 4. Use [CacheBuilder] to display cache data:
///
/// ```dart
/// CacheBuilder<User>(
///   cacheKey: 'user:123',
///   fetch: (req) => api.getUser(123),
///   builder: (context, snapshot) {
///     if (!snapshot.hasData) {
///       return const CircularProgressIndicator();
///     }
///     return UserCard(user: snapshot.data!);
///   },
/// )
/// ```
///
/// ## Multiple Cache Types
///
/// For apps with multiple cache types, use [MultiSyncacheScope]:
///
/// ```dart
/// MultiSyncacheScope(
///   network: network,
///   configs: [
///     SyncacheScopeConfig<User>(userCache),
///     SyncacheScopeConfig<Post>(postCache),
///   ],
///   child: MyApp(),
/// )
/// ```
library syncache_flutter;

export 'src/cache_builder.dart' show CacheBuilder;
export 'src/cache_consumer.dart' show CacheConsumer;
export 'src/extensions.dart'
    show SyncacheFlutterExtensions, SyncacheValueListenable;
export 'src/flutter_network.dart' show FlutterNetwork;
export 'src/lifecycle_observer.dart'
    show LifecycleConfig, SyncacheLifecycleObserver, WatcherRegistration;
export 'src/multi_syncache_scope.dart'
    show MultiSyncacheScope, SyncacheScopeConfig;
export 'src/syncache_scope.dart' show SyncacheScope;
