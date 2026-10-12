import 'mutation_outbox.dart';
import 'pending_mutation_record.dart';

/// In-memory [MutationOutbox] shipped with core syncache.
///
/// Serves three purposes:
/// - the canonical reference implementation of the four-method contract,
/// - the test-suite backend,
/// - the copy-paste template for apps rolling their own backend.
///
/// **It does not survive process death** — it is a plain map in memory.
/// It does survive `Syncache.dispose()`/recreate within a process (records
/// are kept until deleted or cleared), which makes it useful for simulating
/// restarts in tests and demos. For durability across process death use a
/// persistent backend such as `HiveMutationOutbox` from `syncache_hive`, or
/// implement the interface over your own storage.
class MemoryMutationOutbox implements MutationOutbox {
  final Map<String, PendingMutationRecord> _records = {};

  @override
  Future<void> save(PendingMutationRecord record) async {
    _records[record.id] = record;
  }

  @override
  Future<void> delete(String id) async {
    _records.remove(id);
  }

  @override
  Future<void> clear() async {
    _records.clear();
  }

  @override
  Future<List<PendingMutationRecord>> loadAll() async {
    final records = _records.values.toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
    return records;
  }
}
