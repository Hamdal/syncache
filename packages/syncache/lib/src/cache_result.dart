/// A cache result containing a value and its metadata.
///
/// [CacheResult] wraps a cached value with information about whether
/// the data came from cache, its freshness, and when it was stored.
/// This enables UI to show stale indicators and age information.
///
/// Example:
/// ```dart
/// final result = await cache.getWithMeta(
///   key: 'user:123',
///   fetch: fetchUser,
/// );
///
/// updateUI(result.value);
///
/// if (result.meta.isStale) {
///   showStaleDataBanner();
/// }
///
/// if (result.meta.age != null && result.meta.age! > Duration(hours: 1)) {
///   showOldDataWarning();
/// }
/// ```
class CacheResult<T> {
  /// The cached or fetched value.
  final T value;

  /// Metadata about the cache entry.
  final CacheResultMeta meta;

  /// Creates a [CacheResult] with the given [value] and [meta].
  const CacheResult({required this.value, required this.meta});
}

/// Metadata about a cache result's source and freshness.
///
/// Provides information about whether data came from cache,
/// whether it's stale, and when it was stored. Useful for
/// displaying sync indicators and data freshness in the UI.
class CacheResultMeta {
  /// Whether the data came from cache (vs fresh fetch).
  ///
  /// `true` if the value was retrieved from the local cache,
  /// `false` if it was freshly fetched from the network.
  final bool isFromCache;

  /// Whether the cached data has expired based on TTL.
  ///
  /// `true` if the cache entry's TTL has expired,
  /// `false` if the data is still fresh or has no TTL.
  final bool isStale;

  /// When the data was stored in cache.
  ///
  /// `null` if the data was freshly fetched and not yet stored,
  /// or if metadata is not available.
  final DateTime? storedAt;

  /// Cache entry version number.
  ///
  /// Incremented each time the cache entry is updated.
  final int version;

  /// Creates a [CacheResultMeta] instance.
  const CacheResultMeta({
    required this.isFromCache,
    required this.isStale,
    this.storedAt,
    required this.version,
  });

  /// Age of the cached data since it was stored.
  ///
  /// Returns `null` if [storedAt] is not available.
  Duration? get age =>
      storedAt != null ? DateTime.now().difference(storedAt!) : null;

  /// Creates metadata for a fresh fetch result.
  factory CacheResultMeta.fresh({required int version, DateTime? storedAt}) {
    return CacheResultMeta(
      isFromCache: false,
      isStale: false,
      storedAt: storedAt,
      version: version,
    );
  }

  /// Creates metadata for a cache hit result.
  factory CacheResultMeta.fromCache({
    required bool isStale,
    required DateTime storedAt,
    required int version,
  }) {
    return CacheResultMeta(
      isFromCache: true,
      isStale: isStale,
      storedAt: storedAt,
      version: version,
    );
  }
}
