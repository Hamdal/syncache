import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncache/syncache.dart';
import 'package:syncache_flutter/syncache_flutter.dart';

/// A [Network] whose connectivity the test controls.
class FakeNetwork implements Network {
  FakeNetwork({this.online = true});
  bool online;

  @override
  bool get isOnline => online;
}

void main() {
  group('SyncacheScope outbox recovery', () {
    testWidgets(
        'replays persisted records on mount and reports via onRecovered',
        (tester) async {
      final store = MemoryStore<String>();
      final outbox = MemoryMutationOutbox();
      final network = FakeNetwork(online: false);

      // "Previous session": queue an offline write, then die.
      final previous = Syncache<String>(
        store: store,
        network: network,
        outbox: outbox,
      );
      await previous.set(key: 'k', value: 'v0');
      await previous.mutate(
        key: 'k',
        mutation: Mutation<String>(
          apply: (_) => 'v1',
          send: (_) async => 'v1-server',
        ),
        payload: {'op': 'update', 'n': 1},
      );
      expect(await outbox.loadAll(), hasLength(1));
      previous.dispose();

      // New session: online, scope auto-recovers on mount.
      network.online = true;
      final recoveredCounts = <int>[];
      await tester.pumpWidget(
        SyncacheScope<String>(
          cache: Syncache<String>(
            store: store,
            network: network,
            outbox: outbox,
          ),
          resolvePendingMutation: (record) async => Mutation<String>(
            apply: (_) => 'v${record.payload['n']}',
            send: (_) async => 'v1-server',
          ),
          onRecovered: recoveredCounts.add,
          child: const SizedBox(),
        ),
      );
      await tester.pumpAndSettle();

      expect(recoveredCounts, [1]);
      expect(
        await outbox.loadAll(),
        isEmpty,
        reason: 'recovered mutation flushed on mount (network online)',
      );
    });

    testWidgets('resolver is optional: no recovery without it', (tester) async {
      final store = MemoryStore<String>();
      final outbox = MemoryMutationOutbox();
      final network = FakeNetwork(online: false);
      final cache = Syncache<String>(
        store: store,
        network: network,
        outbox: outbox,
      );
      addTearDown(cache.dispose);

      await tester.pumpWidget(
        SyncacheScope<String>(
          cache: cache,
          child: const SizedBox(),
        ),
      );
      await tester.pumpAndSettle();

      expect(cache.pendingMutationCount, 0);
    });
  });
}
