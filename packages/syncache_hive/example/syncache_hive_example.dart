// ignore_for_file: unused_local_variable, avoid_print

import 'dart:io';

import 'package:hive/hive.dart';
import 'package:syncache/syncache.dart';
import 'package:syncache_hive/syncache_hive.dart';

/// Example model with JSON serialization.
class User {
  final String id;
  final String name;
  final String email;

  User({required this.id, required this.name, required this.email});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
      };

  @override
  String toString() => 'User($id, $name, $email)';
}

Future<void> main() async {
  // Initialize Hive with a directory path
  final tempDir = await Directory.systemTemp.createTemp('hive_example_');
  Hive.init(tempDir.path);

  // Open a HiveStore with JSON serialization functions
  final store = await HiveStore.open<User>(
    boxName: 'users',
    fromJson: User.fromJson,
    toJson: (user) => user.toJson(),
  );

  // Create a Syncache instance with the persistent store
  final cache = Syncache<User>(store: store);

  // --- Basic Usage ---

  // Fetch and cache a user
  final user = await cache.get(
    key: 'user:1',
    fetch: (req) async {
      // Simulate API call
      return User(id: '1', name: 'Alice', email: 'alice@example.com');
    },
  );
  print('Fetched: $user');

  // Subsequent calls return cached value (no fetch)
  final cachedUser = await cache.get(
    key: 'user:1',
    fetch: (req) async {
      throw StateError('Should not be called - using cache');
    },
  );
  print('Cached: $cachedUser');

  // --- Using Tags ---

  // Store users with tags for grouped invalidation
  await cache.get(
    key: 'user:2',
    fetch: (req) async => User(id: '2', name: 'Bob', email: 'bob@example.com'),
    tags: ['team:engineering', 'role:developer'],
  );

  await cache.get(
    key: 'user:3',
    fetch: (req) async =>
        User(id: '3', name: 'Carol', email: 'carol@example.com'),
    tags: ['team:engineering', 'role:manager'],
  );

  // Invalidate all entries with a specific tag
  await cache.invalidateTag('team:engineering');
  print('Invalidated all engineering team members');

  // --- Pattern-Based Operations ---

  // Store multiple items
  await cache.get(
    key: 'user:active:4',
    fetch: (req) async =>
        User(id: '4', name: 'Dave', email: 'dave@example.com'),
  );

  await cache.get(
    key: 'user:active:5',
    fetch: (req) async => User(id: '5', name: 'Eve', email: 'eve@example.com'),
  );

  // Invalidate by pattern (glob-style wildcards)
  await cache.invalidate('user:active:*');
  print('Invalidated all active users');

  // --- Direct Store Operations ---

  // Get keys matching a pattern
  final keys = await store.getKeysByPattern('user:*');
  print('Keys matching "user:*": $keys');

  // Get tags for a specific key
  final tags = await store.getTags('user:1');
  print('Tags for user:1: $tags');

  // --- Cleanup ---

  // Dispose cache and close store
  cache.dispose();
  await store.close();

  // Clean up temp directory
  await tempDir.delete(recursive: true);

  print('Done!');
}
