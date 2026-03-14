import 'exceptions.dart';

/// A token that can be used to cancel asynchronous operations.
///
/// Create a [CancellationToken] and pass it to [Syncache.get] to enable
/// cancellation of in-flight requests. Call [cancel] to signal that the
/// operation should be aborted.
///
/// ## Example
///
/// ```dart
/// final token = CancellationToken();
///
/// // Start a cancellable request
/// final future = cache.get(
///   key: 'data',
///   fetch: (request) async {
///     final response = await http.get(url);
///     return parseResponse(response);
///   },
///   cancel: token,
/// );
///
/// // Later, if user navigates away:
/// token.cancel();
///
/// // The future will complete with CancelledException
/// ```
///
/// ## Checking Cancellation in Fetchers
///
/// For long-running fetchers, you can check the token periodically:
///
/// ```dart
/// fetch: (request) async {
///   final items = <Item>[];
///   for (final id in ids) {
///     token.throwIfCancelled(); // Check before each operation
///     items.add(await fetchItem(id));
///   }
///   return items;
/// }
/// ```
///
/// ## Listening for Cancellation
///
/// Use [onCancel] to register cleanup callbacks:
///
/// ```dart
/// token.onCancel(() {
///   subscription.cancel();
///   controller.close();
/// });
/// ```
class CancellationToken {
  bool _isCancelled = false;
  final List<void Function()> _listeners = [];

  /// Whether this token has been cancelled.
  ///
  /// Once cancelled, this remains `true` permanently.
  bool get isCancelled => _isCancelled;

  /// Cancels the operation associated with this token.
  ///
  /// This sets [isCancelled] to `true` and notifies all registered
  /// listeners. Calling [cancel] multiple times has no additional effect.
  ///
  /// Example:
  /// ```dart
  /// final token = CancellationToken();
  /// // ... start operation with token ...
  /// token.cancel(); // Signal cancellation
  /// ```
  void cancel() {
    if (_isCancelled) return;

    _isCancelled = true;
    for (final listener in _listeners) {
      try {
        listener();
      } catch (_) {
        // Don't let listener errors break cancellation
      }
    }
    _listeners.clear();
  }

  /// Registers a callback to be invoked when [cancel] is called.
  ///
  /// If the token is already cancelled, the callback is invoked immediately.
  /// Otherwise, it will be called when [cancel] is invoked.
  ///
  /// Use this to clean up resources when an operation is cancelled:
  ///
  /// ```dart
  /// token.onCancel(() {
  ///   httpClient.close();
  ///   streamSubscription.cancel();
  /// });
  /// ```
  void onCancel(void Function() callback) {
    if (_isCancelled) {
      try {
        callback();
      } catch (_) {
        // Don't let callback errors propagate
      }
    } else {
      _listeners.add(callback);
    }
  }

  /// Removes a previously registered cancellation callback.
  ///
  /// Returns `true` if the callback was found and removed.
  bool removeOnCancel(void Function() callback) {
    return _listeners.remove(callback);
  }

  /// Throws [CancelledException] if this token has been cancelled.
  ///
  /// Use this in long-running operations to check for cancellation:
  ///
  /// ```dart
  /// for (final item in items) {
  ///   token.throwIfCancelled();
  ///   await processItem(item);
  /// }
  /// ```
  void throwIfCancelled() {
    if (_isCancelled) {
      throw CancelledException();
    }
  }

  @override
  String toString() {
    return 'CancellationToken(isCancelled: $_isCancelled)';
  }
}

/// Exception thrown when an operation is cancelled via [CancellationToken].
///
/// This exception is thrown by:
/// - [CancellationToken.throwIfCancelled] when the token is cancelled
/// - [Syncache.get] when the operation is cancelled before completion
///
/// ## Handling Cancellation
///
/// ```dart
/// try {
///   final data = await cache.get(
///     key: 'data',
///     fetch: fetchData,
///     cancel: token,
///   );
/// } on CancelledException {
///   // Operation was cancelled, handle gracefully
///   print('Request cancelled');
/// }
/// ```
class CancelledException extends SyncacheException {
  /// Creates a cancellation exception with an optional [message].
  const CancelledException([String message = 'Operation was cancelled'])
      : super(message);

  @override
  String toString() => 'CancelledException: $message';
}
