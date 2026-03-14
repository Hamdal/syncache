import 'dart:async';

import 'cancellation.dart';
import 'fetcher.dart';
import 'metadata.dart';
import 'observer.dart';
import 'retry.dart';
import 'store.dart';
import 'stored.dart';

typedef StoreWriter<T> = Future<void> Function(
    String key, Stored<T> entry, List<String>? tags);

/// Handles fetch operations with retry, cancellation, and request deduplication.
class FetchEngine<T> {
  final Store<T> store;
  final StoreWriter<T> writeToStore;
  final void Function(void Function(SyncacheObserver observer)) notifyObservers;
  final Map<String, Future<T>> _inFlight = {};

  FetchEngine({
    required this.store,
    required this.writeToStore,
    required this.notifyObservers,
  });

  /// Fetches and stores a value with request deduplication.
  ///
  /// If there's already an in-flight request for [key], returns the existing
  /// Future. The caller's cancellation token is still respected when joining.
  Future<T> fetchAndStore(
    String key,
    Fetcher<T> fetch,
    Duration? ttl,
    RetryConfig retry,
    CancellationToken? cancel, [
    List<String>? tags,
  ]) {
    cancel?.throwIfCancelled();

    if (_inFlight.containsKey(key)) {
      final existing = _inFlight[key]!;
      if (cancel == null) {
        return existing;
      }
      return _wrapWithCancellation(existing, cancel);
    }

    final future = _doFetchAndStore(key, fetch, ttl, retry, cancel, tags);
    _inFlight[key] = future;

    return future.whenComplete(() => _inFlight.remove(key));
  }

  /// Fetches using ConditionalFetcher (no deduplication since result depends
  /// on cached metadata at call time).
  Future<T> fetchAndStoreConditional(
    String key,
    ConditionalFetcher<T> fetch,
    Duration? ttl,
    RetryConfig retry,
    CancellationToken? cancel, [
    List<String>? tags,
  ]) {
    cancel?.throwIfCancelled();
    return _doFetchAndStoreConditional(key, fetch, ttl, retry, cancel, tags);
  }

  void clear() {
    _inFlight.clear();
  }

  Future<T> _wrapWithCancellation(Future<T> future, CancellationToken cancel) {
    final completer = Completer<T>();

    void onCancel() {
      if (!completer.isCompleted) {
        completer.completeError(CancelledException());
      }
    }

    cancel.onCancel(onCancel);

    future.then((value) {
      cancel.removeOnCancel(onCancel);
      if (!completer.isCompleted) {
        completer.complete(value);
      }
    }).catchError((Object error, StackTrace stackTrace) {
      cancel.removeOnCancel(onCancel);
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    });

    return completer.future;
  }

  /// Wraps a simple Fetcher as a ConditionalFetcher.
  Future<T> _doFetchAndStore(
    String key,
    Fetcher<T> fetch,
    Duration? ttl,
    RetryConfig retry,
    CancellationToken? cancel, [
    List<String>? tags,
  ]) {
    Future<FetchResult<T>> conditionalFetch(SyncacheRequest request) async {
      final value = await fetch(request);
      return FetchResult.data(value);
    }

    return _doFetchAndStoreConditional(
        key, conditionalFetch, ttl, retry, cancel, tags);
  }

  Future<T> _doFetchAndStoreConditional(
    String key,
    ConditionalFetcher<T> fetch,
    Duration? ttl,
    RetryConfig retry,
    CancellationToken? cancel, [
    List<String>? tags,
  ]) async {
    cancel?.throwIfCancelled();

    final cached = await store.read(key);
    final headers = _buildConditionalHeaders(cached?.meta);
    final request = SyncacheRequest(headers: headers);

    Object? lastError;
    StackTrace? lastStack;

    for (var attempt = 0; attempt <= retry.maxAttempts; attempt++) {
      if (cancel?.isCancelled ?? false) {
        notifyObservers((o) => o.onFetchCancelled(key));
        throw CancelledException();
      }

      notifyObservers((o) => o.onFetchStart(key));
      final stopwatch = Stopwatch()..start();

      try {
        final result = await fetch(request);

        if (cancel?.isCancelled ?? false) {
          stopwatch.stop();
          notifyObservers((o) => o.onFetchCancelled(key));
          throw CancelledException();
        }

        stopwatch.stop();
        notifyObservers((o) => o.onFetchSuccess(key, stopwatch.elapsed));

        if (result.isNotModified) {
          if (cached == null) {
            throw CacheMissForConditionalException(key);
          }
          final refreshedMeta = cached.meta.copyWith(
            storedAt: DateTime.now(),
            ttl: ttl ?? cached.meta.ttl,
          );
          await writeToStore(
              key, Stored<T>(value: cached.value, meta: refreshedMeta), tags);
          notifyObservers((o) => o.onStore(key));
          return cached.value;
        }

        final meta = Metadata(
          version: (cached?.meta.version ?? 0) + 1,
          storedAt: DateTime.now(),
          ttl: ttl,
          etag: result.etag ?? cached?.meta.etag,
          lastModified: result.lastModified ?? cached?.meta.lastModified,
        );

        await writeToStore(
            key, Stored<T>(value: result.value as T, meta: meta), tags);
        notifyObservers((o) => o.onStore(key));

        return result.value as T;
      } on CancelledException {
        stopwatch.stop();
        notifyObservers((o) => o.onFetchCancelled(key));
        rethrow;
      } catch (e, st) {
        stopwatch.stop();
        lastError = e;
        lastStack = st;
        notifyObservers((o) => o.onFetchError(key, e, st));

        final shouldRetry = attempt < retry.maxAttempts &&
            retry.shouldRetry(e) &&
            !(cancel?.isCancelled ?? false);

        if (!shouldRetry) {
          if (cancel?.isCancelled ?? false) {
            notifyObservers((o) => o.onFetchCancelled(key));
            throw CancelledException();
          }
          break;
        }

        final delay = retry.delay(attempt);
        notifyObservers((o) => o.onRetry(key, attempt, e, delay));

        await _delayWithCancellation(delay, cancel);

        if (cancel?.isCancelled ?? false) {
          notifyObservers((o) => o.onFetchCancelled(key));
          throw CancelledException();
        }
      }
    }

    if (retry.maxAttempts > 0) {
      notifyObservers(
          (o) => o.onRetryExhausted(key, retry.maxAttempts + 1, lastError!));
    }

    Error.throwWithStackTrace(lastError!, lastStack!);
  }

  Future<void> _delayWithCancellation(
      Duration delay, CancellationToken? cancel) async {
    if (cancel == null) {
      await Future.delayed(delay);
      return;
    }

    final completer = Completer<void>();

    void onCancel() {
      if (!completer.isCompleted) {
        completer.completeError(CancelledException());
      }
    }

    cancel.onCancel(onCancel);

    Future.delayed(delay).then((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      await completer.future;
    } finally {
      cancel.removeOnCancel(onCancel);
    }
  }

  Map<String, String> _buildConditionalHeaders(Metadata? meta) {
    if (meta == null) return const {};
    final headers = <String, String>{};

    if (meta.etag != null) {
      headers['If-None-Match'] = meta.etag!;
    }

    if (meta.lastModified != null) {
      headers['If-Modified-Since'] = formatHttpDate(meta.lastModified!);
    }

    return headers;
  }

  /// Formats a DateTime as HTTP date: "Wed, 21 Oct 2015 07:28:00 GMT"
  static String formatHttpDate(DateTime date) {
    final utc = date.toUtc();
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final weekday = weekdays[utc.weekday - 1];
    final day = utc.day.toString().padLeft(2, '0');
    final month = months[utc.month - 1];
    final year = utc.year;
    final hour = utc.hour.toString().padLeft(2, '0');
    final minute = utc.minute.toString().padLeft(2, '0');
    final second = utc.second.toString().padLeft(2, '0');
    return '$weekday, $day $month $year $hour:$minute:$second GMT';
  }
}

/// Thrown when a conditional fetch returns 304 but no cached value exists.
class CacheMissForConditionalException implements Exception {
  final String key;

  const CacheMissForConditionalException(this.key);

  @override
  String toString() =>
      'CacheMissForConditionalException: No cached value for key: $key';
}
