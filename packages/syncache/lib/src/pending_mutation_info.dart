/// Information about a pending mutation in the sync queue.
///
/// Provides details about a mutation that is waiting to be synced
/// to the server, including retry information and error state.
/// Useful for displaying sync status indicators in the UI.
///
/// Example:
/// ```dart
/// cache.pendingMutationsStream.listen((mutations) {
///   setState(() {
///     pendingCount = mutations.length;
///     isSyncing = mutations.any((m) => m.status == PendingMutationStatus.syncing);
///   });
/// });
/// ```
class PendingMutationInfo {
  /// Unique identifier for this mutation.
  final String id;

  /// The cache key this mutation affects.
  final String key;

  /// Number of retry attempts made (0 = not yet retried).
  final int retryCount;

  /// When this mutation was added to the queue.
  final DateTime queuedAt;

  /// When the last sync attempt was made.
  ///
  /// `null` if no attempt has been made yet.
  final DateTime? lastAttemptAt;

  /// The error from the last failed attempt.
  ///
  /// `null` if no attempt has failed.
  final Object? lastError;

  /// Current status of this mutation.
  final PendingMutationStatus status;

  /// Creates a [PendingMutationInfo] instance.
  const PendingMutationInfo({
    required this.id,
    required this.key,
    required this.retryCount,
    required this.queuedAt,
    this.lastAttemptAt,
    this.lastError,
    required this.status,
  });

  @override
  String toString() {
    return 'PendingMutationInfo(id: $id, key: $key, status: $status, retryCount: $retryCount)';
  }
}

/// Status of a pending mutation.
enum PendingMutationStatus {
  /// Mutation is waiting in the queue.
  pending,

  /// Mutation is currently being sent to the server.
  syncing,

  /// Mutation failed and will be retried.
  retrying,

  /// Mutation exceeded retry limit and will be removed.
  failed,
}
