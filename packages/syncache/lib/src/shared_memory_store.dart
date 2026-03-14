import 'package:syncache/src/exceptions.dart';

import 'store.dart';
import 'stored.dart';

/// A [Store] that shares data across instances with the same [namespace].
///
/// Supports tag-based operations via [TaggableStore].
///
/// **Important:** All stores sharing a namespace must use the same type.
///
/// Example:
/// ```dart
/// final store1 = SharedMemoryStore<User>(namespace: 'users');
/// final store2 = SharedMemoryStore<User>(namespace: 'users');
///
/// await store1.write('key', storedValue);
/// final value = await store2.read('key'); // Same value
/// ```
class SharedMemoryStore<T> implements TaggableStore<T> {
  static final Map<String, Map<String, Object>> _registry = {};
  static final Map<String, Map<String, Set<String>>> _tagRegistry = {};
  static final Map<String, Type> _typeRegistry = {};

  final String namespace;

  /// Throws [SyncacheException] if namespace exists with different type.
  SharedMemoryStore({this.namespace = 'default'}) {
    _validateType();
  }

  void _validateType() {
    final existingType = _typeRegistry[namespace];
    if (existingType != null && existingType != T) {
      throw SyncacheException(
        'Type mismatch for namespace "$namespace": '
        'expected $existingType but got $T. '
        'All SharedMemoryStore instances with the same namespace must use the same type.',
      );
    }
    _typeRegistry[namespace] = T;
  }

  Map<String, Stored<T>> get _cache {
    _registry[namespace] ??= <String, Stored<T>>{};
    return _registry[namespace]! as Map<String, Stored<T>>;
  }

  Map<String, Set<String>> get _tags {
    _tagRegistry[namespace] ??= <String, Set<String>>{};
    return _tagRegistry[namespace]!;
  }

  @override
  Future<void> write(String key, Stored<T> entry) async => _cache[key] = entry;

  @override
  Future<void> writeWithTags(
      String key, Stored<T> entry, List<String> tags) async {
    _cache[key] = entry;
    _tags[key] = tags.toSet();
  }

  @override
  Future<Stored<T>?> read(String key) async => _cache[key];

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

  static void clearNamespace(String namespace) {
    _registry.remove(namespace);
    _tagRegistry.remove(namespace);
    _typeRegistry.remove(namespace);
  }

  /// Clears all shared storage across all namespaces.
  static void clearAll() {
    _registry.clear();
    _tagRegistry.clear();
    _typeRegistry.clear();
  }

  static List<String> get namespaces => _registry.keys.toList();
  static bool hasNamespace(String namespace) =>
      _registry.containsKey(namespace);
}
