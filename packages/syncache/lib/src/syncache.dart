import 'dart:async';

import 'package:syncache/src/exceptions.dart';
import 'cache_result.dart';
import 'cancellation.dart';
import 'fetch_engine.dart';
import 'fetcher.dart';
import 'metadata.dart';
import 'mutation.dart';
import 'mutation_queue.dart';
import 'network.dart';
import 'observer.dart';
import 'pending_mutation_info.dart';
import 'policy.dart';
import 'prefetch.dart';
import 'retry.dart';
import 'scoped_syncache.dart';
import 'store.dart';
import 'stored.dart';

/// An offline-first cache and sync engine for Dart applications.
///
/// [Syncache] provides a unified API for caching data with multiple
/// strategies, reactive updates via streams, and optimistic mutations
/// with automatic background sync.
///
/// ## Basic Usage
///
/// ```dart
/// // Create a cache instance
/// final cache = Syncache<User>(
///   store: MemoryStore<User>(),
/// );
///
/// // Fetch data with offline-first policy
/// final user = await cache.get(
///   key: 'user:123',
///   fetch: (request) => api.getUser(123),
/// );
///
/// // Watch for reactive updates
/// cache.watch(
///   key: 'user:123',
///   fetch: (request) => api.getUser(123),
/// ).listen((user) {
///   print('User updated: ${user.name}');
/// });
/// ```
///
/// ## Caching Policies
///
/// Control caching behavior with [Policy]:
/// - [Policy.offlineFirst]: Cache first, fetch if expired (default)
/// - [Policy.cacheOnly]: Only use cached data
/// - [Policy.networkOnly]: Always fetch from network
/// - [Policy.refresh]: Fetch if online, cache if offline
/// - [Policy.staleWhileRefresh]: Return cache, refresh in background
///
/// ## Optimistic Mutations
///
/// ```dart
/// await cache.mutate(
///   key: 'user:123',
///   mutation: Mutation<User>(
///     apply: (user) => user.copyWith(name: 'New Name'),
///     send: (user) => api.updateUser(user),
///   ),
/// );
/// ```
///
/// ## Network Awareness
///
/// Provide a custom [Network] implementation for offline detection:
///
/// ```dart
/// final cache = Syncache<User>(
///   store: MemoryStore<User>(),
///   network: MyConnectivityNetwork(),
/// );
/// ```
///
/// See also:
/// - [Store] for storage backend options
/// - [Policy] for caching strategies
/// - [Mutation] for optimistic updates
/// - [SyncacheObserver] for monitoring cache operations
class Syncache<T> {
  final Store<T> store;
  final Network network;
  final List<SyncacheObserver> observers;
  final RetryConfig defaultRetry;
  final MutationRetryConfig mutationRetry;

  late final FetchEngine<T> _fetchEngine;
  late final MutationQueue<T> _mutationQueue;

  final Map<String, StreamController<T>> _controllers = {};
  final Map<String, StreamController<CacheResult<T>>> _metaControllers = {};
  bool _isDisposed = false;

  /// Key: dependency key, Value: set of keys that depend on it.
  final Map<String, Set<String>> _dependents = {};

  /// Key: watcher key, Value: info about the watcher including its fetcher.
  final Map<String, _DependencyWatcher<T>> _dependencyWatchers = {};

  /// Creates a [Syncache] instance with the given [store] and optional [network].
  ///
  /// If [network] is not provided, [AlwaysOnline] is used, meaning the cache
  /// will always attempt network requests when needed.
  ///
  /// Provide [observers] to monitor cache operations for logging or analytics.
  ///
  /// Set [defaultRetry] to enable automatic retries for all [get] operations.
  /// By default, retries are disabled.
  ///
  /// Set [mutationRetry] to configure retry behavior for mutation sync operations.
  /// By default, mutations are retried up to 3 times with exponential backoff.
  ///
  /// Example:
  /// ```dart
  /// final cache = Syncache<User>(
  ///   store: MemoryStore<User>(),
  ///   network: MyConnectivityNetwork(), // Optional
  ///   observers: [LoggingObserver()],   // Optional
  ///   defaultRetry: RetryConfig(maxAttempts: 3), // Optional
  ///   mutationRetry: MutationRetryConfig(maxAttempts: 5), // Optional
  /// );
  /// ```
  Syncache({
    required this.store,
    Network? network,
    List<SyncacheObserver>? observers,
    RetryConfig? defaultRetry,
    MutationRetryConfig? mutationRetry,
  })  : network = network ?? const AlwaysOnline(),
        observers = observers ?? const [],
        defaultRetry = defaultRetry ?? RetryConfig.none,
        mutationRetry = mutationRetry ?? const MutationRetryConfig() {
    _fetchEngine = FetchEngine<T>(
      store: store,
      writeToStore: _writeToStore,
      notifyObservers: _notifyObservers,
    );
    _mutationQueue = MutationQueue<T>(
      store: store,
      network: this.network,
      retryConfig: this.mutationRetry,
      notifyObservers: _notifyObservers,
      notifyWatchers: (key) => _notify(key, isFromCache: false),
      performInvalidations: _performMutationInvalidations,
    );
  }

  /// Notifies all observers, catching errors to prevent observer failures
  /// from breaking cache operations.
  void _notifyObservers(void Function(SyncacheObserver observer) callback) {
    for (final observer in observers) {
      try {
        callback(observer);
      } catch (_) {}
    }
  }

  void _checkNotDisposed() {
    if (_isDisposed) {
      throw StateError('Syncache instance has been disposed');
    }
  }

  // ============================================================
  // Core Cache Operations
  // ============================================================

  /// Retrieves a value from the cache or network based on the [policy].
  ///
  /// The [key] uniquely identifies the cached data. The [fetch] function
  /// is called when fresh data needs to be retrieved from the network.
  ///
  /// The [policy] determines the caching strategy (defaults to [Policy.offlineFirst]).
  /// The optional [ttl] sets the time-to-live for the cached entry.
  ///
  /// The optional [retry] configures automatic retry behavior for transient
  /// failures. If not provided, uses [defaultRetry] (which defaults to no retries).
  ///
  /// The optional [cancel] token allows the operation to be cancelled. When
  /// cancelled, the operation throws [CancelledException].
  ///
  /// Example:
  /// ```dart
  /// final token = CancellationToken();
  ///
  /// final future = cache.get(
  ///   key: 'user:123',
  ///   fetch: (request) => api.getUser(123),
  ///   policy: Policy.offlineFirst,
  ///   ttl: Duration(minutes: 5),
  ///   retry: RetryConfig(maxAttempts: 3),
  ///   cancel: token,
  /// );
  ///
  /// // Later, to cancel:
  /// token.cancel();
  /// ```
  ///
  /// Throws [CacheMissException] if no data is available according to the policy.
  /// Throws [CancelledException] if the operation is cancelled.
  /// Throws [SyncacheException] or the fetcher's exception if the network request fails.
  Future<T> get({
    required String key,
    required Fetcher<T> fetch,
    Policy policy = Policy.offlineFirst,
    Duration? ttl,
    RetryConfig? retry,
    CancellationToken? cancel,
    List<String>? tags,
  }) async {
    _checkNotDisposed();
    cancel?.throwIfCancelled();

    return _executePolicy<T>(
      key: key,
      policy: policy,
      strategy: _StandardFetchStrategy<T>(fetch),
      ttl: ttl,
      retry: retry ?? defaultRetry,
      cancel: cancel,
      tags: tags,
    );
  }

  /// Retrieves a value with cache metadata.
  ///
  /// Similar to [get], but returns a [CacheResult] that includes
  /// metadata about whether the data came from cache, its freshness,
  /// and when it was stored. Useful for displaying stale indicators
  /// or data age in the UI.
  ///
  /// Example:
  /// ```dart
  /// final result = await cache.getWithMeta(
  ///   key: 'user:123',
  ///   fetch: (request) => api.getUser(123),
  /// );
  ///
  /// updateUI(result.value);
  ///
  /// if (result.meta.isStale) {
  ///   showStaleDataBanner();
  /// }
  ///
  /// if (result.meta.age != null && result.meta.age! > Duration(hours: 1)) {
  ///   showOldDataWarning();
  /// }
  /// ```
  Future<CacheResult<T>> getWithMeta({
    required String key,
    required Fetcher<T> fetch,
    Policy policy = Policy.offlineFirst,
    Duration? ttl,
    RetryConfig? retry,
    CancellationToken? cancel,
  }) async {
    _checkNotDisposed();
    cancel?.throwIfCancelled();

    return _executePolicy<CacheResult<T>>(
      key: key,
      policy: policy,
      strategy: _MetaFetchStrategy<T>(fetch, store, _notifyValue),
      ttl: ttl,
      retry: retry ?? defaultRetry,
      cancel: cancel,
      tags: null,
    );
  }

  /// Retrieves a value using a [ConditionalFetcher] that supports HTTP 304.
  ///
  /// This method is similar to [get] but uses a [ConditionalFetcher] that
  /// can return [FetchResult.notModified] when the server responds with
  /// HTTP 304 Not Modified, indicating the cached data is still valid.
  ///
  /// When the fetcher returns [FetchResult.notModified], the cached value
  /// is returned and its metadata is refreshed (new storedAt time).
  ///
  /// The [FetchResult.etag] and [FetchResult.lastModified] values from the
  /// response are stored in the metadata for future conditional requests.
  ///
  /// Example:
  /// ```dart
  /// final user = await cache.getConditional(
  ///   key: 'user:123',
  ///   fetch: (request) async {
  ///     final response = await http.get(
  ///       Uri.parse('https://api.example.com/user/123'),
  ///       headers: request.headers,
  ///     );
  ///     if (response.statusCode == 304) {
  ///       return FetchResult.notModified();
  ///     }
  ///     return FetchResult.data(
  ///       User.fromJson(jsonDecode(response.body)),
  ///       etag: response.headers['etag'],
  ///     );
  ///   },
  /// );
  /// ```
  Future<T> getConditional({
    required String key,
    required ConditionalFetcher<T> fetch,
    Policy policy = Policy.offlineFirst,
    Duration? ttl,
    RetryConfig? retry,
    CancellationToken? cancel,
  }) async {
    _checkNotDisposed();
    cancel?.throwIfCancelled();

    return _executePolicy<T>(
      key: key,
      policy: policy,
      strategy: _ConditionalFetchStrategy<T>(fetch),
      ttl: ttl,
      retry: retry ?? defaultRetry,
      cancel: cancel,
      tags: null,
    );
  }

  /// Sets a value directly in the cache without fetching.
  ///
  /// This method stores the value immediately and notifies all watchers,
  /// including any watchers that depend on this key via [watchWithDependencies].
  ///
  /// Use this when you have a value from an external source (e.g., a push
  /// notification, WebSocket message, or user input) that should update
  /// the cache without a network fetch.
  ///
  /// Example:
  /// ```dart
  /// // Update cache from a WebSocket message
  /// socket.onMessage.listen((data) {
  ///   final user = User.fromJson(data);
  ///   cache.set(key: 'user:${user.id}', value: user);
  /// });
  ///
  /// // Set with TTL
  /// await cache.set(
  ///   key: 'session:token',
  ///   value: token,
  ///   ttl: Duration(hours: 1),
  /// );
  /// ```
  ///
  /// This will trigger refetch for any keys watching this key via
  /// [watchWithDependencies].
  Future<void> set({
    required String key,
    required T value,
    Duration? ttl,
  }) async {
    _checkNotDisposed();

    final existingEntry = await store.read(key);
    final newMeta = Metadata(
      version: (existingEntry?.meta.version ?? 0) + 1,
      storedAt: DateTime.now(),
      ttl: ttl ?? existingEntry?.meta.ttl,
      etag: existingEntry?.meta.etag,
      lastModified: existingEntry?.meta.lastModified,
    );

    await store.write(key, Stored(value: value, meta: newMeta));
    _notifyObservers((o) => o.onStore(key));
    await _notify(key, isFromCache: false);

    // Trigger refetch for dependent watchers
    await _notifyDependents(key);
  }

  /// Notifies dependent watchers to refetch when a dependency changes.
  Future<void> _notifyDependents(String key) async {
    final dependentKeys = _dependents[key];
    if (dependentKeys == null || dependentKeys.isEmpty) {
      return;
    }

    for (final dependentKey in dependentKeys.toList()) {
      final watcher = _dependencyWatchers[dependentKey];
      if (watcher == null) continue;

      final controller = _controllers[dependentKey];
      if (controller == null || controller.isClosed) {
        _removeDependencyWatcher(dependentKey);
        continue;
      }

      try {
        await get(
          key: watcher.key,
          fetch: watcher.fetch,
          policy: Policy.refresh,
          ttl: watcher.ttl,
        );
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError(e);
        }
      }
    }
  }

  /// Removes a dependency watcher and cleans up tracking.
  void _removeDependencyWatcher(String key) {
    final watcher = _dependencyWatchers.remove(key);
    if (watcher == null) return;

    for (final dep in watcher.dependsOn) {
      _dependents[dep]?.remove(key);
      if (_dependents[dep]?.isEmpty ?? false) {
        _dependents.remove(dep);
      }
    }
  }

  // ============================================================
  // Watch (Reactive Streams)
  // ============================================================

  /// Returns a reactive stream of values for the given [key].
  ///
  /// The stream emits the current cached value (or fetches it) immediately,
  /// then emits updates whenever the value changes due to cache refreshes
  /// or mutations.
  ///
  /// The stream is a broadcast stream, allowing multiple listeners.
  /// When all listeners unsubscribe, the stream controller is closed
  /// and removed.
  ///
  /// Example:
  /// ```dart
  /// final subscription = cache.watch(
  ///   key: 'user:123',
  ///   fetch: (request) => api.getUser(123),
  /// ).listen(
  ///   (user) => updateUI(user),
  ///   onError: (e) => showError(e),
  /// );
  ///
  /// // Later, to stop watching:
  /// await subscription.cancel();
  /// ```
  ///
  /// Errors during fetch are emitted as stream errors rather than thrown.
  Stream<T> watch({
    required String key,
    required Fetcher<T> fetch,
    Policy policy = Policy.offlineFirst,
    Duration? ttl,
  }) {
    _checkNotDisposed();
    final controller = _controllers.putIfAbsent(
      key,
      () => StreamController<T>.broadcast(
        onCancel: () {
          _controllers[key]?.close();
          _controllers.remove(key);
        },
      ),
    );

    final controllerAtStart = controller;

    () async {
      try {
        await get(
          key: key,
          fetch: fetch,
          policy: policy,
          ttl: ttl,
        );
      } catch (e) {
        final currentController = _controllers[key];
        if (currentController != null &&
            currentController == controllerAtStart &&
            !currentController.isClosed) {
          currentController.addError(e);
        }
      }
    }();

    return controller.stream;
  }

  /// Returns a reactive stream of values with metadata for the given [key].
  ///
  /// Similar to [watch], but emits [CacheResult] objects that include
  /// metadata about whether the data came from cache, its freshness,
  /// and when it was stored.
  ///
  /// Example:
  /// ```dart
  /// final subscription = cache.watchWithMeta(
  ///   key: 'user:123',
  ///   fetch: (request) => api.getUser(123),
  /// ).listen(
  ///   (result) {
  ///     updateUI(result.value);
  ///     if (result.meta.isStale) {
  ///       showStaleIndicator();
  ///     }
  ///   },
  /// );
  /// ```
  Stream<CacheResult<T>> watchWithMeta({
    required String key,
    required Fetcher<T> fetch,
    Policy policy = Policy.offlineFirst,
    Duration? ttl,
  }) {
    _checkNotDisposed();
    final controller = _metaControllers.putIfAbsent(
      key,
      () => StreamController<CacheResult<T>>.broadcast(
        onCancel: () {
          _metaControllers[key]?.close();
          _metaControllers.remove(key);
        },
      ),
    );

    final controllerAtStart = controller;

    () async {
      try {
        final result = await getWithMeta(
          key: key,
          fetch: fetch,
          policy: policy,
          ttl: ttl,
        );

        final currentController = _metaControllers[key];
        if (currentController != null &&
            currentController == controllerAtStart &&
            !currentController.isClosed) {
          currentController.add(result);
        }
      } catch (e) {
        final currentController = _metaControllers[key];
        if (currentController != null &&
            currentController == controllerAtStart &&
            !currentController.isClosed) {
          currentController.addError(e);
        }
      }
    }();

    return controller.stream;
  }

  /// Returns a reactive stream that automatically refetches when dependencies change.
  ///
  /// This method creates a watch stream that listens to dependency keys and
  /// automatically triggers a refetch when any of those dependencies change
  /// (via [set], [mutate], or a fetch operation).
  ///
  /// Use this when you have data that depends on other cached values. For example,
  /// calendar events that should refresh when the current workspace changes.
  ///
  /// Example:
  /// ```dart
  /// // Calendar events refetch when current workspace changes
  /// cache.watchWithDependencies(
  ///   key: 'calendar:events',
  ///   fetch: fetchEvents,
  ///   refetchWhen: ['workspace:current', 'user:preferences'],
  /// ).listen((events) {
  ///   updateEventsList(events);
  /// });
  ///
  /// // Later, when workspace changes:
  /// await cache.set(key: 'workspace:current', value: newWorkspace);
  /// // ^ Automatically triggers refetch of calendar:events
  /// ```
  ///
  /// The stream emits:
  /// 1. The initial value (fetched or from cache)
  /// 2. Updates whenever the key itself changes
  /// 3. Refetched values whenever any dependency key changes
  ///
  /// When all listeners unsubscribe, the dependency tracking is cleaned up.
  ///
  /// Note: The dependency keys don't need to exist in the cache beforehand.
  /// The watcher will trigger a refetch whenever any of the listed keys
  /// are modified via [set] or [mutate].
  Stream<T> watchWithDependencies({
    required String key,
    required Fetcher<T> fetch,
    required List<String> refetchWhen,
    Policy policy = Policy.offlineFirst,
    Duration? ttl,
  }) {
    _checkNotDisposed();

    if (refetchWhen.isEmpty) {
      return watch(key: key, fetch: fetch, policy: policy, ttl: ttl);
    }

    _dependencyWatchers[key] = _DependencyWatcher<T>(
      key: key,
      fetch: fetch,
      policy: policy,
      ttl: ttl,
      dependsOn: refetchWhen,
    );

    for (final dep in refetchWhen) {
      _dependents.putIfAbsent(dep, () => {}).add(key);
    }

    final controller = _controllers.putIfAbsent(
      key,
      () => StreamController<T>.broadcast(
        onCancel: () {
          _controllers[key]?.close();
          _controllers.remove(key);
          _removeDependencyWatcher(key);
        },
      ),
    );

    final controllerAtStart = controller;

    () async {
      try {
        await get(
          key: key,
          fetch: fetch,
          policy: policy,
          ttl: ttl,
        );
      } catch (e) {
        final currentController = _controllers[key];
        if (currentController != null &&
            currentController == controllerAtStart &&
            !currentController.isClosed) {
          currentController.addError(e);
        }
      }
    }();

    return controller.stream;
  }

  // ============================================================
  // Mutations
  // ============================================================

  /// Applies an optimistic mutation to a cached value.
  ///
  /// The mutation's [Mutation.apply] function is called immediately to
  /// update the local cache, providing instant feedback. The [Mutation.send]
  /// function is then queued for background sync to persist the change.
  ///
  /// If [send] succeeds, the server's response replaces the optimistic value.
  /// If [send] fails, the mutation remains queued and will retry when online.
  ///
  /// Watchers of the [key] are notified of both the optimistic update
  /// and the eventual server confirmation.
  ///
  /// Example:
  /// ```dart
  /// await cache.mutate(
  ///   key: 'user:123',
  ///   mutation: Mutation<User>(
  ///     apply: (user) => user.copyWith(name: 'New Name'),
  ///     send: (user) async {
  ///       final response = await api.updateUser(user);
  ///       return User.fromJson(response);
  ///     },
  ///   ),
  /// );
  /// ```
  ///
  /// You can also specify cache entries to invalidate after successful sync:
  ///
  /// ```dart
  /// await cache.mutate(
  ///   key: 'event:456',
  ///   mutation: mutation,
  ///   invalidates: ['calendar:*'],           // Pattern-based invalidation
  ///   invalidateTags: ['events', 'calendar'], // Tag-based invalidation
  /// );
  /// ```
  ///
  /// Throws [CacheMissException] if no cached value exists for [key].
  Future<void> mutate({
    required String key,
    required Mutation<T> mutation,
    List<String>? invalidates,
    List<String>? invalidateTags,
  }) async {
    _checkNotDisposed();
    final cached = await store.read(key);
    if (cached == null) {
      throw CacheMissException(key);
    }

    _notifyObservers((o) => o.onMutationStart(key));

    final optimisticValue = mutation.apply(cached.value);
    final newMeta = Metadata(
      version: cached.meta.version + 1,
      storedAt: DateTime.now(),
      ttl: cached.meta.ttl,
      etag: cached.meta.etag,
      lastModified: cached.meta.lastModified,
    );

    await store.write(key, Stored(value: optimisticValue, meta: newMeta));
    _notifyObservers((o) => o.onStore(key));
    _notify(key, isFromCache: false);

    _notifyDependents(key);

    _mutationQueue.add(PendingMutation(
      key: key,
      mutation: mutation,
      optimisticValue: optimisticValue,
      invalidates: invalidates,
      invalidateTags: invalidateTags,
    ));
  }

  /// Returns the number of pending mutations.
  int get pendingMutationCount {
    _checkNotDisposed();
    return _mutationQueue.count;
  }

  /// Returns whether there are any pending mutations.
  bool get hasPendingMutations {
    _checkNotDisposed();
    return _mutationQueue.hasPending;
  }

  /// Returns a snapshot of current pending mutations.
  List<PendingMutationInfo> get pendingMutationsSnapshot {
    _checkNotDisposed();
    return _mutationQueue.snapshot;
  }

  /// Stream of pending mutation info for UI sync indicators.
  Stream<List<PendingMutationInfo>> get pendingMutationsStream {
    _checkNotDisposed();
    return _mutationQueue.stream;
  }

  /// Stream that emits true when all mutations are synced.
  Stream<bool> get isSyncedStream {
    _checkNotDisposed();
    return _mutationQueue.isSyncedStream;
  }

  /// Removes all pending mutations from the sync queue.
  void clearPendingMutations() {
    _checkNotDisposed();
    _mutationQueue.clear();
  }

  /// Removes the first pending mutation from the sync queue.
  bool removeFirstPendingMutation() {
    _checkNotDisposed();
    return _mutationQueue.removeFirst();
  }

  // ============================================================
  // Invalidation
  // ============================================================

  /// Invalidates (deletes) the cached entry for the given [key].
  ///
  /// Any active watchers for the key will have their streams closed.
  /// The next [get] or [watch] call will fetch fresh data.
  ///
  /// Example:
  /// ```dart
  /// await cache.invalidate('user:123');
  /// ```
  Future<void> invalidate(String key) async {
    _checkNotDisposed();
    await store.delete(key);
    _notifyObservers((o) => o.onInvalidate(key));
    _notifyRemoval(key);
  }

  /// Invalidates all cache entries with the specified [tag].
  ///
  /// Requires the store to implement [TaggableStore].
  /// If the store doesn't support tagging, this method does nothing.
  ///
  /// All watchers for affected entries will have their streams closed.
  ///
  /// Example:
  /// ```dart
  /// // Store entries with tags
  /// await cache.get(
  ///   key: 'user:123',
  ///   fetch: fetchUser,
  ///   tags: ['users', 'workspace:456'],
  /// );
  ///
  /// // Invalidate all entries tagged with 'users'
  /// await cache.invalidateTag('users');
  /// ```
  Future<void> invalidateTag(String tag) async {
    _checkNotDisposed();
    if (store is! TaggableStore<T>) return;

    final taggableStore = store as TaggableStore<T>;
    final keys = await taggableStore.getKeysByTag(tag);
    await taggableStore.deleteByTag(tag);

    for (final key in keys) {
      _notifyObservers((o) => o.onInvalidate(key));
      _notifyRemoval(key);
    }
  }

  /// Invalidates all cache entries that have any of the specified [tags].
  ///
  /// If [matchAll] is true, only entries with ALL tags are invalidated.
  /// Requires [TaggableStore].
  Future<void> invalidateTags(List<String> tags,
      {bool matchAll = false}) async {
    _checkNotDisposed();
    if (store is! TaggableStore<T>) return;
    if (tags.isEmpty) return;

    final taggableStore = store as TaggableStore<T>;

    final keysToNotify = <String>{};
    if (matchAll) {
      var intersection = (await taggableStore.getKeysByTag(tags.first)).toSet();
      for (final tag in tags.skip(1)) {
        final keysForTag = (await taggableStore.getKeysByTag(tag)).toSet();
        intersection = intersection.intersection(keysForTag);
      }
      keysToNotify.addAll(intersection);
    } else {
      for (final tag in tags) {
        keysToNotify.addAll(await taggableStore.getKeysByTag(tag));
      }
    }

    await taggableStore.deleteByTags(tags, matchAll: matchAll);

    for (final key in keysToNotify) {
      _notifyObservers((o) => o.onInvalidate(key));
      _notifyRemoval(key);
    }
  }

  /// Invalidates all cache entries whose keys match the given glob [pattern].
  ///
  /// Requires the store to implement [TaggableStore].
  /// If the store doesn't support pattern matching, this method does nothing.
  ///
  /// Supports simple glob patterns:
  /// - `*` matches any characters
  /// - `?` matches a single character
  ///
  /// Example:
  /// ```dart
  /// // Invalidate all user entries
  /// await cache.invalidatePattern('user:*');
  ///
  /// // Invalidate entries for a specific date pattern
  /// await cache.invalidatePattern('events:2024-03-*');
  /// ```
  Future<void> invalidatePattern(String pattern) async {
    _checkNotDisposed();
    if (store is! TaggableStore<T>) return;

    final taggableStore = store as TaggableStore<T>;
    final keys = await taggableStore.getKeysByPattern(pattern);
    await taggableStore.deleteByPattern(pattern);

    for (final key in keys) {
      _notifyObservers((o) => o.onInvalidate(key));
      _notifyRemoval(key);
    }
  }

  /// Clears all cached entries.
  Future<void> clear() async {
    _checkNotDisposed();
    await store.clear();
    _notifyObservers((o) => o.onClear());
    final allKeys = {..._controllers.keys, ..._metaControllers.keys};
    for (final key in allKeys) {
      _notifyRemoval(key);
    }
  }

  // ============================================================
  // Cache Scoping
  // ============================================================

  /// Creates a scoped view of this cache.
  ///
  /// All operations on the returned [ScopedSyncache] will automatically
  /// prefix keys with `$scope:`, providing isolation between different
  /// contexts (e.g., workspaces, tenants, user sessions).
  ///
  /// Example:
  /// ```dart
  /// // Create workspace-scoped caches
  /// final workspace1Cache = cache.scoped('workspace:1');
  /// final workspace2Cache = cache.scoped('workspace:2');
  ///
  /// // Operations are isolated
  /// await workspace1Cache.get(key: 'users', fetch: fetchUsers);
  /// // Actually stores as: 'workspace:1:users'
  ///
  /// await workspace2Cache.get(key: 'users', fetch: fetchUsers);
  /// // Actually stores as: 'workspace:2:users'
  /// ```
  ScopedSyncache<T> scoped(String scope) {
    _checkNotDisposed();
    return ScopedSyncache<T>(this, scope);
  }

  /// Clears all cached entries within a scope.
  ///
  /// Requires [TaggableStore] for pattern matching.
  Future<void> clearScope(String scope) async {
    _checkNotDisposed();
    await invalidatePattern('$scope:*');
  }

  /// Invalidates entries within a scope matching a pattern.
  ///
  /// The [pattern] is automatically prefixed with `$scope:`.
  /// Requires [TaggableStore] for pattern matching.
  Future<void> invalidateInScope(String scope, String pattern) async {
    _checkNotDisposed();
    await invalidatePattern('$scope:$pattern');
  }

  // ============================================================
  // Prefetch
  // ============================================================

  /// Prefetches multiple cache entries in parallel.
  ///
  /// Use this to warm the cache before navigation or display,
  /// improving perceived performance. All prefetches run in parallel
  /// and failures are captured in the results rather than thrown.
  ///
  /// Returns a list of [PrefetchResult] objects indicating success or
  /// failure for each request. The results are in the same order as
  /// the input [requests].
  ///
  /// Example:
  /// ```dart
  /// // Before navigation
  /// final results = await cache.prefetch([
  ///   PrefetchRequest(key: 'profile', fetch: fetchProfile),
  ///   PrefetchRequest(key: 'settings', fetch: fetchSettings),
  /// ]);
  ///
  /// // Check results if needed
  /// for (final result in results) {
  ///   if (!result.success) {
  ///     print('Failed to prefetch ${result.key}: ${result.error}');
  ///   }
  /// }
  ///
  /// Navigator.push(context, ProfilePage());
  /// ```
  ///
  /// By default, prefetch uses [Policy.refresh] to always fetch fresh data.
  /// You can override this per-request using [PrefetchRequest.policy].
  Future<List<PrefetchResult>> prefetch(List<PrefetchRequest<T>> requests) {
    _checkNotDisposed();
    return Future.wait(
      requests.map((req) async {
        try {
          await get(
            key: req.key,
            fetch: req.fetch,
            ttl: req.ttl,
            policy: req.policy,
            retry: req.retry,
          );
          return PrefetchResult.success(req.key);
        } catch (e, st) {
          return PrefetchResult.failure(req.key, e, st);
        }
      }),
      eagerError: false,
    );
  }

  /// Prefetches a single cache entry. Returns true on success.
  Future<bool> prefetchOne({
    required String key,
    required Fetcher<T> fetch,
    Duration? ttl,
    Policy policy = Policy.refresh,
    RetryConfig? retry,
  }) async {
    _checkNotDisposed();
    try {
      await get(
        key: key,
        fetch: fetch,
        ttl: ttl,
        policy: policy,
        retry: retry,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Prefetches multiple cache entries with dependency ordering.
  ///
  /// Nodes are executed in dependency order, with independent nodes running
  /// in parallel for optimal performance. A node will only start after all
  /// its dependencies have completed (successfully or not).
  ///
  /// Example:
  /// ```dart
  /// // Profile must load before settings (settings depends on profile data)
  /// // Notifications can load in parallel with profile
  /// final result = await cache.prefetchGraph([
  ///   PrefetchNode(
  ///     key: 'user:profile',
  ///     fetch: fetchProfile,
  ///   ),
  ///   PrefetchNode(
  ///     key: 'user:settings',
  ///     fetch: fetchSettings,
  ///     dependsOn: ['user:profile'],
  ///   ),
  ///   PrefetchNode(
  ///     key: 'notifications',
  ///     fetch: fetchNotifications,
  ///     // No dependencies - runs in parallel with profile
  ///   ),
  /// ]);
  ///
  /// if (!result.allSucceeded) {
  ///   print('Failed to prefetch: ${result.failedKeys}');
  /// }
  /// ```
  ///
  /// The method validates the dependency graph and throws [ArgumentError] if:
  /// - A node depends on a key that doesn't exist in the graph
  /// - The graph contains circular dependencies
  ///
  /// Returns a [PrefetchGraphResult] containing results for all nodes.
  Future<PrefetchGraphResult> prefetchGraph(
    List<PrefetchNode<T>> nodes, {
    PrefetchGraphOptions options = PrefetchGraphOptions.defaults,
  }) async {
    _checkNotDisposed();

    if (nodes.isEmpty) {
      return PrefetchGraphResult(
        results: {},
        totalDuration: Duration.zero,
      );
    }

    final stopwatch = Stopwatch()..start();

    final nodeMap = <String, PrefetchNode<T>>{};
    for (final node in nodes) {
      if (nodeMap.containsKey(node.key)) {
        throw ArgumentError('Duplicate key in prefetch graph: ${node.key}');
      }
      nodeMap[node.key] = node;
    }

    for (final node in nodes) {
      for (final dep in node.dependsOn) {
        if (!nodeMap.containsKey(dep)) {
          throw ArgumentError(
            'Node "${node.key}" depends on "$dep" which is not in the graph',
          );
        }
      }
    }

    _validateNoCycles(nodeMap);

    final results = <String, PrefetchNodeResult>{};
    final completers = <String, Completer<PrefetchNodeResult>>{};
    var failFastTriggered = false;

    for (final node in nodes) {
      completers[node.key] = Completer<PrefetchNodeResult>();
    }

    final futures = <Future<void>>[];
    for (final node in nodes) {
      futures.add(_executePrefetchNode(
        node: node,
        nodeMap: nodeMap,
        completers: completers,
        results: results,
        options: options,
        isFailFastTriggered: () => failFastTriggered,
        onFailFast: () => failFastTriggered = true,
      ));
    }

    await Future.wait(futures);

    stopwatch.stop();

    return PrefetchGraphResult(
      results: results,
      totalDuration: stopwatch.elapsed,
    );
  }

  /// Validates that the dependency graph has no cycles using DFS.
  void _validateNoCycles(Map<String, PrefetchNode<T>> nodeMap) {
    final visited = <String>{};
    final inStack = <String>{};

    void visit(String key, List<String> path) {
      if (inStack.contains(key)) {
        final cycleStart = path.indexOf(key);
        final cycle = [...path.sublist(cycleStart), key];
        throw ArgumentError(
          'Circular dependency detected: ${cycle.join(' -> ')}',
        );
      }
      if (visited.contains(key)) return;

      inStack.add(key);
      path.add(key);

      final node = nodeMap[key]!;
      for (final dep in node.dependsOn) {
        visit(dep, path);
      }

      path.removeLast();
      inStack.remove(key);
      visited.add(key);
    }

    for (final key in nodeMap.keys) {
      if (!visited.contains(key)) {
        visit(key, []);
      }
    }
  }

  /// Executes a single prefetch node after its dependencies complete.
  Future<void> _executePrefetchNode({
    required PrefetchNode<T> node,
    required Map<String, PrefetchNode<T>> nodeMap,
    required Map<String, Completer<PrefetchNodeResult>> completers,
    required Map<String, PrefetchNodeResult> results,
    required PrefetchGraphOptions options,
    required bool Function() isFailFastTriggered,
    required void Function() onFailFast,
  }) async {
    final depResults = <PrefetchNodeResult>[];
    for (final depKey in node.dependsOn) {
      final depResult = await completers[depKey]!.future;
      depResults.add(depResult);
    }

    if (options.failFast && isFailFastTriggered()) {
      final result = PrefetchNodeResult.skipped(
        node.key,
        'Skipped due to fail-fast',
      );
      results[node.key] = result;
      completers[node.key]!.complete(result);
      return;
    }

    if (options.skipOnDependencyFailure) {
      final failedDep = depResults.where((r) => !r.success).firstOrNull;
      if (failedDep != null) {
        final result = PrefetchNodeResult.skipped(
          node.key,
          'Dependency "${failedDep.key}" failed',
        );
        results[node.key] = result;
        completers[node.key]!.complete(result);
        return;
      }
    }

    final nodeStopwatch = Stopwatch()..start();
    try {
      await get(
        key: node.key,
        fetch: node.fetch,
        ttl: node.ttl,
        policy: node.policy,
        retry: node.retry,
      );
      nodeStopwatch.stop();
      final result =
          PrefetchNodeResult.success(node.key, nodeStopwatch.elapsed);
      results[node.key] = result;
      completers[node.key]!.complete(result);
    } catch (e, st) {
      nodeStopwatch.stop();
      if (options.failFast) {
        onFailFast();
      }
      final result = PrefetchNodeResult.failure(
        node.key,
        e,
        st,
        nodeStopwatch.elapsed,
      );
      results[node.key] = result;
      completers[node.key]!.complete(result);
    }
  }

  // ============================================================
  // Lifecycle
  // ============================================================

  /// Disposes of this Syncache instance and releases all resources.
  ///
  /// This method:
  /// - Closes all active stream controllers (watchers)
  /// - Clears the pending mutations queue
  /// - Does NOT clear cached data from the store
  ///
  /// After calling dispose, this instance should not be used.
  /// Create a new instance if you need to continue using the cache.
  /// Calling any public method after dispose will throw [StateError].
  ///
  /// Example:
  /// ```dart
  /// await cache.dispose();
  /// ```
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    // Close all stream controllers
    for (final controller in _controllers.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    _controllers.clear();

    // Close all meta stream controllers
    for (final controller in _metaControllers.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    _metaControllers.clear();

    // Dispose mutation queue
    _mutationQueue.dispose();

    // Clear fetch engine tracking
    _fetchEngine.clear();
  }

  // ============================================================
  // Internal Helpers
  // ============================================================

  /// Writes to the store, using tags if the store supports it.
  Future<void> _writeToStore(
      String key, Stored<T> entry, List<String>? tags) async {
    if (tags != null && tags.isNotEmpty && store is TaggableStore<T>) {
      await (store as TaggableStore<T>).writeWithTags(key, entry, tags);
    } else {
      await store.write(key, entry);
    }
  }

  /// Performs invalidations specified by a mutation after successful sync.
  Future<void> _performMutationInvalidations(
      List<String>? patterns, List<String>? tags) async {
    // Invalidate by patterns
    if (patterns != null && patterns.isNotEmpty) {
      for (final pattern in patterns) {
        await invalidatePattern(pattern);
      }
    }

    // Invalidate by tags
    if (tags != null && tags.isNotEmpty) {
      await invalidateTags(tags);
    }
  }

  /// Notifies watchers that a key's value has changed.
  ///
  /// The [isFromCache] parameter indicates whether the notification is for
  /// data that was already in the cache (true) or freshly fetched (false).
  /// This affects the metadata emitted to [watchWithMeta] streams.
  Future<void> _notify(String key, {bool isFromCache = true}) async {
    final controller = _controllers[key];
    final metaController = _metaControllers[key];

    if ((controller == null || controller.isClosed) &&
        (metaController == null || metaController.isClosed)) {
      return;
    }

    try {
      final cached = await store.read(key);
      if (cached != null) {
        if (controller != null && !controller.isClosed) {
          controller.add(cached.value);
        }
        if (metaController != null && !metaController.isClosed) {
          final meta = isFromCache
              ? CacheResultMeta.fromCache(
                  isStale: cached.meta.isExpired,
                  storedAt: cached.meta.storedAt,
                  version: cached.meta.version,
                )
              : CacheResultMeta.fresh(
                  version: cached.meta.version,
                  storedAt: cached.meta.storedAt,
                );
          metaController.add(CacheResult(value: cached.value, meta: meta));
        }
      }
    } catch (e, st) {
      // Notify observers about the store read error
      _notifyObservers((o) => o.onFetchError(key, e, st));
      // Propagate to stream listeners if controllers are still active
      if (controller != null && !controller.isClosed) {
        controller.addError(e, st);
      }
      if (metaController != null && !metaController.isClosed) {
        metaController.addError(e, st);
      }
    }
  }

  /// Notifies only value watchers (watch() streams) that a key's value changed.
  ///
  /// This is used by methods that handle meta notifications separately,
  /// like [_fetchAndStoreWithMeta] which returns metadata directly to callers.
  Future<void> _notifyValue(String key) async {
    final controller = _controllers[key];
    if (controller == null || controller.isClosed) {
      return;
    }

    try {
      final cached = await store.read(key);
      if (cached != null) {
        controller.add(cached.value);
      }
    } catch (e, st) {
      _notifyObservers((o) => o.onFetchError(key, e, st));
      if (!controller.isClosed) {
        controller.addError(e, st);
      }
    }
  }

  /// Notifies watchers that a key has been removed.
  void _notifyRemoval(String key) {
    final controller = _controllers[key];
    if (controller != null && !controller.isClosed) {
      controller.close();
      _controllers.remove(key);
    }
    final metaController = _metaControllers[key];
    if (metaController != null && !metaController.isClosed) {
      metaController.close();
      _metaControllers.remove(key);
    }
  }

  /// Executes caching logic based on the given [policy] using a [strategy].
  ///
  /// This unified method handles all policy variants,
  /// delegating fetch/wrap operations to the strategy.
  Future<R> _executePolicy<R>({
    required String key,
    required Policy policy,
    required _FetchStrategy<T, R> strategy,
    required Duration? ttl,
    required RetryConfig retry,
    required CancellationToken? cancel,
    required List<String>? tags,
  }) async {
    switch (policy) {
      case Policy.cacheOnly:
        final cached = await store.read(key);
        if (cached == null) {
          throw CacheMissException(key);
        }
        _notify(key, isFromCache: true);
        return strategy.wrapCached(cached, isStale: cached.meta.isExpired);

      case Policy.networkOnly:
        final result = await strategy.fetchAndStore(
          _fetchEngine,
          key,
          ttl,
          retry,
          cancel,
          tags,
        );
        _notify(key, isFromCache: false);
        return result;

      case Policy.refresh:
        if (network.isOnline) {
          final result = await strategy.fetchAndStore(
            _fetchEngine,
            key,
            ttl,
            retry,
            cancel,
            tags,
          );
          _notify(key, isFromCache: false);
          return result;
        }
        final cached = await store.read(key);
        if (cached == null) {
          throw CacheMissException(key);
        }
        _notify(key, isFromCache: true);
        return strategy.wrapCached(cached, isStale: cached.meta.isExpired);

      case Policy.offlineFirst:
        final cached = await store.read(key);
        if (cached != null && !cached.meta.isExpired) {
          _notifyObservers((o) => o.onCacheHit(key));
          _notify(key, isFromCache: true);
          return strategy.wrapCached(cached, isStale: false);
        }

        _notifyObservers((o) => o.onCacheMiss(key));

        if (network.isOnline) {
          try {
            final result = await strategy.fetchAndStore(
              _fetchEngine,
              key,
              ttl,
              retry,
              cancel,
              tags,
            );
            _notify(key, isFromCache: false);
            return result;
          } on CancelledException {
            rethrow;
          } catch (e) {
            if (strategy.isConvertibleToCacheMiss(e)) {
              throw CacheMissException(key);
            }
            if (cached != null) {
              _notify(key, isFromCache: true);
              return strategy.wrapCached(cached,
                  isStale: cached.meta.isExpired);
            }
            rethrow;
          }
        }

        if (cached != null) {
          _notify(key, isFromCache: true);
          return strategy.wrapCached(cached, isStale: cached.meta.isExpired);
        }

        throw CacheMissException(key);

      case Policy.staleWhileRefresh:
        return _executeStaleWhileRefresh(
          key: key,
          strategy: strategy,
          ttl: ttl,
          retry: retry,
          cancel: cancel,
          tags: tags,
          refreshOnlyIfExpired: true,
        );

      case Policy.cacheAndRefresh:
        return _executeStaleWhileRefresh(
          key: key,
          strategy: strategy,
          ttl: ttl,
          retry: retry,
          cancel: cancel,
          tags: tags,
          refreshOnlyIfExpired: false,
        );
    }
  }

  /// Shared logic for staleWhileRefresh and cacheAndRefresh policies.
  ///
  /// The only difference between these policies is [refreshOnlyIfExpired]:
  /// - staleWhileRefresh: only refreshes if cache is expired
  /// - cacheAndRefresh: always refreshes in background
  Future<R> _executeStaleWhileRefresh<R>({
    required String key,
    required _FetchStrategy<T, R> strategy,
    required Duration? ttl,
    required RetryConfig retry,
    required CancellationToken? cancel,
    required List<String>? tags,
    required bool refreshOnlyIfExpired,
  }) async {
    final cached = await store.read(key);

    if (cached != null) {
      _notifyObservers((o) => o.onCacheHit(key));

      final shouldRefresh =
          network.isOnline && (!refreshOnlyIfExpired || cached.meta.isExpired);

      if (shouldRefresh) {
        strategy
            .backgroundRefresh(_fetchEngine, key, ttl, retry, tags)
            .then((_) => _notify(key, isFromCache: false))
            .catchError((Object e, StackTrace st) {
          _notifyObservers((o) => o.onFetchError(key, e, st));
        });
      }

      _notify(key, isFromCache: true);
      return strategy.wrapCached(cached, isStale: cached.meta.isExpired);
    }

    _notifyObservers((o) => o.onCacheMiss(key));

    if (network.isOnline) {
      final result = await strategy.fetchAndStore(
        _fetchEngine,
        key,
        ttl,
        retry,
        cancel,
        tags,
      );
      _notify(key, isFromCache: false);
      return result;
    }

    throw CacheMissException(key);
  }
}

/// Internal class to track dependency watcher information.
class _DependencyWatcher<T> {
  /// The cache key being watched.
  final String key;

  /// The fetcher function for refetching.
  final Fetcher<T> fetch;

  /// The policy to use when refetching.
  final Policy policy;

  /// The TTL to use when refetching.
  final Duration? ttl;

  /// The keys this watcher depends on.
  final List<String> dependsOn;

  const _DependencyWatcher({
    required this.key,
    required this.fetch,
    required this.policy,
    required this.ttl,
    required this.dependsOn,
  });
}

/// Strategy for fetching and wrapping cache results.
abstract class _FetchStrategy<T, R> {
  /// Fetches fresh data and stores it, returning the wrapped result.
  Future<R> fetchAndStore(
    FetchEngine<T> engine,
    String key,
    Duration? ttl,
    RetryConfig retry,
    CancellationToken? cancel,
    List<String>? tags,
  );

  /// Wraps a cached value into the result type.
  R wrapCached(Stored<T> cached, {required bool isStale});

  /// Performs a background refresh (fire-and-forget).
  /// Returns a Future that completes when the refresh is done.
  Future<void> backgroundRefresh(
    FetchEngine<T> engine,
    String key,
    Duration? ttl,
    RetryConfig retry,
    List<String>? tags,
  );

  /// Additional error types to catch and convert to CacheMissException.
  /// Override in subclasses that need special error handling.
  bool isConvertibleToCacheMiss(Object error) => false;
}

/// Standard fetch strategy that returns T directly.
class _StandardFetchStrategy<T> extends _FetchStrategy<T, T> {
  final Fetcher<T> fetch;

  _StandardFetchStrategy(this.fetch);

  @override
  Future<T> fetchAndStore(
    FetchEngine<T> engine,
    String key,
    Duration? ttl,
    RetryConfig retry,
    CancellationToken? cancel,
    List<String>? tags,
  ) {
    return engine.fetchAndStore(key, fetch, ttl, retry, cancel, tags);
  }

  @override
  T wrapCached(Stored<T> cached, {required bool isStale}) => cached.value;

  @override
  Future<void> backgroundRefresh(
    FetchEngine<T> engine,
    String key,
    Duration? ttl,
    RetryConfig retry,
    List<String>? tags,
  ) {
    return engine.fetchAndStore(key, fetch, ttl, retry, null, tags);
  }
}

/// Fetch strategy that returns CacheResult<T> with metadata.
class _MetaFetchStrategy<T> extends _FetchStrategy<T, CacheResult<T>> {
  final Fetcher<T> fetch;
  final Store<T> store;
  final Future<void> Function(String key) notifyValue;

  _MetaFetchStrategy(this.fetch, this.store, this.notifyValue);

  @override
  Future<CacheResult<T>> fetchAndStore(
    FetchEngine<T> engine,
    String key,
    Duration? ttl,
    RetryConfig retry,
    CancellationToken? cancel,
    List<String>? tags,
  ) async {
    final value =
        await engine.fetchAndStore(key, fetch, ttl, retry, cancel, tags);
    final cached = await store.read(key);

    await notifyValue(key);

    return CacheResult(
      value: value,
      meta: CacheResultMeta.fresh(
        version: cached?.meta.version ?? 1,
        storedAt: cached?.meta.storedAt,
      ),
    );
  }

  @override
  CacheResult<T> wrapCached(Stored<T> cached, {required bool isStale}) {
    return CacheResult(
      value: cached.value,
      meta: CacheResultMeta.fromCache(
        isStale: isStale,
        storedAt: cached.meta.storedAt,
        version: cached.meta.version,
      ),
    );
  }

  @override
  Future<void> backgroundRefresh(
    FetchEngine<T> engine,
    String key,
    Duration? ttl,
    RetryConfig retry,
    List<String>? tags,
  ) {
    return engine.fetchAndStore(key, fetch, ttl, retry, null, tags);
  }
}

/// Conditional fetch strategy that supports HTTP 304.
class _ConditionalFetchStrategy<T> extends _FetchStrategy<T, T> {
  final ConditionalFetcher<T> fetch;

  _ConditionalFetchStrategy(this.fetch);

  @override
  Future<T> fetchAndStore(
    FetchEngine<T> engine,
    String key,
    Duration? ttl,
    RetryConfig retry,
    CancellationToken? cancel,
    List<String>? tags,
  ) {
    return engine.fetchAndStoreConditional(
        key, fetch, ttl, retry, cancel, tags);
  }

  @override
  T wrapCached(Stored<T> cached, {required bool isStale}) => cached.value;

  @override
  Future<void> backgroundRefresh(
    FetchEngine<T> engine,
    String key,
    Duration? ttl,
    RetryConfig retry,
    List<String>? tags,
  ) {
    return engine.fetchAndStoreConditional(key, fetch, ttl, retry, null, tags);
  }

  @override
  bool isConvertibleToCacheMiss(Object error) =>
      error is CacheMissForConditionalException;
}
