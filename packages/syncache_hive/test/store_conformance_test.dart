import 'dart:io';

import 'package:hive_ce/hive_ce.dart';
import 'package:syncache_hive/syncache_hive.dart';
import 'package:test/test.dart';

// Shared conformance suite, canonical copy lives in the core package.
import '../../syncache/test/taggable_store_conformance.dart';

void main() {
  late Directory tempDir;
  var boxCounter = 0;
  final stores = <HiveStore<String>>[];

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_conformance_');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    for (final store in stores) {
      if (store.isOpen) {
        await store.close();
      }
    }
    await tempDir.delete(recursive: true);
  });

  testTaggableStoreConformance(
    'HiveStore',
    () async {
      final store = await HiveStore.open<String>(
        boxName: 'conformance_${++boxCounter}',
        fromJson: (json) => json['v'] as String,
        toJson: (value) => {'v': value},
      );
      stores.add(store);
      return store;
    },
  );
}
