import 'dart:async';

import 'metadata.dart';
import 'mutation.dart';
import 'mutation_handle.dart';
import 'mutation_outbox.dart';
import 'network.dart';
import 'observer.dart';
import 'pending_mutation_info.dart';
import 'pending_mutation_record.dart';
import 'retry.dart';
import 'store.dart';
import 'stored.dart';

int _mutationIdCounter = 0;

class PendingMutation<T> {
  final String id;
  final String key;
  final Mutation<T> mutation;

  /// Caller-supplied, JSON-safe description of the change, persisted in the
  /// outbox (when configured) and handed back to the recovery resolver.
  final Map<String, Object?>? payload;

  /// Mutable because it's updated when earlier mutations complete and the
  /// base value changes. Subsequent pending mutations for the same key have
  /// their `apply` functions re-applied on top of the new server value.
  T optimisticValue;

  /// Monotonic enqueue order, assigned by [MutationQueue.add]. Replayed
  /// mutations keep the seq of their persisted record.
  int seq;

  int retryCount;
  final DateTime queuedAt;
  DateTime? lastAttemptAt;
  Object? lastError;
  PendingMutationStatus status;
  final List<String>? invalidates;
  final List<String>? invalidateTags;

  final Completer<MutationOutcome<T>> _outcomeCompleter =
      Completer<MutationOutcome<T>>();

  PendingMutation({
    required this.key,
    required this.mutation,
    required this.optimisticValue,
    this.retryCount = 0,
    this.invalidates,
    this.invalidateTags,
    this.payload,
    this.seq = 0,
    String? id,
  })  : id = id ?? 'mut_${++_mutationIdCounter}',
        queuedAt = DateTime.now(),
        status = PendingMutationStatus.pending {
    // Replayed mutations keep their original (possibly from a previous
    // process) id; seed the counter past it so freshly generated ids can
    // never collide with a still-pending replayed one.
    final match = RegExp(r'^mut_(\d+)$').firstMatch(this.id);
    final n = match == null ? null : int.parse(match.group(1)!);
    if (n != null && n > _mutationIdCounter) _mutationIdCounter = n;
  }

  /// The handle callers receive from `Syncache.mutate`.
  MutationHandle<T> get handle =>
      MutationHandle<T>.fromCompleter(_outcomeCompleter);

  /// Settles the handle exactly once; later settlement attempts are
  /// ignored (e.g. a removed in-flight mutation whose send still succeeds).
  void settle(MutationOutcome<T> outcome) {
    if (!_outcomeCompleter.isCompleted) {
      _outcomeCompleter.complete(outcome);
    }
  }

  PendingMutationInfo toInfo() {
    return PendingMutationInfo(
      id: id,
      key: key,
      retryCount: retryCount,
      queuedAt: queuedAt,
      lastAttemptAt: lastAttemptAt,
      lastError: lastError,
      status: status,
      payload: payload,
    );
  }

  /// The outbox record describing this mutation for persistence.
  PendingMutationRecord toRecord() {
    return PendingMutationRecord(
      id: id,
      key: key,
      seq: seq,
      payload: payload ?? const {},
      queuedAt: queuedAt,
    );
  }
}

typedef InvalidationCallback = Future<void> Function(
    List<String>? patterns, List<String>? tags);

typedef NotifyCallback = Future<void> Function(String key);

/// Manages the queue of pending mutations and their sync processing.
class MutationQueue<T> {
  final Store<T> store;
  final Network network;
  final MutationRetryConfig retryConfig;
  final MutationOutbox? outbox;
  final void Function(void Function(SyncacheObserver observer)) notifyObservers;
  final NotifyCallback notifyWatchers;
  final InvalidationCallback performInvalidations;

  final List<PendingMutation<T>> _pendingMutations = [];
  bool _isProcessingQueue = false;
  int _seqCounter = 0;
  StreamController<List<PendingMutationInfo>>? _pendingMutationsController;
  StreamController<bool>? _isSyncedController;
  MutationQueue({
    required this.store,
    required this.network,
    required this.retryConfig,
    required this.notifyObservers,
    required this.notifyWatchers,
    required this.performInvalidations,
    this.outbox,
  });

  int get count => _pendingMutations.length;
  bool get hasPending => _pendingMutations.isNotEmpty;

  List<PendingMutationInfo> get snapshot =>
      _pendingMutations.map((m) => m.toInfo()).toList();

  /// Emits a new list whenever the pending mutations change.
  ///
  /// Seeded: every new listener first receives the current pending list,
  /// then live updates — late subscribers never miss the current state.
  Stream<List<PendingMutationInfo>> get stream {
    _pendingMutationsController ??=
        StreamController<List<PendingMutationInfo>>.broadcast();
    final controller = _pendingMutationsController!;
    return Stream<List<PendingMutationInfo>>.multi((listener) {
      listener.add(snapshot);
      final subscription = controller.stream.listen(
        listener.add,
        onError: listener.addError,
        onDone: listener.close,
      );
      listener.onCancel = subscription.cancel;
    });
  }

  /// Emits `true` when all mutations are synced, `false` otherwise.
  ///
  /// Seeded: every new listener first receives the current sync state
  /// (`false` while mutations are pending, `true` when the queue is empty),
  /// then live updates.
  Stream<bool> get isSyncedStream {
    _isSyncedController ??= StreamController<bool>.broadcast();
    final controller = _isSyncedController!;
    return Stream<bool>.multi((listener) {
      listener.add(_pendingMutations.isEmpty);
      final subscription = controller.stream.listen(
        listener.add,
        onError: listener.addError,
        onDone: listener.close,
      );
      listener.onCancel = subscription.cancel;
    });
  }

  void add(PendingMutation<T> mutation) {
    _pendingMutations.add(mutation);
    _notifyChanged();
    if (outbox == null) {
      processQueue();
      return;
    }
    // With an outbox, the record is persisted before the processing pass
    // starts: a crash between enqueue and send must not lose the write.
    mutation.seq = ++_seqCounter;
    unawaited(_saveToOutbox(mutation).then((_) => processQueue()));
  }

  /// Persists [mutation] to the outbox. Failures are reported via
  /// `onOutboxError` and never block the in-memory queue.
  Future<void> _saveToOutbox(PendingMutation<T> mutation) async {
    try {
      await outbox!.save(mutation.toRecord());
      // The mutation may have been discarded while the save was in flight;
      // drop the freshly written record so the outbox mirrors the queue.
      if (!_pendingMutations.contains(mutation)) {
        await _deleteFromOutbox(mutation.id);
      }
    } catch (e) {
      notifyObservers((o) => o.onOutboxError(e));
    }
  }

  /// Removes [id]'s record from the outbox. Failures are reported via
  /// `onOutboxError`; a lingering record is replayed on the next recovery,
  /// which is why endpoints should be idempotent.
  Future<void> _deleteFromOutbox(String id) async {
    try {
      await outbox!.delete(id);
    } catch (e) {
      notifyObservers((o) => o.onOutboxError(e));
    }
  }

  /// Clears pending mutations. The currently syncing mutation (if any)
  /// will complete, but no further mutations will be processed after it.
  ///
  /// Every removed mutation's [MutationHandle] is settled with
  /// [MutationDiscarded].
  void clear() {
    final List<PendingMutation<T>> removed;
    // Keep only the in-flight mutation to avoid corrupting the processing loop
    if (_isProcessingQueue && _pendingMutations.isNotEmpty) {
      final current = _pendingMutations.first;
      removed = _pendingMutations.sublist(1);
      _pendingMutations.clear();
      _pendingMutations.add(current);
    } else {
      removed = _pendingMutations.toList();
      _pendingMutations.clear();
    }
    for (final mutation in removed) {
      mutation.settle(MutationDiscarded<T>());
      if (outbox != null) {
        unawaited(_deleteFromOutbox(mutation.id));
      }
    }
    _notifyChanged();
  }

  /// Returns `true` if a mutation was removed, `false` if empty.
  ///
  /// Deprecated: use [removeById] to remove a specific mutation.
  @Deprecated('Use removeById to remove a specific mutation')
  bool removeFirst() {
    if (_pendingMutations.isEmpty) return false;
    final removed = _pendingMutations.removeAt(0);
    removed.settle(MutationDiscarded<T>());
    if (outbox != null) {
      unawaited(_deleteFromOutbox(removed.id));
    }
    _notifyChanged();
    return true;
  }

  /// Removes the pending mutation with the given [id] from the queue and
  /// settles its handle with [MutationDiscarded].
  ///
  /// Returns `true` if a mutation with that id was found and removed.
  /// If the removed mutation was currently syncing, its request may still
  /// reach the server; Syncache simply stops tracking it.
  bool removeById(String id) {
    final index = _pendingMutations.indexWhere((m) => m.id == id);
    if (index < 0) return false;
    final removed = _pendingMutations.removeAt(index);
    removed.settle(MutationDiscarded<T>());
    if (outbox != null) {
      unawaited(_deleteFromOutbox(removed.id));
    }
    _notifyChanged();
    return true;
  }

  /// Re-enqueues persisted outbox records as live pending mutations.
  ///
  /// Loads all records ordered by seq and, for each one the [resolve]
  /// callback successfully maps back to a [Mutation], appends it to the
  /// queue **without re-applying or re-writing** the optimistic update —
  /// the optimistic value was already written to the store before the
  /// process died. The value handed to `send` is re-derived as
  /// `apply(currentCached)` so the user's intent is preserved even if the
  /// cached entry was refreshed while offline.
  ///
  /// Records whose resolver throws — or whose cache entry is gone — are
  /// reported via `onOutboxReplayFailed` and left in the outbox; they are
  /// never dropped silently.
  ///
  /// After recovery the queue is flushed immediately if the network is
  /// online. Records stay in the outbox until each send succeeds, so a
  /// crash mid-replay is safe to recover from again.
  ///
  /// Returns the number of mutations re-enqueued. Returns 0 when no outbox
  /// is configured. Intended to be called once at startup, before
  /// [Syncache.recoverPendingMutations] hands control back to the app.
  Future<int> recover(
    Future<Mutation<T>> Function(PendingMutationRecord record) resolve,
  ) async {
    final outbox = this.outbox;
    if (outbox == null) return 0;

    final records = await outbox.loadAll();
    var reEnqueued = 0;
    for (final record in records) {
      try {
        final cached = await store.read(record.key);
        if (cached == null) {
          throw StateError(
            'No cache entry for key "${record.key}"; '
            'cannot re-derive the value to send.',
          );
        }
        final mutation = await resolve(record);
        final optimisticValue = mutation.apply(cached.value);
        // Seed the seq counter past replayed records so mutations enqueued
        // later in this process order after them.
        if (record.seq > _seqCounter) _seqCounter = record.seq;
        _pendingMutations.add(PendingMutation<T>(
          key: record.key,
          mutation: mutation,
          optimisticValue: optimisticValue,
          payload: record.payload,
          seq: record.seq,
          id: record.id,
        ));
        reEnqueued++;
        _notifyChanged();
      } catch (e) {
        notifyObservers((o) => o.onOutboxReplayFailed(record, e));
      }
    }
    if (reEnqueued > 0) {
      unawaited(processQueue());
    }
    return reEnqueued;
  }

  void dispose() {
    // Settle every outstanding handle (including an in-flight mutation's)
    // so callers awaiting MutationHandle.outcome are never left hanging.
    for (final mutation in _pendingMutations) {
      mutation.settle(MutationDiscarded<T>());
    }
    _pendingMutations.clear();
    // Deliberately NOT clearing the outbox here: preserving records across
    // dispose/recreate is what lets a fresh Syncache replay unsynced
    // writes after a process restart (see [recover]).
    _isProcessingQueue = false;
    _pendingMutationsController?.close();
    _pendingMutationsController = null;
    _isSyncedController?.close();
    _isSyncedController = null;
  }

  void _notifyChanged() {
    if (_pendingMutationsController != null &&
        !_pendingMutationsController!.isClosed) {
      _pendingMutationsController!.add(snapshot);
    }
    if (_isSyncedController != null && !_isSyncedController!.isClosed) {
      _isSyncedController!.add(_pendingMutations.isEmpty);
    }
  }

  /// Processes the pending mutation queue now.
  ///
  /// Idempotent: if a processing pass is already running (or the network
  /// is offline) this returns immediately and the existing pass keeps
  /// running. Used by [Syncache.processPendingMutations] and by the
  /// automatic reconnect flush for [ReactiveNetwork] networks.
  Future<void> processQueue() async {
    if (_isProcessingQueue || !network.isOnline) return;
    _isProcessingQueue = true;

    while (_pendingMutations.isNotEmpty && network.isOnline) {
      final pending = _pendingMutations.first;

      pending.status = PendingMutationStatus.syncing;
      pending.lastAttemptAt = DateTime.now();
      _notifyChanged();

      try {
        final serverValue =
            await pending.mutation.send(pending.optimisticValue);

        var currentValue = serverValue;

        // Re-apply pending mutations for the same key to preserve optimistic
        // updates from mutations that were added while this one was in flight.
        final pendingSnapshot = _pendingMutations.toList();
        for (final pendingMutation in pendingSnapshot) {
          if (pendingMutation.key == pending.key &&
              pendingMutation != pending) {
            currentValue = pendingMutation.mutation.apply(currentValue);
            pendingMutation.optimisticValue = currentValue;
          }
        }

        final cached = await store.read(pending.key);
        final meta = Metadata(
          version: (cached?.meta.version ?? 0) + 1,
          storedAt: DateTime.now(),
          ttl: cached?.meta.ttl,
          etag: cached?.meta.etag,
          lastModified: cached?.meta.lastModified,
        );

        await store.write(pending.key, Stored(value: currentValue, meta: meta));
        notifyObservers((o) => o.onStore(pending.key));
        notifyObservers((o) => o.onMutationSuccess(pending.key));
        await notifyWatchers(pending.key);
        await performInvalidations(pending.invalidates, pending.invalidateTags);

        // Remove by identity: if this mutation was removed from the queue
        // while in flight, removing the first element would drop an
        // unrelated mutation instead.
        _pendingMutations.remove(pending);
        if (outbox != null) {
          unawaited(_deleteFromOutbox(pending.id));
        }
        pending.settle(MutationSuccess(serverValue));
        _notifyChanged();
      } catch (e, st) {
        pending.lastError = e;
        notifyObservers((o) => o.onMutationError(pending.key, e, st));

        final shouldRetry = retryConfig.shouldRetry(e) &&
            pending.retryCount < retryConfig.maxAttempts;

        if (!shouldRetry) {
          pending.status = PendingMutationStatus.failed;
          _notifyChanged();

          _pendingMutations.remove(pending);
          if (outbox != null) {
            unawaited(_deleteFromOutbox(pending.id));
          }
          notifyObservers((o) => o.onMutationRetryExhausted(
              pending.key, pending.retryCount + 1, e));
          pending.settle(MutationFailure<T>(
            error: e,
            stackTrace: st,
            retried: pending.retryCount,
          ));
          _notifyChanged();
          continue;
        }

        pending.status = PendingMutationStatus.retrying;
        _notifyChanged();

        final delay = retryConfig.delay(pending.retryCount);
        notifyObservers((o) =>
            o.onMutationRetry(pending.key, pending.retryCount, e, delay));

        pending.retryCount++;
        await Future<void>.delayed(delay);

        if (!network.isOnline) {
          pending.status = PendingMutationStatus.pending;
          _notifyChanged();
          break;
        }
      }
    }

    _isProcessingQueue = false;
  }
}
