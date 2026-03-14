# syncache_flutter

Flutter integration for [Syncache](https://pub.dev/packages/syncache) - lifecycle management, widgets, and connectivity detection.

## Installation

```yaml
dependencies:
  syncache: ^0.1.0
  syncache_flutter: ^0.1.0
```

## Quick Start

### 1. Provide the cache with SyncacheScope

Wrap your app (or a subtree) with `SyncacheScope` to provide cache instances to descendants:

```dart
import 'package:syncache/syncache.dart';
import 'package:syncache_flutter/syncache_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize connectivity detection
  final network = FlutterNetwork();
  await network.initialize();
  
  // Create your cache
  final userCache = Syncache<User>(
    store: MemoryStore<User>(),
    network: network,
  );

  runApp(
    SyncacheScope<User>(
      cache: userCache,
      network: network,
      child: MyApp(),
    ),
  );
}
```

### 2. Display cached data with CacheBuilder

Use `CacheBuilder` to reactively display cached data:

```dart
class UserProfile extends StatelessWidget {
  final String userId;
  
  const UserProfile({required this.userId});

  @override
  Widget build(BuildContext context) {
    return CacheBuilder<User>(
      cacheKey: 'user:$userId',
      fetch: (request) => api.getUser(userId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorWidget(snapshot.error!);
        }
        if (!snapshot.hasData) {
          return const CircularProgressIndicator();
        }
        return Text('Hello, ${snapshot.data!.name}');
      },
    );
  }
}
```

## Features

### SyncacheScope

Provides cache instances to the widget subtree via `InheritedWidget`:

```dart
// Access cache anywhere in the subtree
final cache = SyncacheScope.of<User>(context);

// Access the lifecycle observer
final observer = SyncacheScope.observerOf<User>(context);
```

### MultiSyncacheScope

Provide multiple cache types without deep nesting:

```dart
MultiSyncacheScope(
  network: flutterNetwork,
  configs: [
    SyncacheScopeConfig<User>(userCache),
    SyncacheScopeConfig<Post>(postCache),
    SyncacheScopeConfig<Settings>(settingsCache),
  ],
  child: MyApp(),
)
```

### CacheBuilder

StreamBuilder-style widget for reactive cache display:

```dart
CacheBuilder<User>(
  cacheKey: 'user:123',
  fetch: fetchUser,
  policy: Policy.staleWhileRefresh,
  ttl: Duration(minutes: 5),
  initialData: cachedUser,
  buildWhen: (previous, current) => previous.id != current.id,
  builder: (context, snapshot) {
    // Build UI based on snapshot state
  },
)
```

### CacheConsumer

Consumer pattern with separate listener for side effects:

```dart
CacheConsumer<User>(
  cacheKey: 'user:123',
  fetch: fetchUser,
  listener: (context, data) {
    // Handle side effects (e.g., show snackbar, navigate)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('User updated: ${data.name}')),
    );
  },
  builder: (context, snapshot) {
    // Build UI
  },
)
```

### FlutterNetwork

Connectivity detection using `connectivity_plus`:

```dart
final network = FlutterNetwork(
  debounceDuration: Duration(milliseconds: 500),
);
await network.initialize();

// Check current status
print('Online: ${network.isOnline}');

// Listen to connectivity changes
network.onConnectivityChanged.listen((isOnline) {
  print('Connectivity changed: $isOnline');
});
```

### Lifecycle Management

Configure automatic refetching on app resume and connectivity restoration:

```dart
SyncacheScope<User>(
  cache: userCache,
  network: network,
  config: LifecycleConfig(
    refetchOnResume: true,
    refetchOnResumeMinDuration: Duration(minutes: 1),
    refetchOnReconnect: true,
    onRefetchError: (key, error, stackTrace) {
      logger.warning('Failed to refetch $key: $error');
    },
  ),
  child: MyApp(),
)
```

### SyncacheValueListenable

Use with `ValueListenableBuilder` for more control:

```dart
final listenable = cache.toValueListenable(
  key: 'user:123',
  fetch: fetchUser,
);

ValueListenableBuilder<AsyncSnapshot<User>>(
  valueListenable: listenable,
  builder: (context, snapshot, child) {
    // Build UI
  },
)

// Trigger manual refresh
await listenable.refresh();

// Don't forget to dispose
listenable.dispose();
```

## API Reference

### Widgets

| Widget | Description |
|--------|-------------|
| `SyncacheScope<T>` | InheritedWidget for cache dependency injection |
| `MultiSyncacheScope` | Provides multiple cache types without nesting |
| `CacheBuilder<T>` | StreamBuilder-style reactive cache display |
| `CacheConsumer<T>` | Consumer pattern with listener callback |

### Classes

| Class | Description |
|-------|-------------|
| `FlutterNetwork` | Connectivity detection with debouncing |
| `SyncacheLifecycleObserver<T>` | App lifecycle and reconnect handling |
| `LifecycleConfig` | Configuration for lifecycle behavior |
| `SyncacheValueListenable<T>` | ValueListenable wrapper for cache streams |
| `WatcherRegistration<T>` | Registration info for lifecycle-based refetching |

## Requirements

- Dart SDK: ^3.0.0
- Flutter: >=3.10.0
- syncache: ^0.1.0
- connectivity_plus: ^7.0.0

## License

MIT License - see [LICENSE](LICENSE) for details.
