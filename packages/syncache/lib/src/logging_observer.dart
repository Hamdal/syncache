import 'observer.dart';

/// A function that outputs a log message.
///
/// Use this typedef to provide a custom logging implementation
/// to [LoggingObserver].
typedef LogFunction = void Function(String message);

/// A [SyncacheObserver] that logs cache operations.
///
/// Useful for debugging and development. Logs include timestamps
/// for easy reading.
///
/// ## Example with default print
///
/// ```dart
/// final cache = Syncache<User>(
///   store: MemoryStore(),
///   observers: [LoggingObserver()],
/// );
/// ```
///
/// ## Example with custom logger
///
/// ```dart
/// final cache = Syncache<User>(
///   store: MemoryStore(),
///   observers: [
///     LoggingObserver(
///       log: (message) => logger.debug(message),
///     ),
///   ],
/// );
/// ```
///
/// ## Flutter apps
///
/// The default log function uses [print], which is right for pure Dart.
/// In Flutter, route the output through `debugPrint` so logs are batched
/// and never dropped by the platform logger on high-traffic caches:
///
/// ```dart
/// import 'package:syncache_flutter/syncache_flutter.dart';
///
/// final cache = Syncache<User>(
///   store: MemoryStore(),
///   observers: [
///     LoggingObserver(log: syncacheDebugLog, verbose: false),
///   ],
/// );
/// ```
///
/// With [verbose] set to `false`, only high-signal events are logged
/// (misses, fetch outcomes, invalidations, mutations, retries, errors);
/// the per-operation chatter (`CACHE HIT`, `STORE`, `FETCH START`) is
/// suppressed.
///
/// ## Output Format
///
/// ```
/// [Syncache] 12:34:56.789 CACHE HIT: user:123
/// [Syncache] 12:34:56.790 FETCH START: user:456
/// [Syncache] 12:34:57.123 FETCH SUCCESS: user:456 (333ms)
/// [Syncache] 12:34:57.200 FETCH ERROR: user:789 - Connection timeout
/// ```
class LoggingObserver extends SyncacheObserver {
  /// Whether to include stack traces in error logs.
  final bool includeStackTrace;

  /// Optional prefix for all log messages.
  final String prefix;

  /// Whether to log high-frequency per-operation events.
  ///
  /// When `true` (the default), every observed event is logged. When
  /// `false`, the chatty events (`CACHE HIT`, `STORE`, `FETCH START`) are
  /// suppressed so the log stays readable on hot caches; everything else
  /// (misses, fetch success/error/cancel, invalidations, clears,
  /// mutations, retries) is still logged.
  final bool verbose;

  /// The logging function to use for output.
  ///
  /// Defaults to [print] if not provided. Flutter apps should prefer
  /// `syncacheDebugLog` (from `package:syncache_flutter`), which wraps
  /// Flutter's `debugPrint`.
  final LogFunction log;

  /// Creates a logging observer.
  ///
  /// Set [includeStackTrace] to `true` to log full stack traces on errors.
  /// The [prefix] defaults to `'Syncache'` but can be customized.
  /// Provide [log] to use a custom logging function instead of [print].
  /// Set [verbose] to `false` to suppress high-frequency events.
  LoggingObserver({
    this.includeStackTrace = false,
    this.prefix = 'Syncache',
    this.verbose = true,
    LogFunction? log,
  }) : log = log ?? print;

  void _log(String level, String message) {
    final timestamp = _formatTime(DateTime.now());
    log('[$prefix] $timestamp $level: $message');
  }

  /// Logs only when [verbose] is enabled; used for high-frequency events.
  void _logVerbose(String level, String message) {
    if (!verbose) return;
    _log(level, message);
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    final ms = time.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  @override
  void onCacheHit(String key) {
    _logVerbose('CACHE HIT', key);
  }

  @override
  void onCacheMiss(String key) {
    _log('CACHE MISS', key);
  }

  @override
  void onFetchStart(String key) {
    _logVerbose('FETCH START', key);
  }

  @override
  void onFetchSuccess(String key, Duration duration) {
    _log('FETCH SUCCESS', '$key (${duration.inMilliseconds}ms)');
  }

  @override
  void onFetchError(String key, Object error, StackTrace stackTrace) {
    _log('FETCH ERROR', '$key - $error');
    if (includeStackTrace) {
      log(stackTrace.toString());
    }
  }

  @override
  void onInvalidate(String key) {
    _log('INVALIDATE', key);
  }

  @override
  void onClear() {
    _log('CLEAR', 'all entries');
  }

  @override
  void onMutationStart(String key) {
    _log('MUTATION START', key);
  }

  @override
  void onMutationSuccess(String key) {
    _log('MUTATION SUCCESS', key);
  }

  @override
  void onMutationError(String key, Object error, StackTrace stackTrace) {
    _log('MUTATION ERROR', '$key - $error');
    if (includeStackTrace) {
      log(stackTrace.toString());
    }
  }

  @override
  void onStore(String key) {
    _logVerbose('STORE', key);
  }

  @override
  void onEvict(String key) {
    _log('EVICT', key);
  }

  @override
  void onRetry(String key, int attempt, Object error, Duration delay) {
    _log('RETRY',
        '$key - attempt ${attempt + 1}, retrying in ${delay.inMilliseconds}ms');
  }

  @override
  void onRetryExhausted(String key, int totalAttempts, Object finalError) {
    _log('RETRY EXHAUSTED', '$key - failed after $totalAttempts attempts');
  }

  @override
  void onFetchCancelled(String key) {
    _log('FETCH CANCELLED', key);
  }

  @override
  void onMutationRetry(String key, int attempt, Object error, Duration delay) {
    _log('MUTATION RETRY',
        '$key - attempt ${attempt + 1}, retrying in ${delay.inMilliseconds}ms');
  }

  @override
  void onMutationRetryExhausted(
      String key, int totalAttempts, Object finalError) {
    _log('MUTATION RETRY EXHAUSTED',
        '$key - failed after $totalAttempts attempts');
  }

  @override
  void onMutationConflict(String key, Object error) {
    _log('MUTATION CONFLICT', '$key - $error');
  }

  @override
  void onMutationResolved(String key) {
    _log('MUTATION RESOLVED', key);
  }
}
