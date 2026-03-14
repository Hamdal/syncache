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
