# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.6.0

### Added

- **Pagination / infinite lists.** `PaginatedCache<T>` (core) fetches pages
  one at a time and accumulates them into a windowed list stored as a
  normal cached value — so persistence, `mutateList`/`ListOperation`
  optimistic edits, outbox durability, and pattern/tag invalidation all
  work on paginated data. Includes: `loadMore` (coalesced, failure-safe,
  cursor-preserving), `refresh` (re-fetch page 1 and merge, deduping the
  tail by `==`), `invalidate` (re-fetch page 1, drop the tail), `maxItems`
  front-trimming, automatic refetch on external invalidation
  (`autoRefreshOnInvalidation`, default on; eviction/clear never refetch),
  and a post-restart rule that refresh-merges instead of duplicating the
  rehydrated window. Flutter: `PaginatedCacheBuilder<T>` — a thin builder
  exposing state plus a `loadMore` callback; scroll wiring stays app-owned.
- **Dynamic observer registration.** `Syncache.addObserver(observer)` /
  `removeObserver(observer)` attach and detach observers after
  construction (the constructor list stays immutable). Additive.
- **Conflict resolution.** Throw `SyncacheConflictException<T>(serverValue)`
  from a mutation's `send` when the server rejects a stale write (typically
  HTTP 409 with the server's current state in the body). Syncache never
  retries a conflict: it consults a `ConflictResolver<T>` — passed per call
  via `mutate(conflictResolver: ...)`, or configured cache-wide via
  `Syncache(conflictResolver: ...)` — stores the resolved value (re-applying
  mutations queued behind it), removes the outbox record, and settles the
  handle with a new `MutationResolved<T>(resolvedValue, wasConflict)` outcome.
  Built-in resolvers: `serverWins<T>()` and `clientWins<T>()`. New observer
  events: `onMutationConflict(key, error)` and `onMutationResolved(key)`.

### Changed

- **BREAKING**: `MutationOutcome` gained the `MutationResolved` case, so
  exhaustive `switch`es over outcomes must add it (sealed-class exhaustiveness
  makes this a compile-time break for code that switches without a default).
- Conflicts thrown without any configured `ConflictResolver` now fail the
  mutation terminally instead of being retried (only affects code already
  throwing `SyncacheConflictException`, which did not exist before this
  release).

## 0.5.0

### Added

- **Typed entries API.** `cache.entry(key, fetch: ..., policy: ..., ttl: ...,
  tags: ...)` returns a `SyncacheEntry<T>` — a lightweight, stateless view of
  one cache key bound to its fetcher and default parameters. Entries expose
  `get` / `getWithMeta` (with per-call policy override), `watch` /
  `watchWithMeta`, `refresh` (get with `Policy.refresh`), `set`, and
  `invalidate`, each delegating to the identical `Syncache` operation.
  Entries hold no stream controllers or other resources: they are cheap to
  create, shareable, and never need disposing. `ScopedSyncache.entry(...)`
  creates entries with automatic scope prefixing (`entry.key` is the
  resolved, prefixed key).

## 0.4.0

### Added

- **Bounded caches with LRU eviction.** `MemoryStore` now implements the new
  optional `BoundedStore` capability: pass `maxLength` (constructor or the
  settable property) to evict the **least-recently-used** entry whenever a
  write exceeds the limit — reads and writes both refresh recency, evicted
  entries leave the tag maps, and every eviction fires `onEvict`. Default
  stays unbounded. `Syncache` wires a bounded store's evictions into its
  observers, so apps see `SyncacheObserver.onEvict(key)` (watchers are not
  refetched — eviction is a capacity event, not an invalidation).
- **`IterableStore` capability** (`keys()`): implemented by `MemoryStore`,
  `SharedMemoryStore`, and `HiveStore`. `Store` itself is unchanged — both
  new capabilities are opt-in interfaces so third-party backends keep
  compiling.
- **`Syncache.cleanup()`**: removes every expired entry in one pass and
  returns the count; swept keys notify observers (`onInvalidate`) and their
  watchers refetch exactly like `invalidate()` does (streams stay open).
  Returns 0 for
  stores without key enumeration.
- **Automatic cleanup options** (both default `null` = manual only):
  `cleanupInterval` runs a periodic sweep (timer cancelled in `dispose`),
  and `opportunisticCleanupEvery` sweeps at most once per N writes —
  constant amortized cost, disable with `null`.
- **`SyncacheStats` snapshots** via the async `Syncache.stats` getter:
  hits, misses, fetches started/succeeded/failed/retried/cancelled, stores,
  invalidations, evictions, live pending-mutation count, and approximate
  `entryCount` (null when the store can't enumerate). Counters only — no
  per-key maps. `resetStats()` zeroes everything; pass a
  `Set<SyncacheCounter>` to reset individual counters. Powered by an
  internal observer that never appears in the `observers` list.
- **`SyncacheObserver.onEvict(key)`** for bounded-store evictions.
- **`LoggingObserver.verbose`** (default `true`): set `false` to suppress
  the high-frequency `CACHE HIT` / `FETCH START` / `STORE` lines.

### Changed

- `LoggingObserver` documentation now points Flutter apps at
  `syncacheDebugLog` (from `syncache_flutter`) to route output through
  `debugPrint`; pure Dart keeps `print`.

## 0.3.0

### Added

- **Durable mutation outbox (opt-in).** Pass a `MutationOutbox` to the
  `Syncache` constructor and every enqueued mutation is mirrored to it as a
  `PendingMutationRecord` (id, key, monotonic `seq`, caller-supplied JSON
  `payload`, `queuedAt`). Records are deleted when the mutation settles and
  are **preserved across `dispose()`**, so a freshly constructed cache can
  replay unsynced writes after a process restart.
- `Syncache.recoverPendingMutations(resolve)`: replays persisted records in
  enqueue order without re-writing the optimistic update, reports records
  that fail to resolve via `SyncacheObserver.onOutboxReplayFailed` (never
  dropped silently), and flushes immediately when online. Returns the number
  of mutations re-enqueued.
- `Syncache.mutate(payload: ...)`: persists a JSON-safe payload with the
  record. Throws `StateError` when a payload is given but no outbox is
  configured — fail loud instead of silently losing durability.
- **Exact replay via optimistic snapshots.** `Syncache.mutate` accepts
  `optimisticSnapshot:` — a JSON-safe snapshot of the optimistic value —
  persisted with the record, and `Syncache` accepts
  `decodeOptimisticSnapshot:` to decode it at recovery. Replay then sends
  the *exact pre-death value* instead of re-deriving
  `apply(currentCached)`, which double-applied base-dependent mutations
  (increments, appends) when the cache retained the optimistic state.
  Records stored without a snapshot fall back to re-derivation (documented
  below); a record that carries a snapshot but no configured codec fails
  loudly via `onOutboxReplayFailed` instead of silently falling back.
- `SyncacheObserver.onOutboxError(Object error)`: outbox write failures never
  block cache operations.
- `MemoryMutationOutbox`: in-process reference implementation of the outbox
  contract (survives dispose/recreate, not process death).
- `PendingMutationInfo.payload` so a UI can describe queued changes.
- `ScopedSyncache.mutate(payload: ...)` and
  `ScopedSyncache.recoverPendingMutations`.

### Implementation notes

- When an outbox is configured, `mutate()` resolves only after the record is
  persisted (a crash after `mutate()` completes can never lose the write).
  Memory-only behavior (no outbox) is unchanged from 0.2.0.
- **Replay values come from optimistic snapshots.** Pass
  `optimisticSnapshot:` to `mutate()` (and configure
  `decodeOptimisticSnapshot:` on the cache) and replay sends the exact
  pre-death value. Records stored without a snapshot fall back to
  re-deriving `apply(currentCached)` — computed only, never re-written to
  the store — which can double-apply base-dependent mutations when the
  cache retained the optimistic write. If a replayed record's cache entry
  is gone, the record is reported via `onOutboxReplayFailed`.
- Replayed records keep their original ids; the internal id/seq counters are
  seeded past them so new mutations can never collide with or order before
  replayed ones.

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
