import 'pending_mutation_record.dart';

/// Persistence backend for pending mutations.
///
/// When an outbox is configured on [Syncache], every enqueued mutation is
/// mirrored to it as a [PendingMutationRecord] and removed when the mutation
/// settles (sent, exhausted, or discarded). Records survive `Syncache.dispose`
/// so a freshly constructed instance can replay unsynced writes via
/// [Syncache.recoverPendingMutations] — this is what makes offline writes
/// survive process death.
///
/// The interface is deliberately tiny (four methods) so apps can implement it
/// over any persistence they already own (`shared_preferences`, SQLite,
/// IndexedDB, …). Syncache ships [MemoryMutationOutbox] as an in-process
/// reference implementation, and `syncache_hive` ships `HiveMutationOutbox`
/// for durable storage.
///
/// The outbox backend is independent of the cache [Store] backend: a drift
/// cache with a Hive outbox is a valid mix.
///
/// ## Error handling
///
/// Outbox failures never block cache operations. A failing `save` or `delete`
/// is reported to observers via `SyncacheObserver.onOutboxError` and the
/// mutation continues in memory. Note that a failed `delete` leaves a record
/// behind which will be replayed on the next recovery — make server
/// endpoints idempotent (client-generated operation ids in the payload help
/// with deduplication).
abstract class MutationOutbox {
  /// Persists (or replaces) [record], keyed by its id.
  Future<void> save(PendingMutationRecord record);

  /// Removes the record with the given [id]. Must be a no-op if absent.
  Future<void> delete(String id);

  /// Removes all records.
  Future<void> clear();

  /// Loads all records, ordered by [PendingMutationRecord.seq] ascending.
  Future<List<PendingMutationRecord>> loadAll();
}
