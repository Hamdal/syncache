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

/// A [Network] that also reports connectivity *changes*.
///
/// Implement this (in addition to [Network]) to let [Syncache] react to
/// the device coming back online: pending mutations are automatically
/// flushed as soon as [onConnectivityChanged] emits `true` — without any
/// new `mutate()` call from application code.
///
/// `syncache_flutter`'s `FlutterNetwork` implements this interface, so
/// using it as the [Syncache] network is enough to enable reconnect
/// flushing.
///
/// Example:
/// ```dart
/// class MyReactiveNetwork implements ReactiveNetwork {
///   @override
///   bool get isOnline => _online;
///
///   @override
///   Stream<bool> get onConnectivityChanged => _changes;
/// }
///
/// final cache = Syncache<User>(
///   store: MemoryStore<User>(),
///   network: MyReactiveNetwork(), // offline mutations flush on reconnect
/// );
/// ```
abstract class ReactiveNetwork implements Network {
  /// Emits connectivity transitions.
  ///
  /// `true` = back online, `false` = connection lost. Implementations
  /// should only emit on *changes*, not repeatedly for the same state.
  Stream<bool> get onConnectivityChanged;
}
