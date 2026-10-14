# syncache_flutter_example

The offline demo for Syncache — every `syncache_flutter` feature in one
app, plus a durable-outbox background-flush demo.

## Demos

| Section | Shows |
|---------|-------|
| CacheBuilder | Reactive widget rebuilding on cache updates |
| CacheConsumer | Listener + builder pattern for side effects |
| Multiple Caches | Different cache types working together |
| Lifecycle Demo | Refetch on resume and connectivity changes |
| Optimistic Mutation | `mutate()` with rollback on failure |
| Paginated List | `PaginatedCacheBuilder` infinite scrolling |
| Debug Inspector | `SyncacheInspectorScreen` — live entries, stats, pending mutations |
| **Background Flush** | `syncache_workmanager`: offline edits queued into a Hive outbox and replayed by OS background tasks |

## Background flush demo

The **Background Flush** section uses a durable Hive outbox and schedules
a periodic flush via workmanager. Try it:

1. Toggle **Airplane mode** on.
2. Tap **Queue an offline edit** a few times — each write lands in the
   outbox (it survives killing the app).
3. Tap **Run flush task (workmanager)** to make the OS run the flush in a
   background isolate, or **Flush in-process** to run the same engine
   without the scheduler (works on desktop/simulator).
4. Watch the console for `[background] task` and the `[server] delivered`
   lines, then toggle airplane mode off and observe the foreground queue
   drain.

Platform notes for the background part:

- **iOS:** the Runner already sets `UIBackgroundModes: fetch` and lists
  `syncache.periodic-flush` under `BGTaskSchedulerPermittedIdentifiers`
  (iOS 14+ deployment target). Actual task timing is iOS-controlled.
- **Android:** no setup needed; periodic runs are at least 15 minutes
  apart and `minSdk` is 23 (workmanager requirement).

`syncache_workmanager`'s own README documents the full pattern.
