/// Hive storage backend for Syncache.
///
/// This library provides [HiveStore], a persistent storage implementation
/// using Hive that can be used with [Syncache].
///
/// ## Getting Started
///
/// ```dart
/// import 'package:hive/hive.dart';
/// import 'package:syncache/syncache.dart';
/// import 'package:syncache_hive/syncache_hive.dart';
///
/// void main() async {
///   // Initialize Hive (required once)
///   Hive.init('path/to/hive');
///
///   // Open a HiveStore
///   final store = await HiveStore.open<User>(
///     boxName: 'users',
///     fromJson: User.fromJson,
///     toJson: (user) => user.toJson(),
///   );
///
///   // Use with Syncache
///   final cache = Syncache<User>(store: store);
///
///   // Fetch and cache data
///   final user = await cache.get(
///     key: 'user:123',
///     fetch: (req) => api.getUser('123'),
///   );
/// }
/// ```
///
/// ## Flutter Usage
///
/// For Flutter apps, use the `hive_flutter` package:
///
/// ```dart
/// import 'package:hive_flutter/hive_flutter.dart';
///
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await Hive.initFlutter();
///   // ... rest of setup
/// }
/// ```
library syncache_hive;

export 'src/hive_store.dart' show HiveStore;
