import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

/// Shared conformance suite for [TaggableStore] implementations.
///
/// Every storage backend that implements [TaggableStore] must pass these
/// tests so that tag semantics are identical regardless of the storage
/// engine. See the tag lifecycle contract documented on [TaggableStore]:
///
/// - plain [TaggableStore.write] preserves existing tags,
/// - [TaggableStore.writeWithTags] replaces tags entirely,
/// - [TaggableStore.delete] and [TaggableStore.clear] remove tag mappings.
void testTaggableStoreConformance(
  String label,
  Future<TaggableStore<String>> Function() createStore,
) {
  group('$label TaggableStore conformance', () {
    late TaggableStore<String> store;

    setUp(() async {
      store = await createStore();
    });

    Stored<String> entry(String value) => Stored(
          value: value,
          meta: Metadata(version: 1, storedAt: DateTime.now()),
        );

    test('writeWithTags associates tags with the key', () async {
      await store.writeWithTags('k1', entry('v1'), ['a', 'b']);

      expect(await store.getTags('k1'), unorderedEquals(['a', 'b']));
      expect(await store.getKeysByTag('a'), contains('k1'));
      expect(await store.getKeysByTag('b'), contains('k1'));
    });

    test('plain write preserves existing tags', () async {
      await store.writeWithTags('k1', entry('v1'), ['a']);

      await store.write('k1', entry('v2'));

      expect(await store.getTags('k1'), equals(['a']));
      expect(await store.getKeysByTag('a'), contains('k1'));
      expect((await store.read('k1'))!.value, equals('v2'));
    });

    test('writeWithTags replaces tags entirely', () async {
      await store.writeWithTags('k1', entry('v1'), ['a', 'b']);

      await store.writeWithTags('k1', entry('v2'), ['c']);

      expect(await store.getTags('k1'), equals(['c']));
      expect(await store.getKeysByTag('a'), isNot(contains('k1')));
      expect(await store.getKeysByTag('b'), isNot(contains('k1')));
      expect(await store.getKeysByTag('c'), contains('k1'));
    });

    test('writeWithTags with empty list clears tags', () async {
      await store.writeWithTags('k1', entry('v1'), ['a']);

      await store.writeWithTags('k1', entry('v2'), <String>[]);

      expect(await store.getTags('k1'), isEmpty);
      expect(await store.getKeysByTag('a'), isNot(contains('k1')));
    });

    test('write on a new key leaves no tags', () async {
      await store.write('k1', entry('v1'));

      expect(await store.getTags('k1'), isEmpty);
      expect(await store.getKeysByTag('a'), isNot(contains('k1')));
    });

    test('delete removes tag mappings', () async {
      await store.writeWithTags('k1', entry('v1'), ['a']);

      await store.delete('k1');

      expect(await store.getTags('k1'), isEmpty);
      expect(await store.getKeysByTag('a'), isNot(contains('k1')));
      expect(await store.read('k1'), isNull);
    });

    test('clear removes all entries and tags', () async {
      await store.writeWithTags('k1', entry('v1'), ['a']);
      await store.writeWithTags('k2', entry('v2'), ['b']);

      await store.clear();

      expect(await store.read('k1'), isNull);
      expect(await store.read('k2'), isNull);
      expect(await store.getKeysByTag('a'), isEmpty);
      expect(await store.getKeysByTag('b'), isEmpty);
    });

    test('deleteByTag deletes only matching entries', () async {
      await store.writeWithTags('k1', entry('v1'), ['a']);
      await store.writeWithTags('k2', entry('v2'), ['b']);

      await store.deleteByTag('a');

      expect(await store.read('k1'), isNull);
      expect(await store.read('k2'), isNotNull);
    });

    test('deleteByTags matchAll:false deletes entries with any tag', () async {
      await store.writeWithTags('k1', entry('v1'), ['a', 'x']);
      await store.writeWithTags('k2', entry('v2'), ['b']);
      await store.writeWithTags('k3', entry('v3'), ['c']);

      await store.deleteByTags(['a', 'b']);

      expect(await store.read('k1'), isNull);
      expect(await store.read('k2'), isNull);
      expect(await store.read('k3'), isNotNull);
    });

    test('deleteByTags matchAll:true deletes only entries with all tags',
        () async {
      await store.writeWithTags('k1', entry('v1'), ['a', 'b']);
      await store.writeWithTags('k2', entry('v2'), ['a']);

      await store.deleteByTags(['a', 'b'], matchAll: true);

      expect(await store.read('k1'), isNull);
      expect(await store.read('k2'), isNotNull);
    });

    test('pattern operations match keys and clean up tags', () async {
      await store.writeWithTags('user:1', entry('v1'), ['users']);
      await store.writeWithTags('user:2', entry('v2'), ['users']);
      await store.writeWithTags('post:1', entry('v3'), ['posts']);

      expect(
        await store.getKeysByPattern('user:*'),
        unorderedEquals(['user:1', 'user:2']),
      );

      await store.deleteByPattern('user:*');

      expect(await store.read('user:1'), isNull);
      expect(await store.read('user:2'), isNull);
      expect(await store.getKeysByTag('users'), isEmpty);
      expect(await store.read('post:1'), isNotNull);
      expect(await store.getKeysByTag('posts'), contains('post:1'));
    });

    test('getTags on a missing key returns empty', () async {
      expect(await store.getTags('missing'), isEmpty);
    });
  });
}
