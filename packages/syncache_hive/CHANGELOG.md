## 0.6.0

### Changed

- `syncache` dependency constraint bumped to `^0.6.0` — released in
  lockstep with the core package (shared `TaggableStore` /
  `MutationOutbox` interfaces). No API changes in this package.

## 0.5.0

### Changed

- Bumped the `syncache` dependency to `^0.5.0` (typed entries API,
  `SyncacheDebug` debug dumps) in lockstep. No behavioral changes in this
  package.

## 0.4.0

### Added

- **Index-backed tag operations.** `HiveStore` now maintains an in-memory
  secondary tag index (`tag → keys`) that is rebuilt lazily on the first
  tag operation after open — a single box scan that reads only each entry's
  `tags` field, never deserializing values — and then kept in sync on
  every `write`/`writeWithTags`/`delete`/`clear`/`deleteByTag(s)`.
  `getKeysByTag` and `deleteByTag(s)` are O(matches) instead of a full
  scan that deserializes every value. Corrupted entries are skipped during
  the rebuild (consistent with `read`'s corruption handling). On-disk
  format is unchanged — boxes written by earlier versions open as-is.
- **`IterableStore` support** (`keys()`): `HiveStore` can enumerate its
  keys cheaply, enabling `Syncache.cleanup()` (expired-entry collection)
  and `SyncacheStats.entryCount` over persistent caches. Pattern
  operations already scanned keys only; tests now lock that in.

### Changed

- Dependency alignment with `syncache` 0.4.0 (constraint raised to
  `^0.4.0`). `hive_ce` stays on an honest caret (`^2.20.2`); the README now
  documents the upgrade stance for `hive_ce`'s independent major bumps.

## 0.3.0

### Added

- **`HiveMutationOutbox`**: a durable `MutationOutbox` (see `syncache` 0.3.0)
  backed by its own Hive box (default name `syncache_outbox`) — deliberately
  separate from any `HiveStore` cache box, so clearing the cache never
  destroys unsynced writes. Records persist across close/reopen; corrupted
  records are skipped and reported via the optional `onError` callback
  instead of crashing `loadAll`. Safe-close semantics mirror `HiveStore`.

## 0.2.0

### Changed

- Version alignment with `syncache` 0.2.0 (dependency constraint raised to
  `^0.2.0`). No functional changes in this package.

## 0.1.2

### Changed

- **Dependency swap: `hive` → `hive_ce` ^2.20.2.** `hive_ce` is the actively
  maintained community fork of Hive. It is a drop-in replacement: the API and
  the on-disk box format are unchanged, so existing boxes open as-is. Apps
  may keep using `hive` directly for their own boxes, but the same box file
  must never be opened by both packages. For Flutter apps, use
  `hive_ce_flutter` (instead of `hive_flutter`) for `initFlutter()`.
- Plain `write` now **preserves** tags previously associated with the key,
  aligning `HiveStore` with `MemoryStore` and the tag lifecycle contract
  documented on `TaggableStore`. Use `writeWithTags(key, entry, [])` to
  clear tags explicitly.

### Added

- Shared `TaggableStore` conformance suite run against `HiveStore`.
- Regression test locking in the on-disk entry shape across the storage
  engine swap.

## 0.1.0

- Initial release
- `HiveStore<T>` implementation of `TaggableStore<T>`
- Full support for tag-based cache invalidation
- Pattern-based key matching and deletion
- Automatic JSON serialization for metadata
- Atomic operations - tags embedded in entries for consistency
- State management with `isOpen`/`isClosed` properties
- Graceful handling of corrupted data (returns null, deletes entry)
- Idempotent `close()` method
- Thread-safe `close()` - waits for pending operations to complete
- Graceful handling of invalid tags data (returns empty list)
