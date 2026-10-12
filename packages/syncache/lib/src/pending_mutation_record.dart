/// A persisted, serializable description of a pending mutation.
///
/// [Mutation] contains closures (`apply`, `send`) and cannot be serialized.
/// The outbox therefore persists a *record* — an opaque, JSON-safe [payload]
/// the caller supplies to [Syncache.mutate] — and the app maps records back
/// to live `Mutation` objects on recovery via the resolver passed to
/// [Syncache.recoverPendingMutations].
class PendingMutationRecord {
  /// Stable mutation id, matching [PendingMutationInfo.id] from the queue.
  final String id;

  /// The cache key this mutation affects.
  final String key;

  /// Monotonic enqueue order. Records with lower [seq] were enqueued first
  /// and must be replayed first.
  final int seq;

  /// Caller-supplied, JSON-safe description of the change to make.
  ///
  /// Syncache never interprets the payload; the recovery resolver reads it
  /// to rebuild the live `Mutation` (e.g. switching on an `'op'` field).
  final Map<String, Object?> payload;

  /// When the mutation was originally enqueued.
  final DateTime queuedAt;

  /// Creates a pending mutation record.
  const PendingMutationRecord({
    required this.id,
    required this.key,
    required this.seq,
    required this.payload,
    required this.queuedAt,
  });

  @override
  String toString() {
    return 'PendingMutationRecord(id: $id, key: $key, seq: $seq)';
  }
}
