# Syncache

An offline-first cache and sync engine for Dart and Flutter applications.

## Packages

| Package | Description | pub.dev |
|---------|-------------|---------|
| [syncache](packages/syncache) | Core caching library for Dart | [![pub package](https://img.shields.io/pub/v/syncache.svg)](https://pub.dev/packages/syncache) |
| [syncache_flutter](packages/syncache_flutter) | Flutter integration with widgets and lifecycle management | [![pub package](https://img.shields.io/pub/v/syncache_flutter.svg)](https://pub.dev/packages/syncache_flutter) |
| [syncache_hive](packages/syncache_hive) | Persistent storage backend using Hive | [![pub package](https://img.shields.io/pub/v/syncache_hive.svg)](https://pub.dev/packages/syncache_hive) |
| [syncache_drift](packages/syncache_drift) | Persistent storage backend using SQLite (Drift) | [![pub package](https://img.shields.io/pub/v/syncache_drift.svg)](https://pub.dev/packages/syncache_drift) |

## Features

- **Multiple caching policies** - offlineFirst, cacheOnly, networkOnly, refresh, staleWhileRefresh
- **Typed entries** - bind a key + fetcher once with `cache.entry(...)`, then `get`/`watch`/`refresh`
- **Reactive streams** - Subscribe to cache updates with `watch()`
- **Optimistic mutations** - Update UI immediately while syncing in background
- **Durable offline writes** - Queue mutations to an outbox and replay them after restarts
- **Tag-based invalidation** - Group and invalidate related cache entries
- **Cache lifecycle** - LRU-bounded stores, expired-entry collection, health stats
- **Debug tooling** - JSON state dumps (`SyncacheDebug`) and a Flutter inspector screen
- **Persistent storage** - Store cache data on disk with Hive or Drift (SQLite) backends
- **Flutter integration** - Widgets, lifecycle management, connectivity detection

## Quick Start

### Dart

```yaml
dependencies:
  syncache: ^0.5.0
```

```dart
final cache = Syncache<User>(store: MemoryStore<User>());

// Bind the data source once...
final userEntry = cache.entry(
  'user:123',
  fetch: (request) => api.getUser(123),
  ttl: const Duration(minutes: 5),
);

// ...then read and watch without repeating key or fetcher.
final user = await userEntry.get();
userEntry.watch().listen((user) => print('updated: ${user.name}'));
```

### Flutter

```yaml
dependencies:
  syncache: ^0.5.0
  syncache_flutter: ^0.5.0
```

```dart
// Provide cache to widget tree
SyncacheScope<User>(
  cache: userCache,
  network: FlutterNetwork(),
  child: MyApp(),
);

// Display cached data reactively
CacheBuilder<User>(
  cacheKey: 'user:123',
  fetch: (request) => api.getUser(123),
  builder: (context, snapshot) {
    if (!snapshot.hasData) return const CircularProgressIndicator();
    return Text(snapshot.data!.name);
  },
);
```

### Persistent Storage

```yaml
dependencies:
  syncache: ^0.5.0
  syncache_hive: ^0.5.0
  hive_ce: ^2.20.2
```

```dart
import 'package:hive_ce/hive_ce.dart';
import 'package:syncache/syncache.dart';
import 'package:syncache_hive/syncache_hive.dart';

class User {
  final int id;
  final String name;
  const User({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  static User fromJson(Map<String, dynamic> json) =>
      User(id: json['id'] as int, name: json['name'] as String);
}

Future<void> main() async {
  // Initialize Hive
  Hive.init('path/to/hive');

  // Create a persistent store with JSON serialization
  final store = await HiveStore.open<User>(
    boxName: 'users',
    fromJson: User.fromJson,
    toJson: (user) => user.toJson(),
  );

  // Use with Syncache - data persists across app restarts
  final cache = Syncache<User>(store: store);
  print(cache);
}
```

Prefer SQLite? [`syncache_drift`](packages/syncache_drift) offers the same
`TaggableStore` interface plus a durable outbox over one shared database.

## Documentation

- [syncache documentation](packages/syncache/README.md)
- [syncache_flutter documentation](packages/syncache_flutter/README.md)
- [syncache_hive documentation](packages/syncache_hive/README.md)
- [syncache_drift documentation](packages/syncache_drift/README.md)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — melos bootstrap, test commands, and
the milestone workflow. Every README code sample in this repo is mechanically
validated (`dart run tool/validate_readme_samples.dart`).

## License

MIT License - see [LICENSE](LICENSE) for details.
