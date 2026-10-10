# Syncache

An offline-first cache and sync engine for Dart applications.

Syncache provides a unified API for caching data with multiple strategies, reactive updates via streams, and optimistic mutations with automatic background sync.

## Installation

```yaml
dependencies:
  syncache: ^0.2.0
```

## Quick Start

```dart
import 'package:syncache/syncache.dart';

// Create a cache instance
final cache = Syncache<User>(
  store: MemoryStore<User>(),
);

// Fetch data with offline-first policy
final user = await cache.get(
  key: 'user:123',
  fetch: (request) => api.getUser(123),
);

// Watch for reactive updates
cache.watch(
  key: 'user:123',
  fetch: (request) => api.getUser(123),
).listen((user) {
  print('User updated: ${user.name}');
});
```

## Features

### Caching Policies

Control how data is fetched and cached with six built-in policies:

| Policy | Behavior |
|--------|----------|
| `offlineFirst` | Returns cached data if valid; fetches if expired or missing (default) |
| `cacheOnly` | Returns only cached data; never makes network requests |
| `networkOnly` | Always fetches from network; ignores cache |
| `refresh` | Fetches from network if online; falls back to cache if offline |
| `staleWhileRefresh` | Returns cache immediately; refreshes in background if expired |
| `cacheAndRefresh` | Returns cache immediately; always refreshes in background |

```dart
final user = await cache.get(
  key: 'user:123',
  fetch: fetchUser,
  policy: Policy.staleWhileRefresh,
  ttl: Duration(minutes: 5),
);
```

### Reactive Streams

Subscribe to cache updates with `watch()`:

```dart
cache.watch(key: 'user:123', fetch: fetchUser).listen((user) {
  // Called on initial fetch and every subsequent update
});

// With metadata (cache status, staleness, age)
cache.watchWithMeta(key: 'user:123', fetch: fetchUser).listen((result) {
  print('From cache: ${result.meta.isFromCache}');
  print('Is stale: ${result.meta.isStale}');
});
```

### Optimistic Mutations

Update the UI immediately while syncing to the server in the background:

```dart
await cache.mutate(
  key: 'user:123',
  mutation: Mutation<User>(
    apply: (user) => user.copyWith(name: 'New Name'),
    send: (user) => api.updateUser(user),
  ),
);
```

Failed mutations are automatically queued and retried when the network becomes available.

> **Scope of the promise (0.2.0):** the retry runs *in-process*. When your
> `Network` implements `ReactiveNetwork` — `syncache_flutter`'s
> `FlutterNetwork` does — queued mutations are flushed automatically the
> moment connectivity returns, with no new `mutate()` call. Mutations are not
> yet persisted across app restarts; durable outbox semantics land in 0.3.0.

### What happens when connectivity returns

With a `ReactiveNetwork` connected (for Flutter apps, just pass
`FlutterNetwork()` to your `Syncache`), the reconnect sequence is:

1. Queued mutations are sent to the server automatically, in order, and the
   cache is updated with each confirmed server value.
2. Watchers of keys invalidated by a mutation (`invalidates:` /
   `invalidateTags:`) refetch with their own parameters — streams stay open
   and their listeners keep the last value until fresh data arrives.
3. In `syncache_flutter`, `SyncacheLifecycleObserver` also refreshes watched
   keys on reconnect (configurable via `LifecycleConfig.refetchOnReconnect`).

You can also trigger a pass manually, e.g. from a "Retry now" button:

```dart
await cache.processPendingMutations();
```

Queue visibility for sync indicators is fully reactive — late subscribers are
seeded with the current state:

```dart
cache.pendingMutationsStream.listen((pending) {
  showSyncBanner(pending.isNotEmpty);
});

// Await a specific mutation's server confirmation:
final handle = await cache.mutate(key: 'todo:1', mutation: mutation);
switch (await handle.outcome) {
  case MutationSuccess(:final serverValue):
    // Server confirmed; the cache holds the server value.
  case MutationFailure(:final error, :final retried):
    // Retries exhausted; the optimistic value remains cached.
  case MutationDiscarded():
    // Removed via clearPendingMutations / removePendingMutation / dispose.
}
```

### Tag-Based Invalidation

Group related cache entries with tags for bulk invalidation:

```dart
// Store with tags
await cache.get(
  key: 'user:123',
  fetch: fetchUser,
  tags: ['users', 'account:456'],
);

// Invalidate all entries with a tag
await cache.invalidateTag('users');

// Invalidate by pattern
await cache.invalidatePattern('user:*');
```

### Request Deduplication

Concurrent requests for the same key are automatically deduplicated:

```dart
// These three calls result in only one network request
final results = await Future.wait([
  cache.get(key: 'user:123', fetch: fetchUser),
  cache.get(key: 'user:123', fetch: fetchUser),
  cache.get(key: 'user:123', fetch: fetchUser),
]);
```

### Retry with Exponential Backoff

Configure automatic retries for transient failures:

```dart
final user = await cache.get(
  key: 'user:123',
  fetch: fetchUser,
  retry: RetryConfig(
    maxAttempts: 3,
    retryIf: (error) => error is SocketException,
  ),
);
```

### Cancellation

Cancel in-flight requests with cancellation tokens:

```dart
final token = CancellationToken();

// Start fetch
final future = cache.get(
  key: 'user:123',
  fetch: fetchUser,
  cancel: token,
);

// Cancel if needed
token.cancel();
```

### Scoped Caches

Isolate cache entries with key prefixes for multi-tenant scenarios:

```dart
final tenantCache = cache.scoped('tenant:abc');

// All operations are prefixed with 'tenant:abc:'
await tenantCache.get(key: 'user:123', fetch: fetchUser);
// Actually stored as 'tenant:abc:user:123'
```

### Prefetching

Prefetch multiple items in parallel or with dependency ordering:

```dart
// Parallel prefetch
final results = await cache.prefetch([
  PrefetchRequest(key: 'user:1', fetch: fetchUser1),
  PrefetchRequest(key: 'user:2', fetch: fetchUser2),
]);

// Dependency graph prefetch
final results = await cache.prefetchGraph([
  PrefetchNode(key: 'config', fetch: fetchConfig),
  PrefetchNode(key: 'user', fetch: fetchUser, dependsOn: ['config']),
  PrefetchNode(key: 'posts', fetch: fetchPosts, dependsOn: ['user']),
]);
```

### Observability

Monitor cache operations for logging and analytics:

```dart
final cache = Syncache<User>(
  store: MemoryStore<User>(),
  observers: [LoggingObserver()],
);

// Or implement your own
class AnalyticsObserver extends SyncacheObserver {
  @override
  void onCacheHit(String key) => analytics.track('cache_hit', {'key': key});
  
  @override
  void onCacheMiss(String key) => analytics.track('cache_miss', {'key': key});
}
```

## Storage Backends

### MemoryStore

In-memory storage with optional tag support:

```dart
final cache = Syncache<User>(
  store: MemoryStore<User>(),
);
```

### SharedMemoryStore

Share cache data across multiple Syncache instances:

```dart
final cache1 = Syncache<User>(store: SharedMemoryStore<User>('users'));
final cache2 = Syncache<User>(store: SharedMemoryStore<User>('users'));
// Both instances share the same underlying data
```

### Custom Store

Implement the `Store` interface for custom backends (SQLite, Hive, etc.):

```dart
class SqliteStore<T> implements Store<T> {
  @override
  Future<void> write(String key, Stored<T> entry) async { ... }
  
  @override
  Future<Stored<T>?> read(String key) async { ... }
  
  @override
  Future<void> delete(String key) async { ... }
  
  @override
  Future<void> clear() async { ... }
}
```

## Network Awareness

Provide a custom `Network` implementation for offline detection:

```dart
class ConnectivityNetwork implements Network {
  final Connectivity _connectivity;

  ConnectivityNetwork(this._connectivity);

  @override
  bool get isOnline => _connectivity.hasConnection;
}

final cache = Syncache<User>(
  store: MemoryStore<User>(),
  network: ConnectivityNetwork(),
);
```

## Related Packages

Looking for additional functionality? Check out these companion packages:

| Package | Description |
|---------|-------------|
| [syncache_flutter](https://pub.dev/packages/syncache_flutter) | Flutter integration with widgets (`CacheBuilder`, `CacheConsumer`), lifecycle management, and connectivity detection via `FlutterNetwork` |
| [syncache_hive](https://pub.dev/packages/syncache_hive) | Persistent storage backend using Hive for cross-platform caching (iOS, Android, Web, Desktop) |

## License

MIT License. See [LICENSE](LICENSE) for details.
