import 'dart:async';

/// The terminal outcome of a submitted optimistic mutation.
///
/// Obtain an outcome through [MutationHandle.outcome] and destructure it
/// with a switch expression:
///
/// ```dart
/// final handle = await cache.mutate(
///   key: 'user:123',
///   mutation: Mutation<User>(...),
/// );
///
/// switch (await handle.outcome) {
///   case MutationSuccess(:final serverValue):
///     print('Server confirmed: $serverValue');
///   case MutationResolved(:final resolvedValue, :final wasConflict):
///     print('A conflict was resolved to: $resolvedValue');
///   case MutationFailure(:final error, :final retried):
///     print('Gave up after $retried retries: $error');
///   case MutationDiscarded():
///     print('Removed from the queue before syncing');
/// }
/// ```
sealed class MutationOutcome<T> {
  const MutationOutcome();
}

/// The server accepted the mutation.
class MutationSuccess<T> extends MutationOutcome<T> {
  /// The value confirmed by the server — the result of
  /// [Mutation.send]. This is the value that replaced the optimistic
  /// value in the cache.
  final T serverValue;

  const MutationSuccess(this.serverValue);

  @override
  String toString() => 'MutationSuccess($serverValue)';
}

/// The mutation exhausted its retry attempts and was removed from the
/// queue. The optimistic value remains in the cache until the entry is
/// refetched or invalidated.
class MutationFailure<T> extends MutationOutcome<T> {
  /// The error from the last failed send attempt.
  final Object error;

  /// The stack trace of the last failed send attempt.
  final StackTrace stackTrace;

  /// How many retry attempts were made after the initial failure
  /// (0 when the very first attempt failed and retries were disabled).
  final int retried;

  const MutationFailure({
    required this.error,
    required this.stackTrace,
    required this.retried,
  });

  @override
  String toString() => 'MutationFailure(error: $error, retried: $retried)';
}

/// The mutation was removed from the queue before the server confirmed it:
/// via [Syncache.clearPendingMutations], [Syncache.removePendingMutation],
/// or [Syncache.dispose].
///
/// Note: if the mutation was already in flight when it was removed, the
/// request may still have reached the server — discarding only guarantees
/// that Syncache stopped tracking it.
class MutationDiscarded<T> extends MutationOutcome<T> {
  const MutationDiscarded();

  @override
  String toString() => 'MutationDiscarded()';
}

/// The mutation hit a server-side conflict ([SyncacheConflictException]
/// thrown from [Mutation.send]) and the configured [ConflictResolver]
/// produced the final value.
///
/// The mutation is **not** retried and its outbox record is removed: the
/// conflict is considered settled. [resolvedValue] is what the resolver
/// returned — it (with any mutations queued behind it re-applied) is the
/// value now in the cache.
///
/// ```dart
/// switch (await handle.outcome) {
///   case MutationResolved(:final resolvedValue):
///     print('Merged; final value: $resolvedValue');
///   case MutationSuccess():
///     // ...
/// }
/// ```
class MutationResolved<T> extends MutationOutcome<T> {
  /// The value produced by the [ConflictResolver] for this mutation.
  final T resolvedValue;

  /// Whether this outcome originates from a conflict. Syncache only settles
  /// [MutationResolved] for resolved conflicts today, so this is always
  /// `true`; the flag keeps outcome handling uniform for future resolution
  /// paths.
  final bool wasConflict;

  const MutationResolved(this.resolvedValue, {this.wasConflict = true});

  @override
  String toString() =>
      'MutationResolved($resolvedValue, wasConflict: $wasConflict)';
}

/// A handle for awaiting the server-side outcome of one specific mutation.
///
/// Returned by [Syncache.mutate]. The optimistic update is applied before
/// the handle is returned (as before); awaiting [outcome] waits until the
/// server confirmed the mutation, its retries were exhausted, or it was
/// discarded.
///
/// ```dart
/// final handle = await cache.mutate(
///   key: 'todo:1',
///   mutation: Mutation<Todo>(...),
/// );
/// // The optimistic value is already visible here.
///
/// final outcome = await handle.outcome;
/// if (outcome is MutationSuccess<Todo>) {
///   navigateWithConfirmed(outcome.serverValue);
/// }
/// ```
class MutationHandle<T> {
  final Completer<MutationOutcome<T>> _completer;

  /// Internal: creates a handle backed by `completer`. Called by the
  /// mutation queue when a mutation is submitted — application code should
  /// only ever *receive* handles from `Syncache.mutate`.
  const MutationHandle.fromCompleter(this._completer);

  /// Resolves when the mutation reaches a terminal outcome:
  /// [MutationSuccess], [MutationResolved], [MutationFailure], or
  /// [MutationDiscarded].
  ///
  /// The future never errors — failures are delivered as
  /// [MutationFailure] outcomes. It also never times out: a mutation that
  /// stays queued offline keeps the future pending until it is processed,
  /// removed, or the cache is disposed.
  Future<MutationOutcome<T>> get outcome => _completer.future;

  /// Whether the mutation has reached a terminal outcome.
  bool get isSettled => _completer.isCompleted;

  @override
  String toString() => isSettled
      ? 'MutationHandle(settled: ${_completer.future})'
      : 'MutationHandle(pending)';
}
