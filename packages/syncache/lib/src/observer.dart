import 'pending_mutation_record.dart';

/// Observer interface for monitoring Syncache operations.
///
/// Implement this class to receive notifications about cache events
/// such as hits, misses, fetches, and mutations. Useful for logging,
/// analytics, debugging, and performance monitoring.
///
/// All methods have empty default implementations, so you only need
/// to override the events you care about.
///
/// ## Example
///
/// ```dart
/// class AnalyticsObserver extends SyncacheObserver {
///   @override
///   void onFetchSuccess(String key, Duration duration) {
///     analytics.track('cache_fetch', {
///       'key': key,
///       'duration_ms': duration.inMilliseconds,
///     });
///   }
///
///   @override
///   void onFetchError(String key, Object error, StackTrace stackTrace) {
///     errorReporter.report(error, stackTrace);
///   }
/// }
/// ```
///
/// ## Usage
///
/// ```dart
/// final cache = Syncache<User>(
///   store: MemoryStore(),
///   observers: [LoggingObserver(), AnalyticsObserver()],
/// );
/// ```
abstract class SyncacheObserver {
  /// Called when a valid (non-expired) value is found in cache.
  ///
  /// This indicates a successful cache hit that avoided a network request.
  void onCacheHit(String key) {}

  /// Called when no value is found in cache, or the cached value is expired.
  ///
  /// This typically triggers a network fetch (depending on policy).
  void onCacheMiss(String key) {}

  /// Called when a network fetch operation starts.
  ///
  /// Use this to track in-flight requests or show loading indicators.
  void onFetchStart(String key) {}

  /// Called when a network fetch completes successfully.
  ///
  /// The [duration] indicates how long the fetch took.
  void onFetchSuccess(String key, Duration duration) {}

  /// Called when a network fetch fails with an error.
  ///
  /// The [error] and [stackTrace] provide details about the failure.
  void onFetchError(String key, Object error, StackTrace stackTrace) {}

  /// Called when a cache entry is explicitly invalidated.
  void onInvalidate(String key) {}

  /// Called when the entire cache is cleared.
  void onClear() {}

  /// Called when a mutation's optimistic update is applied locally.
  ///
  /// This happens immediately when [Syncache.mutate] is called,
  /// before the server sync completes.
  void onMutationStart(String key) {}

  /// Called when a mutation's server sync completes successfully.
  ///
  /// The local cache has been updated with the server's response.
  void onMutationSuccess(String key) {}

  /// Called when a mutation's server sync fails.
  ///
  /// The optimistic update remains in cache but the sync failed.
  /// The mutation will be retried when the network is available.
  void onMutationError(String key, Object error, StackTrace stackTrace) {}

  /// Called when a mutation sync fails and a retry is about to be attempted.
  ///
  /// The [attempt] is 0-indexed (0 for first retry after initial failure).
  /// The [error] is the exception that triggered the retry.
  /// The [delay] is the duration before the retry will be attempted.
  void onMutationRetry(String key, int attempt, Object error, Duration delay) {}

  /// Called when all mutation retry attempts have been exhausted.
  ///
  /// The [totalAttempts] is the total number of attempts made
  /// (initial + retries). The [finalError] is the last error encountered.
  /// At this point, the mutation has been removed from the queue.
  void onMutationRetryExhausted(
      String key, int totalAttempts, Object finalError) {}

  /// Called when a mutation's [Mutation.send] threw a
  /// [SyncacheConflictException] — the server reports the resource changed
  /// concurrently.
  ///
  /// The [error] is the conflict exception itself; its `serverValue` is the
  /// server's current state. Conflicts are never retried: the configured
  /// [ConflictResolver] decides the outcome next. When it resolves, this is
  /// followed by [onMutationResolved]; when it throws (or no resolver is
  /// configured), the mutation fails without retry and this is followed by
  /// [onMutationError] plus [onMutationRetryExhausted].
  void onMutationConflict(String key, Object error) {}

  /// Called after a [SyncacheConflictException] was resolved: the
  /// [ConflictResolver]'s value has been written to the cache and the
  /// mutation settled with a [MutationResolved] outcome — it is removed
  /// from the queue and will not be retried.
  void onMutationResolved(String key) {}

  /// Called when a value is stored in the cache.
  ///
  /// This happens after successful fetches and mutations.
  void onStore(String key) {}

  /// Called when an entry is evicted from a bounded store because the
  /// store exceeded its capacity (e.g. least-recently-used eviction in a
  /// `MemoryStore` configured with `maxLength`).
  ///
  /// Unlike [onInvalidate], an eviction is a capacity event: watchers of
  /// the evicted key keep their last value and are **not** refetched, so a
  /// small cache does not trigger a refill storm.
  void onEvict(String key) {}

  /// Called when a fetch fails and a retry is about to be attempted.
  ///
  /// The [attempt] is 0-indexed (0 for first retry after initial failure).
  /// The [error] is the exception that triggered the retry.
  /// The [delay] is the duration before the retry will be attempted.
  void onRetry(String key, int attempt, Object error, Duration delay) {}

  /// Called when all retry attempts have been exhausted.
  ///
  /// The [totalAttempts] is the total number of attempts made
  /// (initial + retries). The [finalError] is the last error encountered.
  void onRetryExhausted(String key, int totalAttempts, Object finalError) {}

  /// Called when a fetch operation is cancelled via [CancellationToken].
  ///
  /// This is called when the operation is aborted before completion.
  void onFetchCancelled(String key) {}

  /// Called when an outbox write fails.
  ///
  /// Outbox failures never block cache operations: the mutation continues
  /// to be tracked in memory. Note that a failed `delete` leaves a durable
  /// record behind which will be replayed on the next
  /// [Syncache.recoverPendingMutations] — make server endpoints idempotent.
  void onOutboxError(Object error) {}

  /// Called when a persisted mutation record could not be turned back into
  /// a live mutation during [Syncache.recoverPendingMutations].
  ///
  /// The [record] is reported, never dropped silently. The app's resolver
  /// threw [error] (or the record's cache entry was missing), so the change
  /// could not be re-enqueued; the record stays in the outbox.
  void onOutboxReplayFailed(PendingMutationRecord record, Object error) {}
}
