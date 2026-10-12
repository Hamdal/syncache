import 'dart:async';

import 'cache_result.dart';
import 'cancellation.dart';
import 'fetcher.dart';
import 'mutation.dart';
import 'mutation_handle.dart';
import 'pending_mutation_info.dart';
import 'pending_mutation_record.dart';
import 'policy.dart';
import 'prefetch.dart';
import 'retry.dart';
import 'syncache.dart';

/// A scoped view of a [Syncache] instance.
///
/// All keys are automatically prefixed with the scope, providing isolation
/// between different contexts (e.g., workspaces, tenants, user sessions).
///
/// Example:
/// ```dart
/// final cache = Syncache<User>(store: MemoryStore());
///
/// // Create scoped caches for different workspaces
/// final workspace1Cache = cache.scoped('workspace:1');
/// final workspace2Cache = cache.scoped('workspace:2');
///
/// // Operations are isolated
/// await workspace1Cache.get(key: 'users', fetch: fetchUsers);
/// // Actually stores as: 'workspace:1:users'
///
/// await workspace2Cache.get(key: 'users', fetch: fetchUsers);
/// // Actually stores as: 'workspace:2:users'
///
/// // Clear all data for workspace 1
/// await cache.clearScope('workspace:1');
/// ```
class ScopedSyncache<T> {
  final Syncache<T> _cache;
  final String scope;

  /// Creates a scoped view where all keys are prefixed with `$scope:`.
  ScopedSyncache(this._cache, this.scope);

  String _scopedKey(String key) => '$scope:$key';

  /// See [Syncache.get] for full documentation.
  Future<T> get({
    required String key,
    required Fetcher<T> fetch,
    Policy policy = Policy.offlineFirst,
    Duration? ttl,
    RetryConfig? retry,
    CancellationToken? cancel,
    List<String>? tags,
  }) {
    return _cache.get(
      key: _scopedKey(key),
      fetch: fetch,
      policy: policy,
      ttl: ttl,
      retry: retry,
      cancel: cancel,
      tags: tags,
    );
  }

  /// See [Syncache.getWithMeta] for full documentation.
  Future<CacheResult<T>> getWithMeta({
    required String key,
    required Fetcher<T> fetch,
    Policy policy = Policy.offlineFirst,
    Duration? ttl,
    RetryConfig? retry,
    CancellationToken? cancel,
  }) {
    return _cache.getWithMeta(
      key: _scopedKey(key),
      fetch: fetch,
      policy: policy,
      ttl: ttl,
      retry: retry,
      cancel: cancel,
    );
  }

  /// See [Syncache.getConditional] for full documentation.
  Future<T> getConditional({
    required String key,
    required ConditionalFetcher<T> fetch,
    Policy policy = Policy.offlineFirst,
    Duration? ttl,
    RetryConfig? retry,
    CancellationToken? cancel,
  }) {
    return _cache.getConditional(
      key: _scopedKey(key),
      fetch: fetch,
      policy: policy,
      ttl: ttl,
      retry: retry,
      cancel: cancel,
    );
  }

  /// See [Syncache.watch] for full documentation.
  Stream<T> watch({
    required String key,
    required Fetcher<T> fetch,
    Policy policy = Policy.offlineFirst,
    Duration? ttl,
  }) {
    return _cache.watch(
      key: _scopedKey(key),
      fetch: fetch,
      policy: policy,
      ttl: ttl,
    );
  }

  /// See [Syncache.watchWithMeta] for full documentation.
  Stream<CacheResult<T>> watchWithMeta({
    required String key,
    required Fetcher<T> fetch,
    Policy policy = Policy.offlineFirst,
    Duration? ttl,
  }) {
    return _cache.watchWithMeta(
      key: _scopedKey(key),
      fetch: fetch,
      policy: policy,
      ttl: ttl,
    );
  }

  /// See [Syncache.watchWithDependencies] for full documentation.
  ///
  /// Both [key] and the keys in [refetchWhen] are automatically scoped.
  Stream<T> watchWithDependencies({
    required String key,
    required Fetcher<T> fetch,
    required List<String> refetchWhen,
    Policy policy = Policy.offlineFirst,
    Duration? ttl,
  }) {
    return _cache.watchWithDependencies(
      key: _scopedKey(key),
      fetch: fetch,
      refetchWhen: refetchWhen.map(_scopedKey).toList(),
      policy: policy,
      ttl: ttl,
    );
  }

  /// See [Syncache.set] for full documentation.
  Future<void> set({
    required String key,
    required T value,
    Duration? ttl,
  }) {
    return _cache.set(key: _scopedKey(key), value: value, ttl: ttl);
  }

  /// See [Syncache.mutate] for full documentation.
  Future<MutationHandle<T>> mutate({
    required String key,
    required Mutation<T> mutation,
    List<String>? invalidates,
    List<String>? invalidateTags,
    Map<String, Object?>? payload,
    Object? optimisticSnapshot,
  }) {
    final scopedInvalidates = invalidates?.map(_scopedKey).toList();

    return _cache.mutate(
      key: _scopedKey(key),
      mutation: mutation,
      invalidates: scopedInvalidates,
      invalidateTags: invalidateTags,
      payload: payload,
      optimisticSnapshot: optimisticSnapshot,
    );
  }

  /// See [Syncache.invalidate] for full documentation.
  Future<void> invalidate(String key) {
    return _cache.invalidate(_scopedKey(key));
  }

  /// Tags are NOT scoped - they are shared across all scopes.
  /// See [Syncache.invalidateTag] for full documentation.
  Future<void> invalidateTag(String tag) {
    return _cache.invalidateTag(tag);
  }

  /// Tags are NOT scoped. See [Syncache.invalidateTags] for full documentation.
  Future<void> invalidateTags(List<String> tags, {bool matchAll = false}) {
    return _cache.invalidateTags(tags, matchAll: matchAll);
  }

  /// Pattern is auto-prefixed. See [Syncache.invalidatePattern] for full documentation.
  Future<void> invalidatePattern(String pattern) {
    return _cache.invalidatePattern(_scopedKey(pattern));
  }

  /// Clears all cached entries within this scope.
  ///
  /// By default active watchers are refetched and their streams stay open
  /// (see [Syncache.clear]); pass `refetchWatchers: false` to wipe without
  /// triggering refetches.
  Future<void> clear({bool refetchWatchers = true}) {
    return _cache.clearScope(scope, refetchWatchers: refetchWatchers);
  }

  /// See [Syncache.prefetch] for full documentation.
  Future<List<PrefetchResult>> prefetch(List<PrefetchRequest<T>> requests) {
    final scopedRequests = requests
        .map((r) => PrefetchRequest<T>(
              key: _scopedKey(r.key),
              fetch: r.fetch,
              policy: r.policy,
              ttl: r.ttl,
              retry: r.retry,
            ))
        .toList();

    return _cache.prefetch(scopedRequests);
  }

  /// See [Syncache.prefetchOne] for full documentation.
  Future<bool> prefetchOne({
    required String key,
    required Fetcher<T> fetch,
    Policy policy = Policy.refresh,
    Duration? ttl,
    RetryConfig? retry,
  }) {
    return _cache.prefetchOne(
      key: _scopedKey(key),
      fetch: fetch,
      policy: policy,
      ttl: ttl,
      retry: retry,
    );
  }

  // Mutation queue properties operate globally across ALL scopes

  /// Count for ALL scopes, not just this scope.
  int get pendingMutationCount => _cache.pendingMutationCount;

  /// Checks ALL scopes, not just this scope.
  bool get hasPendingMutations => _cache.hasPendingMutations;

  /// Returns mutations for ALL scopes.
  List<PendingMutationInfo> get pendingMutationsSnapshot =>
      _cache.pendingMutationsSnapshot;

  /// Streams mutations for ALL scopes.
  Stream<List<PendingMutationInfo>> get pendingMutationsStream =>
      _cache.pendingMutationsStream;

  /// Tracks sync status for ALL scopes.
  Stream<bool> get isSyncedStream => _cache.isSyncedStream;

  /// Clears mutations for ALL scopes.
  void clearPendingMutations() => _cache.clearPendingMutations();

  /// Removes a pending mutation by id across ALL scopes.
  /// See [Syncache.removePendingMutation].
  bool removePendingMutation(String id) => _cache.removePendingMutation(id);

  /// Removes the first pending mutation across ALL scopes.
  @Deprecated('Use removePendingMutation to remove a specific mutation')
  bool removeFirstPendingMutation() => _cache.removeFirstPendingMutation();

  /// Processes pending mutations across ALL scopes.
  /// See [Syncache.processPendingMutations].
  Future<void> processPendingMutations() => _cache.processPendingMutations();

  /// See [Syncache.recoverPendingMutations].
  Future<int> recoverPendingMutations(
    Future<Mutation<T>> Function(PendingMutationRecord record) resolve,
  ) =>
      _cache.recoverPendingMutations(resolve);

  Syncache<T> get cache => _cache;
}
