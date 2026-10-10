import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

void main() {
  late MemoryStore<String> store;
  late Syncache<String> cache;

  setUp(() {
    store = MemoryStore<String>();
    cache = Syncache<String>(store: store);
  });

  tearDown(() {
    cache.dispose();
  });

  group('getConditional', () {
    test('stores etag and sends conditional header on next fetch', () async {
      final seenHeaders = <Map<String, String>>[];
      // networkOnly bypasses the offlineFirst cache hit so the fetcher
      // actually runs on both calls.
      const policy = Policy.networkOnly;

      await cache.getConditional(
        key: 'user:1',
        policy: policy,
        fetch: (request) {
          seenHeaders.add(request.headers);
          return Future.value(FetchResult.data('v1', etag: '"abc"'));
        },
      );

      await cache.getConditional(
        key: 'user:1',
        policy: policy,
        fetch: (request) {
          seenHeaders.add(request.headers);
          return Future.value(FetchResult.data('v2'));
        },
      );

      expect(seenHeaders, hasLength(2));
      expect(seenHeaders.first, isEmpty);
      expect(seenHeaders.last['If-None-Match'], equals('"abc"'));
    });

    test('notModified returns cached value and refreshes storedAt', () async {
      await cache.getConditional(
        key: 'user:1',
        fetch: (_) async => FetchResult.data('v1', etag: '"abc"'),
      );
      final storedAtBefore = (await store.read('user:1'))!.meta.storedAt;

      // Give the clock a moment so storedAt can be observed changing.
      await Future<void>.delayed(const Duration(milliseconds: 5));

      final value = await cache.getConditional(
        key: 'user:1',
        policy: Policy.networkOnly,
        fetch: (_) async => FetchResult<String>.notModified(),
      );

      expect(value, equals('v1'));
      expect(
        (await store.read('user:1'))!.meta.storedAt.isAfter(storedAtBefore),
        isTrue,
      );
    });

    test('notModified without cache throws the exported conditional miss',
        () async {
      await expectLater(
        cache.getConditional(
          key: 'missing',
          // networkOnly surfaces the specific type; offlineFirst converts
          // it to a plain CacheMissException by design (see
          // _ConditionalFetchStrategy.isConvertibleToCacheMiss).
          policy: Policy.networkOnly,
          fetch: (_) async => FetchResult<String>.notModified(),
        ),
        throwsA(isA<CacheMissForConditionalException>()),
      );

      await expectLater(
        cache.getConditional(
          key: 'missing',
          policy: Policy.networkOnly,
          fetch: (_) async => FetchResult<String>.notModified(),
        ),
        throwsA(isA<CacheMissException>()),
      );
    });

    test('offlineFirst converts a conditional miss into CacheMissException',
        () async {
      await expectLater(
        cache.getConditional(
          key: 'missing',
          policy: Policy.offlineFirst,
          fetch: (_) async => FetchResult<String>.notModified(),
        ),
        // The plain base type, NOT the conditional subclass.
        throwsA(
          isA<CacheMissException>()
              .having((e) => e.runtimeType, 'runtimeType', CacheMissException),
        ),
      );
    });
  });
}
