import 'dart:async';

import 'package:syncache/syncache.dart';

/// How often the flusher checks whether the mutation queue has drained.
const Duration _pollInterval = Duration(milliseconds: 100);

/// The type-erased contract the [SyncacheBackgroundFlusher] drives.
///
/// Implemented by [SyncacheBackgroundCacheRegistration] so caches of
/// different value types can share one flusher.
abstract interface class SyncacheFlushTarget {
  /// Runs one flush pass for this target and returns a
  /// `SyncacheFlushReport`-shaped record of what happened.
  Future<SyncacheFlushReport> flush({
    required bool cleanup,
    required DateTime deadline,
  });
}

/// A typed cache registration for background flushes.
///
/// Background isolates are separate Dart worlds: caches, stores, and
/// outboxes built in the main isolate do not exist there. Instead, the
/// flusher rebuilds everything it needs inside the background task:
///
/// - [createCache] constructs a fresh `Syncache<T>` — typically over the
///   **same durable store and [MutationOutbox]** the foreground app uses,
///   so outbox records persisted before the process died are visible here.
/// - [resolveRecord] maps a persisted [PendingMutationRecord] back to the
///   live `Mutation<T>` to replay — the same resolver you pass to
///   `Syncache.recoverPendingMutations`, usually a switch on the payload's
///   `'op'` field.
///
/// The flush pass itself is fixed: recover → process → (optional cleanup)
/// → dispose. Dispose never deletes outbox records, so anything this pass
/// could not send simply waits for the next one.
///
/// Both callbacks run inside the background isolate; keep them top-level
/// functions or static methods so they can be referenced from the
/// dispatcher.
///
/// ```dart
/// final registration = SyncacheBackgroundCacheRegistration<User>(
///   createCache: buildUserCache, // opens the store + outbox, builds Syncache
///   resolveRecord: resolveUserRecord, // payload -> Mutation<User>
/// );
/// ```
final class SyncacheBackgroundCacheRegistration<T>
    implements SyncacheFlushTarget {
  /// Builds a fresh `Syncache<T>` inside the current isolate.
  ///
  /// Called once per flush pass. Open the durable store and outbox here
  /// (e.g. Hive boxes) — they must be the same persistence the foreground
  /// app writes to, or there is nothing to recover.
  final Future<Syncache<T>> Function() createCache;

  /// Rebuilds the live mutation for a persisted outbox record.
  final Future<Mutation<T>> Function(PendingMutationRecord record)
      resolveRecord;

  /// Creates a registration for one typed cache.
  const SyncacheBackgroundCacheRegistration({
    required this.createCache,
    required this.resolveRecord,
  });

  @override
  Future<SyncacheFlushReport> flush({
    required bool cleanup,
    required DateTime deadline,
  }) async {
    final cache = await createCache();
    try {
      final recovered = await cache.recoverPendingMutations(resolveRecord);
      // Recovery starts a processing pass itself (when online and anything
      // was re-enqueued); this call is a no-op while that pass runs and a
      // safety net when it was not started.
      await cache.processPendingMutations();
      final exhaustedBudget = await _awaitSettled(cache, deadline);
      // Out of budget means out of budget: leftover expired entries are
      // swept by the next run instead of risking the task being killed
      // mid-way by the OS.
      final swept = !exhaustedBudget && cleanup ? await cache.cleanup() : 0;
      return SyncacheFlushReport(
        recovered: recovered,
        remaining: cache.pendingMutationCount,
        swept: swept,
        exhaustedBudget: exhaustedBudget,
      );
    } finally {
      // Settles this pass's outstanding handles; deliberately keeps the
      // outbox records so unsent mutations survive for the next run.
      cache.dispose();
    }
  }

  /// Waits until the mutation queue drains, the network drops, or
  /// [deadline] passes — whichever comes first. Returns whether the
  /// deadline ended the wait while mutations were still pending.
  ///
  /// Polling rather than awaiting a stream: recovery kicks off processing
  /// in the background, so the queue may drain at any moment and a missed
  /// stream event would otherwise hang until the deadline anyway.
  static Future<bool> _awaitSettled(
    Syncache<Object?> cache,
    DateTime deadline,
  ) async {
    while (cache.hasPendingMutations && cache.network.isOnline) {
      if (!DateTime.now().isBefore(deadline)) return true;
      await Future<void>.delayed(_pollInterval);
    }
    return false;
  }
}

/// Flushes Syncache outbox records inside a background task.
///
/// The flusher owns no state itself: every flush pass builds fresh caches
/// through its registered [SyncacheBackgroundCacheRegistration]s, so it
/// is safe to construct a new flusher inside every background task (and
/// you should — background isolates cannot reuse main-isolate objects).
///
/// Per target the pass is: `recoverPendingMutations` (re-enqueue persisted
/// records) → `processPendingMutations` (send everything while online) →
/// optional `cleanup` (sweep expired entries) → `dispose`. Unsent
/// mutations stay in the outbox for the next scheduled run.
///
/// ```dart
/// final flusher = SyncacheBackgroundFlusher(registrations: [
///   SyncacheBackgroundCacheRegistration<User>(
///     createCache: buildUserCache,
///     resolveRecord: resolveUserRecord,
///   ),
/// ]);
/// final report = await flusher.flush();
/// ```
final class SyncacheBackgroundFlusher {
  /// The caches this flusher flushes, in order.
  final List<SyncacheFlushTarget> registrations;

  /// Creates a flusher for [registrations]. Targets are flushed
  /// sequentially in list order, so work stays predictable inside the
  /// platform's background time budget.
  SyncacheBackgroundFlusher({required List<SyncacheFlushTarget> registrations})
      : registrations = List.unmodifiable(registrations);

  /// Runs one flush pass across every registration.
  ///
  /// [cleanup] additionally sweeps expired entries from each cache after
  /// its mutations are flushed (wire this to a periodic maintenance task).
  ///
  /// [timeBudget] bounds the whole pass — background execution time is
  /// granted and enforced by the OS (roughly 30s on iOS, a few minutes on
  /// Android). When the budget runs out with mutations still pending, the
  /// report's [SyncacheFlushReport.exhaustedBudget] is true and the
  /// leftover work waits in the outbox for the next run.
  ///
  /// Errors from a registration's [SyncacheBackgroundCacheRegistration
  /// .createCache] (e.g. the persistence layer failed to open) propagate
  /// to the caller — surface them to the platform as a task failure so
  /// workmanager retries with backoff; `runSyncacheTask` does this for you.
  Future<SyncacheFlushReport> flush({
    bool cleanup = false,
    Duration timeBudget = defaultFlushTimeBudget,
  }) async {
    final startedAt = DateTime.now();
    final deadline = startedAt.add(timeBudget);

    var recovered = 0;
    var remaining = 0;
    var swept = 0;
    var exhaustedBudget = false;

    for (final registration in registrations) {
      final report = await registration.flush(
        cleanup: cleanup,
        deadline: deadline,
      );
      recovered += report.recovered;
      remaining += report.remaining;
      swept += report.swept;
      exhaustedBudget = exhaustedBudget || report.exhaustedBudget;
    }

    return SyncacheFlushReport(
      recovered: recovered,
      remaining: remaining,
      swept: swept,
      exhaustedBudget: exhaustedBudget,
      duration: DateTime.now().difference(startedAt),
    );
  }

  /// Default wall-clock budget for one flush pass: conservative enough to
  /// fit inside an iOS background task's ~30 seconds (isolate startup,
  /// storage open, and network calls all come out of the same budget).
  static const Duration defaultFlushTimeBudget = Duration(seconds: 20);
}

/// What one flush pass did.
///
/// - [recovered]: outbox records re-enqueued as live mutations. Records
///   that could not be replayed (e.g. a key no longer in the store) are
///   not counted and stay in the outbox.
/// - [remaining]: mutations still queued when the pass ended — an
///   unreachable server, retry exhaustion handled elsewhere, or
///   [exhaustedBudget]. They remain in the outbox for the next run.
/// - [swept]: expired entries removed by the optional cleanup pass (0 when
///   cleanup was not requested or the store cannot enumerate keys).
/// - [exhaustedBudget]: the time budget ended the pass while mutations
///   were still pending.
final class SyncacheFlushReport {
  /// Outbox records re-enqueued as live mutations during the pass.
  final int recovered;

  /// Mutations still queued when the pass ended.
  final int remaining;

  /// Expired entries removed by the optional cleanup pass.
  final int swept;

  /// Whether the time budget ended the pass with mutations still pending.
  final bool exhaustedBudget;

  /// How long the whole pass took (set by [SyncacheBackgroundFlusher
  /// .flush]; defaults to zero for per-target reports).
  final Duration duration;

  /// Creates a report.
  const SyncacheFlushReport({
    this.recovered = 0,
    this.remaining = 0,
    this.swept = 0,
    this.exhaustedBudget = false,
    this.duration = Duration.zero,
  });

  @override
  String toString() => 'SyncacheFlushReport('
      'recovered: $recovered, remaining: $remaining, swept: $swept, '
      'exhaustedBudget: $exhaustedBudget, duration: $duration)';
}
