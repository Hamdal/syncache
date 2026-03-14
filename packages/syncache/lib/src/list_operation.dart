/// Describes an operation on a cached list.
///
/// Provides built-in operations for common list mutations with type safety.
///
/// Example:
/// ```dart
/// // Append an item
/// final op = ListOperation.append(newItem);
///
/// // Update items matching a condition
/// final op = ListOperation.updateWhere(
///   (item) => item.id == targetId,
///   (item) => item.copyWith(name: 'New Name'),
/// );
///
/// // Remove items matching a condition
/// final op = ListOperation.removeWhere((item) => item.id == targetId);
/// ```
sealed class ListOperation<T> {
  const ListOperation();

  /// Append an item to the end of the list.
  const factory ListOperation.append(T item) = AppendOperation<T>;

  /// Prepend an item to the beginning of the list.
  const factory ListOperation.prepend(T item) = PrependOperation<T>;

  /// Insert an item at a specific index.
  const factory ListOperation.insert(int index, T item) = InsertOperation<T>;

  /// Update items matching a predicate.
  const factory ListOperation.updateWhere(
    bool Function(T) predicate,
    T Function(T) update,
  ) = UpdateWhereOperation<T>;

  /// Remove items matching a predicate.
  const factory ListOperation.removeWhere(
    bool Function(T) predicate,
  ) = RemoveWhereOperation<T>;

  /// Apply this operation to a list and return the result.
  ///
  /// The original list is not modified; a new list is returned.
  List<T> apply(List<T> list);

  /// Get the item being added/modified by this operation, if any.
  ///
  /// Returns `null` for [RemoveWhereOperation].
  T? get item;
}

/// Appends an item to the end of the list.
final class AppendOperation<T> extends ListOperation<T> {
  /// The item to append.
  @override
  final T item;

  const AppendOperation(this.item);

  @override
  List<T> apply(List<T> list) => [...list, item];
}

/// Prepends an item to the beginning of the list.
final class PrependOperation<T> extends ListOperation<T> {
  /// The item to prepend.
  @override
  final T item;

  const PrependOperation(this.item);

  @override
  List<T> apply(List<T> list) => [item, ...list];
}

/// Inserts an item at a specific index.
final class InsertOperation<T> extends ListOperation<T> {
  /// The index at which to insert the item.
  final int index;

  /// The item to insert.
  @override
  final T item;

  const InsertOperation(this.index, this.item);

  @override
  List<T> apply(List<T> list) {
    final result = List<T>.of(list);
    // Clamp index to valid range
    final insertIndex = index.clamp(0, result.length);
    result.insert(insertIndex, item);
    return result;
  }
}

/// Updates items in the list that match a predicate.
final class UpdateWhereOperation<T> extends ListOperation<T> {
  /// The predicate to match items.
  final bool Function(T) predicate;

  /// The function to update matching items.
  final T Function(T) update;

  const UpdateWhereOperation(this.predicate, this.update);

  @override
  List<T> apply(List<T> list) {
    return list.map((item) {
      if (predicate(item)) {
        return update(item);
      }
      return item;
    }).toList();
  }

  /// Returns `null` since this operation updates existing items.
  @override
  T? get item => null;
}

/// Removes items from the list that match a predicate.
final class RemoveWhereOperation<T> extends ListOperation<T> {
  /// The predicate to match items for removal.
  final bool Function(T) predicate;

  const RemoveWhereOperation(this.predicate);

  @override
  List<T> apply(List<T> list) {
    return list.where((item) => !predicate(item)).toList();
  }

  /// Returns `null` since this operation removes items.
  @override
  T? get item => null;
}
