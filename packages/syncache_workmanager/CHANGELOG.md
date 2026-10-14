# Changelog

## 0.1.0

- Initial release.
- `SyncacheBackgroundFlusher`: flushes Syncache outbox mutations inside a
  workmanager background task — recovers pending records
  (`recoverPendingMutations`), sends them (`processPendingMutations`), and
  optionally sweeps expired entries (`cleanup`), within a wall-clock time
  budget suited to OS background-execution limits (≈30s on iOS, a few
  minutes on Android).
- `SyncacheBackgroundCacheRegistration`: wires one typed cache into the
  flusher via injected callbacks (`createCache`, `resolveRecord`) so the
  background isolate rebuilds fresh caches over the app's durable store
  and outbox.
- `SyncacheFlushReport`: per-task counts (recovered, remaining, swept),
  a budget-exhaustion flag, and duration.
- `runSyncacheTask` + `isSyncacheTask` + the canonical
  `syncacheFlushTaskName` / `syncacheCleanupTaskName` constants for wiring
  a workmanager `callbackDispatcher`.
- `registerSyncachePeriodicFlush` / `registerSyncacheOneOffFlush`
  registration helpers defaulting to a network-connected constraint.
- Unsent mutations always stay in the outbox: a background pass that runs
  out of time or network never loses work.
