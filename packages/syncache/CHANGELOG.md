# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.2.0

### BREAKING CHANGES

- **Invalidation no longer closes watch streams.** `invalidate`,
  `invalidateTag`, `invalidateTags`, `invalidatePattern`, and `clear` used to
  close the affected watchers' streams (a `CacheBuilder` landed in
  `ConnectionState.done` and never recovered). Invalidation now refetches each
  affected watcher with the fetch/policy/ttl it was created with: fresh data is
  emitted on success, the error is emitted as a stream error on failure (the
  stream stays open), and `Policy.cacheOnly` watchers receive a
  `CacheMissException` without closing. Listeners keep the last value until the
  refetch completes (stale-while-invalidated). `ConnectionState.done` now only
  occurs when every listener unsubscribes or the cache is disposed. Code that
  relied on a stream's `onDone` firing after invalidation must be updated.
- **`mutate()` returns `Future<MutationHandle<T>>`** (previously
  `Future<void>`). Plain `await cache.mutate(...)` call sites keep compiling;
  only code that explicitly typed the result is affected. The handle resolves
  with a sealed `MutationOutcome`: `MutationSuccess(serverValue)`,
  `MutationFailure(error, stackTrace, retried)`, or `MutationDiscarded`.
- **`clear()` gains an optional `refetchWatchers` parameter** (default `true`,
  so existing calls keep refetching — which is the new behavior instead of
  closing streams). Pass `clear(refetchWatchers: false)` for silent bulk wipes.
  The flag is also available on `clearScope` and `ScopedSyncache.clear`.
- **`ReactiveNetwork` added to core.** A `Network` that also exposes
  `onConnectivityChanged`. Custom `Network` classes are unaffected; see below.

### Added

- **Automatic mutation flush on reconnect.** When the provided `network` is a
  `ReactiveNetwork`, `Syncache` subscribes to its connectivity changes and
  processes pending mutations as soon as the device is back online — no new
  `mutate()` call required. Queued mutations are no longer only processed when
  the next mutation is enqueued.
- `Syncache.processPendingMutations()` — force a queue pass manually
  (idempotent while a pass is running or the network is offline).
- `Syncache.removePendingMutation(String id)` — remove a specific queued
  mutation by its `PendingMutationInfo.id`; the mutation's handle settles with
  `MutationDiscarded`. `removeFirstPendingMutation()` is deprecated in favor of
  this.
- `MutationHandle` / sealed `MutationOutcome` (`MutationSuccess`,
  `MutationFailure`, `MutationDiscarded`) — await a specific mutation's server
  confirmation, retry exhaustion, or removal.
- Seeded queue streams: `pendingMutationsStream` and `isSyncedStream` now emit
  their current state to every new listener before live updates, so late
  subscribers (e.g. a sync indicator built after mutations were queued) see the
  present state immediately.
- `Syncache.clearScope` / `ScopedSyncache.clear` accept `refetchWatchers`.

### Fixed

- Removing an in-flight mutation (via queue control) no longer makes the
  processing loop drop the *next* queued mutation on completion — mutations are
  now removed by identity instead of by position.

## 0.1.2

### Fixed

- `mutateListItem` with `updateWhere` now sends the item matching the predicate (previously it sent the first item of the list and never evaluated the predicate)
- `mutateListItem` with `removeWhere` now calls `send` once per removed item, deduplicated by `idSelector` (previously the server call was silently skipped)
- Plain `write` now preserves existing tags on all `TaggableStore` implementations — behavior was previously inconsistent between `MemoryStore`/`SharedMemoryStore` (preserve) and `HiveStore` (clear). The contract is now documented on `TaggableStore`: plain `write` preserves tags, `writeWithTags` replaces them
- `CacheMissForConditionalException` is now exported from the public API and extends `CacheMissException`, so conditional cache misses can be caught with a single `on CacheMissException` clause
- `ScopedSyncache.prefetch` now passes through `PrefetchRequest.retry`
- Documentation: fixed the `Network`, `RetryConfig`, and `SyncacheObserver` examples; policy table now includes `cacheAndRefresh`

### Added

- `ScopedSyncache.set` and `ScopedSyncache.watchWithDependencies`
- `ScopedSyncache.prefetchOne` accepts a `retry` parameter
- Shared `TaggableStore` conformance suite covering tag lifecycle semantics
- Tests for `getConditional` (conditional headers, 304 handling, cache-miss behavior)

## 0.1.1

- Add `Policy.cacheAndRefresh` - returns cached data immediately and always refreshes in background (unlike `staleWhileRefresh` which only refreshes when expired)

## 0.1.0

- Initial release
- Core caching with five policies: offlineFirst, cacheOnly, networkOnly, refresh, staleWhileRefresh
- Reactive streams via `watch()` and `watchWithMeta()`
- Optimistic mutations with automatic background sync
- Tag-based cache invalidation
- Pattern-based cache invalidation (glob support)
- Request deduplication for concurrent fetches
- Retry with exponential backoff
- Cancellation token support
- Scoped caches with key prefixing
- Parallel and dependency-graph prefetching
- Observer pattern for logging and analytics
- MemoryStore and SharedMemoryStore implementations
