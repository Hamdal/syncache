import 'package:syncache/syncache.dart';

import 'taggable_store_conformance.dart';

void main() {
  var namespaceCounter = 0;

  testTaggableStoreConformance(
    'MemoryStore',
    () async => MemoryStore<String>(),
  );

  testTaggableStoreConformance(
    'SharedMemoryStore',
    // Unique namespace per creation: SharedMemoryStore shares data through a
    // static registry, so tests must not see each other's entries.
    () async => SharedMemoryStore<String>(
      namespace: 'conformance-${++namespaceCounter}',
    ),
  );
}
