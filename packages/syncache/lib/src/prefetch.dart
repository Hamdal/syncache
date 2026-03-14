import 'fetcher.dart';
import 'policy.dart';
import 'retry.dart';

/// A request to prefetch a cache entry.
///
/// Example:
/// ```dart
/// await cache.prefetch([
///   PrefetchRequest(key: 'user:123', fetch: fetchUser),
///   PrefetchRequest(key: 'settings', fetch: fetchSettings, ttl: Duration(hours: 1)),
/// ]);
/// ```
class PrefetchRequest<T> {
  final String key;
  final Fetcher<T> fetch;
  final Duration? ttl;

  /// Defaults to [Policy.refresh] to always fetch fresh data.
  final Policy policy;

  /// If null, uses the cache's [defaultRetry] setting.
  final RetryConfig? retry;

  const PrefetchRequest({
    required this.key,
    required this.fetch,
    this.ttl,
    this.policy = Policy.refresh,
    this.retry,
  });
}

/// Result of a single prefetch operation.
class PrefetchResult {
  final String key;
  final bool success;
  final Object? error;
  final StackTrace? stackTrace;

  const PrefetchResult._({
    required this.key,
    required this.success,
    this.error,
    this.stackTrace,
  });

  const PrefetchResult.success(String key) : this._(key: key, success: true);

  const PrefetchResult.failure(String key, Object error, StackTrace stackTrace)
      : this._(key: key, success: false, error: error, stackTrace: stackTrace);

  @override
  String toString() {
    if (success) {
      return 'PrefetchResult.success($key)';
    }
    return 'PrefetchResult.failure($key, $error)';
  }
}

/// A node in a prefetch dependency graph.
///
/// Example:
/// ```dart
/// // Profile must load before settings; notifications runs in parallel
/// final result = await cache.prefetchGraph([
///   PrefetchNode(key: 'user:profile', fetch: fetchProfile),
///   PrefetchNode(key: 'user:settings', fetch: fetchSettings, dependsOn: ['user:profile']),
///   PrefetchNode(key: 'notifications', fetch: fetchNotifications),
/// ]);
/// ```
class PrefetchNode<T> {
  final String key;
  final Fetcher<T> fetch;
  final Duration? ttl;

  /// Defaults to [Policy.refresh].
  final Policy policy;
  final RetryConfig? retry;

  /// Keys that must complete before this node can execute.
  final List<String> dependsOn;

  const PrefetchNode({
    required this.key,
    required this.fetch,
    this.ttl,
    this.policy = Policy.refresh,
    this.retry,
    this.dependsOn = const [],
  });
}

/// Options for controlling prefetch graph execution.
class PrefetchGraphOptions {
  /// Stop executing when any node fails. In-flight nodes continue to completion.
  final bool failFast;

  /// Skip nodes whose dependencies failed (prevents cascading failures).
  final bool skipOnDependencyFailure;

  const PrefetchGraphOptions({
    this.failFast = false,
    this.skipOnDependencyFailure = true,
  });

  static const PrefetchGraphOptions defaults = PrefetchGraphOptions();
}

/// Result of a prefetch graph execution.
class PrefetchGraphResult {
  final Map<String, PrefetchNodeResult> results;
  final Duration totalDuration;

  const PrefetchGraphResult({
    required this.results,
    required this.totalDuration,
  });

  bool get allSucceeded => results.values.every((r) => r.success);
  bool get anySucceeded => results.values.any((r) => r.success);

  List<String> get failedKeys => results.entries
      .where((e) => e.value.status == PrefetchNodeStatus.failed)
      .map((e) => e.key)
      .toList();

  List<String> get skippedKeys => results.entries
      .where((e) => e.value.status == PrefetchNodeStatus.skipped)
      .map((e) => e.key)
      .toList();

  List<String> get succeededKeys =>
      results.entries.where((e) => e.value.success).map((e) => e.key).toList();

  PrefetchNodeResult? operator [](String key) => results[key];

  @override
  String toString() {
    final succeeded = succeededKeys.length;
    final failed = failedKeys.length;
    final skipped = skippedKeys.length;
    return 'PrefetchGraphResult(succeeded: $succeeded, failed: $failed, '
        'skipped: $skipped, duration: ${totalDuration.inMilliseconds}ms)';
  }
}

enum PrefetchNodeStatus {
  success,
  failed,
  skipped,
}

/// Result of a single node in a prefetch graph.
class PrefetchNodeResult {
  final String key;
  final PrefetchNodeStatus status;
  final Object? error;
  final StackTrace? stackTrace;

  /// Null if skipped.
  final Duration? duration;

  const PrefetchNodeResult._({
    required this.key,
    required this.status,
    this.error,
    this.stackTrace,
    this.duration,
  });

  bool get success => status == PrefetchNodeStatus.success;
  bool get skipped => status == PrefetchNodeStatus.skipped;

  const PrefetchNodeResult.success(String key, Duration duration)
      : this._(
          key: key,
          status: PrefetchNodeStatus.success,
          duration: duration,
        );

  const PrefetchNodeResult.failure(
    String key,
    Object error,
    StackTrace stackTrace,
    Duration duration,
  ) : this._(
          key: key,
          status: PrefetchNodeStatus.failed,
          error: error,
          stackTrace: stackTrace,
          duration: duration,
        );

  const PrefetchNodeResult.skipped(String key, String reason)
      : this._(
          key: key,
          status: PrefetchNodeStatus.skipped,
          error: reason,
        );

  @override
  String toString() {
    switch (status) {
      case PrefetchNodeStatus.success:
        return 'PrefetchNodeResult.success($key, ${duration?.inMilliseconds}ms)';
      case PrefetchNodeStatus.failed:
        return 'PrefetchNodeResult.failure($key, $error)';
      case PrefetchNodeStatus.skipped:
        return 'PrefetchNodeResult.skipped($key, $error)';
    }
  }
}
