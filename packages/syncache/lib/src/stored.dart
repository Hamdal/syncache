import 'metadata.dart';

/// A cached value with its associated metadata.
///
/// [Stored] wraps a cached value of type [T] along with [Metadata]
/// that tracks versioning, TTL, and HTTP caching information.
///
/// This class is used internally by [Store] implementations and
/// is returned when reading from the cache.
///
/// Example:
/// ```dart
/// final stored = Stored<User>(
///   value: user,
///   meta: Metadata(
///     version: 1,
///     storedAt: DateTime.now(),
///     ttl: Duration(minutes: 5),
///   ),
/// );
///
/// print(stored.value.name);
/// print(stored.meta.isExpired);
/// ```
class Stored<T> {
  /// The cached value.
  final T value;

  /// Metadata associated with this cached entry.
  final Metadata meta;

  /// Creates a [Stored] instance with the given [value] and [meta].
  const Stored({required this.value, required this.meta});
}
