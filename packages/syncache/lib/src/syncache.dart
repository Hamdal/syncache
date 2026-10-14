import 'dart:async';

import 'package:syncache/src/exceptions.dart';
import 'cache_result.dart';
import 'cancellation.dart';
import 'conflict_resolver.dart';
import 'fetch_engine.dart';
import 'fetcher.dart';
import 'metadata.dart';
import 'mutation.dart';
import 'mutation_handle.dart';
import 'mutation_outbox.dart';
import 'mutation_queue.dart';
import 'network.dart';
import 'observer.dart';
import 'pending_mutation_info.dart';
import 'pending_mutation_record.dart';
import 'policy.dart';
import 'prefetch.dart';
import 'retry.dart';
import 'scoped_syncache.dart';
import 'stats_collector.dart';
import 'store.dart';
import 'stored.dart';
import 'syncache_entry.dart';
import 'syncache_stats.dart';

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

  /// Optional persistence backend for pending mutations.
  ///
  /// When non-null, every enqueued mutation is mirrored to it as a
  /// [PendingMutationRecord] and survives [dispose] — a freshly constructed
  /// [Syncache] over the same outbox can replay unsynced writes via
  /// [recoverPendingMutations], making offline writes survive process
  /// death. When null (the default) the queue is memory-only.
  final MutationOutbox? outbox;

  /// Decodes a persisted optimistic snapshot (see [mutate]) back into a
  /// `T` during [recoverPendingMutations].
  ///
  /// Provide this when mutations are enqueued with `optimisticSnapshot`:
  /// replay then sends the exact pre-death value instead of re-deriving
  /// `apply(currentCached)` — which can double-apply base-dependent
  /// mutations (increments, appends) after a crash. If a record carries a
  /// snapshot but no codec is configured, recovery reports the record via
  /// `SyncacheObserver.onOutboxReplayFailed` rather than silently falling
  /// back.
  final T Function(Object? snapshot)? decodeOptimisticSnapshot;

  /// How often a periodic expired-entry sweep runs, or `null` (the default)
  /// for manual-only cleanup via [cleanup].
  ///
  /// Expired entries otherwise linger until their key is next read or an
  /// explicit [cleanup] call — with this set, they are collected
  /// periodically even when never read again. The timer is cancelled in
  /// [dispose].
  final Duration? cleanupInterval;

  /// Cache-wide default [ConflictResolver], consulted when a mutation's
  /// `send` throws a [SyncacheConflictException] (typically HTTP 409) and
  /// the call did not pass its own resolver via `mutate(conflictResolver:)`.
  ///
  /// Conflicts are never retried: the resolver decides the final value and
  /// the mutation settles with a [MutationResolved] outcome. When this is
  /// null and no per-call resolver is given, a conflict fails terminally
  /// instead.
  final ConflictResolver<T>? conflictResolver;

  /// Opportunistic cleanup frequency: run a sweep at most once every N
  /// writes, or `null` (the default) to disable opportunistic sweeping.
  ///
  /// This is a cheap heuristic for apps that write steadily but never want
  /// to think about expiry: every Nth write triggers a [cleanup] pass,
  /// making the amortized cost constant. Writes are counted across fetches,
  /// [set], and [mutate].
  final int? opportunisticCleanupEvery;

  late final FetchEngine<T> _fetchEngine;
  late final MutationQueue<T> _mutationQueue;

  /// Observers attached after construction via [addObserver], dispatched
  /// through the same path as the constructor-provided [observers]. Kept
  /// separate so the public [observers] list stays exactly what the caller
  /// passed in.
  final List<SyncacheObserver> _dynamicObservers = <SyncacheObserver>[];

  /// Internal stats accumulator. Dispatched through [_notifyObservers] like
  /// a regular observer but never exposed in the [observers] list.
  final StatsCollector _statsCollector = StatsCollector();

  /// Periodic cleanup timer, created when [cleanupInterval] is set and
  /// cancelled in [dispose].
  Timer? _cleanupTimer;

  /// Writes observed since the last opportunistic sweep.
  int _writesSinceSweep = 0;

  /// Re-entrancy guard so overlapping sweeps (timer + opportunistic +
  /// manual) coalesce into the first one running.
  bool _isSweeping = false;

  final Map<String, StreamController<T>> _controllers = {};
  final Map<String, StreamController<CacheResult<T>>> _metaControllers = {};
  bool _isDisposed = false;

  /// Key: dependency key, Value: set of keys that depend on it.
  final Map<String, Set<String>> _dependents = {};

  /// Active value-watch registrations (`watch` / `watchWithDependencies`),
  /// keyed by cache key. Records the parameters each watcher was created
  /// with so its entry can be refetched with those same parameters.
  final Map<String, _WatchRegistration<T>> _watchers = {};

  /// Active metadata-watch registrations (`watchWithMeta`), keyed by cache
  /// key.
  final Map<String, _WatchRegistration<T>> _metaWatchers = {};

  /// Subscription to a [ReactiveNetwork]'s connectivity changes, used to
  /// flush pending mutations when the device comes back online. Null when
  /// the provided [network] is not a [ReactiveNetwork].
  StreamSubscription<bool>? _connectivitySubscription;

  /// Creates a [Syncache] instance with the given [store] and optional [network].
  ///
  /// If [network] is not provided, [AlwaysOnline] is used, meaning the cache
  /// will always attempt network requests when needed.
  ///
  /// If [network] is a [ReactiveNetwork], the cache subscribes to its
  /// connectivity changes and automatically flushes pending mutations when
  /// the device comes back online — no new `mutate()` call required.
  ///
  /// Provide [observers] to monitor cache operations for logging or analytics.
  ///
  /// Set [defaultRetry] to enable automatic retries for all [get] operations.
  /// By default, retries are disabled.
  ///
  /// Set [mutationRetry] to configure retry behavior for mutation sync operations.
  /// By default, mutations are retried up to 3 times with exponential backoff.
  ///
  /// Provide [outbox] to make offline writes durable: mutations are mirrored
  /// to it and can be replayed after a process restart via
  /// [recoverPendingMutations]. Without an outbox the mutation queue is
  /// memory-only and unsynced writes are lost when the process dies.
  ///
  /// Set [cleanupInterval] to sweep expired entries periodically, and/or
  /// [opportunisticCleanupEvery] to sweep at most once per N writes. Both
  /// default to `null` — expired entries are then only removed when their
  /// key is next read or [cleanup] is called manually.
  ///
  /// Pass a store implementing [BoundedStore] (e.g. `MemoryStore(maxLength:)`)
  /// to bound memory: evictions surface as `SyncacheObserver.onEvict`.
  ///
  /// Provide [conflictResolver] to decide the final value when a mutation's
  /// `send` throws [SyncacheConflictException] (e.g. an HTTP 409): the
  /// resolver's value is stored, the handle settles with [MutationResolved],
  /// and the mutation is not retried. Individual `mutate` calls can override
  /// it with their own resolver.
  ///
  /// Example:
  /// ```dart
  /// final cache = Syncache<User>(
  ///   store: MemoryStore<User>(),
  ///   network: MyConnectivityNetwork(), // Optional
  ///   observers: [LoggingObserver()],   // Optional
  ///   defaultRetry: RetryConfig(maxAttempts: 3), // Optional
  ///   mutationRetry: MutationRetryConfig(maxAttempts: 5), // Optional
  ///   conflictResolver: serverWins<User>(), // Optional
  ///   cleanupInterval: Duration(minutes: 10), // Optional
  /// );
  /// ```
  Syncache({
    required this.store,
    Network? network,
    List<SyncacheObserver>? observers,
    RetryConfig? defaultRetry,
    MutationRetryConfig? mutationRetry,
    MutationOutbox? outbox,
    this.decodeOptimisticSnapshot,
    this.cleanupInterval,
    this.opportunisticCleanupEvery,
    this.conflictResolver,
  })  : network = network ?? const AlwaysOnline(),
        observers = observers ?? const [],
        defaultRetry = defaultRetry ?? RetryConfig.none,
        mutationRetry = mutationRetry ?? const MutationRetryConfig(),
        outbox = outbox {
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
      outbox: outbox,
      decodeOptimisticSnapshot: decodeOptimisticSnapshot,
      conflictResolver: conflictResolver,
    );

    // Wire eviction events from bounded stores into the observer path so
    // user observers and the stats collector both see them.
    if (store is BoundedStore<T>) {
      (store as BoundedStore<T>).onEvict = (key) {
        _notifyObservers((o) => o.onEvict(key));
      };
    }

    // Periodic expired-entry collection.
    if (cleanupInterval != null) {
      _cleanupTimer = Timer.periodic(cleanupInterval!, (_) {
        unawaited(_sweep());
      });
    }

    // Automatic mutation flush on reconnect: only possible when the
    // network reports connectivity changes.
    if (this.network is ReactiveNetwork) {
      _connectivitySubscription = (this.network as ReactiveNetwork)
          .onConnectivityChanged
          .listen((online) {
        if (online && !_isDisposed) {
          unawaited(_mutationQueue.processQueue());
        }
      });
    }
  }

  /// Notifies all observers — user-provided ones plus the internal stats
  /// collector — catching errors to prevent observer failures from breaking
  /// cache operations.
  void _notifyObservers(void Function(SyncacheObserver observer) callback) {
    try {
      callback(_statsCollector);
    } catch (_) {}
    for (final observer in observers) {
      try {
        callback(observer);
      } catch (_) {}
    }
    // Dynamic observers ([addObserver]). Index-bounded so an observer that
    // removes itself or a peer from within a callback cannot corrupt the
    // loop; observers added mid-notification receive the *next* event.
    final dynamicCount = _dynamicObservers.length;
    for (var i = 0; i < dynamicCount; i++) {
      if (i >= _dynamicObservers.length) break;
      try {
        callback(_dynamicObservers[i]);
      } catch (_) {}
    }
  }

  /// Registers [observer] for all cache events, in addition to any observers
  /// passed to the constructor. Unlike the constructor list, observers can
  /// be attached and detached at any time — used by helpers that observe a
  /// cache they were given (e.g. `PaginatedCache`).
  ///
  /// Avoid adding or removing observers from within an observer callback;
  /// additions take effect from the next event onwards, and removals of the
  /// calling observer itself are safe.
  void addObserver(SyncacheObserver observer) {
    _dynamicObservers.add(observer);
  }

  /// Unregisters an observer previously attached via [addObserver].
  /// Silently does nothing if it is not registered.
  void removeObserver(SyncacheObserver observer) {
    _dynamicObservers.remove(observer);
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
      skipNotify: true, // Meta strategy handles its own notifications
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
    _recordWrite();
    await _notify(key, isFromCache: false);

    // Trigger refetch for dependent watchers
    await _notifyDependents(key);
  }

  // ============================================================
  // Typed Entries
  // ============================================================

  /// Creates a typed [SyncacheEntry] bound to [key], [fetch] and the given
  /// default cache parameters.
  ///
  /// An entry is a lightweight, stateless view of one cache key: it
  /// removes the repeated string-key + fetch-closure ergonomics by binding
  /// them once. Every entry method delegates to the corresponding
  /// [Syncache] operation with the bound defaults, so behavior (policies,
  /// invalidation semantics, stream lifecycles) is identical to calling
  /// the cache directly.
  ///
  /// ```dart
  /// final entry = cache.entry(
  ///   'user:123',
  ///   fetch: (req) => api.getUser(123),
  ///   ttl: const Duration(minutes: 5),
  /// );
  ///
  /// final user = await entry.get();
  /// await entry.refresh();
  /// await entry.invalidate();
  /// ```
  ///
  /// Entries hold no stream controllers or other resources: create as many
  /// as you like, store them anywhere, and never dispose them. See
  /// [SyncacheEntry] for the full contract.
  SyncacheEntry<T> entry(
    String key, {
    required Fetcher<T> fetch,
    Policy policy = Policy.offlineFirst,
    Duration? ttl,
    List<String>? tags,
  }) {
    _checkNotDisposed();
    return SyncacheEntry.of(
      this,
      key: key,
      fetch: fetch,
      policy: policy,
      ttl: ttl,
      tags: tags,
    );
  }

  /// Notifies dependent watchers to refetch when a dependency changes.
  Future<void> _notifyDependents(String key) async {
    final dependentKeys = _dependents[key];
    if (dependentKeys == null || dependentKeys.isEmpty) {
      return;
    }

    for (final dependentKey in dependentKeys.toList()) {
      final watcher = _watchers[dependentKey];
      if (watcher == null) continue;

      final controller = _controllers[dependentKey];
      if (controller == null || controller.isClosed) {
        _removeValueWatcher(dependentKey);
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

  /// Removes a value-watch registration and cleans up its dependency edges.
  void _removeValueWatcher(String key) {
    final watcher = _watchers.remove(key);
    if (watcher == null) return;

    _removeDependentEdges(key, watcher.dependsOn);
  }

  /// Removes the dependent edges [key] contributes for each of [dependsOn].
  void _removeDependentEdges(String key, List<String> dependsOn) {
    for (final dep in dependsOn) {
      _dependents[dep]?.remove(key);
      if (_dependents[dep]?.isEmpty ?? false) {
        _dependents.remove(dep);
      }
    }
  }

  /// Records a watch registration in [registry] for [key], replacing any
  /// previous registration and re-wiring its dependency edges.
  void _registerWatcher(
    Map<String, _WatchRegistration<T>> registry,
    String key, {
    required Fetcher<T> fetch,
    required Policy policy,
    required Duration? ttl,
    List<String> dependsOn = const [],
  }) {
    final existing = registry[key];
    if (existing != null) {
      _removeDependentEdges(key, existing.dependsOn);
    }

    registry[key] = _WatchRegistration<T>(
      key: key,
      fetch: fetch,
      policy: policy,
      ttl: ttl,
      dependsOn: dependsOn,
    );

    for (final dep in dependsOn) {
      _dependents.putIfAbsent(dep, () => {}).add(key);
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
  /// ## Invalidation semantics
  ///
  /// Invalidation ([invalidate], [invalidateTag], [invalidatePattern],
  /// [clear]) does **not** close this stream. Instead the watcher is
  /// refetched with the fetch/policy/ttl it was created with:
  ///
  /// - Refetch success → the fresh value is emitted.
  /// - Refetch failure → the error is emitted and the stream remains
  ///   usable.
  /// - [Policy.cacheOnly] watchers receive a [CacheMissException] (their
  ///   entry was deleted) as a stream error, without closing.
  ///
  /// Listeners keep receiving the last value until the refetch completes
  /// (stale-while-invalidated). The stream only completes
  /// (`ConnectionState.done`) when every listener unsubscribes or the
  /// cache is disposed.
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
          _removeValueWatcher(key);
        },
      ),
    );

    _registerWatcher(_watchers, key, fetch: fetch, policy: policy, ttl: ttl);

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
  /// Like [watch], invalidation refetches this stream instead of closing
  /// it: listeners keep the last [CacheResult] until the refetch emits.
  /// See [watch] for the full contract.
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
          _metaWatchers.remove(key);
        },
      ),
    );

    _registerWatcher(_metaWatchers, key,
        fetch: fetch, policy: policy, ttl: ttl);

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
  /// Like [watch], invalidation of this key refetches the stream instead
  /// of closing it. See [watch] for the full contract.
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

    final controller = _controllers.putIfAbsent(
      key,
      () => StreamController<T>.broadcast(
        onCancel: () {
          _controllers[key]?.close();
          _controllers.remove(key);
          _removeValueWatcher(key);
        },
      ),
    );

    _registerWatcher(
      _watchers,
      key,
      fetch: fetch,
      policy: policy,
      ttl: ttl,
      dependsOn: refetchWhen,
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
  /// The mutation's `apply` function is called immediately to
  /// update the local cache, providing instant feedback. The
  /// [Mutation.send] function is then queued for background sync to
  /// persist the change.
  ///
  /// If `send` succeeds, the server's response replaces the optimistic value.
  /// If `send` fails, the mutation remains queued and will retry when online.
  ///
  /// Watchers of the [key] are notified of both the optimistic update
  /// and the eventual server confirmation.
  ///
  /// Returns a [MutationHandle] for awaiting *this* mutation's server
  /// confirmation. The returned future completes as soon as the optimistic
  /// value is applied — it does not wait for the server. Use the handle to
  /// await the outcome:
  ///
  /// ```dart
  /// final handle = await cache.mutate(
  ///   key: 'user:123',
  ///   mutation: Mutation<User>(
  ///     apply: (user) => user.copyWith(name: 'New Name'),
  ///     send: (user) => api.updateUser(user),
  ///   ),
  /// );
  ///
  /// switch (await handle.outcome) {
  ///   case MutationSuccess(:final serverValue):
  ///     print('Server confirmed: $serverValue');
  ///   case MutationFailure(:final error, :final retried):
  ///     print('Failed after $retried retries: $error');
  ///   case MutationDiscarded():
  ///     print('Removed before syncing');
  /// }
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
  /// If [payload] is provided, the mutation is persisted to the configured
  /// [outbox] as a [PendingMutationRecord] so it can survive process death
  /// and be replayed with [recoverPendingMutations]. The payload is opaque
  /// to Syncache — make it JSON-safe and self-describing (e.g.
  /// `{'op': 'updateName', 'userId': 123, 'name': 'X'}`) so your recovery
  /// resolver can rebuild the [Mutation]. **Throws [StateError]** if a
  /// payload is given but no outbox is configured: the payload would never
  /// be persisted, silently breaking the durability the caller asked for.
  ///
  /// If [optimisticSnapshot] is provided, the *optimistic value* (the value
  /// `mutation.apply` just produced) is persisted alongside the payload as
  /// a JSON-safe snapshot. At recovery, with `decodeOptimisticSnapshot`
  /// configured on the cache, replay sends the exact pre-death value.
  /// Without a snapshot, replay falls back to re-deriving
  /// `apply(currentCached)` — which double-applies base-dependent mutations
  /// (increments, appends) when the cache retained the optimistic state, so
  /// prefer passing a snapshot (e.g. `optimisticSnapshot: user.toJson()`).
  ///
  /// ```dart
  /// final handle = await cache.mutate(
  ///   key: 'user:123',
  ///   mutation: Mutation<User>(...),
  ///   payload: {'op': 'updateName', 'userId': 123, 'name': 'X'},
  ///   optimisticSnapshot: user.toJson(),
  /// );
  /// final outcome = await handle.outcome;
  /// ```
  ///
  /// If [conflictResolver] is provided, it handles this mutation only: when
  /// `send` throws [SyncacheConflictException] (typically HTTP 409 with the
  /// server's current state), the resolver decides the final value, the
  /// cache is updated with it, and the handle settles with a
  /// [MutationResolved] outcome — the mutation is never retried and its
  /// outbox record is removed. Without a per-call resolver the cache-wide
  /// `Syncache(conflictResolver:)` default applies; when neither exists the
  /// conflict fails terminally (still without retrying). The per-call
  /// resolver is not persisted with the payload — after a process restart
  /// replayed mutations use the cache-wide default.
  ///
  /// Throws [CacheMissException] if no cached value exists for [key].
  Future<MutationHandle<T>> mutate({
    required String key,
    required Mutation<T> mutation,
    List<String>? invalidates,
    List<String>? invalidateTags,
    Map<String, Object?>? payload,
    Object? optimisticSnapshot,
    ConflictResolver<T>? conflictResolver,
  }) async {
    _checkNotDisposed();
    if ((payload != null || optimisticSnapshot != null) && outbox == null) {
      throw StateError(
        'mutate(payload: ... / optimisticSnapshot: ...) was called but no '
        'MutationOutbox is configured. Pass an outbox to the Syncache '
        'constructor — without one the data could never be persisted and '
        'the mutation would be lost on process death.',
      );
    }
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
    _recordWrite();
    unawaited(_notify(key, isFromCache: false));

    unawaited(_notifyDependents(key));

    final pending = PendingMutation(
      key: key,
      mutation: mutation,
      optimisticValue: optimisticValue,
      invalidates: invalidates,
      invalidateTags: invalidateTags,
      payload: payload,
      optimisticSnapshot: optimisticSnapshot,
      conflictResolver: conflictResolver,
    );
    await _mutationQueue.add(pending);
    return pending.handle;
  }

  /// Replays persisted outbox records as live pending mutations.
  ///
  /// Call this once at startup — after constructing [Syncache] with an
  /// [outbox] and before widgets/UI start fetching — to restore writes that
  /// were queued when the process last died. For each persisted
  /// [PendingMutationRecord], [resolve] rebuilds the live [Mutation] from
  /// the payload the app supplied to [mutate]:
  ///
  /// ```dart
  /// final restored = await cache.recoverPendingMutations((record) async {
  ///   switch (record.payload['op']) {
  ///     case 'updateName':
  ///       return Mutation<User>(
  ///         apply: (u) => u.copyWith(name: record.payload['name'] as String),
  ///         send: (_) => api.updateName(
  ///           record.payload['userId'] as int,
  ///           record.payload['name'] as String,
  ///         ),
  ///       );
  ///     default:
  ///       throw UnimplementedError('unknown op ${record.payload['op']}');
  ///   }
  /// });
  /// ```
  ///
  /// Recovery preserves enqueue order (records are ordered by their `seq`)
  /// and does **not** re-apply the optimistic update to the store — the
  /// optimistic value was already written before the process died.
  ///
  /// The value sent to the server comes from each record's
  /// `optimisticSnapshot` (decoded via the cache's `decodeOptimisticSnapshot`
  /// codec), reproducing the exact pre-death value. Records stored without a
  /// snapshot fall back to re-deriving `apply(currentCached)`; see
  /// [mutate] for why snapshots matter and how to provide them.
  ///
  /// Records whose resolver throws (or whose cache entry has disappeared)
  /// are reported to observers via `SyncacheObserver.onOutboxReplayFailed`
  /// and left in the outbox — never dropped silently.
  ///
  /// If the network is online, the recovered mutations are flushed
  /// immediately. Returns the number of mutations re-enqueued (0 when no
  /// outbox is configured or the outbox is empty).
  ///
  /// Because replay can double-apply non-idempotent operations, server
  /// endpoints should be idempotent; put a client-generated operation id in
  /// the payload for deduplication.
  Future<int> recoverPendingMutations(
    Future<Mutation<T>> Function(PendingMutationRecord record) resolve,
  ) async {
    _checkNotDisposed();
    return _mutationQueue.recover(resolve);
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
  ///
  /// The mutation currently syncing (if any) is allowed to finish, but no
  /// further mutations are processed. Removed mutations' handles settle
  /// with [MutationDiscarded].
  void clearPendingMutations() {
    _checkNotDisposed();
    _mutationQueue.clear();
  }

  /// Removes the pending mutation with the given [id] from the sync queue.
  ///
  /// Returns `true` if a mutation with that id was found and removed, in
  /// which case its handle settles with [MutationDiscarded]. The id is the
  /// `PendingMutationInfo.id` exposed by [pendingMutationsSnapshot] and
  /// [pendingMutationsStream].
  ///
  /// If the removed mutation was currently syncing, its request may still
  /// reach the server — Syncache just stops tracking it.
  bool removePendingMutation(String id) {
    _checkNotDisposed();
    return _mutationQueue.removeById(id);
  }

  /// Removes the first pending mutation from the sync queue.
  @Deprecated('Use removePendingMutation to remove a specific mutation')
  bool removeFirstPendingMutation() {
    _checkNotDisposed();
    return _mutationQueue.removeFirst();
  }

  /// Processes pending mutations now, without waiting for the next
  /// `mutate()` call or a reconnect event.
  ///
  /// Mutations are normally processed automatically: immediately after
  /// [mutate] when online, and when a [ReactiveNetwork] reports that the
  /// device is back online. Call this to force a pass manually — e.g. after
  /// login restores auth, or from a "Retry now" button in a sync banner.
  ///
  /// Safe to call repeatedly: while a processing pass is running (or the
  /// network is offline) additional calls return immediately.
  Future<void> processPendingMutations() async {
    _checkNotDisposed();
    await _mutationQueue.processQueue();
  }

  // ============================================================
  // Cache Lifecycle (cleanup & statistics)
  // ============================================================

  /// Removes every expired entry from the store and returns the count.
  ///
  /// Entries whose TTL has passed normally linger until their key is next
  /// read; [cleanup] collects them all in one pass. It requires the store
  /// to implement `IterableStore` (both [MemoryStore] and `HiveStore` do);
  /// with a store that can't enumerate keys this returns 0.
  ///
  /// Active watchers of swept keys are refetched exactly like
  /// [invalidate] does: their streams stay open and receive the fresh
  /// value (or the refetch error) when it arrives.
  ///
  /// Sweeping can also happen automatically — via the [cleanupInterval]
  /// periodic timer or the [opportunisticCleanupEvery] heuristic — and
  /// overlapping sweeps are coalesced.
  ///
  /// ```dart
  /// final removed = await cache.cleanup();
  /// print('collected $removed expired entries');
  /// ```
  Future<int> cleanup() async {
    _checkNotDisposed();
    return _sweep();
  }

  /// Shared sweep implementation: deletes expired entries, notifies
  /// observers, refetches watchers of swept keys, and returns the count.
  /// Coalesces concurrent sweeps behind [_isSweeping].
  Future<int> _sweep() async {
    if (_isDisposed || _isSweeping) return 0;
    if (store is! IterableStore<T>) return 0;

    _isSweeping = true;
    try {
      final iterableStore = store as IterableStore<T>;
      final keys = await iterableStore.keys();
      final swept = <String>[];
      for (final key in keys) {
        try {
          final entry = await store.read(key);
          if (entry != null && entry.meta.isExpired) {
            await store.delete(key);
            swept.add(key);
          }
        } catch (_) {
          // Unreadable/corrupted entry: skip it. Store-level corruption
          // handling (e.g. HiveStore.read) may already have removed it.
        }
      }

      for (final key in swept) {
        _notifyObservers((o) => o.onInvalidate(key));
      }
      await _refetchWatchers(swept);
      return swept.length;
    } finally {
      _isSweeping = false;
    }
  }

  /// Counts a write and, when [opportunisticCleanupEvery] is configured,
  /// triggers an opportunistic expired-entry sweep at most once per N
  /// writes.
  void _recordWrite() {
    final every = opportunisticCleanupEvery;
    if (every == null || every <= 0) return;
    _writesSinceSweep++;
    if (_writesSinceSweep >= every && !_isSweeping) {
      _writesSinceSweep = 0;
      unawaited(_sweep());
    }
  }

  /// Returns an immutable snapshot of the cache's health counters.
  ///
  /// Counters cover cache hits/misses, fetches started/succeeded/failed/
  /// retried/cancelled, stores, invalidations, evictions, and the live
  /// pending-mutation count. `entryCount` is the approximate store size, or
  /// `null` when the store cannot enumerate keys.
  ///
  /// The getter is async because resolving [SyncacheStats.entryCount] may
  /// require asking the store. Counters only — no per-key bookkeeping — so
  /// snapshotting is O(entryCount) at worst (for the key enumeration) and
  /// stats memory is constant.
  ///
  /// ```dart
  /// final stats = await cache.stats;
  /// final totalReads = stats.hits + stats.misses;
  /// if (totalReads > 0) {
  ///   print('hit rate: ${(stats.hits / totalReads)}');
  /// }
  /// ```
  Future<SyncacheStats> get stats async {
    _checkNotDisposed();
    int? entryCount;
    if (store is IterableStore<T>) {
      try {
        entryCount = (await (store as IterableStore<T>).keys()).length;
      } catch (_) {
        entryCount = null;
      }
    }
    return _statsCollector.snapshot(
      pendingMutations: _mutationQueue.count,
      entryCount: entryCount,
    );
  }

  /// Resets stats counters.
  ///
  /// Pass a subset of [SyncacheCounter] to reset individual counters —
  /// e.g. `resetStats({SyncacheCounter.hits, SyncacheCounter.misses})` to
  /// start a fresh hit-rate measurement window — or call with no arguments
  /// to reset everything. [SyncacheStats.pendingMutations] is live state,
  /// not an accumulator, so it is never reset.
  void resetStats([Set<SyncacheCounter>? counters]) {
    _checkNotDisposed();
    _statsCollector.reset(counters);
  }

  // ============================================================
  // Debug & Introspection
  // ============================================================

  /// Builds a JSON-safe snapshot of the cache's live internal state for
  /// debugging and diagnostics.
  ///
  /// The returned map contains:
  /// - `watchers`: every registered watch stream (value and meta), with its
  ///   key, the policy it will be refetched with, and its TTL.
  /// - `inFlightFetches`: keys with a deduplicated fetch currently running.
  /// - `pendingMutations`: the offline mutation queue — id, key, status,
  ///   retry count, last error (stringified), and enqueue time.
  /// - `stats`: the [SyncacheStats] counters (see [stats]).
  /// - `store`: the approximate entry count and up to [sampleKeyLimit]
  ///   sample keys, or `null` when the store cannot enumerate keys.
  ///
  /// Every value is a JSON primitive, list, or map, so the result can be
  /// logged directly or piped through `jsonEncode` — or use [SyncacheDebug]
  /// for a ready-made facade. This is a diagnostic aid: the shape is not a
  /// stable API contract and may grow over time.
  Future<Map<String, Object?>> debugSnapshot({int sampleKeyLimit = 20}) async {
    _checkNotDisposed();

    final watchers = <Map<String, Object?>>[
      for (final registration in _watchers.values)
        {
          'key': registration.key,
          'kind': 'value',
          'policy': registration.policy.name,
          'ttlMs': registration.ttl?.inMilliseconds,
        },
      for (final registration in _metaWatchers.values)
        {
          'key': registration.key,
          'kind': 'meta',
          'policy': registration.policy.name,
          'ttlMs': registration.ttl?.inMilliseconds,
        },
    ];

    final pendingMutations = <Map<String, Object?>>[
      for (final info in _mutationQueue.snapshot)
        {
          'id': info.id,
          'key': info.key,
          'status': info.status.name,
          'retryCount': info.retryCount,
          'queuedAt': info.queuedAt.toIso8601String(),
          'lastAttemptAt': info.lastAttemptAt?.toIso8601String(),
          'lastError': info.lastError?.toString(),
        },
    ];

    Map<String, Object?>? storeInfo;
    if (store is IterableStore<T>) {
      try {
        final keys = await (store as IterableStore<T>).keys();
        storeInfo = {
          'entryCount': keys.length,
          'sampleKeys': keys.take(sampleKeyLimit).toList(growable: false),
        };
      } catch (_) {
        storeInfo = null;
      }
    }

    return {
      'watchers': watchers,
      'inFlightFetches': _fetchEngine.inFlightKeys,
      'pendingMutations': pendingMutations,
      'stats': (await stats).toDebugJson(),
      'store': storeInfo,
    };
  }

  // ============================================================
  // Invalidation
  // ============================================================

  /// Invalidates (deletes) the cached entry for the given [key].
  ///
  /// Active watchers of the key stay open: each is refetched using its own
  /// fetch/policy/ttl and receives the fresh value when the refetch
  /// completes. Until then listeners keep seeing the last value
  /// (stale-while-invalidated).
  ///
  /// If the refetch fails, the error is emitted on the stream and the
  /// stream remains usable — invalidate again (or restore connectivity) to
  /// retry. [Policy.cacheOnly] watchers cannot recover from a deleted
  /// entry and receive a [CacheMissException] as a stream error, also
  /// without closing the stream.
  ///
  /// The stream only completes (ConnectionState.done) when the watcher is
  /// unsubscribed or the cache is disposed.
  ///
  /// Example:
  /// ```dart
  /// await cache.invalidate('user:123');
  /// ```
  Future<void> invalidate(String key) async {
    _checkNotDisposed();
    await store.delete(key);
    _notifyObservers((o) => o.onInvalidate(key));
    await _refetchWatchers([key]);
  }

  /// Invalidates all cache entries with the specified [tag].
  ///
  /// Requires the store to implement [TaggableStore].
  /// If the store doesn't support tagging, this method does nothing.
  ///
  /// Active watchers of affected entries stay open and are refetched (see
  /// [invalidate] for the exact stream semantics).
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
    }
    await _refetchWatchers(keys);
  }

  /// Invalidates all cache entries that have any of the specified [tags].
  ///
  /// If [matchAll] is true, only entries with ALL tags are invalidated.
  /// Requires [TaggableStore]. Active watchers of affected entries stay
  /// open and are refetched (see [invalidate]).
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
    }
    await _refetchWatchers(keysToNotify);
  }

  /// Invalidates all cache entries whose keys match the given glob [pattern].
  ///
  /// Requires the store to implement [TaggableStore].
  /// If the store doesn't support pattern matching, this method does nothing.
  ///
  /// Active watchers of affected entries stay open and are refetched (see
  /// [invalidate] for the exact stream semantics).
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
  Future<void> invalidatePattern(String pattern) {
    return _invalidatePattern(pattern, refetchWatchers: true);
  }

  /// Shared pattern-invalidation implementation. [refetchWatchers] is false
  /// for scope clears that opt out of refetching (see [clearScope]).
  Future<void> _invalidatePattern(
    String pattern, {
    required bool refetchWatchers,
  }) async {
    _checkNotDisposed();
    if (store is! TaggableStore<T>) return;

    final taggableStore = store as TaggableStore<T>;
    final keys = await taggableStore.getKeysByPattern(pattern);
    await taggableStore.deleteByPattern(pattern);

    for (final key in keys) {
      _notifyObservers((o) => o.onInvalidate(key));
    }
    if (refetchWatchers) {
      await _refetchWatchers(keys);
    }
  }

  /// Clears all cached entries.
  ///
  /// By default every active watcher is refetched afterwards, exactly like
  /// [invalidate] does per key (streams stay open, listeners keep the last
  /// value until the refetch completes). Pass `refetchWatchers: false` for
  /// bulk wipes and tests where refetching everything is undesired: the
  /// streams then stay open and silent instead.
  ///
  /// ```dart
  /// // Logout: wipe everything and let watchers reload
  /// await cache.clear();
  ///
  /// // Bulk wipe without triggering a refill storm
  /// await cache.clear(refetchWatchers: false);
  /// ```
  Future<void> clear({bool refetchWatchers = true}) async {
    _checkNotDisposed();
    await store.clear();
    _notifyObservers((o) => o.onClear());
    if (!refetchWatchers) return;

    final allKeys = {..._controllers.keys, ..._metaControllers.keys};
    await _refetchWatchers(allKeys);
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
  /// By default, active watchers of affected entries are refetched and
  /// their streams stay open — the same semantics as [clear]. Pass
  /// `refetchWatchers: false` to wipe silently without refetching.
  ///
  /// Requires [TaggableStore] for pattern matching.
  Future<void> clearScope(String scope, {bool refetchWatchers = true}) {
    return _invalidatePattern('$scope:*', refetchWatchers: refetchWatchers);
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

    _cleanupTimer?.cancel();
    _cleanupTimer = null;

    unawaited(_connectivitySubscription?.cancel());
    _connectivitySubscription = null;

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

    // Clear watch registrations and dependency tracking
    _watchers.clear();
    _metaWatchers.clear();
    _dependents.clear();

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
    _recordWrite();
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

  /// Refetches every active watcher of the given [keys] after their entries
  /// were invalidated.
  ///
  /// Each watcher is refetched with its own fetch/policy/ttl. Successful
  /// refetches are emitted through the regular notification path; failures
  /// are emitted as stream errors while keeping every stream open.
  Future<void> _refetchWatchers(Iterable<String> keys) async {
    for (final key in keys) {
      final valueRegistration = _watchers[key];
      if (valueRegistration != null) {
        await _refetchValueWatcher(valueRegistration);
      }

      final metaRegistration = _metaWatchers[key];
      if (metaRegistration != null) {
        await _refetchMetaWatcher(metaRegistration);
      }
    }
  }

  /// Refetches a single value watcher after invalidation.
  ///
  /// The stream stays open in all cases: the refetched value is emitted on
  /// success, the error on failure. A [Policy.cacheOnly] watcher therefore
  /// receives a [CacheMissException] (its entry was just deleted and it
  /// never goes to the network) without closing.
  Future<void> _refetchValueWatcher(_WatchRegistration<T> registration) async {
    final controller = _controllers[registration.key];
    if (controller == null || controller.isClosed) return;

    try {
      await get(
        key: registration.key,
        fetch: registration.fetch,
        policy: registration.policy,
        ttl: registration.ttl,
      );
    } catch (error) {
      if (!controller.isClosed) {
        controller.addError(error);
      }
    }
  }

  /// Refetches a single metadata watcher after invalidation.
  ///
  /// Mirrors [_refetchValueWatcher] but emits a full [CacheResult].
  Future<void> _refetchMetaWatcher(_WatchRegistration<T> registration) async {
    final controller = _metaControllers[registration.key];
    if (controller == null || controller.isClosed) return;

    try {
      final result = await getWithMeta(
        key: registration.key,
        fetch: registration.fetch,
        policy: registration.policy,
        ttl: registration.ttl,
      );
      if (!controller.isClosed) {
        controller.add(result);
      }
    } catch (error) {
      if (!controller.isClosed) {
        controller.addError(error);
      }
    }
  }

  /// Executes caching logic based on the given [policy] using a [strategy].
  ///
  /// This unified method handles all policy variants,
  /// delegating fetch/wrap operations to the strategy.
  ///
  /// When [skipNotify] is true, the method will not call [_notify] after
  /// cache hits or fetches. This is used by [getWithMeta] since the meta
  /// strategy handles value notifications internally via [_notifyValue],
  /// and [watchWithMeta] handles meta notifications via manual emission.
  Future<R> _executePolicy<R>({
    required String key,
    required Policy policy,
    required _FetchStrategy<T, R> strategy,
    required Duration? ttl,
    required RetryConfig retry,
    required CancellationToken? cancel,
    required List<String>? tags,
    bool skipNotify = false,
  }) async {
    switch (policy) {
      case Policy.cacheOnly:
        final cached = await store.read(key);
        if (cached == null) {
          throw CacheMissException(key);
        }
        if (!skipNotify) unawaited(_notify(key, isFromCache: true));
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
        if (!skipNotify) unawaited(_notify(key, isFromCache: false));
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
          if (!skipNotify) unawaited(_notify(key, isFromCache: false));
          return result;
        }
        final cached = await store.read(key);
        if (cached == null) {
          throw CacheMissException(key);
        }
        if (!skipNotify) unawaited(_notify(key, isFromCache: true));
        return strategy.wrapCached(cached, isStale: cached.meta.isExpired);

      case Policy.offlineFirst:
        final cached = await store.read(key);
        if (cached != null && !cached.meta.isExpired) {
          _notifyObservers((o) => o.onCacheHit(key));
          if (!skipNotify) unawaited(_notify(key, isFromCache: true));
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
            if (!skipNotify) unawaited(_notify(key, isFromCache: false));
            return result;
          } on CancelledException {
            rethrow;
          } catch (e) {
            if (strategy.isConvertibleToCacheMiss(e)) {
              throw CacheMissException(key);
            }
            if (cached != null) {
              if (!skipNotify) unawaited(_notify(key, isFromCache: true));
              return strategy.wrapCached(cached,
                  isStale: cached.meta.isExpired);
            }
            rethrow;
          }
        }

        if (cached != null) {
          if (!skipNotify) unawaited(_notify(key, isFromCache: true));
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
          skipNotify: skipNotify,
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
          skipNotify: skipNotify,
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
    bool skipNotify = false,
  }) async {
    final cached = await store.read(key);

    if (cached != null) {
      _notifyObservers((o) => o.onCacheHit(key));

      final shouldRefresh =
          network.isOnline && (!refreshOnlyIfExpired || cached.meta.isExpired);

      if (shouldRefresh) {
        unawaited(strategy
            .backgroundRefresh(_fetchEngine, key, ttl, retry, tags)
            .then((_) {
          unawaited(_notify(key, isFromCache: false));
        }).catchError((Object e, StackTrace st) {
          _notifyObservers((o) => o.onFetchError(key, e, st));
        }));
      }

      if (!skipNotify) unawaited(_notify(key, isFromCache: true));
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
      if (!skipNotify) unawaited(_notify(key, isFromCache: false));
      return result;
    }

    throw CacheMissException(key);
  }
}

/// Internal record of an active watch registration.
///
/// Carries the parameters a watcher was created with so the cache can
/// refetch with the watcher's own fetch/policy/ttl, and — for
/// [Syncache.watchWithDependencies] — tracks the dependency keys that
/// trigger refetches.
class _WatchRegistration<T> {
  /// The cache key being watched.
  final String key;

  /// The fetcher function for refetching.
  final Fetcher<T> fetch;

  /// The policy to use when refetching.
  final Policy policy;

  /// The TTL to use when refetching.
  final Duration? ttl;

  /// The keys this watcher depends on (empty for plain watchers).
  final List<String> dependsOn;

  const _WatchRegistration({
    required this.key,
    required this.fetch,
    required this.policy,
    required this.ttl,
    this.dependsOn = const [],
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

/// Fetch strategy that returns `CacheResult<T>` with metadata.
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
