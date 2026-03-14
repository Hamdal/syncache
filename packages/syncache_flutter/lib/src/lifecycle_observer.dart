import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:syncache/syncache.dart';

import 'flutter_network.dart';

/// Configuration for lifecycle-based cache behavior.
///
/// Use this to customize how the cache responds to app lifecycle events
/// and connectivity changes.
///
/// ```dart
/// const config = LifecycleConfig(
///   refetchOnResume: true,
///   refetchOnResumeMinDuration: Duration(minutes: 1),
///   refetchOnReconnect: true,
/// );
/// ```
class LifecycleConfig {
  /// Whether to refetch watched keys when app resumes from background.
  ///
  /// When enabled, all active cache watchers will be refreshed when the
  /// app returns to the foreground after being paused for at least
  /// [refetchOnResumeMinDuration].
  final bool refetchOnResume;

  /// Minimum duration app must be in background before refetch on resume.
  ///
  /// This prevents unnecessary refetches for quick app switches.
  /// Only applies when [refetchOnResume] is true.
  final Duration refetchOnResumeMinDuration;

  /// Whether to refetch watched keys when connectivity is restored.
  ///
  /// When enabled, all active cache watchers will be refreshed when
  /// the device regains network connectivity.
  final bool refetchOnReconnect;

  /// Optional callback for errors that occur during lifecycle refetch.
  ///
  /// If not provided, errors are silently ignored (the watcher stream
  /// will handle them). This can be useful for logging or analytics.
  ///
  /// ```dart
  /// LifecycleConfig(
  ///   onRefetchError: (key, error, stackTrace) {
  ///     logger.warning('Failed to refetch $key: $error');
  ///   },
  /// )
  /// ```
  final void Function(String key, Object error, StackTrace stackTrace)?
      onRefetchError;

  /// Creates a [LifecycleConfig] with the specified options.
  const LifecycleConfig({
    this.refetchOnResume = true,
    this.refetchOnResumeMinDuration = const Duration(seconds: 30),
    this.refetchOnReconnect = true,
    this.onRefetchError,
  });

  /// Default configuration with all features enabled.
  static const defaults = LifecycleConfig();

  /// Configuration that disables all automatic refetching.
  static const disabled = LifecycleConfig(
    refetchOnResume: false,
    refetchOnReconnect: false,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LifecycleConfig &&
          runtimeType == other.runtimeType &&
          refetchOnResume == other.refetchOnResume &&
          refetchOnResumeMinDuration == other.refetchOnResumeMinDuration &&
          refetchOnReconnect == other.refetchOnReconnect &&
          onRefetchError == other.onRefetchError;

  @override
  int get hashCode => Object.hash(
        refetchOnResume,
        refetchOnResumeMinDuration,
        refetchOnReconnect,
        onRefetchError,
      );
}

/// Tracks an active watcher for lifecycle-based refetching.
///
/// This is used internally by [SyncacheLifecycleObserver] to track
/// which cache keys should be refreshed on lifecycle events.
class WatcherRegistration<T> {
  /// The cache key being watched.
  final String key;

  /// The fetcher function to retrieve fresh data.
  final Fetcher<T> fetch;

  /// Optional TTL for cached entries.
  final Duration? ttl;

  /// The caching policy to use.
  final Policy policy;

  /// Creates a [WatcherRegistration].
  const WatcherRegistration({
    required this.key,
    required this.fetch,
    this.ttl,
    this.policy = Policy.offlineFirst,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WatcherRegistration &&
          runtimeType == other.runtimeType &&
          key == other.key;

  @override
  int get hashCode => key.hashCode;
}

/// Observes app lifecycle and triggers cache operations accordingly.
///
/// This observer integrates with Flutter's [WidgetsBindingObserver] to
/// detect when the app is paused/resumed and with [FlutterNetwork] to
/// detect connectivity changes.
///
/// ## Usage
///
/// Typically, you don't use this class directly. Instead, use
/// [SyncacheScope] which manages the lifecycle observer automatically.
///
/// ```dart
/// // Manual usage (not recommended)
/// final observer = SyncacheLifecycleObserver<User>(
///   cache: userCache,
///   network: flutterNetwork,
/// );
/// observer.attach();
///
/// // Register watchers manually
/// observer.registerWatcher(WatcherRegistration(
///   key: 'user:123',
///   fetch: fetchUser,
/// ));
///
/// // Later, when done
/// observer.detach();
/// ```
class SyncacheLifecycleObserver<T> with WidgetsBindingObserver {
  /// The cache instance being observed.
  final Syncache<T> cache;

  /// The network instance for connectivity detection.
  final FlutterNetwork? network;

  /// Configuration for lifecycle behavior.
  final LifecycleConfig config;

  final Set<WatcherRegistration<T>> _activeWatchers = {};
  DateTime? _pausedAt;
  StreamSubscription<bool>? _connectivitySubscription;
  bool _isAttached = false;

  /// Creates a [SyncacheLifecycleObserver].
  SyncacheLifecycleObserver({
    required this.cache,
    this.network,
    this.config = LifecycleConfig.defaults,
  });

  /// Whether the observer is currently attached to the widget binding.
  bool get isAttached => _isAttached;

  /// The number of active watchers.
  int get watcherCount => _activeWatchers.length;

  /// Attach to Flutter's widget binding.
  ///
  /// This starts observing app lifecycle events and connectivity changes.
  /// Must be called before any lifecycle events will be handled.
  void attach() {
    if (_isAttached) return;

    WidgetsBinding.instance.addObserver(this);
    _isAttached = true;

    if (config.refetchOnReconnect && network != null) {
      _connectivitySubscription = network!.onConnectivityChanged.listen(
        (isOnline) {
          if (isOnline) {
            _refetchAll();
          }
        },
      );
    }
  }

  /// Detach from Flutter's widget binding.
  ///
  /// This stops observing app lifecycle events and connectivity changes.
  /// Call this when the observer is no longer needed.
  void detach() {
    if (!_isAttached) return;

    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _isAttached = false;
  }

  /// Register a watcher for lifecycle-based refetching.
  ///
  /// When registered, the watcher will be automatically refreshed on
  /// app resume and connectivity restoration (based on [config]).
  void registerWatcher(WatcherRegistration<T> registration) {
    _activeWatchers.add(registration);
  }

  /// Unregister a watcher by its key.
  void unregisterWatcher(String key) {
    _activeWatchers.removeWhere((w) => w.key == key);
  }

  /// Clears all registered watchers.
  void clearWatchers() {
    _activeWatchers.clear();
  }

  /// Returns a copy of all active watcher registrations.
  ///
  /// This is used internally to transfer watchers when the observer
  /// is recreated (e.g., when [SyncacheScope] is rebuilt with new config).
  Set<WatcherRegistration<T>> copyWatchers() {
    return Set<WatcherRegistration<T>>.from(_activeWatchers);
  }

  /// Adds all watchers from another set.
  ///
  /// This is used internally to restore watchers after observer recreation.
  void restoreWatchers(Set<WatcherRegistration<T>> watchers) {
    _activeWatchers.addAll(watchers);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        // Only start pause timer when actually paused, not on inactive
        // (inactive is a transitional state, e.g., when an overlay appears)
        _pausedAt ??= DateTime.now();
      case AppLifecycleState.inactive:
        // Transitional state - don't start pause timer
        // This happens when showing dialogs, app switcher, etc.
        break;
      case AppLifecycleState.resumed:
        if (config.refetchOnResume && _shouldRefetchOnResume()) {
          _refetchAll();
        }
        _pausedAt = null;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // No action needed
        break;
    }
  }

  bool _shouldRefetchOnResume() {
    if (_pausedAt == null) return false;
    final pausedDuration = DateTime.now().difference(_pausedAt!);
    return pausedDuration >= config.refetchOnResumeMinDuration;
  }

  Future<void> _refetchAll() async {
    // Copy the set to avoid concurrent modification
    final watchers = _activeWatchers.toList();

    for (final watcher in watchers) {
      try {
        await cache.get(
          key: watcher.key,
          fetch: watcher.fetch,
          ttl: watcher.ttl,
          policy: Policy.refresh,
        );
      } catch (error, stackTrace) {
        // Invoke error callback if provided, otherwise silently fail
        // The watcher stream will handle errors for UI updates
        config.onRefetchError?.call(watcher.key, error, stackTrace);
      }
    }
  }
}
