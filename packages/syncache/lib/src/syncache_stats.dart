import 'cancellation.dart';

/// An immutable snapshot of `Syncache` health counters.
///
/// Obtain a snapshot via `Syncache.stats` (an async getter — resolving the
/// approximate entry count may require asking the store) and reset counters
/// with `Syncache.resetStats`. Every field is a plain counter: no per-key
/// bookkeeping is kept, so stats memory usage is constant regardless of
/// cache size.
///
/// ```dart
/// final stats = await cache.stats;
/// final hitRate = stats.hits / (stats.hits + stats.misses);
/// print('hit rate: $hitRate');
/// ```
class SyncacheStats {
  /// Cache reads answered by a valid (non-expired) cached value.
  final int hits;

  /// Cache reads that found nothing usable in the cache.
  final int misses;

  /// Network fetches started (including attempts that later failed).
  final int fetchesStarted;

  /// Network fetches that completed successfully.
  final int fetchesSucceeded;

  /// Network fetches that failed (after any retries were exhausted).
  final int fetchesFailed;

  /// Fetch retry attempts scheduled after a failed attempt.
  final int fetchesRetried;

  /// Fetch attempts aborted via a [CancellationToken].
  final int fetchesCancelled;

  /// Values written to the store (fetches, `Syncache.set`, optimistic
  /// mutations).
  final int stores;

  /// Entries invalidated explicitly (`Syncache.invalidate`, tag/pattern
  /// invalidations) or swept by `Syncache.cleanup`.
  final int invalidations;

  /// Entries evicted by a bounded store (e.g. LRU in `MemoryStore`).
  final int evictions;

  /// Mutations currently queued for background sync.
  final int pendingMutations;

  /// Approximate number of entries in the store, or `null` when the store
  /// cannot enumerate keys (does not implement `IterableStore`).
  final int? entryCount;

  /// Creates a snapshot with the given counter values.
  const SyncacheStats({
    required this.hits,
    required this.misses,
    required this.fetchesStarted,
    required this.fetchesSucceeded,
    required this.fetchesFailed,
    required this.fetchesRetried,
    required this.fetchesCancelled,
    required this.stores,
    required this.invalidations,
    required this.evictions,
    required this.pendingMutations,
    this.entryCount,
  });

  /// A snapshot with every counter at zero.
  static const SyncacheStats zero = SyncacheStats(
    hits: 0,
    misses: 0,
    fetchesStarted: 0,
    fetchesSucceeded: 0,
    fetchesFailed: 0,
    fetchesRetried: 0,
    fetchesCancelled: 0,
    stores: 0,
    invalidations: 0,
    evictions: 0,
    pendingMutations: 0,
  );

  @override
  bool operator ==(Object other) =>
      other is SyncacheStats &&
      other.hits == hits &&
      other.misses == misses &&
      other.fetchesStarted == fetchesStarted &&
      other.fetchesSucceeded == fetchesSucceeded &&
      other.fetchesFailed == fetchesFailed &&
      other.fetchesRetried == fetchesRetried &&
      other.fetchesCancelled == fetchesCancelled &&
      other.stores == stores &&
      other.invalidations == invalidations &&
      other.evictions == evictions &&
      other.pendingMutations == pendingMutations &&
      other.entryCount == entryCount;

  @override
  int get hashCode => Object.hash(
        hits,
        misses,
        fetchesStarted,
        fetchesSucceeded,
        fetchesFailed,
        fetchesRetried,
        fetchesCancelled,
        stores,
        invalidations,
        evictions,
        pendingMutations,
        entryCount,
      );

  @override
  String toString() => 'SyncacheStats('
      'hits: $hits, '
      'misses: $misses, '
      'fetchesStarted: $fetchesStarted, '
      'fetchesSucceeded: $fetchesSucceeded, '
      'fetchesFailed: $fetchesFailed, '
      'fetchesRetried: $fetchesRetried, '
      'fetchesCancelled: $fetchesCancelled, '
      'stores: $stores, '
      'invalidations: $invalidations, '
      'evictions: $evictions, '
      'pendingMutations: $pendingMutations, '
      'entryCount: $entryCount)';

  /// Renders this snapshot as a JSON-encodable map for debug dumps.
  ///
  /// Field names match the constructor parameters. Used by
  /// `Syncache.debugSnapshot`; kept public so custom tooling renders
  /// stats identically.
  Map<String, Object?> toDebugJson() => {
        'hits': hits,
        'misses': misses,
        'fetchesStarted': fetchesStarted,
        'fetchesSucceeded': fetchesSucceeded,
        'fetchesFailed': fetchesFailed,
        'fetchesRetried': fetchesRetried,
        'fetchesCancelled': fetchesCancelled,
        'stores': stores,
        'invalidations': invalidations,
        'evictions': evictions,
        'pendingMutations': pendingMutations,
        'entryCount': entryCount,
      };
}

/// An individual stats counter that can be reset on its own via
/// `Syncache.resetStats`.
enum SyncacheCounter {
  /// Resets [SyncacheStats.hits].
  hits,

  /// Resets [SyncacheStats.misses].
  misses,

  /// Resets [SyncacheStats.fetchesStarted].
  fetchesStarted,

  /// Resets [SyncacheStats.fetchesSucceeded].
  fetchesSucceeded,

  /// Resets [SyncacheStats.fetchesFailed].
  fetchesFailed,

  /// Resets [SyncacheStats.fetchesRetried].
  fetchesRetried,

  /// Resets [SyncacheStats.fetchesCancelled].
  fetchesCancelled,

  /// Resets [SyncacheStats.stores].
  stores,

  /// Resets [SyncacheStats.invalidations].
  invalidations,

  /// Resets [SyncacheStats.evictions].
  evictions,
}
