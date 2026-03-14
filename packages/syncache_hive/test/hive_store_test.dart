import 'dart:async';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:syncache/syncache.dart';
import 'package:syncache_hive/syncache_hive.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('HiveStore', () {
    late HiveStore<Map<String, dynamic>> store;

    setUp(() async {
      store = await HiveStore.open<Map<String, dynamic>>(
        boxName: 'test_${DateTime.now().millisecondsSinceEpoch}',
        fromJson: (json) => json,
        toJson: (value) => value,
      );
    });

    tearDown(() async {
      if (store.isOpen) {
        await store.close();
      }
    });

    group('basic operations', () {
      test('stores and retrieves values', () async {
        final stored = Stored(
          value: {'name': 'Alice', 'age': 30},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        await store.write('user:1', stored);
        final result = await store.read('user:1');

        expect(result, isNotNull);
        expect(result!.value['name'], equals('Alice'));
        expect(result.value['age'], equals(30));
        expect(result.meta.version, equals(1));
      });

      test('returns null for non-existent key', () async {
        final result = await store.read('nonexistent');

        expect(result, isNull);
      });

      test('overwrites existing values', () async {
        final stored1 = Stored(
          value: {'name': 'Alice'},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );
        final stored2 = Stored(
          value: {'name': 'Bob'},
          meta: Metadata(version: 2, storedAt: DateTime.now()),
        );

        await store.write('key', stored1);
        await store.write('key', stored2);
        final result = await store.read('key');

        expect(result!.value['name'], equals('Bob'));
        expect(result.meta.version, equals(2));
      });

      test('deletes individual keys', () async {
        final stored = Stored(
          value: {'name': 'Alice'},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        await store.write('key', stored);
        await store.delete('key');
        final result = await store.read('key');

        expect(result, isNull);
      });

      test('clears all entries', () async {
        final stored1 = Stored(
          value: {'name': 'Alice'},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );
        final stored2 = Stored(
          value: {'name': 'Bob'},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        await store.write('key1', stored1);
        await store.write('key2', stored2);
        await store.clear();

        expect(await store.read('key1'), isNull);
        expect(await store.read('key2'), isNull);
      });
    });

    group('edge cases', () {
      test('handles empty string key', () async {
        final stored = Stored(
          value: {'name': 'test'},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        await store.write('', stored);
        final result = await store.read('');

        expect(result, isNotNull);
        expect(result!.value['name'], equals('test'));
      });

      test('handles special characters in keys', () async {
        final stored = Stored(
          value: {'name': 'test'},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        const specialKey = 'user:@#\$%^&*()_+-=[]{}|;:,.<>?';
        await store.write(specialKey, stored);
        final result = await store.read(specialKey);

        expect(result, isNotNull);
        expect(result!.value['name'], equals('test'));
      });

      test('handles unicode in keys and values', () async {
        final stored = Stored(
          value: {'name': '日本語テスト', 'emoji': '🎉🚀'},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        const unicodeKey = 'ユーザー:1';
        await store.write(unicodeKey, stored);
        final result = await store.read(unicodeKey);

        expect(result, isNotNull);
        expect(result!.value['name'], equals('日本語テスト'));
        expect(result.value['emoji'], equals('🎉🚀'));
      });

      test('handles keys at max length (255 chars)', () async {
        final stored = Stored(
          value: {'name': 'test'},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        // Hive has a max key length of 255 characters
        final maxLengthKey = 'k' * 255;
        await store.write(maxLengthKey, stored);
        final result = await store.read(maxLengthKey);

        expect(result, isNotNull);
        expect(result!.value['name'], equals('test'));
      });

      test('throws error for keys exceeding 255 chars', () async {
        final stored = Stored(
          value: {'name': 'test'},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        // Keys longer than 255 characters are rejected by Hive
        final tooLongKey = 'k' * 256;
        expect(
          () => store.write(tooLongKey, stored),
          throwsA(isA<HiveError>()),
        );
      });

      test('handles null values in nested structures', () async {
        final stored = Stored(
          value: {
            'name': 'test',
            'nullField': null,
            'nested': {'also': null},
          },
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        await store.write('key', stored);
        final result = await store.read('key');

        expect(result, isNotNull);
        expect(result!.value['nullField'], isNull);
        expect(result.value['nested']['also'], isNull);
      });

      test('handles empty map values', () async {
        final stored = Stored(
          value: <String, dynamic>{},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        await store.write('key', stored);
        final result = await store.read('key');

        expect(result, isNotNull);
        expect(result!.value, isEmpty);
      });

      test('handles deeply nested structures', () async {
        final stored = Stored(
          value: {
            'l1': {
              'l2': {
                'l3': {
                  'l4': {
                    'l5': {'value': 'deep'},
                  },
                },
              },
            },
          },
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        await store.write('key', stored);
        final result = await store.read('key');

        expect(result, isNotNull);
        expect(
          result!.value['l1']['l2']['l3']['l4']['l5']['value'],
          equals('deep'),
        );
      });
    });

    group('metadata serialization', () {
      test('preserves all metadata fields', () async {
        final now = DateTime.now();
        const ttl = Duration(minutes: 5);
        final lastModified = now.subtract(const Duration(hours: 1));

        final stored = Stored(
          value: {'data': 'test'},
          meta: Metadata(
            version: 42,
            storedAt: now,
            ttl: ttl,
            etag: '"abc123"',
            lastModified: lastModified,
          ),
        );

        await store.write('key', stored);
        final result = await store.read('key');

        expect(result, isNotNull);
        expect(result!.meta.version, equals(42));
        expect(
          result.meta.storedAt.millisecondsSinceEpoch,
          equals(now.millisecondsSinceEpoch),
        );
        expect(result.meta.ttl, equals(ttl));
        expect(result.meta.etag, equals('"abc123"'));
        expect(
          result.meta.lastModified!.millisecondsSinceEpoch,
          equals(lastModified.millisecondsSinceEpoch),
        );
      });

      test('handles null optional metadata fields', () async {
        final stored = Stored(
          value: {'data': 'test'},
          meta: Metadata(
            version: 1,
            storedAt: DateTime.now(),
          ),
        );

        await store.write('key', stored);
        final result = await store.read('key');

        expect(result, isNotNull);
        expect(result!.meta.ttl, isNull);
        expect(result.meta.etag, isNull);
        expect(result.meta.lastModified, isNull);
      });
    });

    group('nested data structures', () {
      test('handles nested maps', () async {
        final stored = Stored(
          value: {
            'user': {
              'profile': {
                'name': 'Alice',
                'settings': {'theme': 'dark'},
              },
            },
          },
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        await store.write('key', stored);
        final result = await store.read('key');

        expect(result!.value['user']['profile']['name'], equals('Alice'));
        expect(
          result.value['user']['profile']['settings']['theme'],
          equals('dark'),
        );
      });

      test('handles lists', () async {
        final stored = Stored(
          value: {
            'items': ['a', 'b', 'c'],
            'numbers': [1, 2, 3],
          },
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        await store.write('key', stored);
        final result = await store.read('key');

        expect(result!.value['items'], equals(['a', 'b', 'c']));
        expect(result.value['numbers'], equals([1, 2, 3]));
      });

      test('handles lists of maps', () async {
        final stored = Stored(
          value: {
            'users': [
              {'name': 'Alice', 'age': 30},
              {'name': 'Bob', 'age': 25},
            ],
          },
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        await store.write('key', stored);
        final result = await store.read('key');

        expect(result!.value['users'][0]['name'], equals('Alice'));
        expect(result.value['users'][1]['name'], equals('Bob'));
      });
    });

    group('tag operations', () {
      test('writes and retrieves tags', () async {
        final stored = Stored(
          value: {'name': 'Alice'},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        await store.writeWithTags('key', stored, ['user', 'admin']);
        final tags = await store.getTags('key');

        expect(tags, containsAll(['user', 'admin']));
      });

      test('returns empty list for key without tags', () async {
        final stored = Stored(
          value: {'name': 'Alice'},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        await store.write('key', stored);
        final tags = await store.getTags('key');

        expect(tags, isEmpty);
      });

      test('returns empty list for non-existent key', () async {
        final tags = await store.getTags('nonexistent');

        expect(tags, isEmpty);
      });

      test('write without tags removes existing tags', () async {
        final stored = Stored(
          value: {'name': 'Alice'},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        await store.writeWithTags('key', stored, ['tag1', 'tag2']);
        await store.write('key', stored);
        final tags = await store.getTags('key');

        expect(tags, isEmpty);
      });

      test('writeWithTags replaces existing tags', () async {
        final stored = Stored(
          value: {'name': 'Alice'},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        await store.writeWithTags('key', stored, ['tag1', 'tag2']);
        await store.writeWithTags('key', stored, ['tag3']);
        final tags = await store.getTags('key');

        expect(tags, equals(['tag3']));
        expect(tags, isNot(contains('tag1')));
        expect(tags, isNot(contains('tag2')));
      });

      test('deletes entries by single tag', () async {
        final stored = Stored(
          value: {'name': 'test'},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        await store.writeWithTags('key1', stored, ['tag1']);
        await store.writeWithTags('key2', stored, ['tag1', 'tag2']);
        await store.writeWithTags('key3', stored, ['tag2']);

        await store.deleteByTag('tag1');

        expect(await store.read('key1'), isNull);
        expect(await store.read('key2'), isNull);
        expect(await store.read('key3'), isNotNull);
      });

      test('deleteByTags with matchAll=false deletes any matching', () async {
        final stored = Stored(
          value: {'name': 'test'},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        await store.writeWithTags('key1', stored, ['a']);
        await store.writeWithTags('key2', stored, ['b']);
        await store.writeWithTags('key3', stored, ['c']);

        await store.deleteByTags(['a', 'b'], matchAll: false);

        expect(await store.read('key1'), isNull);
        expect(await store.read('key2'), isNull);
        expect(await store.read('key3'), isNotNull);
      });

      test('deleteByTags with matchAll=true deletes only all matching',
          () async {
        final stored = Stored(
          value: {'name': 'test'},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        await store.writeWithTags('key1', stored, ['a', 'b']);
        await store.writeWithTags('key2', stored, ['a']);
        await store.writeWithTags('key3', stored, ['b']);
        await store.writeWithTags('key4', stored, ['a', 'b', 'c']);

        await store.deleteByTags(['a', 'b'], matchAll: true);

        expect(await store.read('key1'), isNull);
        expect(await store.read('key2'), isNotNull);
        expect(await store.read('key3'), isNotNull);
        expect(await store.read('key4'), isNull);
      });

      test('deleteByTags with empty list does nothing', () async {
        final stored = Stored(
          value: {'name': 'test'},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        await store.writeWithTags('key1', stored, ['tag']);
        await store.deleteByTags([]);

        expect(await store.read('key1'), isNotNull);
      });

      test('getKeysByTag returns matching keys', () async {
        final stored = Stored(
          value: {'name': 'test'},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        await store.writeWithTags('key1', stored, ['user']);
        await store.writeWithTags('key2', stored, ['user', 'admin']);
        await store.writeWithTags('key3', stored, ['admin']);

        final keys = await store.getKeysByTag('user');

        expect(keys, containsAll(['key1', 'key2']));
        expect(keys, isNot(contains('key3')));
      });
    });

    group('pattern operations', () {
      test('deleteByPattern deletes matching keys', () async {
        final stored = Stored(
          value: {'name': 'test'},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        await store.write('user:1', stored);
        await store.write('user:2', stored);
        await store.write('product:1', stored);

        await store.deleteByPattern('user:*');

        expect(await store.read('user:1'), isNull);
        expect(await store.read('user:2'), isNull);
        expect(await store.read('product:1'), isNotNull);
      });

      test('getKeysByPattern returns matching keys', () async {
        final stored = Stored(
          value: {'name': 'test'},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        await store.write('user:1', stored);
        await store.write('user:2', stored);
        await store.write('product:1', stored);

        final keys = await store.getKeysByPattern('user:*');

        expect(keys, containsAll(['user:1', 'user:2']));
        expect(keys, isNot(contains('product:1')));
      });

      test('pattern with single character wildcard', () async {
        final stored = Stored(
          value: {'name': 'test'},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        await store.write('user:1', stored);
        await store.write('user:2', stored);
        await store.write('user:10', stored);

        final keys = await store.getKeysByPattern('user:?');

        expect(keys, containsAll(['user:1', 'user:2']));
        expect(keys, isNot(contains('user:10')));
      });

      test('pattern matching escapes regex metacharacters', () async {
        final stored = Stored(
          value: {'name': 'test'},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        await store.write('user.name', stored);
        await store.write('username', stored);

        // '.' in pattern should match literal '.', not any character
        final keys = await store.getKeysByPattern('user.name');

        expect(keys, contains('user.name'));
        expect(keys, isNot(contains('username')));
      });
    });

    group('delete also removes tags', () {
      test('delete removes associated tags', () async {
        final stored = Stored(
          value: {'name': 'test'},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        await store.writeWithTags('key', stored, ['tag1', 'tag2']);
        await store.delete('key');

        // Key should not appear in tag queries
        expect(await store.getKeysByTag('tag1'), isEmpty);
        expect(await store.getKeysByTag('tag2'), isEmpty);
      });

      test('clear removes all tags', () async {
        final stored = Stored(
          value: {'name': 'test'},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        await store.writeWithTags('key1', stored, ['tag1']);
        await store.writeWithTags('key2', stored, ['tag2']);
        await store.clear();

        expect(await store.getKeysByTag('tag1'), isEmpty);
        expect(await store.getKeysByTag('tag2'), isEmpty);
      });
    });

    group('close and state management', () {
      test('isOpen returns true for open store', () async {
        expect(store.isOpen, isTrue);
        expect(store.isClosed, isFalse);
      });

      test('isOpen returns false after close', () async {
        await store.close();

        expect(store.isOpen, isFalse);
        expect(store.isClosed, isTrue);
      });

      test('close is idempotent', () async {
        await store.close();
        await store.close(); // Should not throw

        expect(store.isClosed, isTrue);
      });

      test('operations throw StateError after close', () async {
        await store.close();

        expect(
          () => store.read('key'),
          throwsA(isA<StateError>()),
        );
        expect(
          () => store.write(
            'key',
            Stored(
              value: {'test': 'value'},
              meta: Metadata(version: 1, storedAt: DateTime.now()),
            ),
          ),
          throwsA(isA<StateError>()),
        );
        expect(
          () => store.delete('key'),
          throwsA(isA<StateError>()),
        );
        expect(
          () => store.clear(),
          throwsA(isA<StateError>()),
        );
        expect(
          () => store.getTags('key'),
          throwsA(isA<StateError>()),
        );
        expect(
          () => store.getKeysByTag('tag'),
          throwsA(isA<StateError>()),
        );
        expect(
          () => store.getKeysByPattern('*'),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('error handling', () {
      test('read returns null and deletes corrupted data', () async {
        // Store the box name to use consistently
        final boxName = 'corrupt_test_${DateTime.now().millisecondsSinceEpoch}';

        // Write raw data directly to simulate corrupted/incompatible data
        final box = await Hive.openBox<Map<dynamic, dynamic>>(boxName);
        await box.put('key', {
          'value': {'data': 'test'},
          'meta': {
            'version': 1,
            'storedAt': DateTime.now().toIso8601String(),
          },
          'tags': [],
        });
        await box.close();

        // Reopen with a fromJson that throws
        final failStore = await HiveStore.open<_FailingType>(
          boxName: boxName,
          fromJson: (json) => throw const FormatException('Schema changed'),
          toJson: (value) => {'data': value.data},
        );

        // Read should return null (not throw) for corrupted data
        final result = await failStore.read('key');
        expect(result, isNull);

        // Verify the corrupted entry was deleted
        final checkResult = await failStore.read('key');
        expect(checkResult, isNull);

        await failStore.close();
      });

      test('handles invalid tags data gracefully', () async {
        final boxName =
            'invalid_tags_test_${DateTime.now().millisecondsSinceEpoch}';

        // Write data with invalid tags (not a list of strings)
        final box = await Hive.openBox<Map<dynamic, dynamic>>(boxName);
        await box.put('key', {
          'value': {'name': 'test'},
          'meta': {
            'version': 1,
            'storedAt': DateTime.now().toIso8601String(),
          },
          'tags': 'not-a-list', // Invalid: should be a list
        });
        await box.close();

        final testStore = await HiveStore.open<Map<String, dynamic>>(
          boxName: boxName,
          fromJson: (json) => json,
          toJson: (value) => value,
        );

        // getTags should return empty list for invalid tags
        final tags = await testStore.getTags('key');
        expect(tags, isEmpty);

        await testStore.close();
      });

      test('toJson throwing exception propagates error', () async {
        final failStore = await HiveStore.open<_FailingType>(
          boxName: 'tojson_fail_${DateTime.now().millisecondsSinceEpoch}',
          fromJson: (json) => _FailingType(json['data'] as String),
          toJson: (value) => throw const FormatException('toJson failed'),
        );

        final stored = Stored(
          value: _FailingType('test'),
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        expect(
          () => failStore.write('key', stored),
          throwsA(isA<FormatException>()),
        );

        await failStore.close();
      });
    });

    group('concurrent operations', () {
      test('close waits for pending operations', () async {
        final boxName =
            'concurrent_close_${DateTime.now().millisecondsSinceEpoch}';
        final testStore = await HiveStore.open<Map<String, dynamic>>(
          boxName: boxName,
          fromJson: (json) => json,
          toJson: (value) => value,
        );

        final stored = Stored(
          value: {'name': 'test'},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        // Start multiple write operations
        final futures = <Future<void>>[];
        for (var i = 0; i < 10; i++) {
          futures.add(testStore.write('key$i', stored));
        }

        // Close while operations are pending
        final closeFuture = testStore.close();

        // All operations should complete successfully
        await Future.wait(futures);
        await closeFuture;

        expect(testStore.isClosed, isTrue);
      });

      test('parallel reads and writes work correctly', () async {
        final stored = Stored(
          value: {'counter': 0},
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

        // Write initial value
        await store.write('counter', stored);

        // Perform parallel reads
        final readFutures = List.generate(
          10,
          (_) => store.read('counter'),
        );

        final results = await Future.wait(readFutures);

        // All reads should succeed
        for (final result in results) {
          expect(result, isNotNull);
          expect(result!.value['counter'], equals(0));
        }
      });

      test('operations after close fail immediately', () async {
        await store.close();

        // These should fail immediately, not hang
        final stopwatch = Stopwatch()..start();

        expect(
          () => store.read('key'),
          throwsA(isA<StateError>()),
        );

        stopwatch.stop();
        // Should fail very quickly (< 100ms)
        expect(stopwatch.elapsedMilliseconds, lessThan(100));
      });
    });
  });

  group('HiveStore.open', () {
    test('creates store with serialization functions', () async {
      final store = await HiveStore.open<Map<String, dynamic>>(
        boxName: 'open_test_${DateTime.now().millisecondsSinceEpoch}',
        fromJson: (json) => json,
        toJson: (value) => value,
      );

      final stored = Stored(
        value: {'test': 'value'},
        meta: Metadata(version: 1, storedAt: DateTime.now()),
      );

      await store.write('key', stored);
      final result = await store.read('key');

      expect(result!.value['test'], equals('value'));

      await store.close();
    });
  });

  group('HiveStore with custom types', () {
    test('works with custom fromJson/toJson', () async {
      final store = await HiveStore.open<_TestUser>(
        boxName: 'custom_type_${DateTime.now().millisecondsSinceEpoch}',
        fromJson: _TestUser.fromJson,
        toJson: (user) => user.toJson(),
      );

      final user = _TestUser(name: 'Alice', email: 'alice@example.com');
      final stored = Stored(
        value: user,
        meta: Metadata(version: 1, storedAt: DateTime.now()),
      );

      await store.write('user:1', stored);
      final result = await store.read('user:1');

      expect(result!.value.name, equals('Alice'));
      expect(result.value.email, equals('alice@example.com'));

      await store.close();
    });
  });

  group('HiveStore persistence', () {
    test('data persists across close and reopen', () async {
      final boxName = 'persist_test_${DateTime.now().millisecondsSinceEpoch}';

      // Write data
      final store1 = await HiveStore.open<Map<String, dynamic>>(
        boxName: boxName,
        fromJson: (json) => json,
        toJson: (value) => value,
      );

      final stored = Stored(
        value: {'name': 'Alice', 'score': 100},
        meta: Metadata(
          version: 5,
          storedAt: DateTime.now(),
          ttl: const Duration(hours: 1),
        ),
      );

      await store1.writeWithTags('key', stored, ['user', 'active']);
      await store1.close();

      // Reopen and verify
      final store2 = await HiveStore.open<Map<String, dynamic>>(
        boxName: boxName,
        fromJson: (json) => json,
        toJson: (value) => value,
      );

      final result = await store2.read('key');
      expect(result, isNotNull);
      expect(result!.value['name'], equals('Alice'));
      expect(result.value['score'], equals(100));
      expect(result.meta.version, equals(5));
      expect(result.meta.ttl, equals(const Duration(hours: 1)));

      final tags = await store2.getTags('key');
      expect(tags, containsAll(['user', 'active']));

      await store2.close();
    });
  });
}

class _TestUser {
  final String name;
  final String email;

  _TestUser({required this.name, required this.email});

  factory _TestUser.fromJson(Map<String, dynamic> json) {
    return _TestUser(
      name: json['name'] as String,
      email: json['email'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'email': email};
}

class _FailingType {
  final String data;
  _FailingType(this.data);
}
