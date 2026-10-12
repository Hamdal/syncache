import 'package:flutter/material.dart';
import 'package:syncache/syncache.dart';

import '../models/user.dart';
import '../services/fake_api.dart';

/// Demonstrates the durable mutation outbox: offline writes that survive
/// "app restarts".
///
/// The screen owns its own cache with a [MemoryMutationOutbox] and a
/// [SharedMemoryStore] namespace — both survive dispose/recreate within the
/// process, simulating what `HiveMutationOutbox` + `HiveStore` give you for
/// real across process death.
///
/// Try it:
/// 1. Go offline (toggle below).
/// 2. Tap "Rename user" — the optimistic write lands in the cache and the
///    mutation is queued.
/// 3. Tap "Restart app" — the cache is disposed and recreated, exactly like
///    a process death. The queued mutation is NOT lost: it lives in the
///    outbox.
/// 4. Recovery runs automatically on startup, re-enqueues the queued write,
///    and flushes it as soon as you go back online.
class DurableOutboxDemoScreen extends StatefulWidget {
  const DurableOutboxDemoScreen({super.key});

  @override
  State<DurableOutboxDemoScreen> createState() =>
      _DurableOutboxDemoScreenState();
}

class _DurableOutboxDemoScreenState extends State<DurableOutboxDemoScreen> {
  // Both survive "restarts": the shared store keeps cached values, the
  // outbox keeps queued mutation records. In a real app you would use
  // HiveStore + HiveMutationOutbox (syncache_hive) to survive actual
  // process death.
  final SharedMemoryStore<User> _store =
      SharedMemoryStore<User>(namespace: 'outbox-demo');
  final MemoryMutationOutbox _outbox = MemoryMutationOutbox();

  final _DemoNetwork _network = _DemoNetwork();
  late Syncache<User> _cache;

  int _session = 1;
  User? _user;
  List<PendingMutationInfo> _pending = const [];
  final List<String> _log = [];

  @override
  void initState() {
    super.initState();
    _createCache();
    _bootstrap();
  }

  @override
  void dispose() {
    _cache.dispose();
    super.dispose();
  }

  void _createCache() {
    _cache = Syncache<User>(
      store: _store,
      network: _network,
      outbox: _outbox,
      observers: [
        _DemoObserver(
          onOutboxError: (e) => _appendLog('Outbox error: $e'),
          onOutboxReplayFailed: (record, error) =>
              _appendLog('Replay failed for ${record.id}: $error'),
        ),
      ],
    );
    _cache.pendingMutationsStream.listen((pending) {
      if (mounted) setState(() => _pending = pending);
    });
  }

  /// "App startup": seed the cache if needed, then replay the outbox —
  /// exactly what SyncacheScope does with `resolvePendingMutation`.
  Future<void> _bootstrap() async {
    await _cache.set(
      key: 'user:profile',
      value: await fakeApi.fetchUser(),
    );
    await _refreshUser();

    final resolved = await _cache.recoverPendingMutations((record) async {
      // In a real app, switch on record.payload['op'] and rebuild the
      // Mutation from the serialized change.
      return Mutation<User>(
        apply: (user) =>
            user.copyWith(name: record.payload['name'] as String),
        send: (user) => fakeApi.updateUser(user),
      );
    });
    if (resolved > 0) {
      _appendLog('Recovered $resolved mutation(s) from the outbox');
    }
    await _refreshUser();
  }

  Future<void> _refreshUser() async {
    final user = await _cache.get(
      key: 'user:profile',
      fetch: (_) => fakeApi.fetchUser(),
      policy: Policy.cacheOnly,
    );
    if (mounted) setState(() => _user = user);
  }

  void _appendLog(String message) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, '[s$_session] $message');
      if (_log.length > 12) _log.removeLast();
    });
  }

  Future<void> _renameUser() async {
    final newName = 'User ${DateTime.now().second}';
    await _cache.mutate(
      key: 'user:profile',
      mutation: Mutation<User>(
        apply: (user) => user.copyWith(name: newName),
        send: (user) => fakeApi.updateUser(user),
      ),
      payload: {'op': 'rename', 'name': newName},
    );
    _appendLog(
        _network.isOnline ? 'Mutated & synced "$newName"' : 'Queued "$newName"');
    await _refreshUser();
  }

  /// Simulates a process death: dispose the cache and build a fresh one
  /// over the same (shared) store and outbox.
  Future<void> _restart() async {
    _cache.dispose();
    setState(() {
      _session++;
      _user = null;
      _pending = const [];
      _log.insert(0, '[s$_session] App restarted');
    });
    _createCache();
    await _bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Durable Outbox Demo')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Session $_session',
                            style: Theme.of(context).textTheme.titleMedium),
                        Switch(
                          value: _network.isOnline,
                          onChanged: (online) {
                            setState(() => _network.setOnline(online));
                            _appendLog(online ? 'Back online' : 'Went offline');
                          },
                        ),
                      ],
                    ),
                    Text(_network.isOnline ? 'Online' : 'Offline',
                        style: TextStyle(
                          color: _network.isOnline ? Colors.green : Colors.red,
                        )),
                    const SizedBox(height: 12),
                    Text(
                      _user?.name ?? 'No user loaded',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _pending.isEmpty
                          ? 'Queue: empty'
                          : 'Queue: ${_pending.length} waiting to sync',
                      style: TextStyle(
                        color:
                            _pending.isEmpty ? Colors.grey : Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _renameUser,
              icon: const Icon(Icons.edit),
              label: const Text('Rename user (mutate with payload)'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _restart,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Restart app (dispose + recreate)'),
            ),
            const SizedBox(height: 24),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Event log',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    if (_log.isEmpty)
                      const Text('Go offline, mutate, then restart the app.')
                    else
                      ..._log.map((line) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(line,
                                style: Theme.of(context).textTheme.bodySmall),
                          )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Network whose status the demo controls.
class _DemoNetwork implements Network {
  bool _isOnline = true;

  @override
  bool get isOnline => _isOnline;

  void setOnline(bool online) => _isOnline = online;
}

/// Observer forwarding outbox events to the demo log.
class _DemoObserver extends SyncacheObserver {
  final void Function(Object error) _onOutboxError;
  final void Function(PendingMutationRecord record, Object error)
      _onOutboxReplayFailed;

  _DemoObserver({
    required void Function(Object error) onOutboxError,
    required void Function(PendingMutationRecord record, Object error)
        onOutboxReplayFailed,
  })  : _onOutboxError = onOutboxError,
        _onOutboxReplayFailed = onOutboxReplayFailed;

  @override
  void onOutboxError(Object error) => _onOutboxError(error);

  @override
  void onOutboxReplayFailed(PendingMutationRecord record, Object error) =>
      _onOutboxReplayFailed(record, error);
}
