import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:syncache/syncache.dart';

/// Flutter-specific extensions for [Syncache].
extension SyncacheFlutterExtensions<T> on Syncache<T> {
  /// Creates a [ValueListenable] that tracks the cached value for a key.
  ///
  /// This is useful when you want to use [ValueListenableBuilder] instead
  /// of [CacheBuilder], or when integrating with other Flutter patterns
  /// that expect a [ValueListenable].
  ///
  /// ## Usage
  ///
  /// ```dart
  /// final listenable = cache.toValueListenable(
  ///   key: 'user:123',
  ///   fetch: fetchUser,
  /// );
  ///
  /// return ValueListenableBuilder<AsyncSnapshot<User>>(
  ///   valueListenable: listenable,
  ///   builder: (context, snapshot, child) {
  ///     if (snapshot.hasError) {
  ///       return ErrorWidget(snapshot.error!);
  ///     }
  ///     if (!snapshot.hasData) {
  ///       return const CircularProgressIndicator();
  ///     }
  ///     return UserCard(user: snapshot.data!);
  ///   },
  /// );
  ///
  /// // Don't forget to dispose when done
  /// listenable.dispose();
  /// ```
  ///
  /// **Important**: You must call [SyncacheValueListenable.dispose] when
  /// the listenable is no longer needed to avoid memory leaks.
  SyncacheValueListenable<T> toValueListenable({
    required String key,
    required Fetcher<T> fetch,
    Policy policy = Policy.offlineFirst,
    Duration? ttl,
  }) {
    return SyncacheValueListenable<T>(
      cache: this,
      key: key,
      fetch: fetch,
      policy: policy,
      ttl: ttl,
    );
  }
}

/// A [ValueListenable] wrapper for Syncache streams.
///
/// This class wraps a Syncache watch stream as a [ValueNotifier],
/// allowing it to be used with [ValueListenableBuilder] and other
/// Flutter patterns that expect a [ValueListenable].
///
/// ## Usage
///
/// ```dart
/// final listenable = SyncacheValueListenable<User>(
///   cache: userCache,
///   key: 'user:123',
///   fetch: fetchUser,
/// );
///
/// // Use with ValueListenableBuilder
/// ValueListenableBuilder<AsyncSnapshot<User>>(
///   valueListenable: listenable,
///   builder: (context, snapshot, child) => ...
/// );
///
/// // Dispose when done
/// listenable.dispose();
/// ```
class SyncacheValueListenable<T> extends ValueNotifier<AsyncSnapshot<T>> {
  /// The cache instance.
  final Syncache<T> cache;

  /// The cache key being watched.
  final String key;

  /// The fetcher function to retrieve fresh data.
  final Fetcher<T> fetch;

  /// The caching policy.
  final Policy policy;

  /// Optional TTL for cached entries.
  final Duration? ttl;

  StreamSubscription<T>? _subscription;
  bool _isDisposed = false;

  /// Creates a [SyncacheValueListenable].
  ///
  /// Immediately starts watching the cache key.
  SyncacheValueListenable({
    required this.cache,
    required this.key,
    required this.fetch,
    this.policy = Policy.offlineFirst,
    this.ttl,
  }) : super(AsyncSnapshot<T>.nothing()) {
    _subscribe();
  }

  /// Whether this listenable has been disposed.
  bool get isDisposed => _isDisposed;

  void _subscribe() {
    if (_isDisposed) return;

    value = value.inState(ConnectionState.waiting);

    _subscription = cache
        .watch(
      key: key,
      fetch: fetch,
      policy: policy,
      ttl: ttl,
    )
        .listen(
      (data) {
        if (!_isDisposed) {
          value = AsyncSnapshot<T>.withData(ConnectionState.active, data);
        }
      },
      onError: (Object e, StackTrace st) {
        if (!_isDisposed) {
          value = AsyncSnapshot<T>.withError(ConnectionState.active, e, st);
        }
      },
      onDone: () {
        if (!_isDisposed) {
          value = value.inState(ConnectionState.done);
        }
      },
    );
  }

  /// Re-subscribes to the cache stream.
  ///
  /// This is useful if the stream completed and you want to start
  /// watching again without creating a new instance.
  void resubscribe() {
    if (_isDisposed) {
      throw StateError(
        'Cannot resubscribe to a disposed SyncacheValueListenable',
      );
    }
    _subscription?.cancel();
    _subscription = null;
    _subscribe();
  }

  /// Triggers a refresh of the cached value.
  ///
  /// This will fetch fresh data from the network regardless of
  /// the current cache state.
  Future<void> refresh() async {
    if (_isDisposed) return;
    try {
      await cache.get(
        key: key,
        fetch: fetch,
        policy: Policy.refresh,
        ttl: ttl,
      );
    } catch (_) {
      // Error will be emitted through the stream
    }
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}
