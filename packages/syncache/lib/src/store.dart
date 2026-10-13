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
/// ## Tag lifecycle contract
///
/// All [TaggableStore] implementations must follow these rules so that tag
/// behavior is identical regardless of the storage backend:
///
/// - [write] **preserves** any tags previously associated with the key.
///   This matters because [Syncache.set] and mutation syncs use [write]:
///   replacing a value must not silently detach the entry from its tag
///   groups (e.g. an entry tagged `users` must remain reachable by
///   `invalidateTag('users')` after an optimistic mutation).
/// - [writeWithTags] **replaces** the tags for the key entirely. Passing an
///   empty list clears all tags for the key.
/// - [delete] and [clear] remove tag mappings together with the entries.
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
  /// Writes a [Stored] entry to the cache with the given [key] and tags.
  ///
  /// If an entry with the same key already exists, it is overwritten. The
  /// given [tags] **replace** any previously associated tags; passing an
  /// empty list clears all tags for the key.
  ///
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

/// Extended store interface for caches with a bounded capacity.
///
/// Implement this interface to let a store evict entries when it grows past
/// [maxLength]. [Syncache] detects the capability at construction time and
/// forwards evictions to observers as `SyncacheObserver.onEvict` — the
/// [Store] interface itself never grows, so third-party backends that don't
/// bound themselves keep compiling unchanged.
///
/// The eviction **policy** (e.g. least-recently-used) is an implementation
/// detail of the store; the interface only carries the capacity and the
/// eviction hook.
///
/// See also:
/// - [MemoryStore] for an LRU implementation
abstract class BoundedStore<T> implements Store<T> {
  /// Callback invoked with a key right after that key has been evicted for
  /// exceeding [maxLength].
  ///
  /// [Syncache] assigns this automatically when a [BoundedStore] is passed
  /// to it, so evictions surface as `SyncacheObserver.onEvict` events and
  /// increment `SyncacheStats.evictions`. Leave it unset when the store is
  /// used standalone.
  void Function(String key)? onEvict;

  /// Maximum number of entries the store retains.
  ///
  /// `null` (the default) means the store is unbounded and never evicts.
  set maxLength(int? value);

  /// Maximum number of entries the store retains.
  ///
  /// `null` means the store is unbounded and never evicts.
  int? get maxLength;

  /// Current number of entries in the store.
  Future<int> get length;
}

/// Extended store interface for stores that can enumerate their keys.
///
/// Implement this interface to enable whole-cache maintenance operations on
/// your store — currently [Syncache.cleanup] (expired-entry collection) and
/// `SyncacheStats.entryCount`. The [Store] interface itself never grows, so
/// third-party backends that can't enumerate keys keep compiling unchanged.
///
/// See also:
/// - [MemoryStore] for an in-memory implementation
/// - [HiveStore](package:syncache_hive/syncache_hive.dart) for a persistent
///   implementation
abstract class IterableStore<T> implements Store<T> {
  /// Returns all keys currently present in the store.
  ///
  /// Implementations should avoid deserializing entry values — callers
  /// typically iterate every key (e.g. to find expired entries), and the
  /// point of this capability is cheap enumeration.
  Future<List<String>> keys();
}
