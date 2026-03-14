import 'stored.dart';

/// Abstract interface for cache storage backends.
///
/// Implement this interface to create custom storage backends for
/// [Syncache], such as file-based storage, SQLite, or shared preferences.
///
/// The storage operations are asynchronous to support both in-memory
/// and persistent storage implementations.
///
/// Example implementation:
/// ```dart
/// class SqliteStore<T> implements Store<T> {
///   final Database db;
///   final T Function(Map<String, dynamic>) fromJson;
///   final Map<String, dynamic> Function(T) toJson;
///
///   SqliteStore(this.db, {required this.fromJson, required this.toJson});
///
///   @override
///   Future<void> write(String key, Stored<T> entry) async {
///     await db.insert('cache', {
///       'key': key,
///       'value': jsonEncode(toJson(entry.value)),
///       'metadata': jsonEncode(entry.meta.toJson()),
///     });
///   }
///
///   @override
///   Future<Stored<T>?> read(String key) async {
///     final row = await db.query('cache', where: 'key = ?', whereArgs: [key]);
///     if (row.isEmpty) return null;
///     return Stored(
///       value: fromJson(jsonDecode(row.first['value'])),
///       meta: Metadata.fromJson(jsonDecode(row.first['metadata'])),
///     );
///   }
///
///   // ... delete and clear implementations
/// }
/// ```
///
/// See also:
/// - [MemoryStore] for an in-memory implementation
/// - [SharedMemoryStore] for shared in-memory storage across instances
abstract class Store<T> {
  /// Writes a [Stored] entry to the cache with the given [key].
  ///
  /// If an entry with the same key already exists, it is overwritten.
  Future<void> write(String key, Stored<T> entry);

  /// Reads a cached entry for the given [key].
  ///
  /// Returns `null` if no entry exists for the key.
  Future<Stored<T>?> read(String key);

  /// Deletes the entry for the given [key].
  ///
  /// If no entry exists for the key, this operation is a no-op.
  Future<void> delete(String key);

  /// Clears all entries from the store.
  Future<void> clear();
}

/// Extended store interface that supports tagging entries.
///
/// Implement this interface to enable tag-based invalidation for
/// your store implementation. The [Syncache] class will automatically
/// detect if your store supports tagging and enable tag operations.
///
/// Example:
/// ```dart
/// // Store with tags
/// await cache.get(
///   key: 'calendar:events:2024-03',
///   fetch: fetchEvents,
///   tags: ['calendar', 'events', 'workspace:123'],
/// );
///
/// // Invalidate all entries with 'calendar' tag
/// await cache.invalidateTag('calendar');
/// ```
abstract class TaggableStore<T> implements Store<T> {
  /// Writes a [Stored] entry to the cache with the given [key] and optional [tags].
  ///
  /// If an entry with the same key already exists, it is overwritten.
  /// Tags are used for group-based invalidation.
  Future<void> writeWithTags(String key, Stored<T> entry, List<String> tags);

  /// Returns the tags associated with a [key].
  ///
  /// Returns an empty list if the key doesn't exist or has no tags.
  Future<List<String>> getTags(String key);

  /// Deletes all entries with the given [tag].
  Future<void> deleteByTag(String tag);

  /// Deletes entries that have all of the specified [tags].
  ///
  /// If [matchAll] is true, only entries that have ALL tags are deleted.
  /// If [matchAll] is false, entries that have ANY of the tags are deleted.
  Future<void> deleteByTags(List<String> tags, {bool matchAll = false});

  /// Returns all keys that have the given [tag].
  Future<List<String>> getKeysByTag(String tag);

  /// Deletes entries where the key matches the given glob [pattern].
  ///
  /// Supports simple glob patterns:
  /// - `*` matches any characters
  /// - `?` matches a single character
  Future<void> deleteByPattern(String pattern);

  /// Returns all keys that match the given glob [pattern].
  Future<List<String>> getKeysByPattern(String pattern);
}
