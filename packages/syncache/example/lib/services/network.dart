import 'package:flutter/foundation.dart';
import 'package:syncache/syncache.dart';

/// A simulated network status provider that can be toggled for testing.
///
/// In a real Flutter app, you would implement this using the
/// `connectivity_plus` package to detect actual network status.
///
/// Example with connectivity_plus:
/// ```dart
/// class ConnectivityNetwork implements Network {
///   final Connectivity _connectivity = Connectivity();
///   bool _isOnline = true;
///
///   ConnectivityNetwork() {
///     _connectivity.onConnectivityChanged.listen((result) {
///       _isOnline = result != ConnectivityResult.none;
///     });
///   }
///
///   @override
///   bool get isOnline => _isOnline;
/// }
/// ```
class SimulatedNetwork extends ChangeNotifier implements Network {
  bool _isOnline = true;

  @override
  bool get isOnline => _isOnline;

  /// Toggles the network status (online/offline).
  void toggle() {
    _isOnline = !_isOnline;
    notifyListeners();
  }

  /// Sets the network status explicitly.
  void setOnline(bool online) {
    if (_isOnline != online) {
      _isOnline = online;
      notifyListeners();
    }
  }
}

/// Global instance of the simulated network.
final simulatedNetwork = SimulatedNetwork();
