/// An offline-first cache and sync engine for Dart applications.
///
/// This library exports the complete public API: [Syncache] (the engine),
/// [Store] implementations ([MemoryStore], [SharedMemoryStore]), caching
/// [Policy] variants, reactive streams, optimistic [Mutation] with a
/// durable [MutationOutbox], typed entries ([SyncacheEntry]), stats
/// ([SyncacheStats]), and debug tooling ([SyncacheDebug]).
///
/// Flutter integration lives in `syncache_flutter`; persistent backends in
/// `syncache_hive` and `syncache_drift`.
library syncache;

export 'src/cache_result.dart' show CacheResult, CacheResultMeta;
export 'src/cancellation.dart' show CancellationToken, CancelledException;
export 'src/conflict_resolver.dart'
    show ConflictResolver, serverWins, clientWins;
export 'src/fetch_engine.dart' show CacheMissForConditionalException;
export 'src/fetcher.dart'
    show Fetcher, SyncacheRequest, FetchResult, ConditionalFetcher;
export 'src/memory_store.dart' show MemoryStore;
export 'src/shared_memory_store.dart' show SharedMemoryStore;
export 'src/memory_mutation_outbox.dart' show MemoryMutationOutbox;
export 'src/mutation_outbox.dart' show MutationOutbox;
export 'src/pending_mutation_record.dart' show PendingMutationRecord;
export 'src/mutation.dart' show Mutation;
export 'src/mutation_handle.dart'
    show
        MutationHandle,
        MutationOutcome,
        MutationSuccess,
        MutationResolved,
        MutationFailure,
        MutationDiscarded;
export 'src/network.dart' show Network, ReactiveNetwork, AlwaysOnline;
export 'src/observer.dart' show SyncacheObserver;
export 'src/paginated_cache.dart'
    show PaginatedCache, PageResult, PagedViewState;
export 'src/logging_observer.dart' show LoggingObserver;
export 'src/pending_mutation_info.dart'
    show PendingMutationInfo, PendingMutationStatus;
export 'src/policy.dart' show Policy;
export 'src/prefetch.dart'
    show
        PrefetchRequest,
        PrefetchResult,
        PrefetchNode,
        PrefetchGraphOptions,
        PrefetchGraphResult,
        PrefetchNodeResult,
        PrefetchNodeStatus;
export 'src/query_key.dart' show QueryKey, QueryKeyStringExtension;
export 'src/retry.dart' show RetryConfig, MutationRetryConfig;
export 'src/scoped_syncache.dart' show ScopedSyncache;
export 'src/syncache_entry.dart' show SyncacheEntry;
export 'src/syncache_stats.dart' show SyncacheStats, SyncacheCounter;
export 'src/debug.dart' show SyncacheDebug;
export 'src/store.dart' show Store, TaggableStore, BoundedStore, IterableStore;
export 'src/stored.dart' show Stored;
export 'src/syncache.dart' show Syncache;
export 'src/exceptions.dart'
    show SyncacheException, CacheMissException, SyncacheConflictException;
export 'src/list_operation.dart'
    show
        ListOperation,
        AppendOperation,
        PrependOperation,
        InsertOperation,
        UpdateWhereOperation,
        RemoveWhereOperation;
export 'src/syncache_list_extension.dart' show SyncacheListExtension;

export 'src/metadata.dart' show Metadata;
