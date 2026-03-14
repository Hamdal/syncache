/// Metadata associated with a cached entry.
///
/// [Metadata] tracks versioning, timing, and HTTP caching information
/// for each cached value. This enables features like TTL-based expiration
/// and conditional HTTP requests.
///
/// Example:
/// ```dart
/// final meta = Metadata(
///   version: 1,
///   storedAt: DateTime.now(),
///   ttl: Duration(minutes: 5),
///   etag: '"abc123"',
/// );
///
/// if (meta.isExpired) {
///   // Refresh the cache
/// }
/// ```
class Metadata {
  /// The version number of this cache entry.
  ///
  /// Incremented each time the entry is updated, useful for
  /// conflict detection in optimistic mutations.
  final int version;

  /// When this entry was stored in the cache.
  final DateTime storedAt;

  /// Optional time-to-live duration.
  ///
  /// If set, the entry is considered expired after [storedAt] + [ttl].
  /// A null value means the entry never expires based on time.
  final Duration? ttl;

  /// Optional HTTP ETag for conditional requests.
  ///
  /// When present, Syncache includes an `If-None-Match` header
  /// in subsequent fetch requests.
  final String? etag;

  /// Optional last-modified timestamp for conditional requests.
  ///
  /// When present, Syncache includes an `If-Modified-Since` header
  /// in subsequent fetch requests.
  final DateTime? lastModified;

  /// Creates a [Metadata] instance.
  ///
  /// The [version] and [storedAt] parameters are required.
  /// Other parameters are optional and support HTTP caching semantics.
  const Metadata({
    required this.version,
    required this.storedAt,
    this.ttl,
    this.etag,
    this.lastModified,
  });

  /// Whether this entry has expired based on its [ttl].
  ///
  /// Returns `false` if no [ttl] is set (entry never expires).
  /// Otherwise, returns `true` if the current time is past [storedAt] + [ttl].
  bool get isExpired {
    if (ttl == null) return false;
    return DateTime.now().isAfter(storedAt.add(ttl!));
  }

  /// Creates a copy of this metadata with the given fields replaced.
  Metadata copyWith({
    int? version,
    DateTime? storedAt,
    Duration? ttl,
    String? etag,
    DateTime? lastModified,
  }) {
    return Metadata(
      version: version ?? this.version,
      storedAt: storedAt ?? this.storedAt,
      ttl: ttl ?? this.ttl,
      etag: etag ?? this.etag,
      lastModified: lastModified ?? this.lastModified,
    );
  }
}
