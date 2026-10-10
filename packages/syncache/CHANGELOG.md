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
