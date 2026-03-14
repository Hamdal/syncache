/// A structured cache key with encoded parameters.
///
/// [QueryKey] provides a consistent format for cache keys that include
/// parameters, ensuring:
/// - Consistent key format across the codebase
/// - Parameters are sorted for cache key stability
/// - Easy pattern-based invalidation
///
/// Example:
/// ```dart
/// final key = QueryKey('calendar/events', {
///   'month': '2024-03',
///   'workspace': 123,
/// });
/// // Produces: 'calendar/events?month=2024-03&workspace=123'
///
/// // Invalidate all calendar/events regardless of params
/// await cache.invalidatePattern('calendar/events?*');
/// ```
class QueryKey {
  /// The base path for this key.
  final String base;

  /// The parameters for this key.
  final Map<String, dynamic> params;

  /// Creates a [QueryKey] with the given [base] and optional [params].
  const QueryKey(this.base, [this.params = const {}]);

  /// Encodes to a consistent string format.
  ///
  /// Parameters are sorted alphabetically by key for cache key stability.
  /// Returns just the base if there are no parameters.
  String get encoded {
    if (params.isEmpty) return base;
    final sorted = params.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final paramStr = sorted.map((e) => '${e.key}=${e.value}').join('&');
    return '$base?$paramStr';
  }

  /// Creates a glob pattern that matches any params.
  ///
  /// Useful for invalidating all entries with this base key.
  String get pattern => '$base?*';

  /// Creates a pattern that matches just the base (no params).
  String get basePattern => base;

  @override
  String toString() => encoded;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! QueryKey) return false;
    return encoded == other.encoded;
  }

  @override
  int get hashCode => encoded.hashCode;

  /// Creates a new [QueryKey] with additional or replaced parameters.
  QueryKey copyWith({
    String? base,
    Map<String, dynamic>? params,
  }) {
    return QueryKey(
      base ?? this.base,
      params ?? this.params,
    );
  }

  /// Creates a new [QueryKey] with merged parameters.
  ///
  /// New parameters override existing ones with the same key.
  QueryKey merge(Map<String, dynamic> additionalParams) {
    return QueryKey(base, {...params, ...additionalParams});
  }
}

/// Extension on String to create QueryKey from string.
extension QueryKeyStringExtension on String {
  /// Converts a string to a QueryKey.
  ///
  /// If the string contains a '?', it parses the query parameters.
  /// Otherwise, creates a QueryKey with just the base.
  QueryKey toQueryKey() {
    final parts = split('?');
    if (parts.length == 1) {
      return QueryKey(this);
    }
    final base = parts[0];
    final paramStr = parts.sublist(1).join('?');
    final params = <String, dynamic>{};
    for (final pair in paramStr.split('&')) {
      final kv = pair.split('=');
      if (kv.length == 2) {
        params[kv[0]] = kv[1];
      }
    }
    return QueryKey(base, params);
  }
}
