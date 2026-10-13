import 'dart:io';

import 'package:syncache/syncache.dart';
import 'package:syncache_drift/syncache_drift.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('drift_outbox_test_');
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  String pathFor(String name) => '${tempDir.path}/$name.sqlite';

  PendingMutationRecord record(
    String id,
    int seq, {
    String key = 'k',
    Map<String, Object?> payload = const {'op': 'x'},
  }) =>
      PendingMutationRecord(
        id: id,
        key: key,
        seq: seq,
        payload: payload,
        queuedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000 + seq),
      );

  group('DriftMutationOutbox', () {
    test('saves, loads in seq order, deletes, and clears', () async {
      final outbox = DriftMutationOutbox(db: SyncacheDriftDatabase.inMemory());
      addTearDown(outbox.close);

      await outbox.save(record('b', 2));
      await outbox.save(record('a', 1));

      var all = await outbox.loadAll();
      expect(
        all.map((r) => r.id).toList(),
        ['a', 'b'],
        reason: 'loadAll is ordered by seq',
      );
      expect(all.first.payload, {'op': 'x'});
      expect(all.first.key, 'k');
      expect(
        all.first.queuedAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000001),
      );

      await outbox.delete('a');
      all = await outbox.loadAll();
      expect(all.map((r) => r.id), ['b']);

      await outbox.clear();
      expect(await outbox.loadAll(), isEmpty);
    });

    test('delete of a missing id is a no-op', () async {
      final outbox = DriftMutationOutbox(db: SyncacheDriftDatabase.inMemory());
      addTearDown(outbox.close);

      await outbox.delete('ghost');
      expect(await outbox.loadAll(), isEmpty);
    });

    test('save replaces an existing record with the same id', () async {
      final outbox = DriftMutationOutbox(db: SyncacheDriftDatabase.inMemory());
      addTearDown(outbox.close);

      await outbox.save(record('a', 1));
      await outbox.save(record('a', 5, payload: {'op': 'y'}));

      final all = await outbox.loadAll();
      expect(all, hasLength(1));
      expect(all.single.seq, 5);
      expect(all.single.payload, {'op': 'y'});
    });

    test('records persist across close/reopen (durability)', () async {
      final path = pathFor('durability');
      final outbox1 = DriftMutationOutbox(
        db: SyncacheDriftDatabase.openFile(path),
      );
      await outbox1.save(record('a', 1));
      await outbox1.save(record('b', 2));
      await outbox1.close();

      final outbox2 = DriftMutationOutbox(
        db: SyncacheDriftDatabase.openFile(path),
      );
      addTearDown(outbox2.close);
      final all = await outbox2.loadAll();
      expect(all.map((r) => r.id), ['a', 'b']);
    });

    test('optimisticSnapshot survives close/reopen', () async {
      final path = pathFor('optimistic_snapshot');
      final outbox1 = DriftMutationOutbox(
        db: SyncacheDriftDatabase.openFile(path),
      );
      await outbox1.save(record('a', 1, payload: {'op': 'x'}));
      await outbox1.save(
        PendingMutationRecord(
          id: 'b',
          key: 'k',
          seq: 2,
          payload: {'op': 'y'},
          queuedAt: DateTime.now(),
          optimisticSnapshot: {
            'name': 'Ada',
            'tags': [1, 2],
          },
        ),
      );
      await outbox1.close();

      final outbox2 = DriftMutationOutbox(
        db: SyncacheDriftDatabase.openFile(path),
      );
      addTearDown(outbox2.close);
      final all = await outbox2.loadAll();
      expect(all, hasLength(2));
      expect(
        all[0].optimisticSnapshot,
        isNull,
        reason: 'records saved without a snapshot stay null',
      );
      expect(
        all[1].optimisticSnapshot,
        {
          'name': 'Ada',
          'tags': [1, 2],
        },
      );
    });

    test('corrupted records are skipped and reported, not crashed on',
        () async {
      final errors = <Object>[];
      final db = SyncacheDriftDatabase.inMemory();
      final outbox = DriftMutationOutbox(db: db, onError: errors.add);
      addTearDown(outbox.close);

      // A well-formed record through the public API …
      await outbox.save(record('good', 1));
      // … and a malformed row written directly into the table.
      await db.into(db.mutationOutboxEntries).insert(
            MutationOutboxEntriesCompanion.insert(
              id: 'bad',
              key: 'k',
              seq: 2,
              payload: 'not-json{',
              queuedAt: 1700000000000,
            ),
          );

      final all = await outbox.loadAll();
      expect(
        all.map((r) => r.id),
        ['good'],
        reason: 'the good record survives, the bad one is skipped',
      );
      expect(errors, hasLength(1));
    });

    test('non-object JSON payloads are treated as corruption', () async {
      final errors = <Object>[];
      final db = SyncacheDriftDatabase.inMemory();
      final outbox = DriftMutationOutbox(db: db, onError: errors.add);
      addTearDown(outbox.close);

      await outbox.save(record('good', 1));
      await db.into(db.mutationOutboxEntries).insert(
            MutationOutboxEntriesCompanion.insert(
              id: 'bad',
              key: 'k',
              seq: 2,
              payload: '[1,2]',
              queuedAt: 1700000000000,
            ),
          );

      final all = await outbox.loadAll();
      expect(all.map((r) => r.id), ['good']);
      expect(errors, hasLength(1));
    });

    test('operations throw after close', () async {
      final outbox = DriftMutationOutbox(db: SyncacheDriftDatabase.inMemory());
      await outbox.close();
      await outbox.close(); // idempotent

      expect(outbox.isClosed, isTrue);
      expect(outbox.isOpen, isFalse);
      await expectLater(outbox.save(record('a', 1)), throwsStateError);
      await expectLater(outbox.delete('a'), throwsStateError);
      await expectLater(outbox.loadAll(), throwsStateError);
    });

    test('full cycle with Syncache: offline queue survives a restart',
        () async {
      final path = pathFor('full_cycle');
      final outbox1 = DriftMutationOutbox(
        db: SyncacheDriftDatabase.openFile(path),
      );

      // Session 1: offline cache with a drift-backed taggable store.
      final store1 = DriftStore<String>(
        db: outbox1.db,
        fromJson: (json) => json['value'] as String,
        toJson: (value) => {'value': value},
      );
      final offline = Syncache<String>(
        store: store1,
        network: const _Offline(),
        outbox: outbox1,
      );
      await offline.set(key: 'k', value: 'v0');
      await offline.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'v1',
          send: (_) async => 'v1-server',
        ),
        payload: {'op': 'update', 'n': 1},
      );
      expect(await outbox1.loadAll(), hasLength(1));
      offline.dispose();
      await store1.close();
      await outbox1.close();

      // Session 2: fresh cache + outbox over the same database, online.
      final db2 = SyncacheDriftDatabase.openFile(path);
      final outbox2 = DriftMutationOutbox(db: db2);
      addTearDown(outbox2.close);
      final store2 = DriftStore<String>(
        db: db2,
        fromJson: (json) => json['value'] as String,
        toJson: (value) => {'value': value},
      );

      final online = Syncache<String>(store: store2, outbox: outbox2);
      addTearDown(online.dispose);
      final restored = await online.recoverPendingMutations(
        (r) async => Mutation<String>(
          apply: (_) => 'v${r.payload['n']}',
          send: (_) async => 'v1-server',
        ),
      );

      expect(restored, 1);
      // Replay drains asynchronously (real SQLite IO on a background
      // isolate); pump until the processing pass has deleted the record.
      for (var i = 0; i < 200 && (await outbox2.loadAll()).isNotEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(
        await outbox2.loadAll(),
        isEmpty,
        reason: 'the replayed mutation synced and its record was removed',
      );
      final cached = await store2.read('k');
      expect(cached!.value, 'v1-server');
    });
  });
}

class _Offline implements Network {
  const _Offline();

  @override
  bool get isOnline => false;
}
