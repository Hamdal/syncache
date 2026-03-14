import 'dart:async';

import 'metadata.dart';
import 'mutation.dart';
import 'network.dart';
import 'observer.dart';
import 'pending_mutation_info.dart';
import 'retry.dart';
import 'store.dart';
import 'stored.dart';

int _mutationIdCounter = 0;

class PendingMutation<T> {
  final String id;
  final String key;
  final Mutation<T> mutation;

  /// Mutable because it's updated when earlier mutations complete and the
  /// base value changes. Subsequent pending mutations for the same key have
  /// their `apply` functions re-applied on top of the new server value.
  T optimisticValue;

  int retryCount;
  final DateTime queuedAt;
  DateTime? lastAttemptAt;
  Object? lastError;
  PendingMutationStatus status;
  final List<String>? invalidates;
  final List<String>? invalidateTags;

  PendingMutation({
    required this.key,
    required this.mutation,
    required this.optimisticValue,
    this.retryCount = 0,
    this.invalidates,
    this.invalidateTags,
  })  : id = 'mut_${++_mutationIdCounter}',
        queuedAt = DateTime.now(),
        status = PendingMutationStatus.pending;

  PendingMutationInfo toInfo() {
    return PendingMutationInfo(
      id: id,
      key: key,
      retryCount: retryCount,
      queuedAt: queuedAt,
      lastAttemptAt: lastAttemptAt,
      lastError: lastError,
      status: status,
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
  final void Function(void Function(SyncacheObserver observer)) notifyObservers;
  final NotifyCallback notifyWatchers;
  final InvalidationCallback performInvalidations;

  final List<PendingMutation<T>> _pendingMutations = [];
  bool _isProcessingQueue = false;
  StreamController<List<PendingMutationInfo>>? _pendingMutationsController;
  StreamController<bool>? _isSyncedController;
  MutationQueue({
    required this.store,
    required this.network,
    required this.retryConfig,
    required this.notifyObservers,
    required this.notifyWatchers,
    required this.performInvalidations,
  });

  int get count => _pendingMutations.length;
  bool get hasPending => _pendingMutations.isNotEmpty;

  List<PendingMutationInfo> get snapshot =>
      _pendingMutations.map((m) => m.toInfo()).toList();

  /// Emits a new list whenever the pending mutations change.
  Stream<List<PendingMutationInfo>> get stream {
    _pendingMutationsController ??=
        StreamController<List<PendingMutationInfo>>.broadcast();
    return _pendingMutationsController!.stream;
  }

  /// Emits `true` when all mutations are synced, `false` otherwise.
  Stream<bool> get isSyncedStream {
    _isSyncedController ??= StreamController<bool>.broadcast();
    return _isSyncedController!.stream;
  }

  void add(PendingMutation<T> mutation) {
    _pendingMutations.add(mutation);
    _notifyChanged();
    _processQueue();
  }

  /// Clears pending mutations. The currently syncing mutation (if any)
  /// will complete, but no further mutations will be processed after it.
  void clear() {
    // Keep only the in-flight mutation to avoid corrupting the processing loop
    if (_isProcessingQueue && _pendingMutations.isNotEmpty) {
      final current = _pendingMutations.first;
      _pendingMutations.clear();
      _pendingMutations.add(current);
    } else {
      _pendingMutations.clear();
    }
    _notifyChanged();
  }

  /// Returns `true` if a mutation was removed, `false` if empty.
  bool removeFirst() {
    if (_pendingMutations.isEmpty) return false;
    _pendingMutations.removeAt(0);
    _notifyChanged();
    return true;
  }

  void dispose() {
    _pendingMutationsController?.close();
    _pendingMutationsController = null;
    _isSyncedController?.close();
    _isSyncedController = null;
    _pendingMutations.clear();
    _isProcessingQueue = false;
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

  Future<void> _processQueue() async {
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

        _pendingMutations.removeAt(0);
        _notifyChanged();
      } catch (e, st) {
        pending.lastError = e;
        notifyObservers((o) => o.onMutationError(pending.key, e, st));

        final shouldRetry = retryConfig.shouldRetry(e) &&
            pending.retryCount < retryConfig.maxAttempts;

        if (!shouldRetry) {
          pending.status = PendingMutationStatus.failed;
          _notifyChanged();

          _pendingMutations.removeAt(0);
          notifyObservers((o) => o.onMutationRetryExhausted(
              pending.key, pending.retryCount + 1, e));
          _notifyChanged();
          continue;
        }

        pending.status = PendingMutationStatus.retrying;
        _notifyChanged();

        final delay = retryConfig.delay(pending.retryCount);
        notifyObservers((o) =>
            o.onMutationRetry(pending.key, pending.retryCount, e, delay));

        pending.retryCount++;
        await Future.delayed(delay);

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
