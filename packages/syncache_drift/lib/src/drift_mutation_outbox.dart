import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:syncache/syncache.dart';

import 'drift_database.dart';

/// A Drift (SQLite)-backed [MutationOutbox] for durable offline writes.
///
/// Records live in the `mutation_outbox` table of the **shared**
/// [SyncacheDriftDatabase] — the same database [DriftStore] uses. Clearing
/// the cache never destroys unsynced writes ([DriftStore.clear] only
/// touches the `cache`/`cache_tags` tables), and because both share one
/// connection, outbox writes can run inside the same SQL transaction as
/// cache writes.
///
/// The payload and optimistic snapshot are stored as JSON text
/// (`jsonEncode`), so recovery replays records with full
/// [PendingMutationRecord.optimisticSnapshot] parity to the Hive outbox —
/// exact-replay after process death.
///
/// ## Example
///
/// ```dart
/// final db = SyncacheDriftDatabase.openFile('app.sqlite');
/// final outbox = DriftMutationOutbox(db: db);
/// final cache = Syncache<User>(
///   store: DriftStore(db: db, fromJson: User.fromJson, toJson: (u) => u.toJson()),
///   outbox: outbox,
/// );
/// // ... later, at startup:
/// await cache.recoverPendingMutations(resolve);
/// // ... when shutting down:
/// await outbox.close();
/// ```
///
/// A corrupted record (e.g. written by a different schema version) is
/// skipped and reported through [onError] — it never crashes [loadAll].
class DriftMutationOutbox implements MutationOutbox {
  /// The shared drift database holding the `mutation_outbox` table.
  final SyncacheDriftDatabase db;

  /// Invoked for each corrupted record skipped during [loadAll].
  final void Function(Object error)? onError;

  /// Tracks whether this outbox has been closed.
  bool _isClosed = false;

  /// Tracks the number of pending operations to prevent close during
  /// operation.
  int _pendingOperations = 0;

  /// Completer that resolves when all pending operations complete.
  /// Used by [close] to wait for operations to finish.
  Completer<void>? _pendingCompleter;

  /// Creates a [DriftMutationOutbox] operating on the given [db].
  ///
  /// Pass the same database instance you gave [DriftStore] to get the
  /// shared-connection transaction benefit.
  DriftMutationOutbox({
    required this.db,
    this.onError,
  });

  /// Whether this outbox has been closed.
  ///
  /// After closing, all operations throw [StateError].
  bool get isClosed => _isClosed;

  /// Whether this outbox is open and ready for operations.
  ///
  /// Returns `false` once this outbox instance has been closed via [close].
  bool get isOpen => !_isClosed;

  /// Checks that the outbox is not closed and throws [StateError] if it is.
  void _checkNotClosed() {
    if (_isClosed) {
      throw StateError('DriftMutationOutbox has been closed');
    }
  }

  /// Executes an async operation with safe close handling, mirroring
  /// [DriftStore]: close() waits for in-flight operations to finish.
  Future<R> _withOperation<R>(Future<R> Function() operation) async {
    _checkNotClosed();
    _pendingOperations++;
    try {
      return await operation();
    } finally {
      _pendingOperations--;
      if (_pendingOperations == 0 && _pendingCompleter != null) {
        _pendingCompleter!.complete();
        _pendingCompleter = null;
      }
    }
  }

  /// Closes the outbox, waiting for pending operations to complete.
  ///
  /// Closing closes the underlying database — the same one a [DriftStore]
  /// may be sharing. This method is idempotent, and drift tolerates the
  /// second close when both wrappers are closed.
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    if (_pendingOperations > 0) {
      _pendingCompleter ??= Completer<void>();
      await _pendingCompleter!.future;
    }
    await db.close();
  }

  @override
  Future<void> save(PendingMutationRecord record) {
    return _withOperation(() {
      // INSERT OR REPLACE: a re-saved id replaces its row (equivalent to
      // HiveMutationOutbox saving into an id-keyed box).
      return db.into(db.mutationOutboxEntries).insertOnConflictUpdate(
            MutationOutboxEntriesCompanion.insert(
              id: record.id,
              key: record.key,
              seq: record.seq,
              payload: jsonEncode(record.payload),
              queuedAt: record.queuedAt.millisecondsSinceEpoch,
              optimisticSnapshot: Value(
                record.optimisticSnapshot == null
                    ? null
                    // JSON-safe by contract; encode to survive round-trips.
                    : jsonEncode(record.optimisticSnapshot),
              ),
            ),
          );
    });
  }

  @override
  Future<void> delete(String id) {
    return _withOperation(() async {
      // DELETE BY id — a no-op when the row is absent.
      await (db.delete(db.mutationOutboxEntries)
            ..where((tbl) => tbl.id.equals(id)))
          .go();
    });
  }

  @override
  Future<void> clear() {
    return _withOperation(
      () => db.delete(db.mutationOutboxEntries).go(),
    );
  }

  @override
  Future<List<PendingMutationRecord>> loadAll() {
    return _withOperation(() async {
      final rows = await (db.select(db.mutationOutboxEntries)
            ..orderBy([(tbl) => OrderingTerm.asc(tbl.seq)]))
          .get();
      final records = <PendingMutationRecord>[];
      for (final row in rows) {
        try {
          records.add(_decode(row));
        } catch (e) {
          // Skip corrupted records instead of crashing; report when a
          // callback is installed.
          onError?.call(e);
        }
      }
      return records;
    });
  }

  /// Decodes a row into a [PendingMutationRecord], throwing on malformed
  /// JSON payloads so [loadAll] can treat the row as corrupted.
  PendingMutationRecord _decode(MutationOutboxRecord row) {
    return PendingMutationRecord(
      id: row.id,
      key: row.key,
      seq: row.seq,
      payload: _decodeJsonObject(row.payload),
      queuedAt: DateTime.fromMillisecondsSinceEpoch(row.queuedAt),
      optimisticSnapshot: row.optimisticSnapshot == null
          ? null
          : jsonDecode(row.optimisticSnapshot!),
    );
  }

  /// Decodes a JSON object column, failing loudly on non-object payloads so
  /// callers can treat failures as corruption.
  Map<String, Object?> _decodeJsonObject(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Expected a JSON object');
    }
    return Map<String, Object?>.from(decoded);
  }
}
