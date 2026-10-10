import 'list_operation.dart';
import 'mutation.dart';
import 'syncache.dart';

/// Extension providing list-specific mutation helpers for [Syncache<List<T>>].
///
/// These helpers reduce boilerplate for common list operations like adding,
/// updating, and removing items from cached lists.
///
/// Example:
/// ```dart
/// final cache = Syncache<List<Event>>(store: store);
///
/// // Add event to the list
/// await cache.mutateList(
///   key: 'events',
///   operation: ListOperation.append(newEvent),
///   send: () => api.createEvent(newEvent),
/// );
///
/// // Update an event
/// await cache.mutateList(
///   key: 'events',
///   operation: ListOperation.updateWhere(
///     (e) => e.id == eventId,
///     (e) => e.copyWith(title: 'New Title'),
///   ),
///   send: () => api.updateEvent(eventId, title: 'New Title'),
/// );
///
/// // Remove an event
/// await cache.mutateList(
///   key: 'events',
///   operation: ListOperation.removeWhere((e) => e.id == eventId),
///   send: () => api.deleteEvent(eventId),
/// );
/// ```
extension SyncacheListExtension<T> on Syncache<List<T>> {
  /// Mutates a cached list with a specific operation.
  ///
  /// The [operation] is applied optimistically to the cached list, and [send]
  /// is called asynchronously to persist the change to the server.
  ///
  /// Parameters:
  /// - [key]: The cache key for the list.
  /// - [operation]: The list operation to apply (append, prepend, insert,
  ///   updateWhere, removeWhere).
  /// - [send]: An async function that persists the change to the server.
  ///   It receives no parameters; use closures to capture necessary context.
  /// - [invalidates]: Optional list of cache keys (supports glob patterns)
  ///   to invalidate after successful sync.
  /// - [invalidateTags]: Optional list of tags to invalidate after
  ///   successful sync.
  ///
  /// Example:
  /// ```dart
  /// await cache.mutateList(
  ///   key: 'events',
  ///   operation: ListOperation.append(newEvent),
  ///   send: () => api.createEvent(newEvent),
  /// );
  /// ```
  ///
  /// Throws [CacheMissException] if no cached value exists for [key].
  Future<void> mutateList({
    required String key,
    required ListOperation<T> operation,
    required Future<void> Function() send,
    List<String>? invalidates,
    List<String>? invalidateTags,
  }) async {
    await mutate(
      key: key,
      mutation: Mutation<List<T>>(
        apply: operation.apply,
        send: (list) async {
          await send();
          return list;
        },
      ),
      invalidates: invalidates,
      invalidateTags: invalidateTags,
    );
  }

  /// Mutates a cached list with server response updating the item.
  ///
  /// Similar to [mutateList], but [send] returns the server-confirmed item.
  /// After successful sync, the item in the list is updated with the server
  /// response. This is useful when the server assigns IDs or modifies the item.
  ///
  /// Parameters:
  /// - [key]: The cache key for the list.
  /// - [operation]: The list operation to apply. For operations that add items
  ///   (append, prepend, insert), the item must have an [idSelector] match.
  /// - [send]: An async function that persists the change and returns the
  ///   server-confirmed item. The item from [operation] is passed as argument.
  /// - [idSelector]: A function that extracts a unique identifier from an item.
  ///   Used to find and update the optimistic item with the server response.
  /// - [invalidates]: Optional list of cache keys (supports glob patterns)
  ///   to invalidate after successful sync.
  /// - [invalidateTags]: Optional list of tags to invalidate after
  ///   successful sync.
  ///
  /// Example:
  /// ```dart
  /// // Server assigns an ID to the new event
  /// await cache.mutateListItem(
  ///   key: 'events',
  ///   operation: ListOperation.append(Event(id: 'temp', title: 'New Event')),
  ///   send: (event) async {
  ///     final response = await api.createEvent(event);
  ///     return Event.fromJson(response);
  ///   },
  ///   idSelector: (e) => e.id,
  /// );
  /// ```
  ///
  /// For [UpdateWhereOperation], the [send] function receives the first
  /// matching updated item (the post-apply item that carries the optimistic
  /// changes). The server response updates all items that match the
  /// [idSelector]. If no item matches the predicate, [send] is not called and
  /// the cached list is left unchanged.
  ///
  /// For [RemoveWhereOperation], [send] is called once per removed item
  /// (deduplicated by [idSelector], so a repeated id results in a single
  /// server call) and its return value is ignored.
  ///
  /// Throws [CacheMissException] if no cached value exists for [key].
  /// Throws [StateError] if [send] is called but no item is available
  /// from the operation.
  Future<void> mutateListItem<Id>({
    required String key,
    required ListOperation<T> operation,
    required Future<T> Function(T item) send,
    required Id Function(T item) idSelector,
    List<String>? invalidates,
    List<String>? invalidateTags,
  }) async {
    // Capture the pre-apply list so operations without an explicit item
    // (updateWhere, removeWhere) can locate the affected items, even when the
    // predicate no longer matches after the optimistic update.
    final cached = await store.read(key);
    final originalList = cached?.value ?? <T>[];

    await mutate(
      key: key,
      mutation: Mutation<List<T>>(
        apply: operation.apply,
        send: (list) async {
          if (operation is RemoveWhereOperation<T>) {
            // Send one server call per removed item, deduplicated by id so
            // that a repeated id in the list is not deleted twice.
            final sentIds = <Id>{};
            for (final item in originalList) {
              if (!operation.predicate(item)) continue;
              final id = idSelector(item);
              if (!sentIds.add(id)) continue;
              await send(item);
            }
            return list;
          }

          if (operation is UpdateWhereOperation<T>) {
            // Find the first pre-update item matching the predicate, then
            // send its post-apply version (which carries the optimistic
            // changes). Fall back to the original item if the update changed
            // its id.
            T? targetItem;
            for (final originalItem in originalList) {
              if (!operation.predicate(originalItem)) continue;
              final originalId = idSelector(originalItem);
              for (final newItem in list) {
                if (idSelector(newItem) == originalId) {
                  targetItem = newItem;
                  break;
                }
              }
              targetItem ??= originalItem;
              break;
            }

            if (targetItem == null) {
              // No items matched: nothing to send, list is unchanged.
              return list;
            }

            final serverItem = await send(targetItem);
            final optimisticId = idSelector(targetItem);
            final serverId = idSelector(serverItem);

            return list.map((item) {
              if (idSelector(item) == optimisticId ||
                  idSelector(item) == serverId) {
                return serverItem;
              }
              return item;
            }).toList();
          }

          // Get the item from the operation
          final operationItem = operation.item;
          if (operationItem == null) {
            throw StateError('No item available from operation');
          }

          // Send the item and get server response
          final serverItem = await send(operationItem);
          final optimisticId = idSelector(operationItem);
          final serverId = idSelector(serverItem);

          // Update the item in the list with server response
          return list.map((item) {
            if (idSelector(item) == optimisticId ||
                idSelector(item) == serverId) {
              return serverItem;
            }
            return item;
          }).toList();
        },
      ),
      invalidates: invalidates,
      invalidateTags: invalidateTags,
    );
  }
}
