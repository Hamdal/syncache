import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:syncache/syncache.dart';

import 'lifecycle_observer.dart';
import 'syncache_scope.dart';

/// A widget that builds itself based on the latest cache value.
///
/// Similar to [StreamBuilder] but specifically designed for [Syncache].
/// Automatically subscribes to the cache stream and rebuilds when the
/// value changes.
///
/// ## Basic Usage
///
/// ```dart
/// CacheBuilder<User>(
///   cacheKey: 'user:123',
///   fetch: (req) => api.getUser(123),
///   builder: (context, snapshot) {
///     if (snapshot.hasError) {
///       return ErrorWidget(snapshot.error!);
///     }
///     if (!snapshot.hasData) {
///       return const CircularProgressIndicator();
///     }
///     return UserCard(user: snapshot.data!);
///   },
/// )
/// ```
///
/// ## With Initial Data
///
/// ```dart
/// CacheBuilder<User>(
///   cacheKey: 'user:123',
///   fetch: fetchUser,
///   initialData: cachedUser,  // Show immediately while fetching
///   builder: (context, snapshot) => UserCard(user: snapshot.data!),
/// )
/// ```
///
/// ## Conditional Rebuilds
///
/// Use [buildWhen] to control when the widget rebuilds:
///
/// ```dart
/// CacheBuilder<User>(
///   cacheKey: 'user:123',
///   fetch: fetchUser,
///   buildWhen: (previous, current) => previous?.name != current.name,
///   builder: (context, snapshot) => Text(snapshot.data!.name),
/// )
/// ```
///
/// ## Lifecycle Integration
///
/// When used within a [SyncacheScope], the widget automatically registers
/// with the lifecycle observer for refetch on app resume and connectivity
/// restoration.
class CacheBuilder<T> extends StatefulWidget {
  /// The cache key to watch.
  final String cacheKey;

  /// The fetcher function to retrieve fresh data.
  final Fetcher<T> fetch;

  /// Builder function called with the latest snapshot.
  ///
  /// The snapshot contains:
  /// - [AsyncSnapshot.connectionState]: Current connection state
  /// - [AsyncSnapshot.data]: The cached value (if available)
  /// - [AsyncSnapshot.error]: Any error that occurred
  final Widget Function(BuildContext context, AsyncSnapshot<T> snapshot)
      builder;

  /// Optional cache instance.
  ///
  /// If not provided, uses [SyncacheScope.of<T>(context)].
  final Syncache<T>? cache;

  /// Caching policy (defaults to [Policy.offlineFirst]).
  final Policy policy;

  /// Optional TTL for cached entries.
  final Duration? ttl;

  /// Optional function to determine if rebuild is needed.
  ///
  /// If returns false, the widget won't rebuild for that update.
  /// This is useful for optimizing performance when only certain
  /// properties of the cached value are displayed.
  ///
  /// ```dart
  /// buildWhen: (previous, current) => previous?.id != current.id,
  /// ```
  final bool Function(T? previous, T current)? buildWhen;

  /// Initial data to show before the first fetch completes.
  ///
  /// If provided, the builder will receive this data immediately
  /// while the actual fetch is in progress.
  final T? initialData;

  /// Creates a [CacheBuilder].
  const CacheBuilder({
    super.key,
    required this.cacheKey,
    required this.fetch,
    required this.builder,
    this.cache,
    this.policy = Policy.offlineFirst,
    this.ttl,
    this.buildWhen,
    this.initialData,
  });

  @override
  State<CacheBuilder<T>> createState() => _CacheBuilderState<T>();
}

class _CacheBuilderState<T> extends State<CacheBuilder<T>> {
  StreamSubscription<T>? _subscription;
  late AsyncSnapshot<T> _snapshot;
  T? _lastValue;
  Syncache<T>? _cache;
  SyncacheLifecycleObserver<T>? _observer;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _snapshot = AsyncSnapshot<T>.withData(
        ConnectionState.waiting,
        widget.initialData as T,
      );
      _lastValue = widget.initialData;
    } else {
      _snapshot = AsyncSnapshot<T>.nothing();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newCache = widget.cache ?? SyncacheScope.of<T>(context);
    final newObserver = SyncacheScope.observerOf<T>(context);

    // Only re-subscribe if the cache or observer changed
    if (_cache != newCache || _observer != newObserver) {
      _unsubscribe();
      _subscribe();
    } else if (_subscription == null) {
      // First call - initial subscription
      _subscribe();
    }
  }

  @override
  void didUpdateWidget(CacheBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey ||
        oldWidget.cache != widget.cache ||
        oldWidget.policy != widget.policy) {
      _unsubscribe();
      _subscribe();
    }
  }

  void _subscribe() {
    _cache = widget.cache ?? SyncacheScope.of<T>(context);
    _observer = SyncacheScope.observerOf<T>(context);

    // Register with lifecycle observer for refetch on resume/reconnect
    _observer?.registerWatcher(
      WatcherRegistration<T>(
        key: widget.cacheKey,
        fetch: widget.fetch,
        ttl: widget.ttl,
        policy: widget.policy,
      ),
    );

    final stream = _cache!.watch(
      key: widget.cacheKey,
      fetch: widget.fetch,
      policy: widget.policy,
      ttl: widget.ttl,
    );

    _snapshot = _snapshot.inState(ConnectionState.waiting);

    _subscription = stream.listen(
      _handleData,
      onError: _handleError,
      onDone: _handleDone,
    );
  }

  void _handleData(T data) {
    if (widget.buildWhen != null && !widget.buildWhen!(_lastValue, data)) {
      _lastValue = data;
      return;
    }
    _lastValue = data;
    setState(() {
      _snapshot = AsyncSnapshot<T>.withData(ConnectionState.active, data);
    });
  }

  void _handleError(Object error, StackTrace stackTrace) {
    setState(() {
      _snapshot = AsyncSnapshot<T>.withError(
        ConnectionState.active,
        error,
        stackTrace,
      );
    });
  }

  void _handleDone() {
    setState(() {
      _snapshot = _snapshot.inState(ConnectionState.done);
    });
  }

  void _unsubscribe() {
    _observer?.unregisterWatcher(widget.cacheKey);
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _snapshot);
  }
}
