import 'package:flutter/foundation.dart';
import 'package:syncache/syncache.dart';

/// A `LogFunction` for [LoggingObserver] that routes output through
/// Flutter's `debugPrint`.
///
/// Use it in Flutter apps instead of the observer's default `print` so log
/// output is batched by the framework and never throttled by the platform
/// logger on hot caches:
///
/// ```dart
/// final cache = Syncache<User>(
///   store: MemoryStore<User>(),
///   observers: [
///     LoggingObserver(log: syncacheDebugLog, verbose: false),
///   ],
/// );
/// ```
void syncacheDebugLog(String message) => debugPrint(message);
