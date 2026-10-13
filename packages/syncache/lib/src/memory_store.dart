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
/// ## Bounded capacity (LRU)
///
/// Set [maxLength] (or pass it to the constructor) to make the store evict
/// entries when it grows past the limit: the **least-recently-used** entry
/// is evicted on every write that exceeds [maxLength]. Reads and writes
/// both refresh an entry's recency, so entries in active use are kept while
/// cold ones make room. Tag mappings of evicted entries are removed
/// together with them, and each eviction is reported through [onEvict] —
/// which [Syncache] wires to its observers as `SyncacheObserver.onEvict`.
///
/// ```dart
/// final store = MemoryStore<User>(maxLength: 500);
/// ```
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
class MemoryStore<T>
    implements TaggableStore<T>, BoundedStore<T>, IterableStore<T> {
  /// Access-ordered storage: Dart's default [Map] is a [LinkedHashMap], so
  /// re-inserting a key on access moves it to the most-recently-used end
  /// and the first key is always the least-recently-used candidate.
  final Map<String, Stored<T>> _cache = {};
  final Map<String, Set<String>> _tags = {};

  int? _maxLength;

  @override
  void Function(String key)? onEvict;

  /// Creates an in-memory store.
  ///
  /// Pass [maxLength] to bound the store with least-recently-used eviction;
  /// the default `null` keeps it unbounded. [onEvict] is invoked after each
  /// eviction (it is assigned automatically when the store is used with a
  /// [Syncache]).
  MemoryStore({int? maxLength, this.onEvict}) {
    _maxLength = maxLength;
  }

  @override
  int? get maxLength => _maxLength;

  @override
  set maxLength(int? value) {
    _maxLength = value;
    if (value != null) _evictOverflow();
  }

  @override
  Future<int> get length async => _cache.length;

  @override
  Future<List<String>> keys() async => _cache.keys.toList();

  @override
  Future<void> write(String key, Stored<T> entry) async {
    // Re-insert so an overwrite refreshes the entry's LRU recency.
    _cache.remove(key);
    _cache[key] = entry;
    _evictOverflow();
  }

  @override
  Future<void> writeWithTags(
      String key, Stored<T> entry, List<String> tags) async {
    _cache.remove(key);
    _cache[key] = entry;
    _tags[key] = tags.toSet();
    _evictOverflow();
  }

  @override
  Future<Stored<T>?> read(String key) async {
    final entry = _cache[key];
    if (entry != null) {
      // Touch: re-insert to move the entry to the most-recently-used end.
      // Allocation-light — the same entry object is reused.
      _cache.remove(key);
      _cache[key] = entry;
    }
    return entry;
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
    final keysToDelete = _cache.keys.where(regex.hasMatch).toList();
    for (final key in keysToDelete) {
      _cache.remove(key);
      _tags.remove(key);
    }
  }

  @override
  Future<List<String>> getKeysByPattern(String pattern) async {
    final regex = _patternToRegex(pattern);
    return _cache.keys.where(regex.hasMatch).toList();
  }

  /// Evicts least-recently-used entries until the store fits [maxLength].
  ///
  /// Tag mappings are removed together with each evicted entry so tag
  /// operations never surface ghost keys, and [onEvict] is invoked per
  /// evicted key.
  void _evictOverflow() {
    final limit = _maxLength;
    if (limit == null) return;
    while (_cache.length > limit) {
      final lruKey = _cache.keys.first;
      _cache.remove(lruKey);
      _tags.remove(lruKey);
      onEvict?.call(lruKey);
    }
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
