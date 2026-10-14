/// Base exception class for all Syncache-related errors.
///
/// This exception wraps errors that occur during cache operations,
/// network fetches, or sync queue processing.
///
/// Example:
/// ```dart
/// try {
///   await cache.get(key: 'user:1', fetch: fetchUser);
/// } on SyncacheException catch (e) {
///   print('Cache error: ${e.message}');
///   if (e.cause != null) {
///     print('Caused by: ${e.cause}');
///   }
/// }
/// ```
class SyncacheException implements Exception {
  /// A human-readable description of the error.
  final String message;

  /// The underlying cause of this exception, if any.
  ///
  /// This may contain the original exception that triggered this error,
  /// useful for debugging and error reporting.
  final Object? cause;

  /// Creates a [SyncacheException] with the given [message] and optional [cause].
  const SyncacheException(this.message, [this.cause]);

  @override
  String toString() => 'SyncacheException: $message';
}

/// Thrown when a cache lookup fails to find a value for the requested key.
///
/// This exception is thrown in scenarios where cached data is required
/// but not available:
/// - Using [Policy.cacheOnly] when the key doesn't exist
/// - Using [Policy.offlineFirst] when offline with no cached data
/// - Attempting to `mutate()` a key that hasn't been cached
///
/// Example:
/// ```dart
/// try {
///   await cache.get(key: 'missing', fetch: fetcher, policy: Policy.cacheOnly);
/// } on CacheMissException catch (e) {
///   print('No cached data available');
/// }
/// ```
class CacheMissException extends SyncacheException {
  /// Creates a [CacheMissException] for the given [key].
  const CacheMissException(String key) : super('No cached value for key: $key');
}

/// Thrown by a mutation's [Mutation.send] when the server reports that the
/// resource changed concurrently — typically an HTTP 409, or any response
/// that carries the server's current state alongside a version/etag
/// mismatch.
///
/// Syncache never plain-retries a conflict (the same request would just
/// conflict again). Instead it hands both versions to the configured
/// [ConflictResolver] — the one passed per call via
/// `mutate(conflictResolver: ...)`, or the cache-wide default — stores the
/// resolved value, and settles the mutation's [MutationHandle] with a
/// [MutationResolved] outcome. Without any resolver the mutation fails
/// immediately (still without retrying).
///
/// ## Throwing one from `send`
///
/// Surface the server's version/etag in the request, then throw this
/// exception with the server's current state when it rejects the write:
///
/// ```dart
/// final handle = await cache.mutate(
///   key: 'user:123',
///   conflictResolver: clientWins<User>(),
///   mutation: Mutation<User>(
///     apply: (user) => user.copyWith(name: 'New Name'),
///     send: (user) async {
///       final response = await api.updateUser(
///         user.id,
///         user,
///         ifMatch: user.etag, // precondition: server checks its version
///       );
///       if (response.statusCode == 409) {
///         // The body carries the server's current state — hand it to
///         // Syncache so the resolver can merge against it.
///         throw SyncacheConflictException<User>(
///           User.fromJson(response.body),
///         );
///       }
///       return User.fromJson(response.body);
///     },
///   ),
/// );
/// ```
///
/// The type argument must match the cache's value type: the mutation queue
/// recognizes conflicts via `is SyncacheConflictException<T>` for its own
/// `T`, so a differently-typed conflict exception is treated as an ordinary
/// send failure (and would be retried).
class SyncacheConflictException<T> extends SyncacheException {
  /// The server's current state of the resource, as extracted from the
  /// conflict response. Passed to [ConflictResolver.resolve] as
  /// `serverValue`.
  final T serverValue;

  /// Creates a conflict exception carrying the [serverValue]. The optional
  /// [message] defaults to a generic conflict description; [cause] can hold
  /// the original response or error for diagnostics.
  const SyncacheConflictException(
    this.serverValue, {
    String? message,
    Object? cause,
  }) : super(
          message ??
              'The server rejected the mutation because the resource changed '
                  'concurrently.',
          cause,
        );

  @override
  String toString() =>
      'SyncacheConflictException<$T>: $message (serverValue: $serverValue)';
}
