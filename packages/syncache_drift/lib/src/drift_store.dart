import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:syncache/syncache.dart';

import 'drift_database.dart';

/// A Drift (SQLite)-backed implementation of [TaggableStore] and
/// [IterableStore].
///
/// [DriftStore] provides durable storage in a SQLite database via the
/// `drift` package. Entries are stored as JSON text (serialized with the
/// `fromJson`/`toJson` codecs you supply — the same serialization shape as
/// `HiveStore`), while tags live in a dedicated relational index table, so
/// tag lookups are indexed SQL queries rather than box scans.
///
/// ## Shared database
///
/// The store operates on a [SyncacheDriftDatabase] that can be **shared**
/// with a [DriftMutationOutbox]. `clear()` only removes cache entries and
/// their tags — outbox records in the same database are untouched — and a
/// `db.transaction(...)` can atomically combine cache writes with outbox
/// writes, which is the headline advantage over the Hive backend.
///
/// ## Tag lifecycle contract
///
/// Because tags live in their own table keyed independently of the value
/// row, the [TaggableStore] contract holds naturally:
///
/// - plain [write] touches only the `cache` table, so existing tags are
///   preserved,
/// - [writeWithTags] replaces the tags for the key entirely,
/// - [delete] and [clear] remove tag mappings together with the entries.
///
/// ## Corruption handling
///
/// [read] never throws on a corrupted (unparseable) entry: the bad row and
/// its tag mappings are deleted and the read returns `null` (a cache miss).
///
/// ## Safe close
///
/// [close] waits for all in-flight operations to complete before closing
/// the underlying database, so calling `close()` while writes are pending
/// never truncates them. After closing, all operations throw [StateError].
/// Note that when the database is shared with an outbox, closing either
/// wrapper closes the shared database (drift tolerates the second close).
///
/// ## Pattern syntax
///
/// Pattern matching methods ([deleteByPattern], [getKeysByPattern]) support
/// glob-style patterns with semantics identical to `HiveStore`:
/// - `*` matches any number of characters (including zero)
/// - `?` matches exactly one character
///
/// Example patterns:
/// - `user:*` matches `user:1`, `user:123`, `user:`
/// - `user:?` matches `user:1`, `user:a` but not `user:12`
///
/// ## Example
///
/// ```dart
/// // Open one shared database …
/// final db = SyncacheDriftDatabase.openFile('path/to/cache.sqlite');
///
/// // … and wrap it in a store.
/// final store = DriftStore<User>(
///   db: db,
///   fromJson: User.fromJson,
///   toJson: (user) => user.toJson(),
/// );
///
/// // Use with Syncache
/// final cache = Syncache<User>(store: store);
///
/// // Remember to close when done
/// await store.close();
/// ```
///
/// See also:
/// - [TaggableStore] for the tagging interface
/// - [IterableStore] for key enumeration (expired-entry cleanup)
/// - [Store] for the base storage interface
/// - [SyncacheDriftDatabase] for the database schema
class DriftStore<T> implements TaggableStore<T>, IterableStore<T> {
  /// The shared drift database this store operates on.
  final SyncacheDriftDatabase db;

  /// Converts a JSON map to the value type [T].
  final T Function(Map<String, dynamic> json) fromJson;

  /// Converts a value of type [T] to a JSON map.
  final Map<String, dynamic> Function(T value) toJson;

  /// Tracks whether this store has been closed.
  bool _isClosed = false;

  /// Tracks the number of pending operations to prevent close during
  /// operation.
  int _pendingOperations = 0;

  /// Completer that resolves when all pending operations complete.
  /// Used by [close] to wait for operations to finish.
  Completer<void>? _pendingCompleter;

  /// Creates a [DriftStore] operating on the given [db].
  ///
  /// Prefer [DriftStore.open] when you own the whole database file; use this
  /// constructor to share one database with a [DriftMutationOutbox].
  DriftStore({
    required this.db,
    required this.fromJson,
    required this.toJson,
  });

  /// Opens a file-backed database at [path] and returns a [DriftStore]
  /// bound to it.
  ///
  /// This is the one-call convenience for cache-only usage. When you also
  /// want a mutation outbox sharing the same database (recommended — that's
  /// the point of the drift backend), open the
  /// [SyncacheDriftDatabase] yourself and pass it to both wrappers:
  ///
  /// ```dart
  /// final db = SyncacheDriftDatabase.openFile('app.sqlite');
  /// final store = DriftStore<String>(db: db, fromJson: ..., toJson: ...);
  /// final outbox = DriftMutationOutbox(db: db);
  /// ```
  ///
  /// The [fromJson] and [toJson] functions are required to serialize and
  /// deserialize your data type [T].
  static Future<DriftStore<T>> open<T>({
    required String path,
    required T Function(Map<String, dynamic> json) fromJson,
    required Map<String, dynamic> Function(T value) toJson,
  }) async {
    return DriftStore<T>(
      db: SyncacheDriftDatabase.openFile(path),
      fromJson: fromJson,
      toJson: toJson,
    );
  }

  /// Whether this store has been closed.
  ///
  /// After closing, all operations will throw [StateError].
  bool get isClosed => _isClosed;

  /// Whether this store is open and ready for operations.
  ///
  /// Returns `false` once this store instance has been closed via [close].
  bool get isOpen => !_isClosed;

  /// Checks that the store is not closed and throws [StateError] if it is.
  void _checkNotClosed() {
    if (_isClosed) {
      throw StateError('DriftStore has been closed');
    }
  }

  /// Tracks the start of an operation for safe close handling.
  ///
  /// Must be paired with [_endOperation] in a try/finally block.
  void _beginOperation() {
    _checkNotClosed();
    _pendingOperations++;
  }

  /// Marks an operation as complete.
  ///
  /// If this was the last pending operation and [close] is waiting, signals
  /// that close can proceed.
  void _endOperation() {
    _pendingOperations--;
    if (_pendingOperations == 0 && _pendingCompleter != null) {
      _pendingCompleter!.complete();
      _pendingCompleter = null;
    }
  }

  /// Executes an async operation with proper tracking for safe close
  /// handling.
  Future<R> _withOperation<R>(Future<R> Function() operation) async {
    _beginOperation();
    try {
      return await operation();
    } finally {
      _endOperation();
    }
  }

  /// Closes the underlying database.
  ///
  /// This method waits for all pending operations to complete before
  /// closing. Call this method when you're done using the store to release
  /// resources. After closing, all operations will throw [StateError].
  ///
  /// This method is idempotent — calling it multiple times is safe.
  ///
  /// Note that the database may be shared with a [DriftMutationOutbox];
  /// closing either wrapper closes the shared database, and drift tolerates
  /// the second close.
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;

    // Wait for pending operations to complete.
    if (_pendingOperations > 0) {
      _pendingCompleter = Completer<void>();
      await _pendingCompleter!.future;
    }

    await db.close();
  }

  @override
  Future<void> write(String key, Stored<T> entry) {
    return _withOperation(() async {
      // Touch only the entry row: tags live in the separate cache_tags
      // table and are therefore preserved (see the TaggableStore tag
      // lifecycle contract).
      await db
          .into(db.cacheEntries)
          .insertOnConflictUpdate(_toCompanion(key, entry));
    });
  }

  @override
  Future<void> writeWithTags(
    String key,
    Stored<T> entry,
    List<String> tags,
  ) {
    return _withOperation(() async {
      final uniqueTags = tags.toSet().toList();
      // Replace value and tags atomically.
      await db.transaction(() async {
        await db
            .into(db.cacheEntries)
            .insertOnConflictUpdate(_toCompanion(key, entry));
        await _deleteTagMappings(key);
        if (uniqueTags.isNotEmpty) {
          await db.batch((batch) {
            batch.insertAll(
              db.cacheTags,
              [
                for (final tag in uniqueTags)
                  CacheTagsCompanion.insert(key: key, tag: tag),
              ],
            );
          });
        }
      });
    });
  }

  @override
  Future<Stored<T>?> read(String key) {
    return _withOperation(() async {
      final row = await (db.select(db.cacheEntries)
            ..where((tbl) => tbl.key.equals(key)))
          .getSingleOrNull();
      if (row == null) return null;

      try {
        return _deserializeEntry(row);
      } catch (e) {
        // If deserialization fails, the data is corrupted or the schema
        // changed. Delete the corrupted entry (together with its tag
        // mappings) and return null (cache miss).
        await _withTransaction(() async {
          await _deleteEntryRow(key);
          await _deleteTagMappings(key);
        });
        return null;
      }
    });
  }

  @override
  Future<List<String>> getTags(String key) {
    return _withOperation(() async {
      final rows = await (db.select(db.cacheTags)
            ..where((tbl) => tbl.key.equals(key)))
          .get();
      return rows.map((row) => row.tag).toList();
    });
  }

  @override
  Future<void> delete(String key) {
    return _withOperation(
      () => _withTransaction(() async {
        await _deleteEntryRow(key);
        await _deleteTagMappings(key);
      }),
    );
  }

  @override
  Future<void> clear() {
    return _withOperation(
      () => _withTransaction(() async {
        await db.delete(db.cacheEntries).go();
        await db.delete(db.cacheTags).go();
        // Deliberately does NOT touch the mutation_outbox table: with a
        // shared database, clearing the cache must not destroy unsynced
        // writes.
      }),
    );
  }

  @override
  Future<List<String>> keys() {
    return _withOperation(() async {
      final rows = await db.select(db.cacheEntries).get();
      return rows.map((row) => row.key).toList();
    });
  }

  @override
  Future<void> deleteByTag(String tag) {
    return _withOperation(() async {
      final rows = await (db.select(db.cacheTags)
            ..where((tbl) => tbl.tag.equals(tag)))
          .get();
      await _deleteKeys(rows.map((row) => row.key).toSet());
    });
  }

  @override
  Future<void> deleteByTags(List<String> tags, {bool matchAll = false}) {
    return _withOperation(() async {
      if (tags.isEmpty) return;

      final tagSet = tags.toSet();
      final rows = await (db.select(db.cacheTags)
            ..where((tbl) => tbl.tag.isIn(tagSet)))
          .get();

      final Set<String> keysToDelete;
      if (matchAll) {
        // (key, tag) is the primary key, so counting the matching rows per
        // key gives exactly how many of the requested tags the key has.
        // A key matching every tag therefore appears tagSet.length times.
        final matchCounts = <String, int>{};
        for (final row in rows) {
          matchCounts.update(
            row.key,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }
        keysToDelete = {
          for (final entry in matchCounts.entries)
            if (entry.value >= tagSet.length) entry.key,
        };
      } else {
        // Union: keys present for any tag.
        keysToDelete = rows.map((row) => row.key).toSet();
      }

      await _deleteKeys(keysToDelete);
    });
  }

  @override
  Future<List<String>> getKeysByTag(String tag) {
    return _withOperation(() async {
      final rows = await (db.select(db.cacheTags)
            ..where((tbl) => tbl.tag.equals(tag)))
          .get();
      return rows.map((row) => row.key).toList();
    });
  }

  @override
  Future<void> deleteByPattern(String pattern) {
    return _withOperation(() async {
      final regex = _patternToRegex(pattern);
      final rows = await db.select(db.cacheEntries).get();
      final keysToDelete = {
        for (final row in rows)
          if (regex.hasMatch(row.key)) row.key,
      };
      await _deleteKeys(keysToDelete);
    });
  }

  @override
  Future<List<String>> getKeysByPattern(String pattern) {
    return _withOperation(() async {
      final regex = _patternToRegex(pattern);
      final rows = await db.select(db.cacheEntries).get();
      return [
        for (final row in rows)
          if (regex.hasMatch(row.key)) row.key,
      ];
    });
  }

  // ============================================================
  // Private Helpers
  // ============================================================

  /// Runs [action] in a database transaction.
  ///
  /// Nested inside an already-running transaction (e.g. when a caller wraps
  /// cache and outbox writes in one `db.transaction`), drift joins the
  /// outer transaction, preserving the shared-connection atomicity bonus.
  Future<void> _withTransaction(Future<void> Function() action) {
    return db.transaction(action);
  }

  /// Deletes the `cache` row for [key].
  Future<void> _deleteEntryRow(String key) {
    return (db.delete(db.cacheEntries)..where((tbl) => tbl.key.equals(key)))
        .go();
  }

  /// Deletes all tag mappings for [key].
  Future<void> _deleteTagMappings(String key) {
    return (db.delete(db.cacheTags)..where((tbl) => tbl.key.equals(key))).go();
  }

  /// Deletes [keys] together with their tag mappings.
  ///
  /// No-op when [keys] is empty.
  Future<void> _deleteKeys(Set<String> keys) async {
    if (keys.isEmpty) return;
    await db.transaction(() async {
      await (db.delete(db.cacheEntries)..where((tbl) => tbl.key.isIn(keys)))
          .go();
      await (db.delete(db.cacheTags)..where((tbl) => tbl.key.isIn(keys))).go();
    });
  }

  /// Converts a glob pattern to a [RegExp].
  ///
  /// Supported wildcards:
  /// - `*` matches any sequence of characters (including empty)
  /// - `?` matches exactly one character
  ///
  /// All other regex metacharacters are escaped. Identical translation to
  /// `HiveStore`, so pattern semantics are the same across backends.
  RegExp _patternToRegex(String pattern) {
    final escaped = pattern
        .replaceAll(r'\', r'\\')
        .replaceAll('.', r'\.')
        .replaceAll('+', r'\+')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)')
        .replaceAll('[', r'\[')
        .replaceAll(']', r'\]')
        .replaceAll('{', r'\{')
        .replaceAll('}', r'\}')
        .replaceAll('^', r'\^')
        .replaceAll(r'$', r'\$')
        .replaceAll('|', r'\|')
        .replaceAll('*', '.*')
        .replaceAll('?', '.');
    return RegExp('^$escaped\$');
  }

  // ============================================================
  // Serialization Helpers
  // ============================================================

  /// Serializes a [Stored] entry into an upsertable row companion.
  CacheEntriesCompanion _toCompanion(String key, Stored<T> entry) {
    return CacheEntriesCompanion.insert(
      key: key,
      value: jsonEncode(toJson(entry.value)),
      version: entry.meta.version,
      storedAt: entry.meta.storedAt.millisecondsSinceEpoch,
      ttlMs: Value(entry.meta.ttl?.inMilliseconds),
      etag: Value(entry.meta.etag),
      lastModified: Value(entry.meta.lastModified?.millisecondsSinceEpoch),
    );
  }

  /// Deserializes a row back into a [Stored] entry.
  Stored<T> _deserializeEntry(CacheEntry row) {
    final meta = Metadata(
      version: row.version,
      storedAt: DateTime.fromMillisecondsSinceEpoch(row.storedAt),
      ttl: row.ttlMs == null ? null : Duration(milliseconds: row.ttlMs!),
      etag: row.etag,
      lastModified: row.lastModified == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row.lastModified!),
    );
    return Stored<T>(
      value: fromJson(_decodeJsonObject(row.value)),
      meta: meta,
    );
  }

  /// Decodes a JSON object column, failing loudly on non-object payloads so
  /// callers can treat failures as corruption.
  Map<String, dynamic> _decodeJsonObject(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Expected a JSON object');
    }
    return Map<String, dynamic>.from(decoded);
  }
}
