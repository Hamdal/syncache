import 'dart:io';

import 'package:hive_ce/hive_ce.dart';
import 'package:syncache/syncache.dart';
import 'package:syncache_hive/syncache_hive.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_tag_index_test_');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  /// Opens a store whose [fromJson] calls are counted via [jsonCalls].
  Future<(HiveStore<Map<String, dynamic>>, List<String>)> openCountingStore(
    String boxName,
  ) async {
    final jsonCalls = <String>[];
    final store = await HiveStore.open<Map<String, dynamic>>(
      boxName: boxName,
      fromJson: (json) {
        jsonCalls.add('read');
        return json;
      },
      toJson: (value) => value,
    );
    return (store, jsonCalls);
  }

  Stored<Map<String, dynamic>> entry(Map<String, dynamic> value) => Stored(
        value: value,
        meta: Metadata(version: 1, storedAt: DateTime.now()),
      );

  group('HiveStore tag index', () {
    late HiveStore<Map<String, dynamic>> store;
    late String boxName;

    setUp(() async {
      boxName = 'idx_${DateTime.now().millisecondsSinceEpoch}';
      store = await HiveStore.open<Map<String, dynamic>>(
        boxName: boxName,
        fromJson: (json) => json,
        toJson: (value) => value,
      );
    });

    tearDown(() async {
      if (store.isOpen) await store.close();
    });

    test('getKeysByTag reflects writes without a manual rebuild', () async {
      await store.writeWithTags('k1', entry({'v': 1}), ['a', 'b']);
      await store.writeWithTags('k2', entry({'v': 2}), ['a']);
      await store.write('k3', entry({'v': 3}));

      expect(await store.getKeysByTag('a'), unorderedEquals(['k1', 'k2']));
      expect(await store.getKeysByTag('b'), ['k1']);
      expect(await store.getKeysByTag('missing'), isEmpty);
    });

    test('index tracks tag replacement via writeWithTags', () async {
      await store.writeWithTags('k1', entry({'v': 1}), ['a']);

      await store.writeWithTags('k1', entry({'v': 2}), ['c']);

      expect(await store.getKeysByTag('a'), isEmpty);
      expect(await store.getKeysByTag('c'), ['k1']);
    });

    test('plain write preserves tag membership', () async {
      await store.writeWithTags('k1', entry({'v': 1}), ['a']);

      await store.write('k1', entry({'v': 2}));

      expect(await store.getKeysByTag('a'), ['k1']);
    });

    test('delete removes the key from the index', () async {
      await store.writeWithTags('k1', entry({'v': 1}), ['a']);

      await store.delete('k1');

      expect(await store.getKeysByTag('a'), isEmpty);
    });

    test('clear empties the index', () async {
      await store.writeWithTags('k1', entry({'v': 1}), ['a']);

      await store.clear();

      expect(await store.getKeysByTag('a'), isEmpty);
    });

    test('deleteByTag deletes entries and updates the index', () async {
      await store.writeWithTags('k1', entry({'v': 1}), ['a', 'x']);
      await store.writeWithTags('k2', entry({'v': 2}), ['a', 'y']);

      await store.deleteByTag('a');

      expect(await store.read('k1'), isNull);
      expect(await store.read('k2'), isNull);
      expect(await store.getKeysByTag('a'), isEmpty);
      expect(await store.getKeysByTag('x'), isEmpty);
      expect(await store.getKeysByTag('y'), isEmpty);
    });

    test('deleteByTags (any) deletes and updates the index', () async {
      await store.writeWithTags('k1', entry({'v': 1}), ['a']);
      await store.writeWithTags('k2', entry({'v': 2}), ['b']);
      await store.writeWithTags('k3', entry({'v': 3}), ['c']);

      await store.deleteByTags(['a', 'b']);

      expect(await store.read('k1'), isNull);
      expect(await store.read('k2'), isNull);
      expect(await store.read('k3'), isNotNull);
      expect(await store.getKeysByTag('a'), isEmpty);
      expect(await store.getKeysByTag('b'), isEmpty);
      expect(await store.getKeysByTag('c'), ['k3']);
    });

    test('deleteByTags (all) deletes and updates the index', () async {
      await store.writeWithTags('k1', entry({'v': 1}), ['a', 'b']);
      await store.writeWithTags('k2', entry({'v': 2}), ['a']);

      await store.deleteByTags(['a', 'b'], matchAll: true);

      expect(await store.read('k1'), isNull);
      expect(await store.read('k2'), isNotNull);
      expect(await store.getKeysByTag('a'), ['k2']);
    });

    test('index is rebuilt lazily and correctly after reopen', () async {
      await store.writeWithTags('k1', entry({'v': 1}), ['a']);
      await store.writeWithTags('k2', entry({'v': 2}), ['a', 'b']);
      await store.close();

      final reopened = await HiveStore.open<Map<String, dynamic>>(
        boxName: boxName,
        fromJson: (json) => json,
        toJson: (value) => value,
      );
      addTearDown(reopened.close);

      // First tag operation after open triggers the single-scan rebuild.
      expect(
        await reopened.getKeysByTag('a'),
        unorderedEquals(['k1', 'k2']),
      );
      expect(await reopened.getKeysByTag('b'), ['k2']);

      // The rebuilt index keeps syncing with new writes.
      await reopened.writeWithTags('k3', entry({'v': 3}), ['a']);
      expect(
        await reopened.getKeysByTag('a'),
        unorderedEquals(['k1', 'k2', 'k3']),
      );
      await reopened.delete('k2');
      expect(
        await reopened.getKeysByTag('a'),
        unorderedEquals(['k1', 'k3']),
      );
    });
  });

  group('HiveStore index performance semantics', () {
    test('tag and pattern operations never deserialize values', () async {
      final boxName = 'nodeser_${DateTime.now().millisecondsSinceEpoch}';
      final (store, jsonCalls) = await openCountingStore(boxName);
      addTearDown(store.close);

      for (var i = 0; i < 50; i++) {
        await store.writeWithTags(
          'k$i',
          entry({
            'data': 'value-$i',
            'nested': {'x': i},
          }),
          ['tag${i % 5}'],
        );
      }
      expect(jsonCalls, isEmpty, reason: 'writes must not call fromJson');
      jsonCalls.clear();

      // One read to prove the counter works.
      await store.read('k0');
      expect(jsonCalls, hasLength(1));
      jsonCalls.clear();

      await store.getKeysByTag('tag1');
      await store.getKeysByPattern('k*');
      await store.deleteByTag('tag2');
      await store.deleteByPattern('k1?');
      expect(
        jsonCalls,
        isEmpty,
        reason: 'tag/pattern operations must scan keys only',
      );
    });

    test('getKeysByTag stays fast with 1000 tagged entries', () async {
      final boxName = 'perf_${DateTime.now().millisecondsSinceEpoch}';
      final (store, _) = await openCountingStore(boxName);
      addTearDown(store.close);

      for (var i = 0; i < 1000; i++) {
        await store.writeWithTags(
          'k$i',
          entry({'data': 'payload-$i'}),
          ['bulk', 'group${i % 10}'],
        );
      }

      final stopwatch = Stopwatch()..start();
      final keys = await store.getKeysByTag('bulk');
      stopwatch.stop();

      expect(keys, hasLength(1000));
      // Generous regression tripwire, not a perf claim: the index makes
      // this O(matches); a full scan + deserialize of every value would be
      // an order of magnitude slower.
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('index rebuild skips corrupted entries', () async {
      final boxName = 'corrupt_${DateTime.now().millisecondsSinceEpoch}';
      final box = await Hive.openBox<Map<dynamic, dynamic>>(boxName);
      await box.put('good', {
        'value': {'v': 1},
        'meta': {
          'version': 1,
          'storedAt': DateTime.now().toIso8601String(),
        },
        'tags': ['a'],
      });
      // Corrupted entries: tags of the wrong type, and a missing tags field.
      await box.put('bad_tags', {
        'value': {'v': 2},
        'meta': {
          'version': 1,
          'storedAt': DateTime.now().toIso8601String(),
        },
        'tags': 'not-a-list',
      });
      await box.put('no_tags', {
        'value': {'v': 3},
        'meta': {
          'version': 1,
          'storedAt': DateTime.now().toIso8601String(),
        },
      });

      final store = HiveStore<Map<String, dynamic>>(
        box: box,
        fromJson: (json) => json,
        toJson: (value) => value,
      );
      addTearDown(store.close);

      // Rebuild over the corrupted entries must not throw and must find
      // only the healthy entry.
      expect(await store.getKeysByTag('a'), ['good']);
      expect(
        await store.getKeysByTag('a'),
        ['good'],
        reason: 'second call uses the in-memory index',
      );

      await store.writeWithTags('extra', entry({'v': 4}), ['a']);
      expect(
        await store.getKeysByTag('a'),
        unorderedEquals(['good', 'extra']),
      );
    });
  });

  group('HiveStore IterableStore', () {
    test('keys() enumerates all keys', () async {
      final store = await HiveStore.open<Map<String, dynamic>>(
        boxName: 'keys_${DateTime.now().millisecondsSinceEpoch}',
        fromJson: (json) => json,
        toJson: (value) => value,
      );
      addTearDown(store.close);

      await store.writeWithTags('k1', entry({'v': 1}), ['a']);
      await store.write('k2', entry({'v': 2}));

      expect(await store.keys(), unorderedEquals(['k1', 'k2']));
    });
  });
}
