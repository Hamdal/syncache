# syncache_hive

Hive storage backend for [Syncache](https://pub.dev/packages/syncache) - cross-platform persistent caching.

## Features

- Persistent storage using [Hive](https://pub.dev/packages/hive)
- Cross-platform support (iOS, Android, Web, Desktop, Pure Dart)
- Full support for tag-based cache invalidation
- Pattern-based key matching and deletion
- Automatic serialization via JSON
- **Atomic operations** - each entry (data + tags) is stored as a single unit
- **Index-backed tag operations** - tag lookups use an in-memory secondary
  index (rebuilt lazily with a single key-only scan after open), so
  `getKeysByTag`/`deleteByTag` are O(matches), never a full box scan that
  deserializes every value

## Installation

Add `syncache_hive` to your `pubspec.yaml`:

```yaml
dependencies:
  syncache: ^0.6.0
  syncache_hive: ^0.6.0
  hive_ce: ^2.20.2
```

For Flutter apps, also add `hive_ce_flutter`:

```yaml
dependencies:
  hive_ce_flutter: ^2.4.0
```

### Backend dependency stance

`syncache_hive` depends on [`hive_ce`](https://pub.dev/packages/hive_ce) —
the community edition of Hive — **not** the discontinued `hive` package.
The constraint is an honest caret (`^2.20.2`): any `hive_ce` release within
major version 2 works. `hive_ce` ships independent major bumps, so this
package only follows a major bump deliberately (with migration testing of
on-disk format compatibility), not automatically. Treat `hive_ce` major
upgrades as their own small change to this package, and pin your own app to
a caret range you have tested.

## Usage

### Basic Setup

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

final api = Api();

class Api {
  Future<User> getUser(String id) async => User(id: 123, name: 'User');
}

Future<void> main() async {
  // Initialize Hive (required once per app)
  Hive.init('path/to/hive');

  // Open a HiveStore with your data type
  final store = await HiveStore.open<User>(
    boxName: 'users',
    fromJson: User.fromJson,
    toJson: (user) => user.toJson(),
  );

  // Create a Syncache instance with the store
  final cache = Syncache<User>(store: store);

  // Use the cache
  final user = await cache.get(
    key: 'user:123',
    fetch: (req) => api.getUser('123'),
  );
  print(user);
}
```

### Flutter Setup

```dart
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
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

class MyApp extends StatelessWidget {
  const MyApp({required this.cache});

  final Syncache<User> cache;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive for Flutter
  await Hive.initFlutter();

  final store = await HiveStore.open<User>(
    boxName: 'users',
    fromJson: User.fromJson,
    toJson: (user) => user.toJson(),
  );

  final cache = Syncache<User>(store: store);

  runApp(MyApp(cache: cache));
}
```

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

### Closing the Store

Remember to close the store when you're done:

```dart
await store.close();
```

## API Reference

### HiveStore

```text
class HiveStore<T> implements TaggableStore<T> {
  /// Opens a HiveStore with the specified box name.
  static Future<HiveStore<T>> open<T>({
    required String boxName,
    required T Function(Map<String, dynamic>) fromJson,
    required Map<String, dynamic> Function(T) toJson,
  });

  /// Closes the store and releases resources.
  Future<void> close();
}
```

### Inherited from TaggableStore

- `write(key, entry)` - Store a value
- `writeWithTags(key, entry, tags)` - Store a value with tags
- `read(key)` - Retrieve a value
- `delete(key)` - Delete a value
- `clear()` - Clear all values
- `getTags(key)` - Get tags for a key
- `getKeysByTag(tag)` - Get all keys with a tag
- `deleteByTag(tag)` - Delete all entries with a tag
- `deleteByTags(tags, {matchAll})` - Delete entries matching tags
- `getKeysByPattern(pattern)` - Get keys matching a glob pattern
- `deleteByPattern(pattern)` - Delete keys matching a glob pattern

## Limitations

- **Key length**: Hive limits keys to a maximum of 255 characters. Attempting to use longer keys will throw a `HiveError`.
- **Tag replacement**: Unlike `MemoryStore`, calling `write()` on a key that already has tags will remove those tags. Use `writeWithTags()` to explicitly set tags.

## Serialization

HiveStore requires `fromJson` and `toJson` functions to serialize your data type. This is because Hive stores data as maps internally.

```dart
import 'package:syncache_hive/syncache_hive.dart';

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

final store = HiveStore.open<User>(
  boxName: 'users',
  fromJson: User.fromJson,
  toJson: (user) => user.toJson(),
);
```

## License

MIT License - see LICENSE file for details.
