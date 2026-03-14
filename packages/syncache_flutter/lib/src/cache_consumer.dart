import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:syncache/syncache.dart';

import 'lifecycle_observer.dart';
import 'syncache_scope.dart';

/// A widget that listens to cache changes and optionally rebuilds.
///
/// Unlike [CacheBuilder], this widget separates the listener callback
/// from the builder, allowing side effects without rebuilds.
///
/// ## Basic Usage
///
/// ```dart
/// CacheConsumer<User>(
///   cacheKey: 'user:123',
///   fetch: (req) => api.getUser(123),
///   listener: (context, snapshot) {
///     if (snapshot.hasData) {
///       analytics.trackUserLoaded(snapshot.data!);
///     }
///   },
///   builder: (context, snapshot) {
///     if (!snapshot.hasData) {
///       return const CircularProgressIndicator();
///     }
///     return UserCard(user: snapshot.data!);
///   },
/// )
/// ```
///
/// ## Conditional Listening
///
/// Use [listenWhen] to control when the listener is called:
///
/// ```dart
/// CacheConsumer<User>(
///   cacheKey: 'user:123',
///   fetch: fetchUser,
///   listenWhen: (previous, current) => previous?.status != current.status,
///   listener: (context, snapshot) {
///     showStatusChangeNotification(snapshot.data!.status);
///   },
///   builder: (context, snapshot) => UserCard(user: snapshot.data!),
/// )
/// ```
///
/// ## Conditional Rebuilds
///
/// Use [buildWhen] to control when the widget rebuilds:
///
/// ```dart
/// CacheConsumer<User>(
///   cacheKey: 'user:123',
///   fetch: fetchUser,
///   buildWhen: (previous, current) => previous?.name != current.name,
///   builder: (context, snapshot) => Text(snapshot.data!.name),
/// )
/// ```
class CacheConsumer<T> extends StatefulWidget {
  /// The cache key to watch.
  final String cacheKey;

  /// The fetcher function to retrieve fresh data.
  final Fetcher<T> fetch;

  /// Builder function called with the latest snapshot.
  final Widget Function(BuildContext context, AsyncSnapshot<T> snapshot)
      builder;

  /// Optional listener called when the cache value changes.
  ///
  /// This is called before the widget rebuilds, allowing you to
  /// perform side effects like showing notifications or logging.
  final void Function(BuildContext context, AsyncSnapshot<T> snapshot)?
      listener;

  /// Optional cache instance.
  ///
  /// If not provided, uses [SyncacheScope.of<T>(context)].
  final Syncache<T>? cache;

  /// Caching policy (defaults to [Policy.offlineFirst]).
  final Policy policy;

  /// Optional TTL for cached entries.
  final Duration? ttl;

  /// Optional function to determine if the listener should be called.
  ///
  /// If returns false, the listener won't be called for that update.
  final bool Function(T? previous, T current)? listenWhen;

  /// Optional function to determine if rebuild is needed.
  ///
  /// If returns false, the widget won't rebuild for that update.
  final bool Function(T? previous, T current)? buildWhen;

  /// Initial data to show before the first fetch completes.
  ///
  /// If provided, the builder will receive this data immediately
  /// while the actual fetch is in progress.
  final T? initialData;

  /// Creates a [CacheConsumer].
  const CacheConsumer({
    super.key,
    required this.cacheKey,
    required this.fetch,
    required this.builder,
    this.listener,
    this.cache,
    this.policy = Policy.offlineFirst,
    this.ttl,
    this.listenWhen,
    this.buildWhen,
    this.initialData,
  });

  @override
  State<CacheConsumer<T>> createState() => _CacheConsumerState<T>();
}

class _CacheConsumerState<T> extends State<CacheConsumer<T>> {
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
  void didUpdateWidget(CacheConsumer<T> oldWidget) {
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
    final shouldListen = widget.listenWhen?.call(_lastValue, data) ?? true;
    final shouldBuild = widget.buildWhen?.call(_lastValue, data) ?? true;

    final newSnapshot = AsyncSnapshot<T>.withData(ConnectionState.active, data);

    if (shouldListen && widget.listener != null) {
      widget.listener!(context, newSnapshot);
    }

    _lastValue = data;

    if (shouldBuild) {
      setState(() {
        _snapshot = newSnapshot;
      });
    }
  }

  void _handleError(Object error, StackTrace stackTrace) {
    final newSnapshot = AsyncSnapshot<T>.withError(
      ConnectionState.active,
      error,
      stackTrace,
    );

    widget.listener?.call(context, newSnapshot);

    setState(() {
      _snapshot = newSnapshot;
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
