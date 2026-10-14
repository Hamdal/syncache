# syncache_workmanager

Background flush for [Syncache](https://pub.dev/packages/syncache) outbox mutations, powered by [workmanager](https://pub.dev/packages/workmanager).

Syncache's [mutation outbox](https://pub.dev/packages/syncache) makes offline writes durable, and `recoverPendingMutations()` replays them at app startup. But while the app process is dead, nothing replays them — a user who queues edits on a plane and never reopens the app keeps them hostage. This package closes the gap: workmanager schedules periodic or one-off background tasks, and each task rebuilds fresh `Syncache` instances over the same durable outbox, recovers the pending records, and sends them.

## How it works

Background tasks run in a **separate isolate**: caches, stores, and outboxes built in the UI isolate don't exist there. The package's pattern is:

```text
workmanager task due (app may be dead)
  └─ callbackDispatcher (top-level, @pragma('vm:entry-point'))
       └─ runSyncacheTask(task, flusher: buildFlusher())
            └─ for each SyncacheBackgroundCacheRegistration:
                 ├─ createCache()    → fresh Syncache over the SAME durable
                 │                     store + MutationOutbox
                 ├─ recoverPendingMutations(resolveRecord)
                 ├─ processPendingMutations()
                 ├─ cleanup()        → maintenance task only
                 └─ dispose()        → outbox records for unsent work
                                       are deliberately kept
```

The flush engine is plain Dart with injected dependencies; the workmanager-specific shell is just task-name constants and a routing function.

## Installation

```yaml
dependencies:
  syncache: ^0.5.0
  syncache_workmanager: ^0.1.0
  syncache_hive: ^0.5.0 # or syncache_drift — a durable outbox is required
  workmanager: ^0.10.0
```

A **durable outbox is mandatory** for this package to be useful: `MemoryMutationOutbox` lives in one isolate's memory, so background tasks would always find an empty outbox. Use `HiveMutationOutbox` or `DriftMutationOutbox` (the same one the foreground app writes to).

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:syncache/syncache.dart';
import 'package:syncache_hive/syncache_hive.dart';
import 'package:syncache_workmanager/syncache_workmanager.dart';
import 'package:workmanager/workmanager.dart';

// The callback dispatcher is the entry point of the background isolate.
// It must be a top-level function annotated with @pragma('vm:entry-point').

class User {
  const User({required this.id, required this.name});
  final int id;
  final String name;

  User copyWith({int? id, String? name}) =>
      User(id: id ?? this.id, name: name ?? this.name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory User.fromJson(Map<String, dynamic> json) =>
      User(id: json['id'] as int, name: json['name'] as String);
}

// Stub for the app's real API client.
final api = Api();

class Api {
  Future<User> renameUser(int id, String name) async =>
      User(id: id, name: name);
}

/// Builds a fresh cache over the SAME durable store + outbox the
/// foreground app uses. Runs inside the background isolate — nothing
/// from the UI isolate survives the trip.
Future<Syncache<User>> buildUserCache() async {
  await Hive.initFlutter();
  final store = await HiveStore.open<User>(
    boxName: 'users',
    fromJson: User.fromJson,
    toJson: (user) => user.toJson(),
  );
  final outbox = await HiveMutationOutbox.open(boxName: 'syncache_outbox');
  return Syncache<User>(
    store: store,
    outbox: outbox,
    // Recovery replays the exact pre-death optimistic value.
    decodeOptimisticSnapshot: (snapshot) =>
        User.fromJson(snapshot! as Map<String, dynamic>),
  );
}

/// Maps a persisted record back to the live mutation. Must handle every
/// 'op' the foreground app can enqueue.
Future<Mutation<User>> resolveUserRecord(PendingMutationRecord record) async {
  switch (record.payload['op']) {
    case 'rename':
      return Mutation<User>(
        apply: (user) => user.copyWith(name: record.payload['name'] as String),
        send: (user) => api.renameUser(record.payload['userId'] as int, user.name),
      );
    default:
      throw UnimplementedError('unknown op ${record.payload['op']}');
  }
}

SyncacheBackgroundFlusher buildFlusher() => SyncacheBackgroundFlusher(
      registrations: [
        SyncacheBackgroundCacheRegistration<User>(
          createCache: buildUserCache,
          resolveRecord: resolveUserRecord,
        ),
      ],
    );

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (!isSyncacheTask(task)) return true; // other packages' tasks
    return runSyncacheTask(task, flusher: buildFlusher());
  });
}

Future<void> main() async {
  await Workmanager().initialize(callbackDispatcher);
  await registerSyncachePeriodicFlush(frequency: const Duration(minutes: 15));
  runApp(const SyncacheWorkmanagerExampleApp());
}

class SyncacheWorkmanagerExampleApp extends StatelessWidget {
  const SyncacheWorkmanagerExampleApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(home: Scaffold());
}
```

Enqueue a durable write from the foreground — the record is what the background task later replays:

```dart
await cache.mutate(
  key: 'user:123',
  mutation: Mutation<User>(
    apply: (user) => user.copyWith(name: 'New Name'),
    send: (user) => api.updateUser(user),
  ),
  payload: {'op': 'rename', 'userId': 123, 'name': 'New Name'},
  optimisticSnapshot: user.toJson(),
);
```

## The flush pass

Each flush pass, per registered cache:

1. **Recover** — `recoverPendingMutations(resolveRecord)` re-enqueues every persisted record whose key exists in the store. Records that cannot be replayed (unknown op, missing cache entry) are reported via `SyncacheObserver.onOutboxReplayFailed` and **stay in the outbox** — never dropped silently.
2. **Flush** — `processPendingMutations()` sends everything while online, honoring the cache's retry and conflict-resolver configuration (conflicts resolve exactly like foreground mutations).
3. **Cleanup** (maintenance task only) — `cleanup()` sweeps expired entries.
4. **Dispose** — the cache is disposed; unsent mutations keep their outbox records for the next run.

The whole pass is bounded by a wall-clock [time budget](#time-budgets) (`SyncacheBackgroundFlusher.defaultFlushTimeBudget`, 20s) and reports `SyncacheFlushReport`:

```dart
final report = await buildFlusher().flush(cleanup: true);
debugPrint('background flush: $report');
// SyncacheFlushReport(recovered: 2, remaining: 0, swept: 11,
//     exhaustedBudget: false, duration: 0:00:01.384000)
```

`runSyncacheTask` maps this to workmanager's task contract: it returns `true` when the pass completed — even with `remaining > 0`, because an unreachable server is not a task failure and the next scheduled run retries those mutations — and `false` only when the flusher throws (e.g. persistence failed to open), which asks workmanager to retry the task with backoff.

### Multiple cache types

Register one `SyncacheBackgroundCacheRegistration` per type, each with **its own outbox** (a separate Hive box or drift table). Recovery replays the outbox it is given; records for foreign types would only fail noisily if the boxes were shared.

```dart
SyncacheBackgroundFlusher(registrations: [
  SyncacheBackgroundCacheRegistration<User>(
    createCache: buildUserCache,
    resolveRecord: resolveUserRecord,
  ),
  SyncacheBackgroundCacheRegistration<List<Post>>(
    createCache: buildPostListCache,
    resolveRecord: resolvePostRecord,
  ),
]);
```

### Idempotency (read this)

If the foreground app is alive while a background task fires, both isolates can briefly hold the same mutations: the background one recovers them from the outbox and sends, while the foreground queue still holds them in memory and sends again later. This is inherent to outbox replay across processes — make server endpoints idempotent and put a client-generated operation id in the payload for deduplication (the same rule `recoverPendingMutations` already documents). In practice the overlap window is small: the background task deletes each record when its send settles, and the foreground instance's own sends make the second delete a no-op.

### Time budgets

Background execution time is granted and enforced by the OS:

| Platform | Budget | Notes |
|----------|--------|-------|
| Android (WorkManager) | a few minutes per run | 15-minute minimum periodic frequency; Doze/battery optimizers can defer runs |
| iOS (BGTaskScheduler) | ≈ 30 seconds | the OS alone decides when tasks run; `frequency` is only a hint |

`flush(timeBudget:)` defaults to `SyncacheBackgroundFlusher.defaultFlushTimeBudget` (20s) so a pass fits inside an iOS grant with room for isolate startup and storage open. When the budget ends with mutations pending, the report says `exhaustedBudget: true` and the leftover work waits in the outbox — scheduling more runs is the remedy, not longer budgets.

## Platform setup

Follow workmanager's [platform setup](https://pub.dev/packages/workmanager) for your targets; the short version:

### Android

No native setup required — Android's WorkManager works out of the box.

- **15-minute minimum** periodic frequency; tighter values are clamped.
- Aggressive vendors (Xiaomi, Huawei, …) kill scheduled work via battery optimizers — direct users to whitelist the app for reliable flushes.
- If a flush must survive long-running uploads, pass a `foregroundServiceConfig` when registering (Android 14+ requires declaring the service type — the plugin already declares `dataSync` for you; Android 13+ needs `POST_NOTIFICATIONS` for the notification to be visible).

### iOS

Minimum deployment target **iOS 14**. Two options, pick one:

**Option A — Background Fetch (simplest, ~once per day):** add `fetch` to `UIBackgroundModes` in Info.plist and rely on the automatic periodic fetch. Scheduling is entirely iOS's call — typically once per day, based on the user's usage pattern. Fine as a slow safety net; do not rely on it for timely flushes.

```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
</array>
```

**Option C — Periodic task via BGTaskScheduler (recommended):** add `fetch` to `UIBackgroundModes`, and list the flush task's `uniqueName` under `BGTaskSchedulerPermittedIdentifiers` — on iOS the uniqueName **is** the BGTaskScheduler identifier, and it must match exactly or the task fails with `BGTaskSchedulerErrorDomain Code 3`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
</array>

<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>syncache.periodic-flush</string>
</array>
```

With the default `syncachePeriodicFlushUniqueName`, the entry above is complete — the plugin registers the launch handler automatically at schedule time and on the next app launch. If you customize the unique name, keep Info.plist, the registration call, and (for pre-registration with a custom native frequency) `WorkmanagerPlugin.registerPeriodicTask(withIdentifier:frequency:)` in AppDelegate.swift in sync.

Background tasks run in a separate Flutter engine; for **other plugins** (Firebase, path_provider, …) to work inside `callbackDispatcher`, wire the plugin registrant callback in AppDelegate.swift per workmanager's iOS docs. `syncache_hive`/`syncache_drift` stores opened inside the task use plugins too — with `hive_ce_flutter`'s `Hive.initFlutter()` this wiring is what makes it work in the background engine.

## Debugging

Force a pass while developing — the engine is plain Dart, so it runs anywhere, including tests:

```dart
final report = await buildFlusher().flush();
debugPrint('flushed: $report');
```

Schedule an immediate one-off flush from the foreground (workmanager debug mode runs it right away):

```dart
await registerSyncacheOneOffFlush(initialDelay: const Duration(seconds: 5));
```

And inspect what the OS has scheduled:

```dart
await Workmanager().printScheduledTasks();
```
