/// Background flush for Syncache outbox mutations, powered by
/// [workmanager](https://pub.dev/packages/workmanager).
///
/// Syncache's mutation outbox makes offline writes durable, and
/// `Syncache.recoverPendingMutations` replays them at app startup — but
/// while the app process is dead, nothing replays them. This package
/// closes that gap: workmanager schedules periodic or one-off background
/// tasks, and each task rebuilds fresh `Syncache` instances over the same
/// durable outbox, recovers the pending records, and sends them.
///
/// The Dart surface is deliberately small:
///
/// - [SyncacheBackgroundFlusher] and [SyncacheBackgroundCacheRegistration]
///   — the flush engine (plain Dart, testable with fakes).
/// - [runSyncacheTask] / [isSyncacheTask] and the task-name constants —
///   the dispatcher shell that routes workmanager tasks to the engine.
/// - [registerSyncachePeriodicFlush] / [registerSyncacheOneOffFlush] —
///   registration helpers that pin the canonical task names.
///
/// See the README for the full setup (dispatcher, platform configuration)
/// and the background-isolate pattern.
library syncache_workmanager;

export 'src/background_flush.dart'
    show
        SyncacheBackgroundCacheRegistration,
        SyncacheBackgroundFlusher,
        SyncacheFlushReport,
        SyncacheFlushTarget;
export 'src/registration.dart'
    show registerSyncacheOneOffFlush, registerSyncachePeriodicFlush;
export 'src/syncache_task.dart'
    show
        isSyncacheTask,
        runSyncacheTask,
        syncacheCleanupTaskName,
        syncacheFlushTaskName,
        syncacheOneOffFlushUniqueName,
        syncachePeriodicFlushUniqueName;
