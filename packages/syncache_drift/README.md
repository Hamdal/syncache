# syncache_drift

Drift (SQLite) storage backend for [Syncache](https://pub.dev/packages/syncache) — durable persistent caching with a real relational tag index and a mutation outbox sharing one SQL connection.

## Features

- Persistent storage using [Drift](https://pub.dev/packages/drift) (SQLite)
- Full support for tag-based cache invalidation — tags live in a dedicated
  `cache_tags` table, so tag lookups are **indexed SQL queries** (no scans)
- Pattern-based key matching and deletion with the same glob (`*`/`?`)
  semantics as `syncache_hive`
- Durable mutation outbox (`DriftMutationOutbox`) with
  `optimisticSnapshot` persistence for exact-replay recovery
- **One shared database**: cache and outbox share a single SQLite
  connection, so `clear` never destroys unsynced writes and cache + outbox
  writes can run inside one real SQL transaction
- Automatic serialization via JSON (`fromJson`/`toJson`, same shape as
  `HiveStore`)
- Corrupted rows are handled gracefully: reads skip/delete them instead of
  crashing, outbox loads skip and report them

## Installation

Add `syncache_drift` to your `pubspec.yaml`:

```yaml
dependencies:
  syncache: ^0.5.0
  syncache_drift: ^0.5.0
```

For Flutter apps, also add the SQLite binaries:

```yaml
dependencies:
  sqlite3_flutter_libs: ^0.5.0
```

### Backend dependency stance

This package depends on `drift` **only**. It never depends on `hive`,
`hive_ce`, or `syncache_hive` — backend packages for Syncache are
independent and never reference each other. Use `syncache_drift` *instead
of* `syncache_hive` (or alongside it, e.g. Hive cache + drift outbox, if
you like, though there is rarely a reason to). You never need both for one
backend's features: the drift backend covers everything the Hive backend
does, plus the shared-connection transaction bonus.

## Usage

### Basic Setup

```dart
import 'package:syncache/syncache.dart';
import 'package:syncache_drift/syncache_drift.dart';

class User {
  final int id;
  final String name;
  const User({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  static User fromJson(Map<String, dynamic> json) =>
      User(id: json['id'] as int, name: json['name'] as String);
}

final api = Api();
final fetchUser = (_) async => api.getUser(123);

class Api {
  Future<User> getUser(int id) async => User(id: id, name: 'User');
}

Future<void> main() async {
  // Open ONE database shared by the store and the outbox …
  final db = SyncacheDriftDatabase.openFile('path/to/app.sqlite');

  final store = DriftStore<User>(
    db: db,
    fromJson: User.fromJson,
    toJson: (user) => user.toJson(),
  );
  final outbox = DriftMutationOutbox(db: db);

  // … and wire both into Syncache.
  final cache = Syncache<User>(store: store, outbox: outbox);

  // Fetch and cache data
  final user = await cache.get(
    key: 'user:123',
    fetch: fetchUser,
  );
  print(user);
}
```

Cache-only usage can skip the outbox with the one-call `DriftStore.open`:

```dart
final store = await DriftStore.open<User>(
  path: 'path/to/cache.sqlite',
  fromJson: User.fromJson,
  toJson: (user) => user.toJson(),
);
```

### Table schema

One database, three tables (see `SyncacheDriftDatabase`):

| Table             | Columns                                                                                                  | Purpose                                        |
| ----------------- | -------------------------------------------------------------------------------------------------------- | ---------------------------------------------- |
| `cache`           | `key TEXT PRIMARY KEY, value TEXT, version INTEGER, stored_at INTEGER, ttl_ms INTEGER NULL, etag TEXT NULL, last_modified INTEGER NULL` | cached entries (values as JSON text)  |
| `cache_tags`      | `key TEXT, tag TEXT, PRIMARY KEY(key, tag)` + index on `tag`                                             | relational tag index (no scans)                |
| `mutation_outbox` | `id TEXT PRIMARY KEY, key TEXT, seq INTEGER (indexed), payload TEXT, queued_at INTEGER, optimistic_snapshot TEXT NULL`  | durable pending-mutation records |

### The shared-connection bonus

Because cache and outbox live in one database:

1. **`store.clear()` never deletes outbox records.** Clearing the cache
   removes only the `cache` and `cache_tags` tables — unsynced offline
   writes in `mutation_outbox` are untouched and recovered on next startup.
2. **Cache writes and outbox writes are atomically composable.** Wrap both
   in a real SQL transaction; either both commit, or neither does:

```dart
await db.transaction(() async {
  await store.writeWithTags(key, entry, ['users']);
  await outbox.save(record);
});
```

This is impossible with engines that store cache and outbox in separate
files (e.g. Hive boxes).

### Using Tags

```dart
// Store with tags for grouped invalidation
await cache.get(
  key: 'calendar:events:2024-03',
  fetch: fetchEvents,
  tags: ['calendar', 'events', 'workspace:123'],
);

// Invalidate all entries with 'calendar' tag
await cache.invalidateTag('calendar');
```

The tag lifecycle contract from the core package holds:

- plain `write` **preserves** existing tags (tags live in `cache_tags`, a
  plain write only touches `cache`),
- `writeWithTags` **replaces** tags entirely,
- `delete`/`clear` remove tag mappings together with the entries.

### Pattern support

`getKeysByPattern`/`deleteByPattern` support the glob subset `*` (any
characters) and `?` (one character), translated identically to
`syncache_hive` (regex escaping included), so pattern semantics are
portable across backends.

### Closing

Close the store (or the outbox) when done; either closes the shared
database. `close()` waits for in-flight operations before closing, so
pending writes are never truncated:

```dart
await store.close();
```

## Serialization

`DriftStore` requires `fromJson` and `toJson` functions to serialize your
data type — values are stored as JSON text:

```dart
import 'package:syncache_drift/syncache_drift.dart';

class User {
  final String name;
  final String email;

  User({required this.name, required this.email});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      name: json['name'] as String,
      email: json['email'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
      };
}

final store = DriftStore.open<User>(
  path: 'cache.sqlite',
  fromJson: User.fromJson,
  toJson: (user) => user.toJson(),
);
```

## API Reference

### DriftStore

```text
class DriftStore<T> implements TaggableStore<T>, IterableStore<T> {
  DriftStore({required SyncacheDriftDatabase db, required fromJson, required toJson});
  static Future<DriftStore<T>> open<T>({required String path, required fromJson, required toJson});
  Future<void> close();
}
```

### DriftMutationOutbox

```text
class DriftMutationOutbox implements MutationOutbox {
  DriftMutationOutbox({required SyncacheDriftDatabase db, void Function(Object error)? onError});
  Future<void> close();
}
```

### Inherited from TaggableStore

- `write(key, entry)` - Store a value (preserves tags)
- `writeWithTags(key, entry, tags)` - Store a value with tags
- `read(key)` - Retrieve a value
- `delete(key)` - Delete a value
- `clear()` - Clear all values (outbox records survive)
- `getTags(key)` - Get tags for a key
- `getKeysByTag(tag)` - Get all keys with a tag
- `deleteByTag(tag)` - Delete all entries with a tag
- `deleteByTags(tags, {matchAll})` - Delete entries matching tags
- `getKeysByPattern(pattern)` - Get keys matching a glob pattern
- `deleteByPattern(pattern)` - Delete keys matching a glob pattern
- `keys()` - All keys (no value deserialization)

## Example

See [`example/syncache_drift_example.dart`](example/syncache_drift_example.dart)
for a runnable end-to-end example (cache, tags, patterns, offline mutation,
recovery, shared transaction).

## License

MIT License - see LICENSE file for details.
