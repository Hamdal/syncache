# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- **`PaginatedCacheBuilder<T>`**: a thin widget over core's
  `PaginatedCache<T>` — subscribes to the windowed state, rebuilds on
  changes, and hands the builder the current `PagedViewState<T>` plus a
  `loadMore` callback. Deliberately scroll-agnostic: apps own their
  ScrollController / NotificationListener.

## 0.5.0

### Added

- **`SyncacheInspectorScreen<T>`**: a ready-made debug page for a running
  cache — stats summary, the pending-mutation queue with per-item
  **discard** (and queue-wide **retry now**) actions, a cache-entry list
  (version, storedAt, stale badge), the raw `SyncacheDebug` JSON dump, and
  a clear-cache button. Ship it behind a debug flag; it is also demoed in
  the example app.

### Changed

- Bumped the `syncache` dependency to `^0.5.0` (typed entries API,
  `SyncacheDebug`) in lockstep.

## [0.4.0]

### Added

- `syncacheDebugLog`: a `LogFunction` that routes `LoggingObserver` output
  through Flutter's `debugPrint`, so Flutter apps get framework-batched,
  throttling-safe log output instead of raw `print`. Pair it with the new
  `verbose: false` flag to suppress high-frequency events:
  `LoggingObserver(log: syncacheDebugLog, verbose: false)`.

### Changed

- Dependency alignment with `syncache` 0.4.0 (constraint raised to
  `^0.4.0`).

## [0.3.0]

### Added

- `SyncacheScope` now accepts `resolvePendingMutation` (a record → `Mutation`
  resolver) and `onRecovered`. When provided, the scope replays persisted
  outbox records on mount via `Syncache.recoverPendingMutations`, so offline
  writes queued before an app restart are re-enqueued — and flushed if the
  network is online — before normal usage. Top-level recovery failures are
  reported through `FlutterError.reportError`.

### Changed

- Dependency alignment with `syncache` 0.3.0 (constraint raised to `^0.3.0`).

## [0.2.0]

### Changed

- **Dependency alignment with `syncache` 0.2.0** (constraint raised to
  `^0.2.0`). The core package's breaking changes apply to this package's
  widgets and lifecycle integration — in particular, invalidation no longer
  closes watch streams and `mutate()` returns a `MutationHandle` (see the
  `syncache` changelog).

### Added

- `FlutterNetwork` now implements core's `ReactiveNetwork`. Passing it to a
  `Syncache` makes the cache flush pending mutations automatically when
  connectivity is restored.
- `SyncacheLifecycleObserver` additionally calls
  `processPendingMutations()` on reconnect as a belt-and-braces for caches
  whose `Network` does not report connectivity changes. Watcher refetch on
  reconnect remains gated by `LifecycleConfig.refetchOnReconnect`.
- `CacheBuilder` / `CacheConsumer` documentation updated: the snapshot only
  reaches `ConnectionState.done` on dispose — invalidation refetches in place.

## [0.1.2]

### Changed

- Version alignment with `syncache` 0.1.2 (dependency constraint raised to `^0.1.2`). No functional changes in this package.

## [0.1.0] - 2026-03-14

### Added

- `SyncacheScope` - InheritedWidget for dependency injection of cache instances
- `MultiSyncacheScope` - Helper for providing multiple cache types without deep nesting
- `CacheBuilder` - StreamBuilder-style widget for reactive cache data display
- `CacheConsumer` - Consumer pattern widget with separate listener callback
- `SyncacheLifecycleObserver` - App lifecycle and reconnect handling
  - Automatic refetch on app resume (configurable minimum pause duration)
  - Automatic refetch on connectivity restoration
- `FlutterNetwork` - Connectivity detection using `connectivity_plus`
  - Debounced connectivity change events
  - Concurrent initialization handled via Completer pattern
- `SyncacheValueListenable` - ValueListenable wrapper for use with ValueListenableBuilder
- `LifecycleConfig` - Configuration class for lifecycle behavior customization
