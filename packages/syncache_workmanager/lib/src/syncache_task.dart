import 'package:flutter/foundation.dart';

import 'background_flush.dart';

/// Task name for outbox flush tasks (one-off or periodic).
///
/// This is the `task` string your dispatcher receives; keep it in sync
/// with the name used at registration time — `registerSyncachePeriodicFlush`
/// and `registerSyncacheOneOffFlush` do this for you.
const String syncacheFlushTaskName = 'syncache.flush';

/// Task name for the maintenance task: flush the outbox, then sweep
/// expired entries. Schedule it with workmanager's `registerPeriodicTask`
/// using this constant as the task name.
const String syncacheCleanupTaskName = 'syncache.cleanup';

/// Default `uniqueName` for the periodic flush task.
///
/// On iOS this value is submitted to BGTaskScheduler, so if you keep the
/// default you must also list it under `BGTaskSchedulerPermittedIdentifiers`
/// in Info.plist (see the package README). Pass your own name if you
/// already have a naming convention.
const String syncachePeriodicFlushUniqueName = 'syncache.periodic-flush';

/// Default `uniqueName` for one-off flush tasks.
const String syncacheOneOffFlushUniqueName = 'syncache.oneoff-flush';

/// Whether [taskName] is a Syncache task the package can handle.
///
/// Use it in your dispatcher to route workmanager tasks: return `true` to
/// the platform for tasks that are not yours, and delegate Syncache tasks
/// to [runSyncacheTask].
bool isSyncacheTask(String taskName) =>
    taskName == syncacheFlushTaskName || taskName == syncacheCleanupTaskName;

/// Runs one Syncache background task and maps the result to workmanager's
/// task contract.
///
/// - `syncacheFlushTaskName` flushes the outbox.
/// - `syncacheCleanupTaskName` flushes the outbox and then sweeps expired
///   entries.
///
/// Returns `true` when the pass completed — even with mutations still
/// pending (an unreachable server is not a task failure; the next
/// scheduled run retries them). Returns `false` when the flusher throws
/// (e.g. persistence failed to open), which asks workmanager to retry the
/// task with backoff — the right outcome for broken environment, the
/// wrong one for a busy server.
///
/// [flusher] should be freshly constructed inside the task: background
/// isolates cannot reuse main-isolate caches. See
/// [SyncacheBackgroundFlusher] for the registration pattern.
///
/// [onReport] receives the finished pass's [SyncacheFlushReport] — the
/// right hook for background logging, since nothing else observes a
/// background isolate.
///
/// [onError] receives any flusher error (default: `debugPrint`).
///
/// Throws [ArgumentError] if [taskName] is not a Syncache task — a
/// foreign task reaching this function means the dispatcher routing is
/// wrong; fail loudly in development instead of silently flushing.
Future<bool> runSyncacheTask(
  String taskName, {
  required SyncacheBackgroundFlusher flusher,
  Duration timeBudget = SyncacheBackgroundFlusher.defaultFlushTimeBudget,
  void Function(SyncacheFlushReport report)? onReport,
  void Function(Object error, StackTrace stackTrace)? onError,
}) async {
  if (!isSyncacheTask(taskName)) {
    throw ArgumentError.value(
      taskName,
      'taskName',
      'Not a Syncache task (expected "$syncacheFlushTaskName" or '
          '"$syncacheCleanupTaskName")',
    );
  }
  try {
    final report = await flusher.flush(
      cleanup: taskName == syncacheCleanupTaskName,
      timeBudget: timeBudget,
    );
    onReport?.call(report);
    return true;
  } catch (error, stackTrace) {
    if (onError != null) {
      onError(error, stackTrace);
    } else {
      debugPrint('syncache_workmanager: task "$taskName" failed: '
          '$error\n$stackTrace');
    }
    // Ask workmanager to retry the task with backoff.
    return false;
  }
}
