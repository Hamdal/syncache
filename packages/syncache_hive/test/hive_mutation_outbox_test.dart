import 'dart:io';

import 'package:hive_ce/hive_ce.dart';
import 'package:syncache/syncache.dart';
import 'package:syncache_hive/syncache_hive.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_outbox_test_');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('HiveMutationOutbox', () {
    String boxName() => 'outbox_${DateTime.now().millisecondsSinceEpoch}';
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

    test('saves, loads in seq order, deletes, and clears', () async {
      final outbox = await HiveMutationOutbox.open(boxName: boxName());
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

    test('save replaces an existing record with the same id', () async {
      final outbox = await HiveMutationOutbox.open(boxName: boxName());
      addTearDown(outbox.close);

      await outbox.save(record('a', 1));
      await outbox.save(record('a', 5, payload: {'op': 'y'}));

      final all = await outbox.loadAll();
      expect(all, hasLength(1));
      expect(all.single.seq, 5);
      expect(all.single.payload, {'op': 'y'});
    });

    test('records persist across close/reopen (durability)', () async {
      final name = boxName();
      final outbox = await HiveMutationOutbox.open(boxName: name);
      await outbox.save(record('a', 1));
      await outbox.save(record('b', 2));
      await outbox.close();

      final reopened = await HiveMutationOutbox.open(boxName: name);
      addTearDown(reopened.close);
      final all = await reopened.loadAll();
      expect(all.map((r) => r.id), ['a', 'b']);
    });

    test('corrupted records are skipped and reported, not crashed on',
        () async {
      final name = boxName();
      final box = await Hive.openBox<Map<dynamic, dynamic>>(name);
      // Write a well-formed record and a malformed one directly.
      await box.put('good', {
        'id': 'good',
        'key': 'k',
        'seq': 1,
        'payload': {'op': 'x'},
        'queuedAtMs': 1700000000000,
      });
      await box.put('bad', {'seq': 'not-an-int'});
      await box.close();

      final errors = <Object>[];
      final outbox = await HiveMutationOutbox.open(
        boxName: name,
        onError: errors.add,
      );
      addTearDown(outbox.close);

      final all = await outbox.loadAll();
      expect(
        all.map((r) => r.id),
        ['good'],
        reason: 'the good record survives, the bad one is skipped',
      );
      expect(errors, hasLength(1));
    });

    test('operations throw after close', () async {
      final outbox = await HiveMutationOutbox.open(boxName: boxName());
      await outbox.close();
      expect(outbox.isClosed, isTrue);
      expect(outbox.isOpen, isFalse);
      expect(() => outbox.save(record('a', 1)), throwsStateError);
    });

    test('full cycle with Syncache: offline queue survives a restart',
        () async {
      final name = boxName();
      final outbox = await HiveMutationOutbox.open(boxName: name);

      // Session 1: offline cache with a Hive-backed taggable store.
      final store1 = await HiveStore.open<String>(
        boxName: '${name}_cache',
        fromJson: (json) => json['value'] as String,
        toJson: (value) => {'value': value},
      );
      final offline = Syncache<String>(
        store: store1,
        network: const _Offline(),
        outbox: outbox,
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
      expect(await outbox.loadAll(), hasLength(1));
      offline.dispose();
      await store1.close();
      await outbox.close();

      // Session 2: fresh cache + outbox over the same boxes, online.
      final outbox2 = await HiveMutationOutbox.open(boxName: name);
      addTearDown(outbox2.close);
      final store2 = await HiveStore.open<String>(
        boxName: '${name}_cache',
        fromJson: (json) => json['value'] as String,
        toJson: (value) => {'value': value},
      );
      addTearDown(store2.close);

      final online = Syncache<String>(store: store2, outbox: outbox2);
      addTearDown(online.dispose);
      final restored = await online.recoverPendingMutations(
        (r) async => Mutation<String>(
          apply: (_) => 'v${r.payload['n']}',
          send: (_) async => 'v1-server',
        ),
      );

      expect(restored, 1);
      // Replay drains asynchronously (real Hive IO); pump until the
      // processing pass has deleted the record.
      for (var i = 0; i < 200 && (await outbox2.loadAll()).isNotEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
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
