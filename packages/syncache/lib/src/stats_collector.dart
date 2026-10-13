import 'observer.dart';
import 'syncache_stats.dart';

/// Internal observer that accumulates `Syncache` health counters.
///
/// An instance is attached to every [Syncache](package:syncache/syncache.dart)
/// and dispatched through the same internal observer path as user observers,
/// but it is never visible in the cache's `observers` list.
///
/// Counters only — no per-key maps, so memory usage is constant regardless
/// of cache size.
class StatsCollector extends SyncacheObserver {
  int hits = 0;
  int misses = 0;
  int fetchesStarted = 0;
  int fetchesSucceeded = 0;
  int fetchesFailed = 0;
  int fetchesRetried = 0;
  int fetchesCancelled = 0;
  int stores = 0;
  int invalidations = 0;
  int evictions = 0;

  @override
  void onCacheHit(String key) => hits++;

  @override
  void onCacheMiss(String key) => misses++;

  @override
  void onFetchStart(String key) => fetchesStarted++;

  @override
  void onFetchSuccess(String key, Duration duration) => fetchesSucceeded++;

  @override
  void onFetchError(String key, Object error, StackTrace stackTrace) =>
      fetchesFailed++;

  @override
  void onRetry(String key, int attempt, Object error, Duration delay) =>
      fetchesRetried++;

  @override
  void onFetchCancelled(String key) => fetchesCancelled++;

  @override
  void onStore(String key) => stores++;

  @override
  void onInvalidate(String key) => invalidations++;

  @override
  void onEvict(String key) => evictions++;

  /// Builds an immutable snapshot, adding the live [pendingMutations] count
  /// and the store's [entryCount] (null when the store can't enumerate).
  SyncacheStats snapshot({required int pendingMutations, int? entryCount}) {
    return SyncacheStats(
      hits: hits,
      misses: misses,
      fetchesStarted: fetchesStarted,
      fetchesSucceeded: fetchesSucceeded,
      fetchesFailed: fetchesFailed,
      fetchesRetried: fetchesRetried,
      fetchesCancelled: fetchesCancelled,
      stores: stores,
      invalidations: invalidations,
      evictions: evictions,
      pendingMutations: pendingMutations,
      entryCount: entryCount,
    );
  }

  /// Zeroes the given [counters], or every counter when null.
  void reset([Set<SyncacheCounter>? counters]) {
    if (counters == null ||
        counters.length == SyncacheCounter.values.length ||
        counters.containsAll(SyncacheCounter.values)) {
      hits = 0;
      misses = 0;
      fetchesStarted = 0;
      fetchesSucceeded = 0;
      fetchesFailed = 0;
      fetchesRetried = 0;
      fetchesCancelled = 0;
      stores = 0;
      invalidations = 0;
      evictions = 0;
      return;
    }
    for (final counter in counters) {
      switch (counter) {
        case SyncacheCounter.hits:
          hits = 0;
        case SyncacheCounter.misses:
          misses = 0;
        case SyncacheCounter.fetchesStarted:
          fetchesStarted = 0;
        case SyncacheCounter.fetchesSucceeded:
          fetchesSucceeded = 0;
        case SyncacheCounter.fetchesFailed:
          fetchesFailed = 0;
        case SyncacheCounter.fetchesRetried:
          fetchesRetried = 0;
        case SyncacheCounter.fetchesCancelled:
          fetchesCancelled = 0;
        case SyncacheCounter.stores:
          stores = 0;
        case SyncacheCounter.invalidations:
          invalidations = 0;
        case SyncacheCounter.evictions:
          evictions = 0;
      }
    }
  }
}
