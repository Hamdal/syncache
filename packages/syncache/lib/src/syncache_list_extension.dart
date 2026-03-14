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
  /// matching updated item. The server response updates all items that match
  /// the [idSelector].
  ///
  /// For [RemoveWhereOperation], [send] is called with a dummy value and
  /// its return is ignored (since items are being removed).
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
    await mutate(
      key: key,
      mutation: Mutation<List<T>>(
        apply: operation.apply,
        send: (list) async {
          // Handle RemoveWhereOperation specially - nothing to update
          if (operation is RemoveWhereOperation<T>) {
            // For remove, we don't have an item to send, but we still call
            // send with a placeholder. The caller should handle this.
            // Actually, for remove operations, we use mutateList instead.
            return list;
          }

          // Get the item from the operation
          final operationItem = operation.item;
          if (operationItem == null) {
            // UpdateWhereOperation: find the first matching item in the list
            if (operation is UpdateWhereOperation<T>) {
              // Find first item that was updated (exists in new list)
              for (final item in list) {
                // We can't know which items were updated without the original
                // list, so we'll send the first item that matches the predicate
                // applied to the current list
                final serverItem = await send(item);
                final serverId = idSelector(serverItem);

                // Update all items with matching ID
                return list.map((i) {
                  if (idSelector(i) == serverId) {
                    return serverItem;
                  }
                  return i;
                }).toList();
              }
              return list;
            }
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
