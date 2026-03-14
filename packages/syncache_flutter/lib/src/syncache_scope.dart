import 'package:flutter/widgets.dart';
import 'package:syncache/syncache.dart';

import 'flutter_network.dart';
import 'lifecycle_observer.dart';

/// Provides a [Syncache] instance to descendant widgets and manages
/// its lifecycle integration with Flutter.
///
/// This widget combines dependency injection (via [InheritedWidget]) with
/// automatic lifecycle management. It registers a [SyncacheLifecycleObserver]
/// that handles app resume and connectivity restoration events.
///
/// ## Usage
///
/// Wrap your app (or a subtree) with [SyncacheScope]:
///
/// ```dart
/// SyncacheScope<User>(
///   cache: userCache,
///   network: flutterNetwork,
///   config: const LifecycleConfig(
///     refetchOnResume: true,
///     refetchOnReconnect: true,
///   ),
///   child: MyApp(),
/// )
/// ```
///
/// Then access the cache from any descendant widget:
///
/// ```dart
/// final cache = SyncacheScope.of<User>(context);
/// ```
///
/// ## Multiple Cache Types
///
/// For apps with multiple cache types, you can either:
///
/// 1. Nest multiple [SyncacheScope] widgets:
///    ```dart
///    SyncacheScope<User>(
///      cache: userCache,
///      child: SyncacheScope<Post>(
///        cache: postCache,
///        child: MyApp(),
///      ),
///    )
///    ```
///
/// 2. Use [MultiSyncacheScope] for cleaner syntax:
///    ```dart
///    MultiSyncacheScope(
///      network: flutterNetwork,
///      configs: [
///        SyncacheScopeConfig<User>(userCache),
///        SyncacheScopeConfig<Post>(postCache),
///      ],
///      child: MyApp(),
///    )
///    ```
class SyncacheScope<T> extends StatefulWidget {
  /// The cache instance to provide to descendants.
  final Syncache<T> cache;

  /// Optional network instance for connectivity detection.
  ///
  /// If provided and [config.refetchOnReconnect] is true, watchers
  /// will be refreshed when connectivity is restored.
  final FlutterNetwork? network;

  /// Configuration for lifecycle behavior.
  final LifecycleConfig config;

  /// The widget below this in the tree.
  final Widget child;

  /// Creates a [SyncacheScope].
  const SyncacheScope({
    super.key,
    required this.cache,
    required this.child,
    this.network,
    this.config = LifecycleConfig.defaults,
  });

  /// Retrieves the [Syncache] instance of type [T] from the widget tree.
  ///
  /// Throws if no [SyncacheScope] of the matching type is found.
  ///
  /// ```dart
  /// final cache = SyncacheScope.of<User>(context);
  /// final user = await cache.get(key: 'user:123', fetch: fetchUser);
  /// ```
  static Syncache<T> of<T>(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_SyncacheScopeInherited<T>>();
    assert(
      scope != null,
      'No SyncacheScope<$T> found in widget tree. '
      'Ensure a SyncacheScope<$T> is an ancestor of this widget.',
    );
    return scope!.cache;
  }

  /// Retrieves the [SyncacheLifecycleObserver] from the widget tree.
  ///
  /// Returns null if no [SyncacheScope] of the matching type is found.
  /// This is primarily used internally by [CacheBuilder] and [CacheConsumer].
  static SyncacheLifecycleObserver<T>? observerOf<T>(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_SyncacheScopeInherited<T>>();
    return scope?.observer;
  }

  /// Tries to retrieve the [Syncache] instance, returns null if not found.
  ///
  /// Use this when the cache might not be available in the widget tree.
  ///
  /// ```dart
  /// final cache = SyncacheScope.maybeOf<User>(context);
  /// if (cache != null) {
  ///   // Use cache
  /// }
  /// ```
  static Syncache<T>? maybeOf<T>(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_SyncacheScopeInherited<T>>();
    return scope?.cache;
  }

  @override
  State<SyncacheScope<T>> createState() => _SyncacheScopeState<T>();
}

class _SyncacheScopeState<T> extends State<SyncacheScope<T>> {
  late SyncacheLifecycleObserver<T> _observer;

  @override
  void initState() {
    super.initState();
    _observer = SyncacheLifecycleObserver<T>(
      cache: widget.cache,
      network: widget.network,
      config: widget.config,
    );
    _observer.attach();
  }

  @override
  void didUpdateWidget(SyncacheScope<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If cache or config changed, recreate the observer
    if (widget.cache != oldWidget.cache ||
        widget.network != oldWidget.network ||
        widget.config != oldWidget.config) {
      // Preserve existing watcher registrations
      final existingWatchers = _observer.copyWatchers();

      _observer.detach();
      _observer = SyncacheLifecycleObserver<T>(
        cache: widget.cache,
        network: widget.network,
        config: widget.config,
      );
      // Restore watchers to the new observer
      _observer.restoreWatchers(existingWatchers);
      _observer.attach();
    }
  }

  @override
  void dispose() {
    _observer.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SyncacheScopeInherited<T>(
      cache: widget.cache,
      observer: _observer,
      child: widget.child,
    );
  }
}

class _SyncacheScopeInherited<T> extends InheritedWidget {
  final Syncache<T> cache;
  final SyncacheLifecycleObserver<T> observer;

  const _SyncacheScopeInherited({
    required this.cache,
    required this.observer,
    required super.child,
  });

  @override
  bool updateShouldNotify(_SyncacheScopeInherited<T> oldWidget) {
    return cache != oldWidget.cache;
  }
}
