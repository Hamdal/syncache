# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
