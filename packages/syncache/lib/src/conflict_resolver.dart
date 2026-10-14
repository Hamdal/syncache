import 'mutation.dart';

/// Decides the final value of a mutation whose [Mutation.send] threw a
/// [SyncacheConflictException] (typically an HTTP 409 with the server's
/// current state).
///
/// Conflicts are not transient errors: retrying the same send would just
/// conflict again. Instead, Syncache hands both versions to the configured
/// resolver and stores whatever it returns — the mutation is settled (not
/// retried) and its outbox record, if any, is removed.
///
/// A resolver can be installed per call (`Syncache.mutate` /
/// `ScopedSyncache.mutate` accept `conflictResolver:`) or as a cache-wide
/// default (`Syncache(conflictResolver: ...)`). The per-call resolver wins.
///
/// ## Example
///
/// ```dart
/// class MergeRename implements ConflictResolver<Document> {
///   @override
///   Future<Document> resolve({
///     required Document optimisticValue,
///     required Document serverValue,
///     required Map<String, Object?>? payload,
///   }) async {
///     // Keep the server's title, re-apply only our rename on top.
///     return serverValue.copyWith(title: optimisticValue.title);
///   }
/// }
///
/// final cache = Syncache<Document>(
///   store: store,
///   conflictResolver: MergeRename(),
/// );
/// ```
abstract class ConflictResolver<T> {
  /// Resolves a conflict between the local optimistic write and the
  /// server's current state.
  ///
  /// - [optimisticValue]: the local, unsynced intent — what [Mutation.apply]
  ///   produced (or what the replayed snapshot decoded to).
  /// - [serverValue]: the value carried by the
  ///   [SyncacheConflictException] — the server's current state at the time
  ///   it rejected the write.
  /// - [payload]: the JSON-safe payload passed to `mutate(payload: ...)`,
  ///   when any. Useful for resolvers that need to know *what* changed
  ///   rather than diffing whole objects.
  ///
  /// The returned value replaces the conflicted optimistic value in the
  /// cache and mutations queued behind it are re-applied on top of it.
  ///
  /// Throwing from here fails the mutation with a [MutationFailure] —
  /// resolver errors are terminal, never retried.
  Future<T> resolve({
    required T optimisticValue,
    required T serverValue,
    required Map<String, Object?>? payload,
  });
}

/// A [ConflictResolver] that keeps the server's value: the local optimistic
/// write is dropped and the cache is refreshed with [ConflictResolver.resolve]'s
/// `serverValue`.
///
/// The safest default when the server is authoritative (e.g. inventory
/// counts, server-generated fields).
///
/// ```dart
/// final cache = Syncache<Cart>(
///   store: store,
///   conflictResolver: serverWins<Cart>(),
/// );
/// ```
ConflictResolver<T> serverWins<T>() => _ServerWins<T>();

/// A [ConflictResolver] that keeps the client's optimistic value: the local
/// unsynced intent wins and is stored over the server's state.
///
/// ```dart
/// final cache = Syncache<Draft>(
///   store: store,
///   conflictResolver: clientWins<Draft>(),
/// );
/// ```
///
/// Note that `optimisticValue` was computed against the *pre-conflict* base.
/// To re-base the client's change on top of the server state instead,
/// write a custom resolver (e.g. `serverValue.copyWith(done:
/// optimisticValue.done)` for a single-field flip).
ConflictResolver<T> clientWins<T>() => _ClientWins<T>();

class _ServerWins<T> implements ConflictResolver<T> {
  @override
  Future<T> resolve({
    required T optimisticValue,
    required T serverValue,
    required Map<String, Object?>? payload,
  }) async =>
      serverValue;
}

class _ClientWins<T> implements ConflictResolver<T> {
  @override
  Future<T> resolve({
    required T optimisticValue,
    required T serverValue,
    required Map<String, Object?>? payload,
  }) async =>
      optimisticValue;
}
