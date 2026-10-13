// ignore_for_file: unused_local_variable, avoid_print

import 'dart:io';

import 'package:syncache/syncache.dart';
import 'package:syncache_drift/syncache_drift.dart';

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
  // Open ONE drift database — the cache and the outbox share it.
  final tempDir = await Directory.systemTemp.createTemp('drift_example_');
  final db = SyncacheDriftDatabase.openFile('${tempDir.path}/app.sqlite');

  // Wrap the shared database in a store and an outbox.
  final store = DriftStore<User>(
    db: db,
    fromJson: User.fromJson,
    toJson: (user) => user.toJson(),
  );
  final outbox = DriftMutationOutbox(db: db);

  // Wire both into Syncache: durable cache + durable offline writes.
  final cache = Syncache<User>(store: store, outbox: outbox);

  // --- Basic Usage ---

  // Fetch and cache a user.
  final user = await cache.get(
    key: 'user:1',
    fetch: (req) async {
      // Simulate API call.
      return User(id: '1', name: 'Alice', email: 'alice@example.com');
    },
  );
  print('Fetched: $user');

  // Subsequent calls return the cached value (no fetch).
  final cachedUser = await cache.get(
    key: 'user:1',
    fetch: (req) async {
      throw StateError('Should not be called - using cache');
    },
  );
  print('Cached: $cachedUser');

  // --- Using Tags ---

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

  // Invalidate all entries with a specific tag (a real SQL index backs this).
  await cache.invalidateTag('team:engineering');
  print('Invalidated all engineering team members');

  // --- Pattern-Based Operations ---

  await cache.get(
    key: 'user:active:4',
    fetch: (req) async =>
        User(id: '4', name: 'Dave', email: 'dave@example.com'),
  );

  // Invalidate by pattern (glob-style wildcards).
  await cache.invalidate('user:active:*');
  print('Invalidated all active users');

  // --- Optimistic Mutations (offline writes) ---

  // While offline, a mutation is applied optimistically and mirrored into
  // the mutation_outbox table of the same database.
  final offline = Syncache<User>(
    store: store,
    outbox: outbox,
    network: const _Offline(),
  );
  await offline.mutate(
    key: 'user:1',
    mutation: Mutation<User>(
      apply: (current) =>
          User(id: current.id, name: 'Alice', email: 'alice@new.example.com'),
      send: (next) async => next, // would hit the API
    ),
    payload: {'op': 'update-email', 'id': '1'},
  );
  offline.dispose();
  print('Pending mutations while offline: ${(await outbox.loadAll()).length}');

  // --- Recovery (after a restart) ---

  // A fresh Syncache over the same database replays unsynced writes.
  final online = Syncache<User>(store: store, outbox: outbox);
  final restored = await online.recoverPendingMutations(
    (record) async => Mutation<User>(
      apply: (current) => current,
      send: (next) async => next,
    ),
  );
  print('Recovered $restored pending mutation(s)');

  // The replay drains asynchronously; pump until the record is settled.
  for (var i = 0; i < 200 && (await outbox.loadAll()).isNotEmpty; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  print('Outbox after recovery: ${(await outbox.loadAll()).length} record(s)');
  online.dispose();

  // --- Direct Store Operations ---

  final keys = await store.getKeysByPattern('user:*');
  print('Keys matching "user:*": $keys');

  final tags = await store.getTags('user:1');
  print('Tags for user:1: $tags');

  // --- The shared-connection bonus ---

  // Cache writes and outbox writes can run in ONE SQL transaction — either
  // both commit, or neither does:
  await db.transaction(() async {
    await store.writeWithTags(
      'user:1',
      Stored(
        value: user,
        meta: Metadata(version: 1, storedAt: DateTime.now()),
      ),
      ['team:engineering'],
    );
    await outbox.save(
      PendingMutationRecord(
        id: 'op-1',
        key: 'user:1',
        seq: 1,
        payload: {'op': 'update-email', 'id': '1'},
        queuedAt: DateTime.now(),
      ),
    );
  });
  print('Cache + outbox updated atomically');

  // --- Cleanup ---

  cache.dispose();
  await store.close(); // closes the shared database

  await tempDir.delete(recursive: true);

  print('Done!');
}

/// A [Network] that is always offline, for the offline-mutation demo.
class _Offline implements Network {
  const _Offline();

  @override
  bool get isOnline => false;
}
