import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:syncache/syncache.dart';

/// A [Network] implementation that uses `connectivity_plus` to detect
/// actual network connectivity status.
///
/// This provides real connectivity detection for Flutter apps, unlike
/// [AlwaysOnline] which always reports online status.
///
/// ## Usage
///
/// ```dart
/// final network = FlutterNetwork();
/// await network.initialize();
///
/// final cache = Syncache<User>(
///   store: MemoryStore<User>(),
///   network: network,
/// );
///
/// // Listen to connectivity changes
/// network.onConnectivityChanged.listen((isOnline) {
///   if (isOnline) {
///     print('Back online!');
///   }
/// });
///
/// // Don't forget to dispose when done
/// network.dispose();
/// ```
///
/// ## Web Platform Note
///
/// On web, `connectivity_plus` uses `navigator.onLine` which may not always
/// be reliable. Consider providing a custom [Network] implementation for
/// web-specific needs.
class FlutterNetwork implements Network {
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _isOnline = true;
  bool _isDisposed = false;
  Completer<void>? _initCompleter;
  final StreamController<bool> _connectivityController =
      StreamController<bool>.broadcast();

  /// Duration to debounce rapid connectivity changes.
  ///
  /// This prevents multiple rapid events from triggering multiple refetches.
  final Duration debounceDuration;

  Timer? _debounceTimer;

  /// The last value that was emitted to listeners.
  /// Used to prevent duplicate emissions and fix race conditions.
  bool? _lastEmittedValue;

  /// Creates a [FlutterNetwork] instance.
  ///
  /// Optionally provide a custom [Connectivity] instance for testing.
  /// The [debounceDuration] controls how long to wait before emitting
  /// connectivity change events (defaults to 500ms).
  FlutterNetwork({
    Connectivity? connectivity,
    this.debounceDuration = const Duration(milliseconds: 500),
  }) : _connectivity = connectivity ?? Connectivity();

  /// Initialize the network monitor.
  ///
  /// This must be called before using [isOnline] to get accurate results.
  /// Call this during app startup, typically before creating cache instances.
  ///
  /// This method is safe to call multiple times - subsequent calls will
  /// wait for the first initialization to complete.
  ///
  /// ```dart
  /// void main() async {
  ///   WidgetsFlutterBinding.ensureInitialized();
  ///
  ///   final network = FlutterNetwork();
  ///   await network.initialize();
  ///
  ///   runApp(MyApp(network: network));
  /// }
  /// ```
  Future<void> initialize() async {
    if (_isDisposed) {
      throw StateError('Cannot initialize a disposed FlutterNetwork');
    }

    // Already initialized
    if (_initCompleter?.isCompleted ?? false) return;

    // Initialization in progress - wait for it to complete
    if (_initCompleter != null) {
      await _initCompleter!.future;
      return;
    }

    // Start initialization
    final completer = Completer<void>();
    _initCompleter = completer;
    try {
      final results = await _connectivity.checkConnectivity();
      _isOnline = _isConnected(results);
      // Initialize last emitted value to match the initial state
      // This prevents emitting when the state hasn't actually changed
      _lastEmittedValue = _isOnline;

      _subscription = _connectivity.onConnectivityChanged.listen(_handleChange);
      completer.complete();
    } catch (e) {
      // Reset completer to allow retry on next call
      _initCompleter = null;
      rethrow;
    }
  }

  void _handleChange(List<ConnectivityResult> results) {
    if (_isDisposed) return;

    final newOnlineStatus = _isConnected(results);
    _isOnline = newOnlineStatus;

    // Debounce to avoid rapid state changes
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDuration, () {
      if (_isDisposed || _connectivityController.isClosed) return;

      // Only emit if the current state differs from the last emitted value
      if (_lastEmittedValue != _isOnline) {
        _lastEmittedValue = _isOnline;
        _connectivityController.add(_isOnline);
      }
    });
  }

  bool _isConnected(List<ConnectivityResult> results) {
    // Connected if any result indicates connectivity
    return results.any(
      (r) => r != ConnectivityResult.none,
    );
  }

  @override
  bool get isOnline => _isOnline;

  /// Whether [initialize] has been called and completed successfully.
  bool get isInitialized => _initCompleter?.isCompleted ?? false;

  /// Whether [dispose] has been called.
  bool get isDisposed => _isDisposed;

  /// Stream of connectivity changes.
  ///
  /// Emits `true` when connectivity is restored and `false` when lost.
  /// This stream is debounced to avoid rapid state changes.
  ///
  /// ```dart
  /// network.onConnectivityChanged.listen((isOnline) {
  ///   if (isOnline) {
  ///     // Trigger cache refetch
  ///   }
  /// });
  /// ```
  Stream<bool> get onConnectivityChanged => _connectivityController.stream;

  /// Dispose of resources.
  ///
  /// Call this when the network monitor is no longer needed.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _debounceTimer?.cancel();
    _subscription?.cancel();
    _connectivityController.close();
  }
}
