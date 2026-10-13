import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'drift_database.g.dart';

/// The `cache` table: one row per cached entry.
///
/// The entry value is stored as JSON text and deserialized by the
/// [DriftStore](package:syncache_drift/syncache_drift.dart) codecs, mirroring
/// the serialization shape of `HiveStore`. Timestamps are stored as
/// epoch-milliseconds integers so the schema stays engine-agnostic.
@DataClassName('CacheEntry')
class CacheEntries extends Table {
  /// The cache key (primary key).
  TextColumn get key => text()();

  /// The JSON-encoded cached value.
  TextColumn get value => text()();

  /// Version of this entry, used for conflict detection.
  IntColumn get version => integer()();

  /// When the entry was stored (epoch milliseconds).
  IntColumn get storedAt => integer()();

  /// Time-to-live in milliseconds, or `null` for entries that never expire
  /// based on time.
  IntColumn get ttlMs => integer().nullable()();

  /// HTTP ETag for conditional requests, if any.
  TextColumn get etag => text().nullable()();

  /// HTTP last-modified timestamp (epoch milliseconds), if any.
  IntColumn get lastModified => integer().nullable()();

  @override
  String get tableName => 'cache';

  @override
  Set<Column> get primaryKey => {key};
}

/// The `cache_tags` table: a relational tag index for [CacheEntries].
///
/// Tags live in their own table (one row per `(key, tag)` pair) instead of
/// being embedded in the entry, so tag lookups are real indexed SQL queries
/// — no scans of the value table. An index on [tag] backs
/// `getKeysByTag`/`deleteByTag`.
@DataClassName('CacheTag')
@TableIndex(name: 'cache_tags_tag_idx', columns: {#tag})
class CacheTags extends Table {
  /// The cache key this tag is associated with.
  TextColumn get key => text()();

  /// The tag.
  TextColumn get tag => text()();

  @override
  String get tableName => 'cache_tags';

  @override
  Set<Column> get primaryKey => {key, tag};
}

/// The `mutation_outbox` table: durable pending-mutation records.
///
/// This table lives in the **same database** as [CacheEntries] and
/// [CacheTags]. Clearing the cache never touches it, and — because both
/// share one connection — outbox writes can run inside the same SQL
/// transaction as cache writes.
@DataClassName('MutationOutboxRecord')
@TableIndex(name: 'mutation_outbox_seq_idx', columns: {#seq})
class MutationOutboxEntries extends Table {
  /// Stable mutation id (primary key).
  TextColumn get id => text()();

  /// The cache key this mutation affects.
  TextColumn get key => text()();

  /// Monotonic enqueue order; `loadAll` returns rows ordered by this column.
  IntColumn get seq => integer()();

  /// The caller-supplied JSON payload of the mutation.
  TextColumn get payload => text()();

  /// When the mutation was enqueued (epoch milliseconds).
  IntColumn get queuedAt => integer()();

  /// JSON-encoded optimistic snapshot, or `null` when the caller opted out.
  ///
  /// Persisting this lets recovery replay the *exact* pre-death optimistic
  /// value, matching the behavior of the Hive outbox.
  TextColumn get optimisticSnapshot => text().nullable()();

  @override
  String get tableName => 'mutation_outbox';

  @override
  Set<Column> get primaryKey => {id};
}

/// The shared drift database backing both `DriftStore` and
/// `DriftMutationOutbox`.
///
/// Cache entries, the tag index, and the mutation outbox live in **one
/// database** and therefore share **one connection**. This is the headline
/// advantage over the Hive backend: clearing the cache (`DriftStore.clear`)
/// leaves outbox records untouched, while a [SyncacheDriftDatabase.transaction]
/// can atomically combine cache writes and outbox writes — either both
/// commit or neither does.
///
/// ## Setup
///
/// ```dart
/// // Open one database …
/// final db = SyncacheDriftDatabase.openFile('path/to/app.sqlite');
/// // … and share it between the store and the outbox.
/// final store = DriftStore<String>(
///   db: db,
///   fromJson: (json) => User.fromJson(json),
///   toJson: (user) => user.toJson(),
/// );
/// final outbox = DriftMutationOutbox(db: db);
///
/// final cache = Syncache<String>(store: store, outbox: outbox);
/// ```
///
/// ## Flutter
///
/// This class uses `package:drift/native.dart` for its convenience
/// constructors ([openFile] and [inMemory]), which are available on
/// native platforms (mobile, desktop, server). Flutter apps should add
/// `sqlite3_flutter_libs` to ship the SQLite binaries. Web builds can still
/// use the default constructor with a `WasmDatabase` executor.
///
/// See also:
/// - [DriftStore] for the `TaggableStore` implementation
/// - [DriftMutationOutbox] for the `MutationOutbox` implementation
@DriftDatabase(tables: [CacheEntries, CacheTags, MutationOutboxEntries])
class SyncacheDriftDatabase extends _$SyncacheDriftDatabase {
  /// Creates a database from an arbitrary drift [QueryExecutor].
  ///
  /// Use this constructor to plug in platform-specific executors (e.g. a
  /// `WasmDatabase` on the web). Prefer [openFile] or [inMemory] on native
  /// platforms.
  SyncacheDriftDatabase(super.e);

  /// Creates (or opens) a file-backed database at [path], running SQLite on
  /// a background isolate.
  ///
  /// Parent directories are created if necessary.
  SyncacheDriftDatabase.openFile(String path) : super(_openLazyFile(path));

  /// Creates an in-memory database (primarily useful for tests).
  ///
  /// The data lives only for the lifetime of this instance.
  SyncacheDriftDatabase.inMemory() : super(NativeDatabase.memory());

  static LazyDatabase _openLazyFile(String path) {
    return LazyDatabase(() async {
      final file = File(path);
      await file.parent.create(recursive: true);
      return NativeDatabase.createInBackground(file);
    });
  }

  @override
  int get schemaVersion => 1;
}
