import 'cache_result.dart';
import 'cancellation.dart';
import 'fetcher.dart';
import 'policy.dart';
import 'retry.dart';
import 'syncache.dart';

/// A typed view of a single cache key, bound to its fetcher and default
/// cache parameters.
///
/// Raw string keys plus repeated `fetch` closures are the main ergonomic
/// tax of a cache API. An entry removes both: create it once where the
/// data source lives, then read/watch/write through it without repeating
/// the key or the fetcher.
///
/// ```dart
/// final entry = cache.entry(
///   'user:123',
///   fetch: (req) => api.getUser(123),
///   ttl: const Duration(minutes: 5),
/// );
///
/// final user = await entry.get();          // cache.get with bound defaults
/// Stream<User> s = entry.watch();          // reactive stream for the key
/// await entry.refresh();                   // get with Policy.refresh
/// await entry.invalidate();                // delete the cached entry
/// await entry.set(updatedUser);            // write without fetching
/// CacheResult<User> r = await entry.getWithMeta();
/// ```
///
/// ## Entries are lightweight views
///
/// An entry holds **no state of its own**: no stream controllers, no
/// cached values, no subscriptions. It is a thin, immutable handle that
/// delegates every call to the owning [Syncache] with the bound [key] and
/// defaults. Creating entries is cheap, they never need to be disposed,
/// and they are safe to store in fields, closures, or providers. All
/// lifecycle (watch-stream controllers, refetch bookkeeping, disposal)
/// remains with the [Syncache] instance — see [Syncache.dispose].
///
/// Two entries bound to the same key (even with different defaults) view
/// the same stored data; writes through one are immediately visible to
/// watchers of the other.
///
/// ## Scoping
///
/// Entries created through `ScopedSyncache.entry` are automatically bound
/// to the scope-prefixed key. [key] exposes that resolved, physical key —
/// i.e. for a scoped entry it is the prefixed form that appears in the
/// store, not the logical key passed to `ScopedSyncache.entry`.
///
/// See also:
/// - [Syncache.entry] for creating entries on the root cache
/// - `ScopedSyncache.entry` for creating scope-prefixed entries
/// - [Syncache] for the full semantics of every underlying operation
class SyncacheEntry<T> {
  final Syncache<T> _cache;

  /// The resolved cache key this entry is bound to.
  ///
  /// For entries created through `ScopedSyncache.entry` this is the
  /// scope-prefixed key (e.g. `workspace:1:user:123`); for entries created
  /// through [Syncache.entry] it is the key exactly as passed.
  final String key;

  /// The fetcher bound at creation time, used by every read operation.
  final Fetcher<T> fetch;

  /// The default policy used by [get], [getWithMeta], [watch] and
  /// [watchWithMeta]. Overridable per call via [get] / [getWithMeta].
  final Policy policy;

  /// The default time-to-live applied to fetched and written values.
  ///
  /// [set] accepts a per-call override; when omitted, the bound [ttl] is
  /// used (passing `null` for both means "keep whatever TTL the entry
  /// already has", matching [Syncache.set]).
  final Duration? ttl;

  /// Tags stored alongside fetched values (requires a [TaggableStore]).
  final List<String>? tags;

  const SyncacheEntry._(
    this._cache, {
    required this.key,
    required this.fetch,
    this.policy = Policy.offlineFirst,
    this.ttl,
    this.tags,
  });

  /// Factory used by [Syncache.entry] and `ScopedSyncache.entry`.
  factory SyncacheEntry.of(
    Syncache<T> cache, {
    required String key,
    required Fetcher<T> fetch,
    Policy policy = Policy.offlineFirst,
    Duration? ttl,
    List<String>? tags,
  }) {
    return SyncacheEntry._(
      cache,
      key: key,
      fetch: fetch,
      policy: policy,
      ttl: ttl,
      tags: tags,
    );
  }

  /// Retrieves the value, exactly like [Syncache.get] but with the bound
  /// [key], [fetch], [policy], [ttl] and [tags].
  ///
  /// Pass [policy] to override the bound policy for this call only, e.g.
  /// `entry.get(policy: Policy.networkOnly)`.
  Future<T> get({
    Policy? policy,
    RetryConfig? retry,
    CancellationToken? cancel,
  }) {
    return _cache.get(
      key: key,
      fetch: fetch,
      policy: policy ?? this.policy,
      ttl: ttl,
      retry: retry,
      cancel: cancel,
      tags: tags,
    );
  }

  /// Retrieves the value with cache metadata, exactly like
  /// [Syncache.getWithMeta] but with the bound defaults.
  Future<CacheResult<T>> getWithMeta({
    Policy? policy,
    RetryConfig? retry,
    CancellationToken? cancel,
  }) {
    return _cache.getWithMeta(
      key: key,
      fetch: fetch,
      policy: policy ?? this.policy,
      ttl: ttl,
      retry: retry,
      cancel: cancel,
    );
  }

  /// Returns a reactive stream of values for the bound key, exactly like
  /// [Syncache.watch] but with the bound [fetch], [policy] and [ttl].
  ///
  /// The stream follows the full [Syncache.watch] contract: invalidation
  /// refetches the watcher instead of closing it, and the stream completes
  /// only when every listener unsubscribes or the cache is disposed.
  Stream<T> watch() {
    return _cache.watch(key: key, fetch: fetch, policy: policy, ttl: ttl);
  }

  /// Returns a reactive stream of values with metadata for the bound key,
  /// exactly like [Syncache.watchWithMeta] but with the bound defaults.
  Stream<CacheResult<T>> watchWithMeta() {
    return _cache.watchWithMeta(
      key: key,
      fetch: fetch,
      policy: policy,
      ttl: ttl,
    );
  }

  /// Forces a network refresh of the bound key, exactly like calling
  /// [get] with [Policy.refresh]: fetches when online, falls back to the
  /// cached value when offline (throwing [CacheMissException] when the
  /// cache is empty too).
  Future<T> refresh({
    RetryConfig? retry,
    CancellationToken? cancel,
  }) {
    return get(policy: Policy.refresh, retry: retry, cancel: cancel);
  }

  /// Writes [value] directly to the cache, exactly like [Syncache.set]
  /// but with the bound [key].
  ///
  /// Uses the per-call [ttl] when given, otherwise the bound [ttl]. When
  /// both are null the existing TTL of the entry is preserved (or left
  /// unset for a new key), matching [Syncache.set].
  Future<void> set(T value, {Duration? ttl}) {
    return _cache.set(key: key, value: value, ttl: ttl ?? this.ttl);
  }

  /// Invalidates (deletes) the cached entry for the bound key, exactly
  /// like [Syncache.invalidate]. Active watchers of the key are refetched
  /// with this entry's [fetch]/[policy]/[ttl].
  Future<void> invalidate() {
    return _cache.invalidate(key);
  }

  @override
  String toString() =>
      'SyncacheEntry<$T>(key: $key, policy: $policy, ttl: $ttl)';
}
