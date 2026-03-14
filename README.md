# Syncache

An offline-first cache and sync engine for Dart and Flutter applications.

## Packages

| Package | Description | pub.dev |
|---------|-------------|---------|
| [syncache](packages/syncache) | Core caching library for Dart | [![pub package](https://img.shields.io/pub/v/syncache.svg)](https://pub.dev/packages/syncache) |
| [syncache_flutter](packages/syncache_flutter) | Flutter integration with widgets and lifecycle management | [![pub package](https://img.shields.io/pub/v/syncache_flutter.svg)](https://pub.dev/packages/syncache_flutter) |

## Features

- **Multiple caching policies** - offlineFirst, cacheOnly, networkOnly, refresh, staleWhileRefresh
- **Reactive streams** - Subscribe to cache updates with `watch()`
- **Optimistic mutations** - Update UI immediately while syncing in background
- **Tag-based invalidation** - Group and invalidate related cache entries
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

## Documentation

- [syncache documentation](packages/syncache/README.md)
- [syncache_flutter documentation](packages/syncache_flutter/README.md)

## License

MIT License - see [LICENSE](LICENSE) for details.
