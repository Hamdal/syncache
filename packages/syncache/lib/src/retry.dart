/// Configuration for retry behavior on transient failures.
///
/// Use [RetryConfig] to specify how [Syncache] should handle failed
/// network requests, including the number of retry attempts, delay
/// strategy, and which errors should trigger retries.
///
/// ## Example
///
/// ```dart
/// // Default exponential backoff: 200ms, 400ms, 800ms...
/// final config = RetryConfig();
///
/// // Custom configuration
/// final customConfig = RetryConfig(
///   maxAttempts: 5,
///   delay: (attempt) => Duration(seconds: attempt),
///   retryIf: (error) => error is SocketException,
/// );
///
/// // Disable retries
/// final noRetry = RetryConfig.none;
/// ```
///
/// ## Usage with Syncache
///
/// ```dart
/// final value = await cache.get(
///   key: 'data',
///   fetch: fetchData,
///   retry: RetryConfig(maxAttempts: 3),
/// );
/// ```
class RetryConfig {
  /// Maximum number of retry attempts after the initial request fails.
  ///
  /// For example, `maxAttempts: 3` means up to 4 total attempts
  /// (1 initial + 3 retries).
  ///
  /// Defaults to 3.
  final int maxAttempts;

  /// Function that calculates the delay before each retry attempt.
  ///
  /// The [attempt] parameter is 0-indexed (0 for first retry, 1 for second, etc.).
  ///
  /// Defaults to exponential backoff: 200ms * 2^attempt
  /// (200ms, 400ms, 800ms, 1600ms, ...).
  final Duration Function(int attempt) delay;

  /// Optional predicate to determine if an error should trigger a retry.
  ///
  /// If null (default), all errors trigger retries.
  /// If provided, only errors where `retryIf(error)` returns true
  /// will be retried.
  ///
  /// Example:
  /// ```dart
  /// retryIf: (error) => error is SocketException || error is TimeoutException
  /// ```
  final bool Function(Object error)? retryIf;

  /// Creates a retry configuration.
  ///
  /// - [maxAttempts]: Number of retries after initial failure (default: 3)
  /// - [delay]: Function to calculate delay for each attempt (default: exponential backoff)
  /// - [retryIf]: Optional predicate to filter which errors trigger retries
  const RetryConfig({
    this.maxAttempts = 3,
    this.delay = defaultDelay,
    this.retryIf,
  });

  /// Default exponential backoff delay: 200ms * 2^attempt.
  ///
  /// - Attempt 0: 200ms
  /// - Attempt 1: 400ms
  /// - Attempt 2: 800ms
  /// - Attempt 3: 1600ms
  /// - ...
  static Duration defaultDelay(int attempt) {
    return Duration(milliseconds: 200 * (1 << attempt));
  }

  /// Configuration that disables retries entirely.
  ///
  /// Use this when you want a single attempt with no retries.
  static const none = RetryConfig(maxAttempts: 0);

  /// Whether retries are enabled for this configuration.
  bool get enabled => maxAttempts > 0;

  /// Determines if the given [error] should trigger a retry.
  ///
  /// Returns true if [retryIf] is null or if `retryIf(error)` returns true.
  bool shouldRetry(Object error) {
    return retryIf?.call(error) ?? true;
  }
}

/// Configuration for mutation retry behavior.
///
/// Use [MutationRetryConfig] to control how failed mutations are retried
/// and when they should be removed from the queue.
///
/// ## Example
///
/// ```dart
/// final cache = Syncache<User>(
///   store: MemoryStore<User>(),
///   mutationRetry: MutationRetryConfig(
///     maxAttempts: 5,
///     delay: (attempt) => Duration(seconds: attempt * 2),
///   ),
/// );
/// ```
class MutationRetryConfig {
  /// Maximum number of retry attempts after the initial request fails.
  ///
  /// For example, `maxAttempts: 3` means up to 4 total attempts
  /// (1 initial + 3 retries). After exhausting all attempts, the
  /// mutation is removed from the queue.
  ///
  /// Defaults to 3.
  final int maxAttempts;

  /// Function that calculates the delay before each retry attempt.
  ///
  /// The [attempt] parameter is 0-indexed (0 for first retry, 1 for second, etc.).
  ///
  /// Defaults to exponential backoff: 1s * 2^attempt
  /// (1s, 2s, 4s, 8s, ...).
  final Duration Function(int attempt) delay;

  /// Optional predicate to determine if an error should trigger a retry.
  ///
  /// If null (default), all errors trigger retries.
  /// If provided, only errors where `retryIf(error)` returns true
  /// will be retried. Non-retryable errors cause the mutation to be
  /// removed immediately.
  final bool Function(Object error)? retryIf;

  /// Creates a mutation retry configuration.
  const MutationRetryConfig({
    this.maxAttempts = 3,
    this.delay = defaultDelay,
    this.retryIf,
  });

  /// Default exponential backoff delay: 1s * 2^attempt.
  static Duration defaultDelay(int attempt) {
    return Duration(seconds: 1 << attempt);
  }

  /// Configuration that disables retries entirely.
  ///
  /// Use this when you want a single attempt with no retries.
  /// Failed mutations will be removed immediately.
  static const none = MutationRetryConfig(maxAttempts: 0);

  /// Determines if the given [error] should trigger a retry.
  bool shouldRetry(Object error) {
    return retryIf?.call(error) ?? true;
  }
}
