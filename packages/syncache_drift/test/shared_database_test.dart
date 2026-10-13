import 'package:syncache/syncache.dart';
import 'package:syncache_drift/syncache_drift.dart';
import 'package:test/test.dart';

void main() {
  late SyncacheDriftDatabase db;
  late DriftStore<String> store;
  late DriftMutationOutbox outbox;

  setUp(() {
    db = SyncacheDriftDatabase.inMemory();
    store = DriftStore<String>(
      db: db,
      fromJson: (json) => json['v'] as String,
      toJson: (value) => {'v': value},
    );
    outbox = DriftMutationOutbox(db: db);
  });

  tearDown(() async {
    await store.close();
    await outbox.close(); // closing a second wrapper of one db is tolerated
  });

  Stored<String> entry(String value) => Stored(
        value: value,
        meta: Metadata(version: 1, storedAt: DateTime.now()),
      );

  PendingMutationRecord record(String id, int seq) => PendingMutationRecord(
        id: id,
        key: 'k',
        seq: seq,
        payload: {'op': 'x'},
        queuedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000 + seq),
      );

  group('shared database', () {
    test('clearing the cache store does not delete outbox records', () async {
      await store.writeWithTags('k1', entry('v1'), ['a']);
      await store.writeWithTags('k2', entry('v2'), ['b']);
      await outbox.save(record('m1', 1));
      await outbox.save(record('m2', 2));

      await store.clear();

      expect(await store.read('k1'), isNull);
      expect(await store.read('k2'), isNull);
      expect(await store.getKeysByTag('a'), isEmpty);
      expect(
        await outbox.loadAll(),
        hasLength(2),
        reason: 'unsynced writes survive a cache clear',
      );
    });

    test('the outbox outlives the cache table (empty-store recovery)',
        () async {
      await outbox.save(record('m1', 1));
      await store.write('k', entry('v0'));

      // Simulate a client that wipes its cache but keeps the outbox.
      await db.delete(db.cacheEntries).go();
      await db.delete(db.cacheTags).go();

      expect(await store.keys(), isEmpty);
      expect(await outbox.loadAll(), [isA<PendingMutationRecord>()]);
    });

    test('a transaction spanning store and outbox commits both', () async {
      await db.transaction(() async {
        await store.writeWithTags('k1', entry('v1'), ['a']);
        await outbox.save(record('m1', 1));
      });

      final read = await store.read('k1');
      expect(read, isNotNull);
      expect(await store.getTags('k1'), ['a']);
      expect((await outbox.loadAll()).map((r) => r.id), ['m1']);
    });

    test('a transaction spanning store and outbox rolls back both', () async {
      await expectLater(
        db.transaction(() async {
          await store.writeWithTags('k1', entry('v1'), ['a']);
          await outbox.save(record('m1', 1));
          // Simulate a failure after both writes; drift rolls the whole
          // outer transaction back — impossible when cache and outbox live
          // in separate storage engines.
          throw StateError('simulate mid-transaction failure');
        }),
        throwsStateError,
      );

      expect(
        await store.read('k1'),
        isNull,
        reason: 'the cache write was rolled back',
      );
      expect(
        await outbox.loadAll(),
        isEmpty,
        reason: 'the outbox write was rolled back with it',
      );
    });

    test('closing either wrapper closes the shared database once', () async {
      await store.write('k', entry('v'));
      await outbox.save(record('m1', 1));

      await store.close();
      // Drift tolerates closing the already-closed shared database.
      await outbox.close();

      await expectLater(store.read('k'), throwsStateError);
      await expectLater(outbox.loadAll(), throwsStateError);
    });
  });
}
