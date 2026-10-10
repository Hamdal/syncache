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
