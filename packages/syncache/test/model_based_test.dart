import 'dart:async';
import 'dart:math';

import 'package:syncache/syncache.dart';
import 'package:test/test.dart';

/// Model-based (property) testing of the mutation engine and offline
/// semantics.
///
/// A tiny reference model mirrors the observable state of a `Syncache<int>`
/// (per-key values, pending queue size, handle outcomes). Randomized — but
/// seeded, so every failure is reproducible with the printed seed —
/// operation sequences drive both the real cache and the model, and the two
/// are compared after every step.
///
/// This catches ordering/interleaving regressions that example-based unit
/// tests miss: same-key mutation chains, offline queuing, reconnect flushes,
/// discard semantics, and invalidation/refetch interplay.
///
/// Values are ints and `send` echoes the value it is given, so the model
/// stays exact: a key's value is always the base value plus the sum of all
/// applied deltas since the last set/fetch.
void main() {
  /// Pumps the event loop until [condition] holds (bounded).
  Future<void> pumpUntil(bool Function() condition,
      {int maxPumps = 500}) async {
    for (var i = 0; i < maxPumps && !condition(); i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// The shared key pool is deliberately small so sequences hit the same
  /// keys repeatedly (same-key queues, re-basing, discard interplay).
  const keys = ['a', 'b', 'c'];
  const deltas = [1, -1, 10, -7];

  Future<void> runSeed(int seed, int ops) async {
    final rng = Random(seed);
    final net = _ControllableNetwork();
    final cache = Syncache<int>(
      store: MemoryStore<int>(),
      network: net,
      // Zero-delay retries keep the test fast; behavior is unchanged.
      mutationRetry: const MutationRetryConfig(
        maxAttempts: 2,
        delay: _zeroDelay,
      ),
    );
    addTearDown(cache.dispose);

    // ---- Reference model ----
    // NOTE (pinned semantics): invalidating a key does NOT cancel mutations
    // already queued for it. The reconnect flush still delivers the queued
    // write and its server-confirmed value overwrites the (invalidated)
    // cached entry. The model mirrors this: pending entries carry the
    // optimistic value captured at enqueue time, and flush writes those
    // values back unconditionally.
    final modelValues = <String, int>{};
    final modelPending = <_ModelPending>[];
    var networkCounter = 100;

    final trace = <String>[];
    void check(bool condition, String message) {
      if (!condition) {
        fail('Seed $seed diverged: $message\nRecent ops:\n${trace.join('\n')}');
      }
    }

    Future<int?> readCacheOnly(String key) async {
      try {
        return await cache.get(
          key: key,
          fetch: (_) async => throw StateError('cacheOnly must not fetch'),
          policy: Policy.cacheOnly,
        );
      } on CacheMissException {
        return null;
      }
    }

    Future<int?> readOfflineFirst(String key) async {
      try {
        return await cache.get(
          key: key,
          fetch: (_) async => ++networkCounter,
          policy: Policy.offlineFirst,
        );
      } on CacheMissException {
        return null;
      }
    }

    Future<void> flushIfOnline() async {
      if (!net.online) return;
      await cache.processPendingMutations();
      await pumpUntil(() => cache.pendingMutationCount == 0);
      for (final pending in modelPending) {
        final outcome = await pending.handle.outcome;
        check(outcome is MutationSuccess<int>,
            'flushed handle must succeed, got $outcome');
      }
      // Identity sends: the first queued write for a key lands with its
      // captured optimistic value; later same-key writes re-base on top of
      // the previous one (delta by delta), regardless of any set/invalidate
      // that happened while offline.
      final written = <String, int>{};
      for (final pending in modelPending) {
        final prev = written[pending.key];
        written[pending.key] =
            prev == null ? pending.optimisticValue : prev + pending.delta;
      }
      modelValues.addAll(written);
      modelPending.clear();
    }

    for (var step = 0; step < ops; step++) {
      final op = rng.nextInt(100);

      trace.add("s$step op=$op");
      if (op < 14) {
        // set: overwrite a key with a fresh value.
        final key = keys[rng.nextInt(keys.length)];
        final value = networkCounter++;
        trace.add("set $key=$value");
        await cache.set(key: key, value: value);
        modelValues[key] = value;
      } else if (op < 44) {
        // mutate: optimistic delta on an existing key.
        final key = keys[rng.nextInt(keys.length)];
        final delta = deltas[rng.nextInt(deltas.length)];
        final exists = modelValues.containsKey(key);
        MutationHandle<int>? handle;
        var threwMiss = false;
        try {
          handle = await cache.mutate(
            key: key,
            mutation: Mutation<int>(
              apply: (current) => current + delta,
              send: (value) async => value, // server echoes the value
            ),
          );
        } on CacheMissException {
          threwMiss = true;
        }
        check(threwMiss == !exists,
            'mutate($key): miss=$threwMiss but model says exists=$exists');
        if (handle == null) continue;
        final optimistic = modelValues[key]! + delta;
        modelValues[key] = optimistic;
        if (net.online) {
          // Awaiting the handle is deterministic: the send completes.
          final outcome = await handle.outcome;
          check(outcome is MutationSuccess<int>,
              'online mutate must succeed, got $outcome');
        } else {
          modelPending.add(_ModelPending(
            handle: handle,
            key: key,
            delta: delta,
            optimisticValue: optimistic,
          ));
          check(cache.pendingMutationCount == modelPending.length,
              'pending count mismatch after offline mutate');
        }
      } else if (op < 56) {
        // invalidate: delete a key.
        final key = keys[rng.nextInt(keys.length)];
        trace.add("invalidate $key (model=${modelValues[key]})");
        await cache.invalidate(key);
        modelValues.remove(key);
      } else if (op < 68) {
        // cacheOnly read: must match the model exactly.
        final key = keys[rng.nextInt(keys.length)];
        final actual = await readCacheOnly(key);
        check(actual == modelValues[key],
            'cacheOnly($key): cache=$actual model=${modelValues[key]}');
      } else if (op < 78) {
        // offlineFirst read: cached value, or fetch when missing+online.
        final key = keys[rng.nextInt(keys.length)];
        trace.add(
            "offlineFirst $key online=${net.online} model=${modelValues[key]}");
        final actual = await readOfflineFirst(key);
        if (!modelValues.containsKey(key) && net.online) {
          modelValues[key] = networkCounter;
        }
        check(actual == modelValues[key],
            'offlineFirst($key): cache=$actual model=${modelValues[key]}');
      } else if (op < 86) {
        // go online + flush the queue.
        net.online = true;
        await flushIfOnline();
      } else if (op < 92) {
        // go offline.
        net.online = false;
      } else if (op < 97) {
        // clear pending mutations (discards handles, keeps cached values).
        cache.clearPendingMutations();
        for (final pending in modelPending) {
          final outcome = await pending.handle.outcome;
          check(outcome is MutationDiscarded<int>,
              'cleared handle must be discarded, got $outcome');
        }
        modelPending.clear();
        check(cache.pendingMutationCount == 0, 'queue must be empty');
      } else {
        // Full sweep of all keys against the model.
        for (final key in keys) {
          final actual = await readCacheOnly(key);
          check(actual == modelValues[key],
              'sweep($key): cache=$actual model=${modelValues[key]}');
        }
        check(cache.pendingMutationCount == modelPending.length,
            'sweep: pending mismatch');
      }
    }

    // Final consistency: flush everything and compare the whole model.
    net.online = true;
    await flushIfOnline();
    for (final key in keys) {
      final actual = await readCacheOnly(key);
      check(actual == modelValues[key],
          'final($key): cache=$actual model=${modelValues[key]}');
    }
    check(cache.pendingMutationCount == 0, 'final queue must be empty');
  }

  test('mutation engine matches the reference model across seeds', () async {
    for (final seed in List<int>.generate(25, (i) => i + 1)) {
      await runSeed(seed, 150);
    }
  });

  test('a failing seed can be replayed individually', () async {
    // Hook for reproducing a bug found by the randomized run: paste the
    // printed seed here and replay it deterministically before fixing.
    await runSeed(1, 150);
  });
}

class _ControllableNetwork implements Network {
  bool online = true;

  @override
  bool get isOnline => online;
}

/// A queued mutation as the model sees it: the settled handle, the key it
/// writes, the delta it applies, and the optimistic value captured at
/// enqueue time.
class _ModelPending {
  final MutationHandle<int> handle;
  final String key;
  final int delta;
  final int optimisticValue;

  _ModelPending({
    required this.handle,
    required this.key,
    required this.delta,
    required this.optimisticValue,
  });
}

Duration _zeroDelay(int attempt) => Duration.zero;
