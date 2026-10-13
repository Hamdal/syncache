import 'dart:convert';

import 'syncache.dart';

/// A debug facade over a [Syncache] instance for inspecting live cache
/// state in a running app.
///
/// The dump exposes everything you typically need when debugging cache
/// behavior — registered watchers (with their refetch policy and TTL),
/// in-flight fetches, the pending offline-mutation queue, stats counters,
/// and store contents (key count + sample keys when the store can
/// enumerate them):
///
/// ```dart
/// final debug = SyncacheDebug(cache);
///
/// // Structured, JSON-safe snapshot:
/// final snapshot = await debug.dump();
/// print(snapshot['pendingMutations']);
///
/// // Ready to log or send to a crash-reporting service:
/// print(await SyncacheDebug.dumpJson(cache));
/// ```
///
/// The snapshot is rendered as `Map<String, Object?>` with only JSON
/// primitives inside (policies and statuses become their enum names, times
/// become ISO-8601 strings, errors are stringified), so `jsonEncode` always
/// succeeds. The underlying data comes from
/// [Syncache.debugSnapshot]; that method's shape is diagnostic, not a
/// stable API contract.
///
/// See also:
/// - [Syncache.stats] for health counters without the rest of the dump
/// - `SyncacheInspectorScreen` in `syncache_flutter` for a ready-made
///   debug UI built on this data
class SyncacheDebug<T> {
  /// The cache this facade inspects.
  final Syncache<T> cache;

  /// Creates a debug facade for [cache].
  const SyncacheDebug(this.cache);

  /// Returns the live state of [cache] as a JSON-safe map.
  ///
  /// See [Syncache.debugSnapshot] for the exact shape.
  Future<Map<String, Object?>> dump({int sampleKeyLimit = 20}) {
    return cache.debugSnapshot(sampleKeyLimit: sampleKeyLimit);
  }

  /// Returns the live state of [cache] as a JSON-safe map.
  ///
  /// Static convenience for one-off dumps without constructing a facade.
  static Future<Map<String, Object?>> dumpOf<T>(
    Syncache<T> cache, {
    int sampleKeyLimit = 20,
  }) {
    return cache.debugSnapshot(sampleKeyLimit: sampleKeyLimit);
  }

  /// Returns the live state of [cache] as a pretty-printed JSON string.
  static Future<String> dumpJson<T>(
    Syncache<T> cache, {
    int sampleKeyLimit = 20,
  }) async {
    final snapshot = await cache.debugSnapshot(sampleKeyLimit: sampleKeyLimit);
    return const JsonEncoder.withIndent('  ').convert(snapshot);
  }
}
