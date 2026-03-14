# Syncache

An offline-first cache and sync engine for Dart and Flutter applications.

## Packages

| Package | Description | pub.dev |
|---------|-------------|---------|
| [syncache](packages/syncache) | Core caching library for Dart | [![pub package](https://img.shields.io/pub/v/syncache.svg)](https://pub.dev/packages/syncache) |
| [syncache_flutter](packages/syncache_flutter) | Flutter integration with widgets and lifecycle management | [![pub package](https://img.shields.io/pub/v/syncache_flutter.svg)](https://pub.dev/packages/syncache_flutter) |
| [syncache_hive](packages/syncache_hive) | Persistent storage backend using Hive | [![pub package](https://img.shields.io/pub/v/syncache_hive.svg)](https://pub.dev/packages/syncache_hive) |

## Features

- **Multiple caching policies** - offlineFirst, cacheOnly, networkOnly, refresh, staleWhileRefresh
- **Reactive streams** - Subscribe to cache updates with `watch()`
- **Optimistic mutations** - Update UI immediately while syncing in background
- **Tag-based invalidation** - Group and invalidate related cache entries
- **Persistent storage** - Store cache data on disk with Hive backend
- **Flutter integration** - Widgets, lifecycle management, connectivity detection

## Quick Start

### Dart

```yaml
dependencies:
  syncache: ^0.1.0
```

```dart
import 'package:syncache/syncache.dart';

final cache = Syncache<User>(store: MemoryStore<User>());

// Fetch with offline-first policy
final user = await cache.get(
  key: 'user:123',
  fetch: (request) => api.getUser(123),
);
```

### Flutter

```yaml
dependencies:
  syncache: ^0.1.0
  syncache_flutter: ^0.1.0
```

```dart
import 'package:syncache/syncache.dart';
import 'package:syncache_flutter/syncache_flutter.dart';

// Provide cache to widget tree
SyncacheScope<User>(
  cache: userCache,
  network: FlutterNetwork(),
  child: MyApp(),
)

// Display cached data reactively
CacheBuilder<User>(
  cacheKey: 'user:123',
  fetch: (request) => api.getUser(123),
  builder: (context, snapshot) {
    if (!snapshot.hasData) return CircularProgressIndicator();
    return Text(snapshot.data!.name);
  },
)
```

### Persistent Storage

```yaml
dependencies:
  syncache: ^0.1.0
  syncache_hive: ^0.1.0
  hive: ^2.2.0
```

```dart
import 'package:hive/hive.dart';
import 'package:syncache/syncache.dart';
import 'package:syncache_hive/syncache_hive.dart';

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
```

## Documentation

- [syncache documentation](packages/syncache/README.md)
- [syncache_flutter documentation](packages/syncache_flutter/README.md)
- [syncache_hive documentation](packages/syncache_hive/README.md)

## License

MIT License - see [LICENSE](LICENSE) for details.
