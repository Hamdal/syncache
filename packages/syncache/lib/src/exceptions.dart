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
/// - Attempting to [mutate] a key that hasn't been cached
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
