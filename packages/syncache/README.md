# Syncache

An offline-first cache and sync engine for Dart applications.

Syncache provides a unified API for caching data with multiple strategies, reactive updates via streams, and optimistic mutations with automatic background sync.

## Installation

```yaml
dependencies:
  syncache: ^0.5.0
```

## Quick Start

Bind each data source to a typed **entry** once, then read and watch
without repeating keys or fetchers:

```dart
final cache = Syncache<User>(store: MemoryStore<User>());

final userEntry = cache.entry(
  'user:123',
  fetch: (request) => api.getUser(123),
  ttl: const Duration(minutes: 5),
);

final user = await userEntry.get();        // offline-first fetch + cache
Stream<User> updates = userEntry.watch();  // reactive stream
await userEntry.refresh();                 // force a network refresh
await userEntry.invalidate();              // delete the cached entry
```

Every entry method delegates to the identical `Syncache` operation — see
[Typed Entries](#typed-entries) — so behavior is exactly what the low-level
API would do.

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

### Typed Entries

`cache.entry(...)` returns a `SyncacheEntry<T>` — a lightweight, stateless
view of one key bound to its fetcher and default policy/ttl/tags:

```dart
final entry = cache.entry(
  'user:123',
  fetch: fetchUser,
  policy: Policy.offlineFirst,
  ttl: Duration(minutes: 5),
);

await entry.get(); // bound defaults: key + fetch + policy + ttl
await entry.getWithMeta();
await entry.refresh();
await entry.set(User(id: 123, name: 'Local'));
await entry.invalidate();

Stream<User> values = entry.watch();
Stream<CacheResult<User>> meta = entry.watchWithMeta();
```

Entries hold **no state**: no stream controllers, no subscriptions, nothing
to dispose. Create as many as you like, store them in fields or providers,
and treat them as plain handles onto the cache. Scoped caches produce
prefixed entries automatically:

```dart
final tenantEntry = cache.scoped('tenant:abc').entry(
  'user:123',
  fetch: fetchUser,
);
// Bound to the physical key 'tenant:abc:user:123'
await tenantEntry.get();
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

Invalidation does **not** close watch streams — the watcher is refetched
with its own parameters and the stream stays open.

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

> The retry runs whenever your `Network` reports connectivity — with a
> `ReactiveNetwork` (such as `syncache_flutter`'s `FlutterNetwork`) queued
> mutations are flushed automatically the moment connectivity returns, with
> no new `mutate()` call.

### Offline writes that survive restarts

By default the mutation queue lives in memory: killing the app while offline
loses queued writes. Configure an **outbox** to make them durable:

```dart
final outbox = await HiveMutationOutbox.open();
final cache = Syncache<User>(
  store: store,
  outbox: outbox, // <- offline writes now survive process death
  // Decodes optimistic snapshots at recovery (see below).
  decodeOptimisticSnapshot: (snapshot) => User.fromJson(snapshot as Map<String, dynamic>),
);

// Pass a payload describing the change and a snapshot of the optimistic
// value — both are persisted with the record.
await cache.mutate(
  key: 'user:123',
  mutation: Mutation<User>(
    apply: (user) => user.copyWith(name: 'New Name'),
    send: (user) => api.updateUser(user),
  ),
  payload: {'op': 'rename', 'userId': 123, 'name': 'New Name'},
  optimisticSnapshot: user.copyWith(name: 'New Name').toJson(),
);
```

Every enqueued mutation is mirrored to the outbox and removed once it settles
(sent, exhausted, or discarded). On the next startup, replay what's left with
a **resolver** — a callback that maps a persisted record back to a live
`Mutation`:

```dart
final restored = await cache.recoverPendingMutations((record) async {
  switch (record.payload['op']) {
    case 'rename':
      return Mutation<User>(
        apply: (user) =>
            user.copyWith(name: record.payload['name'] as String),
        send: (user) => api.updateUser(user),
      );
    default:
      throw UnimplementedError('unknown op ${record.payload['op']}');
  }
});
print('$restored unsynced write(s) re-enqueued');
```

Recovery preserves enqueue order, does not double-apply the optimistic update
(it was already written before the process died), and flushes immediately if
the network is online. Because the record carries the `optimisticSnapshot`
(decoded by `decodeOptimisticSnapshot`), replay sends the **exact pre-death
value** — base-dependent mutations like increments and appends replay
correctly. Records stored without a snapshot fall back to re-deriving
`apply(currentCached)`, which can double-apply those same mutations; prefer
always passing a snapshot. In `syncache_flutter`, `SyncacheScope` runs
recovery for you on mount:

```dart
SyncacheScope<User>(
  cache: cache,
  resolvePendingMutation: resolvePending,
  onRecovered: (count) => debugPrint('$count writes restored'),
  child: const MyApp(),
);
```

#### Using the outbox without `syncache_hive`

The outbox is a four-method interface in core `syncache` — implement it over
any persistence you already own, or use the shipped in-memory reference:

```dart
final cache = Syncache<User>(
  store: MemoryStore<User>(),
  outbox: MemoryMutationOutbox(), // or your own MutationOutbox implementation
);
```

The contract: `save`/`delete`/`clear`/`loadAll` (ordered by `seq`). Failing
writes never block the cache — they are reported to observers via
`SyncacheObserver.onOutboxError`. Calling `mutate(payload: ...)` without any
outbox configured throws `StateError` rather than silently dropping the
payload. Backends that implement the interface over another engine (e.g.
`syncache_hive`, `syncache_drift`) can be mixed freely: the outbox backend
is independent of the cache `Store` backend.

> **Make endpoints idempotent.** Retries and replay can double-apply
> non-idempotent operations. Put a client-generated operation id in the
> payload and deduplicate server-side.

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
  case MutationResolved(:final resolvedValue):
    // A conflict (HTTP 409) was resolved by the configured resolver;
    // the cache holds the resolved value.
  case MutationFailure(:final error, :final retried):
    // Retries exhausted; the optimistic value remains cached.
  case MutationDiscarded():
    // Removed via clearPendingMutations / removePendingMutation / dispose.
}
```

### Conflict resolution

By default a mutation's `send` always wins: failures are retried, and the
server is expected to accept eventually. When a server instead rejects
stale writes (version/etag preconditions, HTTP 409), throw a
`SyncacheConflictException` from `send` with the server's current state.
Syncache never retries a conflict — it consults a `ConflictResolver` and
settles the mutation with what the resolver returns:

```dart
// The cache-wide default — every mutation uses it unless overridden.
final cache = Syncache<User>(
  store: store,
  conflictResolver: serverWins<User>(), // or clientWins<User>()
);
```

The resolver is where merge policies live. `ConflictResolver<T>` is an
interface — implement it for any merge policy the built-ins can't express:

```dart
import 'package:syncache/syncache.dart';

class Document {
  final String title;
  final String body;
  const Document({required this.title, required this.body});

  Document copyWith({String? title, String? body}) =>
      Document(title: title ?? this.title, body: body ?? this.body);
}

class KeepServerTitle implements ConflictResolver<Document> {
  @override
  Future<Document> resolve({
    required Document optimisticValue, // local unsynced intent
    required Document serverValue, // server's current state
    required Map<String, Object?>? payload,
  }) async {
    // Re-apply only our change on top of the fresh server value.
    return serverValue.copyWith(title: optimisticValue.title);
  }
}
```

Inside `send`, surface the server's version/etag precondition and turn a
409 into a typed conflict:

```dart
final handle = await cache.mutate(
  key: 'user:123',
  conflictResolver: clientWins<User>(), // per-call override
  mutation: Mutation<User>(
    apply: (user) => user.copyWith(name: 'New Name'),
    send: (user) async {
      final response = await api.updateUser(user);
      if (user.name == 'CONFLICT') {
        // Stand-in for `response.statusCode == 409`: hand the server's
        // current state (parsed from the body) to the resolver.
        throw SyncacheConflictException<User>(response);
      }
      return response;
    },
  ),
);

switch (await handle.outcome) {
  case MutationResolved(:final resolvedValue, :final wasConflict):
    print('Conflict settled; final value: $resolvedValue');
  case MutationSuccess(:final serverValue):
    print('Synced cleanly: $serverValue');
  case MutationFailure(:final error):
    print('Failed: $error');
  case MutationDiscarded():
    print('Removed before syncing');
}
```

Conflicts fire `SyncacheObserver.onMutationConflict` when detected and
`onMutationResolved` once the resolver's value is stored. Without any
resolver configured, a conflict fails terminally instead of retrying —
the optimistic value stays cached until the entry is refreshed.

> Per-call resolvers are not persisted with the outbox payload: after a
> process restart, replayed mutations resolve conflicts through the
> cache-wide default.

### Pagination (infinite lists)

`PaginatedCache<T>` fetches pages one at a time and accumulates them into a
**windowed list stored as a normal cached value** — so persistence,
optimistic `ListOperation` edits, outbox durability, and pattern/tag
invalidation all work on paginated data with nothing new to learn:

```dart
final listCache = Syncache<List<Post>>(store: MemoryStore<List<Post>>());
final posts = PaginatedCache<Post>(
  cache: listCache,
  key: 'posts?feed=home', // a normal key — patterns like 'posts?*' reach it
  fetchPage: (pageKey) async {
    final page = await api.getPosts();
    return PageResult(page, nextPageKey: null); // null ⇒ no more pages
  },
  maxItems: 500, // trim from the front when exceeded
);

await posts.loadMore(); // fetch the next page and append
await posts.refresh(); // re-fetch page 1 and merge (pull-to-refresh)

posts.watch.listen((state) {
  showSyncBanner(state.hasMore && !state.isLoadingMore);
});

// Optimistic add into the window, durable via the outbox:
await listCache.mutateList(
  key: 'posts?feed=home',
  operation: ListOperation.append(posts.state.items.first),
  send: () async {},
  invalidates: ['post:*'], // invalidate item keys — never the window itself
);

// In syncache_flutter, PaginatedCacheBuilder<T> renders the state and hands
// you a loadMore callback — scroll wiring stays app-owned:
PaginatedCacheBuilder<Post>(
  paginated: posts,
  builder: (context, state, loadMore) => ListView.builder(
    itemCount: state.items.length + (state.hasMore ? 1 : 0),
    itemBuilder: (context, index) {
      if (index >= state.items.length) {
        loadMore(); // from your scroll wiring
        return const Text('Loading…');
      }
      return Text(state.items[index].title);
    },
  ),
);
```

The semantics that usually bite:

- **`refresh` merges; invalidation drops.** `refresh()` keeps the scroll
  position: the fresh page 1 wins at the front, duplicates (by `==`) are
  removed from the retained tail. When the window key is invalidated
  externally (`invalidatePattern('posts?*')`, a mutation's `invalidates:`,
  a tag), the tail is **dropped** and page 1 is re-fetched
  (`autoRefreshOnInvalidation: false` to reset state without refetching).
  Eviction and `clear` reset paging state but never trigger a refill.
- **Failed page fetches never throw.** The window and cursor stay put, the
  error lands on `state.error`, and retrying `loadMore()` re-fetches the
  same page. Concurrent `loadMore` calls coalesce into one fetch.
- **Restart-safe.** The window persists in the store; the cursor is
  in-memory. After a restart, `loadMore()` on a non-empty window
  refresh-merges instead of appending — no duplicates.

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
final graph = await cache.prefetchGraph([
  PrefetchNode(key: 'user:1', fetch: fetchUser1),
  PrefetchNode(key: 'user:2', fetch: fetchUser2, dependsOn: ['user:1']),
  PrefetchNode(key: 'user:3', fetch: fetchUser3, dependsOn: ['user:1']),
]);
```

### Observability

Monitor cache operations for logging and analytics:

```dart
final cache = Syncache<User>(
  store: MemoryStore<User>(),
  observers: [LoggingObserver()],
);
```

Or implement your own observer:

```dart
import 'package:syncache/syncache.dart';

// Your analytics SDK (stubbed here).
void trackEvent(String event, Map<String, Object?> properties) {}

class AnalyticsObserver extends SyncacheObserver {
  @override
  void onCacheHit(String key) => trackEvent('cache_hit', {'key': key});

  @override
  void onCacheMiss(String key) => trackEvent('cache_miss', {'key': key});
}
```

In Flutter apps, route log output through `debugPrint` and quiet the
high-frequency events:

```dart
final cache = Syncache<User>(
  store: MemoryStore<User>(),
  observers: [LoggingObserver(log: syncacheDebugLog, verbose: false)],
);
```

### Stats

Every cache keeps constant-memory health counters — snapshot them any time:

```dart
final stats = await cache.stats;
print('hits: ${stats.hits}, misses: ${stats.misses}');
print('pending mutations: ${stats.pendingMutations}');
print('entries: ${stats.entryCount}'); // null if the store can't enumerate

cache.resetStats();                       // zero everything
cache.resetStats({SyncacheCounter.hits}); // or a single counter
```

### Debugging

Dump the live internal state — registered watchers, in-flight fetches,
pending mutations, stats, and store contents — as a JSON-safe map:

```dart
final debug = SyncacheDebug(cache);

print(await debug.dump());          // structured snapshot
print(await SyncacheDebug.dumpJson(cache)); // pretty-printed JSON
```

For a visual inspector in Flutter apps — cache entries, the pending
mutation queue with retry/discard actions, and a clear-cache button — use
`SyncacheInspectorScreen` from `syncache_flutter` (ship it behind a debug
flag).

### Cache Lifecycle

Bounded memory, expired-entry collection:

```dart
// Bounded store: least-recently-used eviction past 500 entries.
final bounded = Syncache<User>(
  store: MemoryStore<User>(maxLength: 500),
);
// Evictions fire SyncacheObserver.onEvict; watchers are not refetched.
```

```dart
// Periodic expired-entry sweep (timer is cancelled on dispose).
final periodic = Syncache<User>(
  store: MemoryStore<User>(),
  cleanupInterval: const Duration(minutes: 10),
);

// Or sweep manually / opportunistically:
final removed = await periodic.cleanup();
final opportunistic = Syncache<User>(
  store: MemoryStore<User>(),
  opportunisticCleanupEvery: 64, // at most once per 64 writes
);
```

### Known limitations

- **Replay without optimistic snapshots re-derives values.** Outbox records
  stored without `optimisticSnapshot:` fall back to re-deriving
  `apply(currentCached)` at recovery, which can double-apply base-dependent
  mutations (increments, appends) when the cache retained the optimistic
  state. Always pass a snapshot for exact replay (see
  [Offline writes that survive restarts](#offline-writes-that-survive-restarts)).
- **Concurrent `mutate()` calls on the same key have racy optimistic
  views.** Parallel mutates each apply from the value they read, so the
  cached value may briefly lag the full sum; the queue re-bases on send and
  converges to the exact fold after the flush.
- **Invalidation does not cancel queued mutations.** An invalidated key with
  queued offline writes still delivers them on reconnect; the
  server-confirmed value overwrites the (invalidated) cached entry.

## Storage Backends

### MemoryStore

In-memory storage with optional tag support:

```dart
final cache = Syncache<User>(
  store: MemoryStore<User>(),
);
```

Pass `maxLength` to bound memory — the least-recently-used entry is evicted
when the limit is exceeded (see [Cache Lifecycle](#cache-lifecycle)):

```dart
final cache = Syncache<User>(
  store: MemoryStore<User>(maxLength: 500),
);
```

### SharedMemoryStore

Share cache data across multiple Syncache instances:

```dart
final cache1 = Syncache<User>(store: SharedMemoryStore<User>(namespace: 'users'));
final cache2 = Syncache<User>(store: SharedMemoryStore<User>(namespace: 'users'));
// Both instances share the same underlying data
```

### Persistent backends

For storage that survives restarts, use a backend package:

- [`syncache_hive`](https://pub.dev/packages/syncache_hive) — Hive-backed
  `TaggableStore` + durable outbox.
- [`syncache_drift`](https://pub.dev/packages/syncache_drift) — SQLite
  (Drift) `TaggableStore` + outbox on one shared connection.

### Custom Store

Implement the `Store` interface for custom backends (SQLite, IndexedDB, etc.):

```dart
import 'package:syncache/syncache.dart';

class SqliteStore<T> implements Store<T> {
  @override
  Future<void> write(String key, Stored<T> entry) async {
    throw UnimplementedError();
  }

  @override
  Future<Stored<T>?> read(String key) async {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String key) async {
    throw UnimplementedError();
  }

  @override
  Future<void> clear() async {
    throw UnimplementedError();
  }
}
```

## Network Awareness

Provide a custom `Network` implementation for offline detection:

```dart
import 'package:syncache/syncache.dart';

class Connectivity {
  bool get hasConnection => true;
}

class ConnectivityNetwork implements Network {
  final Connectivity _connectivity;

  ConnectivityNetwork(this._connectivity);

  @override
  bool get isOnline => _connectivity.hasConnection;
}

final cache = Syncache<String>(
  store: MemoryStore<String>(),
  network: ConnectivityNetwork(Connectivity()),
);
```

Implement `ReactiveNetwork` to get automatic mutation flushes on reconnect.

## Related Packages

| Package | Description |
|---------|-------------|
| [syncache_flutter](https://pub.dev/packages/syncache_flutter) | Flutter integration with widgets (`CacheBuilder`, `CacheConsumer`), lifecycle management, connectivity detection via `FlutterNetwork`, and the `SyncacheInspectorScreen` debug page |
| [syncache_hive](https://pub.dev/packages/syncache_hive) | Persistent storage backend using Hive for cross-platform caching (iOS, Android, Web, Desktop) |
| [syncache_drift](https://pub.dev/packages/syncache_drift) | Persistent storage backend using SQLite (Drift) with a relational tag index and outbox on a shared connection |

## License

MIT License. See [LICENSE](LICENSE) for details.
