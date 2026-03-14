/// Caching policies that determine how [Syncache.get] retrieves data.
///
/// Each policy defines a different strategy for balancing between
/// cached data and fresh network fetches.
enum Policy {
  /// Returns cached data if available and not expired; fetches otherwise.
  ///
  /// This is the default policy and provides the best offline-first
  /// experience. The cache is checked first, and network requests are
  /// only made when necessary.
  ///
  /// Behavior:
  /// 1. If valid (non-expired) cache exists, return it immediately
  /// 2. If online, attempt to fetch fresh data
  /// 3. If fetch fails but stale cache exists, return stale data
  /// 4. If no cache and offline/fetch fails, throw [CacheMissException]
  offlineFirst,

  /// Returns only cached data; never makes network requests.
  ///
  /// Use this policy when you want to ensure no network activity,
  /// such as displaying data that was pre-fetched earlier.
  ///
  /// Throws [CacheMissException] if no cached data exists.
  cacheOnly,

  /// Always fetches from network; ignores cached data.
  ///
  /// Use this policy when you need guaranteed fresh data and
  /// network availability is certain.
  ///
  /// Throws if the network request fails.
  networkOnly,

  /// Fetches from network if online; falls back to cache if offline.
  ///
  /// Similar to [offlineFirst] but always prefers fresh data when
  /// online, regardless of cache validity.
  ///
  /// Behavior:
  /// 1. If online, fetch from network
  /// 2. If offline, return cached data
  /// 3. If offline with no cache, throw [CacheMissException]
  refresh,

  /// Returns cached data immediately; refreshes in background if expired.
  ///
  /// This policy provides the fastest perceived performance by always
  /// returning cached data first, then updating the cache asynchronously.
  /// Subscribers via [Syncache.watch] will receive the updated value.
  ///
  /// Behavior:
  /// 1. If cache exists, return it immediately
  /// 2. If cache is expired and online, trigger background refresh
  /// 3. If no cache exists and online, fetch and return
  /// 4. If no cache and offline, throw [CacheMissException]
  staleWhileRefresh,
}
