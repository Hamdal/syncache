/// Drift (SQLite) storage backend for Syncache.
///
/// This library provides [DriftStore], a persistent `TaggableStore`
/// implementation using [drift](https://pub.dev/packages/drift), and
/// [DriftMutationOutbox], a durable `MutationOutbox` — both operating on a
/// single shared [SyncacheDriftDatabase].
///
/// ## Getting Started
///
/// ```dart
/// import 'package:syncache/syncache.dart';
/// import 'package:syncache_drift/syncache_drift.dart';
///
/// void main() async {
///   // Open ONE database shared by the store and the outbox …
///   final db = SyncacheDriftDatabase.openFile('path/to/cache.sqlite');
///
///   final store = DriftStore<User>(
///     db: db,
///     fromJson: User.fromJson,
///     toJson: (user) => user.toJson(),
///   );
///   final outbox = DriftMutationOutbox(db: db);
///
///   // … and wire both into Syncache.
///   final cache = Syncache<User>(store: store, outbox: outbox);
///
///   // Fetch and cache data
///   final user = await cache.get(
///     key: 'user:123',
///     fetch: (req) => api.getUser('123'),
///   );
///
///   // Recover unsynced writes from a previous session
///   await cache.recoverPendingMutations(resolve);
/// }
/// ```
///
/// ## Shared-connection bonus
///
/// Because the cache tables and the outbox table live in one SQLite
/// database with one connection, clearing the cache never destroys unsynced
/// writes — and `db.transaction(...)` can atomically combine cache writes
/// with outbox writes, something the Hive backend cannot offer.
///
/// ## Flutter Usage
///
/// Add `sqlite3_flutter_libs` to your Flutter app to ship the SQLite
/// binaries:
///
/// ```yaml
/// dependencies:
///   sqlite3_flutter_libs: ^0.5.0
/// ```
///
/// ## Dependency policy
///
/// This package never depends on `hive`, `hive_ce`, or `syncache_hive`. It
/// can be used alongside or instead of `syncache_hive` — backend packages
/// are independent and mutually exclusive by choice, not by requirement.
library syncache_drift;

export 'src/drift_database.dart'
    show
        SyncacheDriftDatabase,
        CacheEntries,
        CacheEntriesCompanion,
        CacheEntry,
        CacheTags,
        CacheTagsCompanion,
        CacheTag,
        MutationOutboxEntries,
        MutationOutboxEntriesCompanion,
        MutationOutboxRecord;
export 'src/drift_mutation_outbox.dart' show DriftMutationOutbox;
export 'src/drift_store.dart' show DriftStore;
