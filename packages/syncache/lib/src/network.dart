/// Abstract interface for checking network connectivity status.
///
/// Implement this interface to provide custom network detection logic
/// to [Syncache]. This allows the cache to make intelligent decisions
/// about when to attempt network fetches versus serving stale data.
///
/// Example:
/// ```dart
/// class ConnectivityNetwork implements Network {
///   final Connectivity _connectivity;
///
///   ConnectivityNetwork(this._connectivity);
///
///   @override
///   bool get isOnline {
///     // Check actual network status
///     return _connectivity.hasConnection;
///   }
/// }
///
/// final cache = Syncache<User>(
///   store: MemoryStore<User>(),
///   network: ConnectivityNetwork(connectivity),
/// );
/// ```
///
/// See also:
/// - [AlwaysOnline] for a default implementation that assumes connectivity
abstract class Network {
  /// Whether the device currently has network connectivity.
  ///
  /// Returns `true` if network requests should be attempted,
  /// `false` if the cache should operate in offline mode.
  bool get isOnline;
}

/// A [Network] implementation that always reports online status.
///
/// This is the default network implementation used by [Syncache] when
/// no custom [Network] is provided. Use this when you don't need
/// offline detection, or when you want to handle network errors
/// through fetch failures instead.
///
/// Example:
/// ```dart
/// final cache = Syncache<User>(
///   store: MemoryStore<User>(),
///   network: const AlwaysOnline(), // Default behavior
/// );
/// ```
class AlwaysOnline implements Network {
  /// Creates an [AlwaysOnline] instance.
  const AlwaysOnline();

  @override
  bool get isOnline => true;
}
