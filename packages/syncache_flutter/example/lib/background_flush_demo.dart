// Background flush demo: the mutation outbox + workmanager.
//
// Offline writes are mirrored into a durable Hive outbox. While the app
// process is alive, Syncache flushes on its own; this demo shows what
// happens when it isn't: a workmanager background task rebuilds a fresh
// cache over the same outbox, recovers the pending records, and sends
// them — even if the app was killed in the meantime.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:syncache/syncache.dart';
import 'package:syncache_hive/syncache_hive.dart';
import 'package:syncache_workmanager/syncache_workmanager.dart';
import 'package:workmanager/workmanager.dart';

// =============================================================================
// Demo data type
// =============================================================================

/// A tiny mutable document so mutations have something to change.
class Note {
  final int id;
  final String title;

  const Note({required this.id, required this.title});

  Note copyWith({int? id, String? title}) =>
      Note(id: id ?? this.id, title: title ?? this.title);

  Map<String, dynamic> toJson() => {'id': id, 'title': title};

  factory Note.fromJson(Map<String, dynamic> json) =>
      Note(id: json['id'] as int, title: json['title'] as String);
}

/// Controllable connectivity so the demo can simulate airplane mode.
class DemoNetwork implements Network {
  DemoNetwork({this.online = true});

  bool online;

  @override
  bool get isOnline => online;
}

// =============================================================================
// Background isolate wiring
// =============================================================================
//
// Everything below must be top-level (or static): background tasks start
// a fresh Dart isolate that cannot close over instances built in the UI
// isolate. The pattern is always: rebuild a fresh Syncache over the SAME
// durable store + outbox, recover, flush, dispose.

/// Simulated server. Per-isolate in-memory state: a background task
/// builds its own copy, which is exactly the point — a flush "succeeds"
/// whenever the device could reach a server.
class NoteApi {
  static const _latency = Duration(milliseconds: 800);

  static int _delivered = 0;

  static Future<Note> rename(Note note) async {
    await Future<void>.delayed(_latency);
    _delivered++;
    debugPrint('[server] delivered note ${note.id}: "${note.title}" '
        '(total: $_delivered)');
    return note;
  }
}

/// Builds a fresh cache over the same Hive boxes the foreground uses.
/// The [network] parameter is for the foreground instance only — the
/// background isolate always constructs it without one (AlwaysOnline:
/// a background task's whole job is to send while it can).
Future<Syncache<Note>> buildNoteCache({Network? network}) async {
  await Hive.initFlutter();
  final store = await HiveStore.open<Note>(
    boxName: 'demo_notes',
    fromJson: Note.fromJson,
    toJson: (note) => note.toJson(),
  );
  final outbox = await HiveMutationOutbox.open(
    boxName: 'demo_notes_outbox',
    // Without this, a corrupted record is skipped silently — in a
    // background isolate nobody would ever know.
    onError: (error) => debugPrint('[note-cache] outbox record error: $error'),
  );
  if (kDebugMode) {
    final box = Hive.box<Map<dynamic, dynamic>>('demo_notes_outbox');
    debugPrint('[note-cache] outbox box at "${box.path}" has '
        '${box.length} entries');
  }
  return Syncache<Note>(
    store: store,
    outbox: outbox,
    // Recovery replays the exact pre-death optimistic value. NOTE: Hive
    // round-trips JSON maps as Map<dynamic, dynamic> — adapt before
    // casting, or every replay fails here (silently, without observers).
    decodeOptimisticSnapshot: (snapshot) =>
        Note.fromJson(Map<String, dynamic>.from(snapshot! as Map)),
    network: network,
    // Surface replay failures in the console — in a background isolate
    // this is the only way to see them.
    observers: [
      LoggingObserver(
        prefix: '[note-cache]',
        log: debugPrint,
        verbose: false,
      ),
    ],
  );
}

/// Maps persisted records back to live mutations. Must handle every
/// 'op' the foreground can enqueue.
Future<Mutation<Note>> resolveNoteRecord(PendingMutationRecord record) async {
  switch (record.payload['op']) {
    case 'rename':
      return Mutation<Note>(
        apply: (note) =>
            note.copyWith(title: record.payload['title'] as String),
        send: NoteApi.rename,
      );
    default:
      throw UnimplementedError('unknown op ${record.payload['op']}');
  }
}

SyncacheBackgroundFlusher buildNoteFlusher() => SyncacheBackgroundFlusher(
      registrations: [
        SyncacheBackgroundCacheRegistration<Note>(
          createCache: buildNoteCache,
          resolveRecord: resolveNoteRecord,
        ),
      ],
    );

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (!isSyncacheTask(task)) return true; // other packages' tasks
    debugPrint('[background] task "$task" starting');
    return runSyncacheTask(
      task,
      flusher: buildNoteFlusher(),
      onReport: (report) => debugPrint('[background] $task → $report'),
    );
  });
}

/// Setup result message shown by the demo page.
String backgroundFlushSetupMessage = '';

/// Initializes workmanager and schedules the periodic flush. On platforms
/// without background-task support (desktop development) this degrades
/// gracefully — the demo's in-process flush button still works.
Future<void> initializeBackgroundFlush() async {
  try {
    await Workmanager().initialize(callbackDispatcher);
    await registerSyncachePeriodicFlush(frequency: const Duration(minutes: 15));
    backgroundFlushSetupMessage =
        'Periodic flush scheduled (every 15 min, network-connected).';
  } catch (error) {
    backgroundFlushSetupMessage =
        'workmanager unavailable on this platform ($error). '
        'Use "Flush in-process" below.';
  }
}

// =============================================================================
// Demo page
// =============================================================================

class BackgroundFlushDemo extends StatefulWidget {
  const BackgroundFlushDemo({super.key});

  @override
  State<BackgroundFlushDemo> createState() => _BackgroundFlushDemoState();
}

class _BackgroundFlushDemoState extends State<BackgroundFlushDemo> {
  static const _noteKey = 'note:1';

  final DemoNetwork _network = DemoNetwork(online: true);
  Syncache<Note>? _cache;
  StreamSubscription<List<PendingMutationInfo>>? _pendingSub;
  final List<String> _events = [];
  int _editCounter = 0;

  @override
  void initState() {
    super.initState();
    _openCache();
  }

  @override
  void dispose() {
    _pendingSub?.cancel();
    _cache?.dispose();
    super.dispose();
  }

  Future<void> _openCache() async {
    // The foreground cache honors the airplane-mode toggle; background
    // tasks build their own AlwaysOnline cache via buildNoteCache().
    final cache = await buildNoteCache(network: _network);
    _cache = cache;

    // Seed the document on first run so mutate() has a cached value.
    final existing = await cache.store.read(_noteKey);
    if (existing == null) {
      await cache.store.write(
        _noteKey,
        Stored(
          value: const Note(id: 1, title: 'Original title'),
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        ),
      );
    }

    _pendingSub = cache.pendingMutationsStream.listen((pending) {
      _log('[queue] ${pending.length} pending mutation(s)');
    });

    setState(() {});
  }

  void _log(String message) {
    debugPrint('[demo] $message');
    if (!mounted) return;
    setState(() {
      final time = DateTime.now();
      final timeStr = '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}:'
          '${time.second.toString().padLeft(2, '0')}';
      _events.insert(0, '$timeStr $message');
      if (_events.length > 30) _events.removeLast();
    });
  }

  Future<void> _toggleAirplaneMode(bool offline) async {
    setState(() => _network.online = !offline);
    _log(offline
        ? '[device] airplane mode ON — foreground stops sending'
        : '[device] airplane mode OFF — foreground flushes again');
  }

  /// Queues a durable write. With airplane mode on, the mutation stays in
  /// the queue and its record in the Hive outbox — exactly what a
  /// background task later replays.
  Future<void> _queueOfflineEdit() async {
    final cache = _cache;
    if (cache == null) return;
    final cached = await cache.store.read(_noteKey);
    if (cached == null) return;

    _editCounter++;
    final newTitle = 'Edit #$_editCounter (queued at ${DateTime.now().minute}'
        ':${DateTime.now().second.toString().padLeft(2, '0')})';
    final optimistic = cached.value.copyWith(title: newTitle);

    await cache.mutate(
      key: _noteKey,
      mutation: Mutation<Note>(
        apply: (note) => note.copyWith(title: newTitle),
        send: NoteApi.rename,
      ),
      // The payload is what the background isolate's resolveNoteRecord
      // reads; the snapshot is what it sends. Both must be JSON-safe.
      payload: {
        'op': 'rename',
        'opId': 'edit-$_editCounter-${DateTime.now().millisecondsSinceEpoch}',
        'noteId': optimistic.id,
        'title': newTitle,
      },
      optimisticSnapshot: optimistic.toJson(),
    );
    _log('[write] queued "$newTitle" (outbox record persisted)');
  }

  /// The real path: ask the OS to run the flush task in a background
  /// isolate. Debug-mode workmanager runs one-off tasks immediately.
  Future<void> _runFlushViaWorkmanager() async {
    try {
      await Workmanager().registerOneOffTask(
        syncacheOneOffFlushUniqueName,
        syncacheFlushTaskName,
        initialDelay: const Duration(seconds: 2),
      );
      _log('[workmanager] one-off flush scheduled — watch the console '
          'for "[background] task"');
    } catch (error) {
      _log('[workmanager] not supported here: $error — '
          'use "Flush in-process"');
    }
  }

  /// The CI-friendly path: run the same engine in-process. This is what
  /// the tests exercise; on-device it skips the OS scheduler.
  Future<void> _flushInProcess() async {
    _log('[flush] running in-process…');
    final report = await buildNoteFlusher().flush();
    _log('[flush] $report');
  }

  @override
  Widget build(BuildContext context) {
    final cache = _cache;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Background flush (workmanager)'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: cache == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Setup',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(backgroundFlushSetupMessage),
                        const SizedBox(height: 8),
                        const Text(
                          'Offline writes live in a Hive outbox and are '
                          'replayed by background tasks even if the app '
                          'process was killed. On iOS, background timing '
                          'is OS-controlled (~30s budget, roughly daily '
                          'fetches); Android runs periodic tasks every '
                          '15+ minutes.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Airplane mode'),
                  subtitle: Text(
                    _network.online
                        ? 'Online — foreground sends immediately'
                        : 'Offline — writes queue durably',
                  ),
                  value: !_network.online,
                  onChanged: _toggleAirplaneMode,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _queueOfflineEdit,
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Queue an offline edit'),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _runFlushViaWorkmanager,
                  icon: const Icon(Icons.cloud_sync),
                  label: const Text('Run flush task (workmanager)'),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _flushInProcess,
                  icon: const Icon(Icons.bolt),
                  label: const Text('Flush in-process (no OS)'),
                ),
                const SizedBox(height: 8),
                StreamBuilder<Note?>(
                  stream: cache.watch(
                    key: _noteKey,
                    // The demo "server" has no fetch endpoint; a refetch
                    // just echoes the stored value back.
                    fetch: (request) async {
                      final stored = await cache.store.read(_noteKey);
                      return stored?.value ??
                          const Note(id: 1, title: 'Original title');
                    },
                  ),
                  builder: (context, snapshot) {
                    final note = snapshot.data;
                    return Card(
                      color: Colors.blueGrey[50],
                      child: ListTile(
                        leading: const Icon(Icons.sticky_note_2),
                        title: const Text('Cached note'),
                        subtitle: Text(note?.title ?? '—'),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text('Events', style: Theme.of(context).textTheme.titleMedium),
                ..._events.map(
                  (event) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      event,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
