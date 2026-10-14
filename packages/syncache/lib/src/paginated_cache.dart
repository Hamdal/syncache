import 'dart:async';

import 'observer.dart';
import 'syncache.dart';

/// The result of fetching one page for a [PaginatedCache].
///
/// Named `PageResult` (not `Page`) to avoid clashing with material's `Page`
/// route class in Flutter apps.
///
/// ```dart
/// Future<PageResult<Post>> fetchPage(Object? pageKey) async {
///   final response = await api.fetchPosts(cursor: pageKey as String?);
///   return PageResult(
///     response.items,
///     nextPageKey: response.nextCursor, // null ⇒ no more pages
///   );
/// }
/// ```
class PageResult<T> {
  /// The items on this page, in server order. May be empty.
  final List<T> items;

  /// The key to pass to the fetcher for the *next* page, or `null` when
  /// this was the last page. Opaque to Syncache — the fetcher owns its
  /// meaning (page numbers, cursors, …); values must implement `==`
  /// (ints and strings do).
  final Object? nextPageKey;

  const PageResult(this.items, {this.nextPageKey});

  @override
  String toString() =>
      'PageResult(${items.length} item(s), nextPageKey: $nextPageKey)';
}

/// An immutable snapshot of a [PaginatedCache]'s window and fetch state.
///
/// Obtained via [PaginatedCache.state] and emitted on
/// [PaginatedCache.watch]. Implements structural equality so Flutter
/// builders only rebuild when something actually changed.
class PagedViewState<T> {
  /// The current window contents (a fresh unmodifiable list on every
  /// emission).
  final List<T> items;

  /// Whether more pages exist server-side. Re-opens on [PaginatedCache.refresh]
  /// and invalidation; goes `false` when a fetch returns `nextPageKey: null`.
  final bool hasMore;

  /// True while the very first page is in flight (empty window before it).
  final bool isLoading;

  /// True while a subsequent page is being appended.
  final bool isLoadingMore;

  /// True while [PaginatedCache.refresh] or an invalidation refetch is in
  /// flight.
  final bool isRefreshing;

  /// The last page-fetch error, if any. Cleared on the next successful
  /// fetch. Fetch failures never throw — they surface here.
  final Object? error;

  const PagedViewState({
    this.items = const [],
    this.hasMore = true,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.isRefreshing = false,
    this.error,
  });

  @override
  bool operator ==(Object other) =>
      other is PagedViewState<T> &&
      other.hasMore == hasMore &&
      other.isLoading == isLoading &&
      other.isLoadingMore == isLoadingMore &&
      other.isRefreshing == isRefreshing &&
      other.error == error &&
      _listsEqual(other.items, items);

  @override
  int get hashCode => Object.hash(
        hasMore,
        isLoading,
        isLoadingMore,
        isRefreshing,
        error,
        Object.hashAll(items),
      );

  @override
  String toString() => 'PagedViewState(${items.length} item(s), '
      'hasMore: $hasMore, loading: $isLoading/$isLoadingMore/$isRefreshing, '
      'error: $error)';

  static bool _listsEqual(List<Object?> a, List<Object?> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Infinite-list cache over a [Syncache]: fetches pages one at a time,
/// accumulates them into a **windowed list stored as a normal cached value**
/// under [key], and exposes it as reactive [watch] state.
///
/// Because the window is a plain cached `List<T>`, everything the cache
/// already does applies to it: persistence via any `Store`, optimistic
/// mutations via `SyncacheListExtension.mutateList` / `ListOperation`
/// (durable through a `MutationOutbox`), and invalidation by pattern or tag
/// — `invalidatePattern('posts?*')` reaches the window key like any other.
///
/// ## Semantics
///
/// - [loadMore] appends the next page. Page-fetch failures keep the window
///   and the cursor unchanged (safe to retry) and surface via
///   [PagedViewState.error] — the returned future never throws. Concurrent
///   calls coalesce into one fetch.
/// - [refresh] re-fetches the **first page** and merges: fresh items win at
///   the front, duplicates (by `==`) are removed from the retained tail.
/// - External invalidation of [key] (pattern, tag, or direct) **drops the
///   tail and re-fetches page 1** when `autoRefreshOnInvalidation` is true
///   (default). Eviction and `clear` reset the paging state but never
///   auto-refetch (capacity events cause no refill storms).
/// - `maxItems` bounds the window by dropping from the **front**; the
///   server cursor is unaffected.
/// - The page cursor is in-memory. After a process restart the stored
///   window rehydrates, the cursor resets to [firstPageKey], and a
///   `loadMore` on a non-empty window **refresh-merges** instead of
///   appending — so it can never duplicate the rehydrated items.
///
/// ## Mutating the window
///
/// Do not go through [PaginatedCache] — mutate the underlying cache
/// directly; the state stream follows automatically:
///
/// ```dart
/// final posts = PaginatedCache<Post>(
///   cache: listCache, // Syncache<List<Post>>
///   key: 'posts?feed=home',
///   fetchPage: (pageKey) async {
///     final response = await api.fetchPosts(cursor: pageKey as String?);
///     return PageResult(response.items, nextPageKey: response.nextCursor);
///   },
///   maxItems: 500,
/// );
///
/// await posts.loadMore();
///
/// // Optimistic append, durable via the configured outbox:
/// await listCache.mutateList(
///   key: 'posts?feed=home',
///   operation: ListOperation.append(newPost),
///   send: () => api.createPost(newPost),
///   // Invalidate ITEM keys, never the window itself — a mutation that
///   // invalidates its own window key drops the tail on every sync.
///   invalidates: ['post:*'],
/// );
/// ```
///
/// One [PaginatedCache] per cache key: two instances over the same key
/// would both fetch and fight over the window. For scoped caches, pass the
/// underlying `Syncache` and the already-prefixed key
/// (`cache.scoped('s').cache` / `'s:posts'`).
class PaginatedCache<T> {
  final Syncache<List<T>> _cache;
  final String key;
  final Future<PageResult<T>> Function(Object? pageKey) _fetchPage;

  /// The key of the very first page (opaque; often `null` for cursor APIs).
  final Object? firstPageKey;

  /// Maximum number of items kept in the window. When exceeded, items are
  /// dropped from the **front** (the oldest pages). `null` = unbounded.
  final int? maxItems;

  final bool _autoRefreshOnInvalidation;

  /// In-memory paging state. The window itself lives in the store; these
  /// fields die with the instance (see the restart rule in [loadMore]).
  Object? _cursor;
  List<T> _items = <T>[];
  bool _hasMore = true;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isRefreshing = false;
  Object? _error;

  /// Bumped whenever the window is invalidated externally or the instance
  /// is disposed; in-flight fetches compare generations and discard
  /// themselves when theirs is stale.
  int _generation = 0;

  /// The single in-flight page fetch, for call coalescing.
  Future<void>? _inFlight;

  /// Suppresses the store-write echo while PaginatedCache itself writes.
  bool _writing = false;

  /// Coalesces bursts of external store events into one re-read.
  bool _syncScheduled = false;

  /// Set by `onInvalidate` so the coalesced sync knows eviction/clear
  /// (`false`) from invalidation (`true`) for the auto-refresh decision.
  bool _autoRefreshPending = false;

  StreamController<PagedViewState<T>>? _controller;
  bool _disposed = false;

  late final Future<void> _initFuture;
  late final _PaginatedObserver<T> _observer;

  /// Creates a paginated cache over [cache]'s window at [key].
  ///
  /// On construction the stored window (if any) is rehydrated; otherwise an
  /// empty window is seeded so window mutations work before the first page
  /// fetch. No page is fetched until [loadMore] or [refresh] is called.
  PaginatedCache({
    required Syncache<List<T>> cache,
    required this.key,
    required Future<PageResult<T>> Function(Object? pageKey) fetchPage,
    this.firstPageKey,
    this.maxItems,
    bool autoRefreshOnInvalidation = true,
  })  : _cache = cache,
        _fetchPage = fetchPage,
        _autoRefreshOnInvalidation = autoRefreshOnInvalidation,
        _cursor = firstPageKey {
    _observer = _PaginatedObserver<T>(this);
    _initFuture = _initialize();
    _cache.addObserver(_observer);
  }

  /// The current window and fetch state.
  PagedViewState<T> get state => _snapshot();

  /// Emits a new [PagedViewState] whenever the window or fetch state
  /// changes. Seeded: every listener first receives the current state.
  /// A stream over a disposed instance completes immediately.
  Stream<PagedViewState<T>> get watch {
    if (_disposed) return Stream<PagedViewState<T>>.empty();
    final controller =
        _controller ??= StreamController<PagedViewState<T>>.broadcast();
    return Stream<PagedViewState<T>>.multi((listener) {
      listener.add(_snapshot());
      final subscription = controller.stream.listen(
        listener.add,
        onError: listener.addError,
        onDone: listener.close,
      );
      listener.onCancel = subscription.cancel;
    });
  }

  /// Fetches the next page and appends it to the window.
  ///
  /// Coalesces with any in-flight fetch (the returned future completes with
  /// it). No-ops when [PagedViewState.hasMore] is false. When the cursor
  /// still points at the first page while the window is non-empty — the
  /// state right after a restart — this refresh-merges instead of appending
  /// so the rehydrated window is never duplicated.
  ///
  /// Fetch failures never throw: they set [PagedViewState.error], leaving
  /// window and cursor unchanged so a retry re-fetches the same page.
  Future<void> loadMore() {
    if (_disposed) return Future.value();
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    return _run(() async {
      await _initFuture;
      if (_disposed) return;
      if (!_hasMore) return;
      if (_cursor == firstPageKey && _items.isNotEmpty) {
        // Restart rule: the stored window predates this instance's cursor.
        // Appending page 1 would duplicate it — merge instead.
        await _fetchAndMerge();
        return;
      }
      await _fetchAndAppend();
    });
  }

  /// Re-fetches the first page and merges it into the window: fresh items
  /// win at the front, duplicates (by `==`) are dropped from the retained
  /// tail. Use this for pull-to-refresh semantics — scroll position and
  /// tail survive.
  Future<void> refresh() {
    if (_disposed) return Future.value();
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    return _run(() async {
      await _initFuture;
      if (_disposed) return;
      await _fetchAndMerge();
    });
  }

  /// Drops the window and re-fetches the first page.
  ///
  /// This is the explicit form of what external invalidation does
  /// automatically (see `autoRefreshOnInvalidation`): the tail is discarded
  /// rather than merged, because post-invalidation it is known-stale.
  Future<void> invalidate() {
    if (_disposed) return Future.value();
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    return _run(() async {
      await _initFuture;
      if (_disposed) return;
      _generation++;
      _cursor = firstPageKey;
      _items = <T>[];
      _hasMore = true;
      _error = null;
      _isRefreshing = true;
      _emit();
      await _fetchFirstPageAndWrite();
    });
  }

  /// Detaches from the cache. The stored window survives; in-flight fetch
  /// results are discarded; the [watch] stream closes.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _cache.removeObserver(_observer);
    _controller?.close();
    _controller = null;
  }

  // ============================================================
  // Internals
  // ============================================================

  /// Rehydrates a persisted window, or seeds an empty one so window
  /// mutations (mutateList) work before the first page fetch.
  Future<void> _initialize() async {
    try {
      final cached = await _cache.store.read(key);
      if (_disposed) return;
      if (cached != null) {
        _items = _trim(List<T>.of(cached.value));
      } else {
        await _writeWindow(_items);
      }
    } catch (_) {
      // A store failure must not break construction; the state stays
      // empty and the first loadMore/refresh still works.
    }
    _emit();
  }

  /// Shared wrapper: registers the in-flight future for coalescing and
  /// clears it when done. The tracked (whenComplete-wrapped) future is what
  /// coalesced callers receive, so `identical` holds across calls.
  /// [operation] runs synchronously up to its first await, so flag updates
  /// are visible before any suspension.
  Future<void> _run(Future<void> Function() operation) {
    Future<void>? tracked;
    tracked = operation().whenComplete(() {
      if (identical(_inFlight, tracked)) _inFlight = null;
    });
    _inFlight = tracked;
    return tracked;
  }

  Future<void> _fetchAndAppend() async {
    _isLoadingMore = true;
    _isLoading = _items.isEmpty;
    _emit();
    final generation = _generation;
    final cursor = _cursor;
    try {
      final page = await _fetchPage(cursor);
      if (_disposed || generation != _generation) return;
      _items = _trim(List<T>.of(_items)..addAll(page.items));
      _cursor = page.nextPageKey;
      _hasMore = page.nextPageKey != null;
      _error = null;
      await _writeWindow(_items);
    } catch (e) {
      if (_disposed || generation != _generation) return;
      // Cursor and window untouched: the retry re-fetches the same page.
      _error = e;
    } finally {
      if (!_disposed) {
        _isLoadingMore = false;
        _isLoading = false;
        _emit();
      }
    }
  }

  Future<void> _fetchAndMerge() async {
    _isRefreshing = true;
    _emit();
    final generation = _generation;
    try {
      final page = await _fetchPage(firstPageKey);
      if (_disposed || generation != _generation) return;
      final fresh = page.items;
      // One-sided dedupe: the fresh page wins; equal items are dropped
      // from the retained tail, whose order is preserved.
      final tail = _items.where((item) => !fresh.contains(item)).toList();
      _items = _trim([...fresh, ...tail]);
      _cursor = page.nextPageKey;
      _hasMore = page.nextPageKey != null;
      _error = null;
      await _writeWindow(_items);
    } catch (e) {
      if (_disposed || generation != _generation) return;
      _error = e;
    } finally {
      if (!_disposed) {
        _isRefreshing = false;
        _emit();
      }
    }
  }

  /// The fetch half of [invalidate] (and of external-invalidation
  /// auto-refresh): replace the window with the fresh first page.
  Future<void> _fetchFirstPageAndWrite() async {
    final generation = _generation;
    try {
      final page = await _fetchPage(firstPageKey);
      if (_disposed || generation != _generation) return;
      _items = _trim(List<T>.of(page.items));
      _cursor = page.nextPageKey;
      _hasMore = page.nextPageKey != null;
      _error = null;
      await _writeWindow(_items);
    } catch (e) {
      if (_disposed || generation != _generation) return;
      _error = e;
    } finally {
      if (!_disposed) {
        _isRefreshing = false;
        _emit();
      }
    }
  }

  /// Keeps at most [maxItems], dropping from the front.
  List<T> _trim(List<T> window) {
    final cap = maxItems;
    if (cap == null || window.length <= cap) return window;
    return window.sublist(window.length - cap);
  }

  Future<void> _writeWindow(List<T> items) async {
    _writing = true;
    try {
      // No TTL: an expiring window would silently drop mid-scroll (see
      // class doc). Fires onStore, which the echo-suppression skips.
      await _cache.set(key: key, value: List<T>.of(items));
    } finally {
      _writing = false;
    }
    _emit();
  }

  PagedViewState<T> _snapshot() => PagedViewState<T>(
        items: List<T>.unmodifiable(_items),
        hasMore: _hasMore,
        isLoading: _isLoading,
        isLoadingMore: _isLoadingMore,
        isRefreshing: _isRefreshing,
        error: _error,
      );

  void _emit() {
    final controller = _controller;
    if (controller != null && !controller.isClosed) {
      controller.add(_snapshot());
    }
  }

  // ------------------------------------------------------------
  // External store events (via the observer registered in the ctor)
  // ------------------------------------------------------------

  /// A write to our key from outside (optimistic mutation, `set`, …):
  /// re-read the window so the state stream reflects it.
  void _onExternalStoreWrite() => _scheduleSync();

  /// Our key was invalidated externally: drop the tail, reset the cursor,
  /// and (by default) re-fetch the first page.
  void _onExternalInvalidation() {
    if (_disposed) return;
    _autoRefreshPending = _autoRefreshOnInvalidation;
    _resetPagingState();
    if (_autoRefreshOnInvalidation) {
      unawaited(_run(_fetchFirstPageAndWrite));
    }
  }

  /// Our key was evicted (capacity event) or the cache cleared: reset the
  /// paging state, never auto-refetch (no refill storms).
  void _onExternalRemoval() {
    if (_disposed) return;
    _autoRefreshPending = false;
    _resetPagingState();
  }

  /// Resets in-memory paging state because the store lost the window
  /// (invalidation, eviction, clear). Emits the emptied state.
  void _resetPagingState() {
    _generation++;
    _cursor = firstPageKey;
    _items = <T>[];
    _hasMore = true;
    _error = null;
    _emit();
  }

  /// Coalesces external store-write events into a single re-read per
  /// microtask, so mutation sequences (optimistic write + confirmed write)
  /// produce one state emission.
  void _scheduleSync() {
    if (_disposed || _writing || _syncScheduled) return;
    _syncScheduled = true;
    Future<void>.microtask(() async {
      _syncScheduled = false;
      if (_disposed) return;
      try {
        final cached = await _cache.store.read(key);
        if (_disposed || _writing) return;
        if (cached == null) {
          // The entry is gone (invalidation raced us, eviction, clear).
          // onInvalidate/onEvict/onClear handle the paging reset; this is
          // just a safety net.
          if (!_autoRefreshPending) _resetPagingState();
          return;
        }
        final window = List<T>.of(cached.value);
        final trimmed = _trim(window);
        final changed = !_listsEqual(trimmed, _items);
        _items = trimmed;
        if (changed) _emit();
      } catch (_) {
        // Store read failures leave the current state in place.
      }
    });
  }

  static bool _listsEqual(List<Object?> a, List<Object?> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Internal observer wiring one [PaginatedCache] into its cache's event
/// stream. Filters by the window key before delegating.
class _PaginatedObserver<T> extends SyncacheObserver {
  final PaginatedCache<T> _owner;

  _PaginatedObserver(this._owner);

  @override
  void onStore(String key) {
    if (key == _owner.key) _owner._onExternalStoreWrite();
  }

  @override
  void onInvalidate(String key) {
    if (key == _owner.key) _owner._onExternalInvalidation();
  }

  @override
  void onEvict(String key) {
    if (key == _owner.key) _owner._onExternalRemoval();
  }

  @override
  void onClear() => _owner._onExternalRemoval();
}
