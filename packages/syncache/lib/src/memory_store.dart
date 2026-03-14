import 'store.dart';
import 'stored.dart';

/// An in-memory implementation of [Store] that supports tagging.
///
/// [MemoryStore] keeps all cached data in a local [Map], making it fast
/// but volatile. Data is lost when the store instance is garbage collected
/// or the application terminates.
///
/// This implementation also supports tag-based operations through
/// [TaggableStore], enabling grouped cache invalidation.
///
/// For shared storage across multiple [Syncache] instances, consider using
/// [SharedMemoryStore] instead.
///
/// Example:
/// ```dart
/// final cache = Syncache<User>(
///   store: MemoryStore<User>(),
/// );
/// ```
///
/// See also:
/// - [SharedMemoryStore] for namespace-based shared storage
/// - [Store] for the abstract storage interface
/// - [TaggableStore] for tag-based operations
class MemoryStore<T> implements TaggableStore<T> {
  final Map<String, Stored<T>> _cache = {};
  final Map<String, Set<String>> _tags = {};

  @override
  Future<void> write(String key, Stored<T> entry) async {
    _cache[key] = entry;
  }

  @override
  Future<void> writeWithTags(
      String key, Stored<T> entry, List<String> tags) async {
    _cache[key] = entry;
    _tags[key] = tags.toSet();
  }

  @override
  Future<Stored<T>?> read(String key) async {
    return _cache[key];
  }

  @override
  Future<List<String>> getTags(String key) async {
    return _tags[key]?.toList() ?? [];
  }

  @override
  Future<void> delete(String key) async {
    _cache.remove(key);
    _tags.remove(key);
  }

  @override
  Future<void> clear() async {
    _cache.clear();
    _tags.clear();
  }

  @override
  Future<void> deleteByTag(String tag) async {
    final keysToDelete = <String>[];
    for (final entry in _tags.entries) {
      if (entry.value.contains(tag)) {
        keysToDelete.add(entry.key);
      }
    }
    for (final key in keysToDelete) {
      _cache.remove(key);
      _tags.remove(key);
    }
  }

  @override
  Future<void> deleteByTags(List<String> tags, {bool matchAll = false}) async {
    if (tags.isEmpty) return;

    final tagSet = tags.toSet();
    final keysToDelete = <String>[];

    for (final entry in _tags.entries) {
      final entryTags = entry.value;
      final shouldDelete = matchAll
          ? tagSet.every(entryTags.contains)
          : tagSet.any(entryTags.contains);
      if (shouldDelete) {
        keysToDelete.add(entry.key);
      }
    }

    for (final key in keysToDelete) {
      _cache.remove(key);
      _tags.remove(key);
    }
  }

  @override
  Future<List<String>> getKeysByTag(String tag) async {
    final keys = <String>[];
    for (final entry in _tags.entries) {
      if (entry.value.contains(tag)) {
        keys.add(entry.key);
      }
    }
    return keys;
  }

  @override
  Future<void> deleteByPattern(String pattern) async {
    final regex = _patternToRegex(pattern);
    final keysToDelete =
        _cache.keys.where((key) => regex.hasMatch(key)).toList();
    for (final key in keysToDelete) {
      _cache.remove(key);
      _tags.remove(key);
    }
  }

  @override
  Future<List<String>> getKeysByPattern(String pattern) async {
    final regex = _patternToRegex(pattern);
    return _cache.keys.where((key) => regex.hasMatch(key)).toList();
  }

  /// Converts a glob pattern to a RegExp.
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
