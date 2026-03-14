import 'dart:async';

import 'package:hive/hive.dart';
import 'package:syncache/syncache.dart';

/// A Hive-backed implementation of [TaggableStore].
///
/// [HiveStore] provides persistent storage using Hive, a fast and
/// lightweight key-value database. Data persists across app restarts.
///
/// This implementation requires serialization functions to convert
/// between your data type [T] and JSON, since Hive stores data as
/// maps internally.
///
/// ## Atomicity
///
/// All operations are atomic - each cache entry (including its tags)
/// is stored as a single Hive entry, ensuring consistency even if
/// the app crashes mid-operation.
///
/// ## Thread Safety
///
/// Operations are protected against concurrent close() calls. However,
/// if multiple [HiveStore] instances are opened on the same box name,
/// closing one will affect all instances since they share the underlying
/// Hive box.
///
/// ## Pattern Syntax
///
/// Pattern matching methods (`deleteByPattern`, `getKeysByPattern`) support
/// glob-style patterns:
/// - `*` matches any number of characters (including zero)
/// - `?` matches exactly one character
///
/// Example patterns:
/// - `user:*` matches `user:1`, `user:123`, `user:`
/// - `user:?` matches `user:1`, `user:a` but not `user:12`
///
/// ## Example
///
/// ```dart
/// import 'package:hive/hive.dart';
/// import 'package:syncache/syncache.dart';
/// import 'package:syncache_hive/syncache_hive.dart';
///
/// // Initialize Hive (required once per app)
/// Hive.init('path/to/hive');  // or Hive.initFlutter() for Flutter
///
/// // Open a HiveStore
/// final store = await HiveStore.open<User>(
///   boxName: 'users',
///   fromJson: User.fromJson,
///   toJson: (user) => user.toJson(),
/// );
///
/// // Use with Syncache
/// final cache = Syncache<User>(store: store);
///
/// // Remember to close when done
/// await store.close();
/// ```
///
/// ## Flutter Usage
///
/// For Flutter apps, use `hive_flutter` package and initialize with:
/// ```dart
/// await Hive.initFlutter();
/// ```
///
/// See also:
/// - [TaggableStore] for the tagging interface
/// - [Store] for the base storage interface
class HiveStore<T> implements TaggableStore<T> {
  /// The Hive box storing cache entries (including embedded tags).
  final Box<Map<dynamic, dynamic>> _box;

  /// Converts a JSON map to the value type [T].
  final T Function(Map<String, dynamic> json) fromJson;

  /// Converts a value of type [T] to a JSON map.
  final Map<String, dynamic> Function(T value) toJson;

  /// Tracks whether this store has been closed.
  bool _isClosed = false;

  /// Tracks the number of pending operations to prevent close during operation.
  int _pendingOperations = 0;

  /// Completer that resolves when all pending operations complete.
  /// Used by close() to wait for operations to finish.
  Completer<void>? _pendingCompleter;

  /// Creates a [HiveStore] with the given box and serialization functions.
  ///
  /// **Important:** Hive must be initialized before creating a store.
  /// Call `Hive.init(path)` or `Hive.initFlutter()` first.
  ///
  /// Prefer using [HiveStore.open] which handles box opening automatically.
  HiveStore({
    required Box<Map<dynamic, dynamic>> box,
    required this.fromJson,
    required this.toJson,
  }) : _box = box;

  /// Opens a [HiveStore] with the specified box name.
  ///
  /// **Important:** Hive must be initialized before calling this method.
  /// Call `Hive.init(path)` or `Hive.initFlutter()` first.
  ///
  /// The [fromJson] and [toJson] functions are required to serialize
  /// and deserialize your data type [T].
  ///
  /// Example:
  /// ```dart
  /// final store = await HiveStore.open<User>(
  ///   boxName: 'users',
  ///   fromJson: User.fromJson,
  ///   toJson: (user) => user.toJson(),
  /// );
  /// ```
  static Future<HiveStore<T>> open<T>({
    required String boxName,
    required T Function(Map<String, dynamic> json) fromJson,
    required Map<String, dynamic> Function(T value) toJson,
  }) async {
    final box = await Hive.openBox<Map<dynamic, dynamic>>(boxName);
    return HiveStore<T>(
      box: box,
      fromJson: fromJson,
      toJson: toJson,
    );
  }

  /// Whether this store has been closed.
  ///
  /// After closing, all operations will throw [StateError].
  bool get isClosed => _isClosed;

  /// Whether this store is open and ready for operations.
  ///
  /// Returns `false` if either:
  /// - This store instance has been closed via [close]
  /// - The underlying Hive box is not open (e.g., closed by another instance)
  bool get isOpen => !_isClosed && _box.isOpen;

  /// Checks that the store is not closed and throws [StateError] if it is.
  void _checkNotClosed() {
    if (_isClosed) {
      throw StateError('HiveStore has been closed');
    }
    if (!_box.isOpen) {
      throw StateError('HiveStore box is not open');
    }
  }

  /// Tracks the start of an operation for safe close handling.
  ///
  /// Must be paired with [_endOperation] in a try/finally block.
  void _beginOperation() {
    _checkNotClosed();
    _pendingOperations++;
  }

  /// Marks an operation as complete.
  ///
  /// If this was the last pending operation and close() is waiting,
  /// signals that close can proceed.
  void _endOperation() {
    _pendingOperations--;
    if (_pendingOperations == 0 && _pendingCompleter != null) {
      _pendingCompleter!.complete();
      _pendingCompleter = null;
    }
  }

  /// Executes an async operation with proper tracking for safe close handling.
  Future<R> _withOperation<R>(Future<R> Function() operation) async {
    _beginOperation();
    try {
      return await operation();
    } finally {
      _endOperation();
    }
  }

  /// Closes the cache box.
  ///
  /// This method waits for all pending operations to complete before closing.
  /// Call this method when you're done using the store to release resources.
  /// After closing, all operations will throw [StateError].
  ///
  /// This method is idempotent - calling it multiple times is safe.
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;

    // Wait for pending operations to complete
    if (_pendingOperations > 0) {
      _pendingCompleter = Completer<void>();
      await _pendingCompleter!.future;
    }

    await _box.close();
  }

  @override
  Future<void> write(String key, Stored<T> entry) {
    return _withOperation(() async {
      final data = _serializeEntry(entry, tags: []);
      await _box.put(key, data);
    });
  }

  @override
  Future<void> writeWithTags(
    String key,
    Stored<T> entry,
    List<String> tags,
  ) {
    return _withOperation(() async {
      final data = _serializeEntry(entry, tags: tags);
      await _box.put(key, data);
    });
  }

  @override
  Future<Stored<T>?> read(String key) {
    return _withOperation(() async {
      final data = _box.get(key);
      if (data == null) return null;

      try {
        return _deserializeEntry(data);
      } catch (e) {
        // If deserialization fails, the data is corrupted or schema changed.
        // Delete the corrupted entry and return null (cache miss).
        await _box.delete(key);
        return null;
      }
    });
  }

  @override
  Future<List<String>> getTags(String key) {
    return _withOperation(() async {
      final data = _box.get(key);
      if (data == null) return [];
      return _extractTags(data);
    });
  }

  @override
  Future<void> delete(String key) {
    return _withOperation(() async {
      await _box.delete(key);
    });
  }

  @override
  Future<void> clear() {
    return _withOperation(() async {
      await _box.clear();
    });
  }

  @override
  Future<void> deleteByTag(String tag) {
    return _withOperation(() async {
      final keysToDelete = await _getKeysByTagInternal(tag);
      await _deleteKeys(keysToDelete);
    });
  }

  @override
  Future<void> deleteByTags(List<String> tags, {bool matchAll = false}) {
    return _withOperation(() async {
      if (tags.isEmpty) return;

      final tagSet = tags.toSet();
      final keysToDelete = <String>[];

      // Copy keys to list to avoid concurrent modification issues
      final keys = _box.keys.toList();
      for (final key in keys) {
        final data = _box.get(key);
        if (data == null) continue;

        final entryTags = _extractTags(data).toSet();
        final shouldDelete = matchAll
            ? tagSet.every(entryTags.contains)
            : tagSet.any(entryTags.contains);

        if (shouldDelete) {
          keysToDelete.add(key as String);
        }
      }

      await _deleteKeys(keysToDelete);
    });
  }

  @override
  Future<List<String>> getKeysByTag(String tag) {
    return _withOperation(() => _getKeysByTagInternal(tag));
  }

  /// Internal implementation of getKeysByTag without operation tracking.
  /// Used by deleteByTag to avoid nested operation tracking.
  Future<List<String>> _getKeysByTagInternal(String tag) async {
    final keys = <String>[];
    // Copy keys to list to avoid concurrent modification issues
    final boxKeys = _box.keys.toList();
    for (final key in boxKeys) {
      final data = _box.get(key);
      if (data == null) continue;

      final entryTags = _extractTags(data);
      if (entryTags.contains(tag)) {
        keys.add(key as String);
      }
    }
    return keys;
  }

  @override
  Future<void> deleteByPattern(String pattern) {
    return _withOperation(() async {
      final regex = _patternToRegex(pattern);
      // Copy keys to list to avoid concurrent modification issues
      final keysToDelete = _box.keys
          .toList()
          .where((key) => regex.hasMatch(key as String))
          .cast<String>()
          .toList();
      await _deleteKeys(keysToDelete);
    });
  }

  @override
  Future<List<String>> getKeysByPattern(String pattern) {
    return _withOperation(() async {
      final regex = _patternToRegex(pattern);
      // Copy keys to list to avoid concurrent modification issues
      return _box.keys
          .toList()
          .where((key) => regex.hasMatch(key as String))
          .cast<String>()
          .toList();
    });
  }

  // ============================================================
  // Private Helpers
  // ============================================================

  /// Deletes multiple keys efficiently using batch delete.
  Future<void> _deleteKeys(List<String> keys) async {
    if (keys.isEmpty) return;
    await _box.deleteAll(keys);
  }

  /// Extracts tags from a serialized entry.
  ///
  /// Returns an empty list if:
  /// - The 'tags' field is missing or null
  /// - The 'tags' field contains invalid data
  List<String> _extractTags(Map<dynamic, dynamic> data) {
    final tags = data['tags'];
    if (tags == null) return [];
    if (tags is! List) return [];

    try {
      return tags.cast<String>().toList();
    } catch (e) {
      // If cast fails (non-string elements), return empty list
      return [];
    }
  }

  // ============================================================
  // Serialization Helpers
  // ============================================================

  /// Serializes a [Stored] entry with its tags for storage in Hive.
  Map<String, dynamic> _serializeEntry(
    Stored<T> entry, {
    required List<String> tags,
  }) {
    return {
      'value': toJson(entry.value),
      'meta': _serializeMetadata(entry.meta),
      'tags': tags,
    };
  }

  /// Deserializes a Hive map back into a [Stored] entry.
  Stored<T> _deserializeEntry(Map<dynamic, dynamic> data) {
    final valueJson = _castMap(data['value'] as Map<dynamic, dynamic>);
    final metaJson = _castMap(data['meta'] as Map<dynamic, dynamic>);

    return Stored<T>(
      value: fromJson(valueJson),
      meta: _deserializeMetadata(metaJson),
    );
  }

  /// Serializes [Metadata] to a JSON-compatible map.
  Map<String, dynamic> _serializeMetadata(Metadata meta) {
    return {
      'version': meta.version,
      'storedAt': meta.storedAt.toIso8601String(),
      if (meta.ttl != null) 'ttlMs': meta.ttl!.inMilliseconds,
      if (meta.etag != null) 'etag': meta.etag,
      if (meta.lastModified != null)
        'lastModified': meta.lastModified!.toIso8601String(),
    };
  }

  /// Deserializes a JSON map back into [Metadata].
  Metadata _deserializeMetadata(Map<String, dynamic> json) {
    return Metadata(
      version: json['version'] as int,
      storedAt: DateTime.parse(json['storedAt'] as String),
      ttl: json['ttlMs'] != null
          ? Duration(milliseconds: json['ttlMs'] as int)
          : null,
      etag: json['etag'] as String?,
      lastModified: json['lastModified'] != null
          ? DateTime.parse(json['lastModified'] as String)
          : null,
    );
  }

  /// Recursively casts a Hive map to a proper Dart Map<String, dynamic>.
  ///
  /// Hive stores maps as `Map<dynamic, dynamic>`, but JSON serialization
  /// typically expects `Map<String, dynamic>`. This method performs the
  /// recursive conversion.
  Map<String, dynamic> _castMap(Map<dynamic, dynamic> map) {
    return map.map((key, value) {
      final castKey = key as String;
      if (value is Map<dynamic, dynamic>) {
        return MapEntry(castKey, _castMap(value));
      } else if (value is List) {
        return MapEntry(castKey, _castList(value));
      }
      return MapEntry(castKey, value);
    });
  }

  /// Recursively casts a Hive list to handle nested maps.
  List<dynamic> _castList(List<dynamic> list) {
    return list.map((item) {
      if (item is Map<dynamic, dynamic>) {
        return _castMap(item);
      } else if (item is List) {
        return _castList(item);
      }
      return item;
    }).toList();
  }

  /// Converts a glob pattern to a RegExp.
  ///
  /// Supported wildcards:
  /// - `*` matches any sequence of characters (including empty)
  /// - `?` matches exactly one character
  ///
  /// All other regex metacharacters are escaped.
  RegExp _patternToRegex(String pattern) {
    final escaped = pattern
        .replaceAll(r'\', r'\\')
        .replaceAll('.', r'\.')
        .replaceAll('+', r'\+')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)')
        .replaceAll('[', r'\[')
        .replaceAll(']', r'\]')
        .replaceAll('{', r'\{')
        .replaceAll('}', r'\}')
        .replaceAll('^', r'\^')
        .replaceAll(r'$', r'\$')
        .replaceAll('|', r'\|')
        .replaceAll('*', '.*')
        .replaceAll('?', '.');
    return RegExp('^$escaped\$');
  }
}
