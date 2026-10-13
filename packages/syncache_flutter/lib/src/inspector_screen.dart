import 'package:flutter/material.dart';
import 'package:syncache/syncache.dart';

/// A ready-made debug page that visualizes a [Syncache]'s live state.
///
/// Sections:
/// - **Stats** — the health counters from `Syncache.stats`.
/// - **Pending mutations** — the offline queue with per-item
///   **retry** (`processPendingMutations`) and **discard**
///   (`removePendingMutation`) actions.
/// - **Entries** — every stored key with its version, `storedAt`, and a
///   stale badge (requires the store to implement `IterableStore`, which
///   `MemoryStore` and `HiveStore` do).
/// - **Raw dump** — the JSON produced by `SyncacheDebug.dumpJson`.
/// - **Clear cache** — wipes all entries (watchers are refetched, exactly
///   like `Syncache.clear`).
///
/// It is a debugging aid: ship it behind a debug flag, never in release
/// builds.
///
/// ```dart
/// Navigator.push(
///   context,
///   MaterialPageRoute(
///     builder: (_) => SyncacheInspectorScreen(cache: userCache),
///   ),
/// );
/// ```
class SyncacheInspectorScreen<T> extends StatefulWidget {
  /// The cache to inspect.
  final Syncache<T> cache;

  /// Maximum number of sample keys shown in the raw dump's store section.
  final int sampleKeyLimit;

  /// Creates an inspector screen for [cache].
  const SyncacheInspectorScreen({
    super.key,
    required this.cache,
    this.sampleKeyLimit = 20,
  });

  @override
  State<SyncacheInspectorScreen<T>> createState() =>
      _SyncacheInspectorScreenState<T>();
}

class _SyncacheInspectorScreenState<T>
    extends State<SyncacheInspectorScreen<T>> {
  /// Bumped on manual refresh so data FutureBuilders re-run.
  int _revision = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Syncache Inspector'),
        actions: [
          IconButton(
            key: const ValueKey('inspector_refresh'),
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _revision++),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildStatsCard(),
          const SizedBox(height: 12),
          _buildPendingMutationsCard(),
          const SizedBox(height: 12),
          _buildEntriesCard(),
          const SizedBox(height: 12),
          _buildRawDumpCard(),
          const SizedBox(height: 12),
          _buildClearButton(),
        ],
      ),
    );
  }

  // ============================================================
  // Stats
  // ============================================================

  Widget _buildStatsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FutureBuilder<SyncacheStats>(
          key: ValueKey('stats-$_revision'),
          future: widget.cache.stats,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const CircularProgressIndicator();
            }
            final stats = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Stats', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _statChip('hits', stats.hits),
                    _statChip('misses', stats.misses),
                    _statChip('stores', stats.stores),
                    _statChip('invalidations', stats.invalidations),
                    _statChip('evictions', stats.evictions),
                    _statChip('fetches', stats.fetchesStarted),
                    if (stats.entryCount != null)
                      _statChip('entries', stats.entryCount!),
                    _statChip('pending', stats.pendingMutations),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _statChip(String label, int value) {
    return Chip(
      label: Text('$label: $value'),
      visualDensity: VisualDensity.compact,
    );
  }

  // ============================================================
  // Pending mutations
  // ============================================================

  Widget _buildPendingMutationsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: StreamBuilder<List<PendingMutationInfo>>(
          stream: widget.cache.pendingMutationsStream,
          builder: (context, snapshot) {
            final mutations = snapshot.data ?? const <PendingMutationInfo>[];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Pending mutations (${mutations.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('inspector_retry_all'),
                      tooltip: 'Retry all now',
                      icon: const Icon(Icons.sync),
                      onPressed: mutations.isEmpty
                          ? null
                          : () => widget.cache.processPendingMutations(),
                    ),
                  ],
                ),
                if (mutations.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Queue is empty.'),
                  )
                else
                  ...mutations.map(_buildMutationTile),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMutationTile(PendingMutationInfo info) {
    return ListTile(
      key: ValueKey('mutation-${info.id}'),
      contentPadding: EdgeInsets.zero,
      leading: _statusIcon(info.status),
      title: Text(info.key),
      subtitle: Text(
        '${info.status.name} · retries: ${info.retryCount}'
        '${info.lastError != null ? ' · ${info.lastError}' : ''}',
      ),
      trailing: IconButton(
        key: ValueKey('discard-${info.id}'),
        tooltip: 'Discard',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => widget.cache.removePendingMutation(info.id),
      ),
    );
  }

  Widget _statusIcon(PendingMutationStatus status) {
    switch (status) {
      case PendingMutationStatus.pending:
        return const Icon(Icons.schedule);
      case PendingMutationStatus.syncing:
        return const Icon(Icons.cloud_upload_outlined);
      case PendingMutationStatus.retrying:
        return const Icon(Icons.error_outline, color: Colors.orange);
      case PendingMutationStatus.failed:
        return const Icon(Icons.error, color: Colors.red);
    }
  }

  // ============================================================
  // Entries
  // ============================================================

  Widget _buildEntriesCard() {
    final store = widget.cache.store;
    if (store is! IterableStore<T>) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FutureBuilder<List<Stored<T>>?>(
          key: ValueKey('entries-$_revision'),
          future: _readAllEntries(store),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const CircularProgressIndicator();
            }
            final entries = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Entries (${entries.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                if (entries.isEmpty)
                  const Text('Cache is empty.')
                else
                  ...entries.map(_buildEntryTile),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<List<Stored<T>>?> _readAllEntries(IterableStore<T> store) async {
    try {
      final keys = await store.keys();
      final entries = <Stored<T>>[];
      for (final key in keys) {
        try {
          final entry = await widget.cache.store.read(key);
          if (entry != null) entries.add(entry);
        } catch (_) {
          // Unreadable entry: skip it.
        }
      }
      return entries;
    } catch (_) {
      return const [];
    }
  }

  Widget _buildEntryTile(Stored<T> entry) {
    final meta = entry.meta;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text('version ${meta.version}'),
      subtitle: Text('stored: ${meta.storedAt.toIso8601String()}'),
      trailing: meta.isExpired
          ? const Chip(
              label: Text('stale'),
              backgroundColor: Colors.orange,
              visualDensity: VisualDensity.compact,
            )
          : const Chip(
              label: Text('fresh'),
              visualDensity: VisualDensity.compact,
            ),
    );
  }

  // ============================================================
  // Raw dump
  // ============================================================

  Widget _buildRawDumpCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FutureBuilder<String>(
          key: ValueKey('dump-$_revision'),
          future: SyncacheDebug.dumpJson(
            widget.cache,
            sampleKeyLimit: widget.sampleKeyLimit,
          ),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const CircularProgressIndicator();
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Raw dump',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SelectableText(
                  snapshot.data!,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ============================================================
  // Clear cache
  // ============================================================

  Widget _buildClearButton() {
    return OutlinedButton.icon(
      key: const ValueKey('inspector_clear_cache'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.error,
      ),
      icon: const Icon(Icons.delete_sweep),
      label: const Text('Clear cache'),
      onPressed: () async {
        await widget.cache.clear();
        if (mounted) {
          setState(() => _revision++);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cache cleared')),
          );
        }
      },
    );
  }
}
