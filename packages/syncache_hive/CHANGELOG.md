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
