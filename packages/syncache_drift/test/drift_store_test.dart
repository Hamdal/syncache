import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:syncache/syncache.dart';
import 'package:syncache_drift/syncache_drift.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('drift_store_test_');
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  String pathFor(String name) => '${tempDir.path}/$name.sqlite';

  DriftStore<String> stringStore(SyncacheDriftDatabase db) =>
      DriftStore<String>(
        db: db,
        fromJson: (json) => json['v'] as String,
        toJson: (value) => {'v': value},
      );

  Stored<String> entry(
    String value, {
    int version = 1,
    Duration? ttl,
    String? etag,
    DateTime? lastModified,
  }) =>
      Stored(
        value: value,
        meta: Metadata(
          version: version,
          storedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
          ttl: ttl,
          etag: etag,
          lastModified: lastModified,
        ),
      );

  group('DriftStore persistence', () {
    test('entries, metadata, and tags survive close/reopen', () async {
      final path = pathFor('persist');
      final store1 = await DriftStore.open<String>(
        path: path,
        fromJson: (json) => json['v'] as String,
        toJson: (value) => {'v': value},
      );

      await store1.writeWithTags(
        'k1',
        entry(
          'v1',
          version: 3,
          ttl: const Duration(minutes: 5),
          etag: '"abc"',
          lastModified: DateTime.fromMillisecondsSinceEpoch(1690000000000),
        ),
        ['users', 'workspace:1'],
      );
      await store1.write('k2', entry('v2'));
      await store1.close();

      final store2 = await DriftStore.open<String>(
        path: path,
        fromJson: (json) => json['v'] as String,
        toJson: (value) => {'v': value},
      );
      addTearDown(store2.close);

      final read = await store2.read('k1');
      expect(read, isNotNull);
      expect(read!.value, 'v1');
      expect(read.meta.version, 3);
      expect(
        read.meta.storedAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(read.meta.ttl, const Duration(minutes: 5));
      expect(read.meta.etag, '"abc"');
      expect(
        read.meta.lastModified,
        DateTime.fromMillisecondsSinceEpoch(1690000000000),
      );
      expect(
        await store2.getTags('k1'),
        unorderedEquals(['users', 'workspace:1']),
      );
      expect(await store2.getKeysByTag('users'), contains('k1'));

      final read2 = await store2.read('k2');
      expect(read2!.value, 'v2');
      expect(read2.meta.ttl, isNull);
      expect(read2.meta.etag, isNull);
      expect(read2.meta.lastModified, isNull);
      expect(await store2.getTags('k2'), isEmpty);
    });

    test('a missing entry reads back as null', () async {
      final store = stringStore(SyncacheDriftDatabase.inMemory());
      addTearDown(store.close);

      expect(await store.read('missing'), isNull);
    });
  });

  group('DriftStore corruption tolerance', () {
    test('read deletes a corrupted entry (and its tags), returns null',
        () async {
      final store = stringStore(SyncacheDriftDatabase.inMemory());
      addTearDown(store.close);
      final db = store.db;

      await store.writeWithTags('bad', entry('v1'), ['a']);
      // Corrupt the value directly in the database.
      await (db.update(db.cacheEntries)..where((tbl) => tbl.key.equals('bad')))
          .write(const CacheEntriesCompanion(value: Value('not-json{')));

      expect(await store.read('bad'), isNull);
      expect(
        await store.keys(),
        isEmpty,
        reason: 'the corrupted row is deleted',
      );
      expect(
        await store.getTags('bad'),
        isEmpty,
        reason: 'tag mappings go with the corrupted entry',
      );
      expect(await store.getKeysByTag('a'), isEmpty);
    });

    test('read treats a non-object JSON value as corruption', () async {
      final store = stringStore(SyncacheDriftDatabase.inMemory());
      addTearDown(store.close);
      final db = store.db;

      await store.write('bad', entry('v1'));
      await (db.update(db.cacheEntries)..where((tbl) => tbl.key.equals('bad')))
          .write(const CacheEntriesCompanion(value: Value('[1,2,3]')));

      expect(await store.read('bad'), isNull);
    });
  });

  group('DriftStore IterableStore', () {
    test('keys() enumerates keys without deserializing values', () async {
      final store = stringStore(SyncacheDriftDatabase.inMemory());
      addTearDown(store.close);
      final db = store.db;

      await store.write('a', entry('v1'));
      await store.write('b', entry('v2'));
      // Corrupt one value: keys() must not care.
      await (db.update(db.cacheEntries)..where((tbl) => tbl.key.equals('b')))
          .write(const CacheEntriesCompanion(value: Value('???')));

      expect(await store.keys(), unorderedEquals(['a', 'b']));
    });
  });

  group('DriftStore pattern matching', () {
    test('glob semantics match HiveStore: ? is one char, * is many', () async {
      final store = stringStore(SyncacheDriftDatabase.inMemory());
      addTearDown(store.close);

      await store.write('user:1', entry('v1'));
      await store.write('user:12', entry('v2'));
      await store.write('user:', entry('v3'));

      expect(
        await store.getKeysByPattern('user:?'),
        unorderedEquals(['user:1']),
        reason: '? matches exactly one character',
      );
      expect(
        await store.getKeysByPattern('user:*'),
        unorderedEquals(['user:1', 'user:12', 'user:']),
      );
    });

    test('regex metacharacters in patterns are escaped', () async {
      final store = stringStore(SyncacheDriftDatabase.inMemory());
      addTearDown(store.close);

      await store.write('v1.0', entry('v1'));
      await store.write('v1X0', entry('v2'));

      expect(
        await store.getKeysByPattern('v1.0'),
        unorderedEquals(['v1.0']),
        reason: 'a dot in the pattern must not act as a wildcard',
      );
      expect(
        await store.getKeysByPattern('v1?0'),
        unorderedEquals(['v1.0', 'v1X0']),
      );
    });

    test('deleteByPattern removes matched entries and their tags', () async {
      final store = stringStore(SyncacheDriftDatabase.inMemory());
      addTearDown(store.close);

      await store.writeWithTags('user:1', entry('v1'), ['users']);
      await store.writeWithTags('post:1', entry('v2'), ['posts']);

      await store.deleteByPattern('user:*');

      expect(await store.read('user:1'), isNull);
      expect(await store.getKeysByTag('users'), isEmpty);
      expect(await store.read('post:1'), isNotNull);
    });
  });

  group('DriftStore lifecycle', () {
    test('operations throw after close; close is idempotent', () async {
      final store = stringStore(SyncacheDriftDatabase.inMemory());
      await store.write('k', entry('v'));
      expect(store.isClosed, isFalse);
      expect(store.isOpen, isTrue);

      await store.close();
      await store.close(); // idempotent

      expect(store.isClosed, isTrue);
      expect(store.isOpen, isFalse);
      await expectLater(store.read('k'), throwsStateError);
      await expectLater(store.write('k', entry('v')), throwsStateError);
      await expectLater(store.keys(), throwsStateError);
    });

    test('close waits for in-flight operations before closing', () async {
      final path = pathFor('safe_close');
      final store = await DriftStore.open<String>(
        path: path,
        fromJson: (json) => json['v'] as String,
        toJson: (value) => {'v': value},
      );

      // The write begins (and registers as in-flight) synchronously, so
      // close() issued afterwards must wait for it to finish instead of
      // tearing down the database mid-write.
      final writeFuture = store.write('k', entry('v'));
      final closing = store.close();
      await writeFuture;
      await closing;
      expect(store.isClosed, isTrue);

      final reopened = await DriftStore.open<String>(
        path: path,
        fromJson: (json) => json['v'] as String,
        toJson: (value) => {'v': value},
      );
      addTearDown(reopened.close);
      final read = await reopened.read('k');
      expect(read, isNotNull, reason: 'the in-flight write was not lost');
      expect(read!.value, 'v');
    });
  });
}
