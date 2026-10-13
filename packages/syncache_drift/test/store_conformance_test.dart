import 'package:syncache_drift/syncache_drift.dart';
import 'package:test/test.dart';

// Shared conformance suite, canonical copy lives in the core package.
import '../../syncache/test/taggable_store_conformance.dart';

void main() {
  final stores = <DriftStore<String>>[];

  tearDownAll(() async {
    for (final store in stores) {
      if (store.isOpen) {
        await store.close();
      }
    }
  });

  testTaggableStoreConformance(
    'DriftStore',
    () async {
      final store = DriftStore<String>(
        db: SyncacheDriftDatabase.inMemory(),
        fromJson: (json) => json['v'] as String,
        toJson: (value) => {'v': value},
      );
      stores.add(store);
      return store;
    },
  );
}
