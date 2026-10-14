import 'package:workmanager/workmanager.dart';

import 'syncache_task.dart';

/// Schedules the periodic Syncache outbox flush.
///
/// Thin wrapper around workmanager's `registerPeriodicTask` that pins the
/// task name to [syncacheFlushTaskName] (what [runSyncacheTask] routes on)
/// and defaults the constraints to "any connection": flushing is
/// pointless without a network, and WorkManager defers the task until one
/// is available.
///
/// Android needs no native setup. On iOS the [uniqueName] must appear in
/// `BGTaskSchedulerPermittedIdentifiers` in Info.plist — see the package
/// README for the full setup.
///
/// ```dart
/// await registerSyncachePeriodicFlush(
///   frequency: const Duration(hours: 6),
/// );
/// ```
Future<void> registerSyncachePeriodicFlush({
  String uniqueName = syncachePeriodicFlushUniqueName,
  Duration frequency = const Duration(minutes: 15),
  Constraints? constraints,
  Duration? flexInterval,
  Duration? initialDelay,
  ExistingPeriodicWorkPolicy? existingWorkPolicy,
  BackoffPolicy? backoffPolicy,
  Duration? backoffPolicyDelay,
  String? tag,
}) {
  return Workmanager().registerPeriodicTask(
    uniqueName,
    syncacheFlushTaskName,
    frequency: frequency,
    flexInterval: flexInterval,
    initialDelay: initialDelay,
    constraints: constraints ?? Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: existingWorkPolicy,
    backoffPolicy: backoffPolicy,
    backoffPolicyDelay: backoffPolicyDelay,
    tag: tag,
  );
}

/// Schedules a one-off Syncache outbox flush.
///
/// Useful to "flush soon, even if the app dies first" — e.g. right after
/// the user finishes a batch of offline edits, or (with `initialDelay`)
/// as a poor man's flush-on-background. The periodic flush remains the
/// safety net; this just gets the queue moving sooner.
///
/// ```dart
/// await registerSyncacheOneOffFlush(
///   initialDelay: const Duration(seconds: 30),
/// );
/// ```
Future<void> registerSyncacheOneOffFlush({
  String uniqueName = syncacheOneOffFlushUniqueName,
  Duration? initialDelay,
  Constraints? constraints,
  bool expedited = false,
}) {
  return Workmanager().registerOneOffTask(
    uniqueName,
    syncacheFlushTaskName,
    initialDelay: initialDelay,
    constraints: constraints ?? Constraints(networkType: NetworkType.connected),
    expedited: expedited,
  );
}
