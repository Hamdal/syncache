import 'dart:async';

import 'package:hive_ce/hive_ce.dart';
import 'package:syncache/syncache.dart';

/// A Hive-backed [MutationOutbox] for durable offline writes.
///
/// Records live in their **own box** (default name `syncache_outbox`), never
/// in the user's cache box: clearing the cache must not destroy unsynced
/// writes. The box can be opened alongside any [HiveStore] (or any other
/// cache backend) — the outbox backend is independent of the cache backend.
///
/// Built on `hive_ce`; the serialized shape is plain JSON maps keyed by
/// mutation id, with `seq` and `queuedAt` embedded so recovery replays in
/// enqueue order.
///
/// ## Example
///
/// ```dart
/// final outbox = await HiveMutationOutbox.open();
/// final cache = Syncache<User>(store: store, outbox: outbox);
/// // ... later, at startup:
/// await cache.recoverPendingMutations(resolve);
/// // ... when shutting down:
/// await outbox.close();
/// ```
///
/// A corrupted record (e.g. written by a different schema version) is
/// skipped and reported through [onError] — it never crashes [loadAll].
class HiveMutationOutbox implements MutationOutbox {
  final Box<Map<dynamic, dynamic>> _box;
  final void Function(Object error)? onError;

  bool _isClosed = false;
  int _pendingOperations = 0;
  Completer<void>? _pendingCompleter;

  /// Use [open] to create a [HiveMutationOutbox] with a managed box.
  HiveMutationOutbox({
    required Box<Map<dynamic, dynamic>> box,
    this.onError,
  }) : _box = box;

  /// Opens a [HiveMutationOutbox] with the specified box name.
  ///
  /// **Important:** Hive must be initialized before calling this method.
  /// Call `Hive.init(path)` — or `Hive.initFlutter()` from `hive_ce_flutter`
  /// in your app — first.
  ///
  /// [onError] is invoked for each corrupted record skipped during
  /// [loadAll].
  static Future<HiveMutationOutbox> open({
    String boxName = 'syncache_outbox',
    void Function(Object error)? onError,
  }) async {
    final box = await Hive.openBox<Map<dynamic, dynamic>>(boxName);
    return HiveMutationOutbox(box: box, onError: onError);
  }

  /// Whether this outbox has been closed.
  ///
  /// After closing, all operations throw [StateError].
  bool get isClosed => _isClosed;

  /// Whether this outbox is open and ready for operations.
  bool get isOpen => !_isClosed && _box.isOpen;

  /// Checks that the outbox is not closed and throws [StateError] if it is.
  void _checkNotClosed() {
    if (_isClosed) {
      throw StateError('HiveMutationOutbox has been closed');
    }
    if (!_box.isOpen) {
      throw StateError('HiveMutationOutbox box is not open');
    }
  }

  /// Executes an async operation with safe close handling, mirroring
  /// [HiveStore]: close() waits for in-flight operations to finish.
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

  /// Closes the outbox box, waiting for pending operations to complete.
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    if (_pendingOperations > 0) {
      _pendingCompleter ??= Completer<void>();
      await _pendingCompleter!.future;
    }
    await _box.close();
  }

  @override
  Future<void> save(PendingMutationRecord record) {
    return _withOperation(() async {
      await _box.put(record.id, {
        'id': record.id,
        'key': record.key,
        'seq': record.seq,
        'payload': record.payload,
        'queuedAtMs': record.queuedAt.millisecondsSinceEpoch,
      });
    });
  }

  @override
  Future<void> delete(String id) {
    return _withOperation(() => _box.delete(id));
  }

  @override
  Future<void> clear() {
    return _withOperation(() => _box.clear());
  }

  @override
  Future<List<PendingMutationRecord>> loadAll() {
    return _withOperation(() async {
      final records = <PendingMutationRecord>[];
      for (final key in _box.keys) {
        final raw = _box.get(key);
        if (raw == null) continue;
        try {
          records.add(_decode(key, raw));
        } catch (e) {
          // Skip corrupted records instead of crashing; report when a
          // callback is installed.
          onError?.call(e);
        }
      }
      records.sort((a, b) => a.seq.compareTo(b.seq));
      return records;
    });
  }

  PendingMutationRecord _decode(dynamic boxKey, Map<dynamic, dynamic> raw) {
    final id = raw['id'];
    final key = raw['key'];
    final seq = raw['seq'];
    final queuedAtMs = raw['queuedAtMs'];
    if (id is! String || key is! String || seq is! int) {
      throw FormatException('Malformed outbox record', raw);
    }
    return PendingMutationRecord(
      id: id,
      key: key,
      seq: seq,
      payload: (raw['payload'] as Map?)?.cast<String, Object?>() ?? const {},
      queuedAt: queuedAtMs is int
          ? DateTime.fromMillisecondsSinceEpoch(queuedAtMs)
          : throw FormatException('Malformed queuedAtMs', raw),
    );
  }
}
