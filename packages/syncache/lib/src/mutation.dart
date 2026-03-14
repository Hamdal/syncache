/// Describes an optimistic mutation operation.
///
/// A [Mutation] consists of two functions:
/// - [apply]: Immediately transforms the cached value (optimistic update)
/// - [send]: Persists the change to the server (async sync)
///
/// This enables optimistic UI updates where the local cache is updated
/// immediately while the server sync happens in the background.
///
/// Example:
/// ```dart
/// await cache.mutate(
///   key: 'user:123',
///   mutation: Mutation<User>(
///     // Optimistically update the local cache
///     apply: (user) => user.copyWith(name: 'New Name'),
///     // Sync to server
///     send: (user) async {
///       final response = await api.updateUser(user);
///       return User.fromJson(response);
///     },
///   ),
/// );
/// ```
///
/// If [send] fails, the mutation remains in the sync queue and will
/// be retried when the network becomes available.
class Mutation<T> {
  /// Transforms the current cached value into the new optimistic value.
  ///
  /// This function is called synchronously to update the local cache
  /// immediately, providing instant feedback to the user.
  final T Function(T current) apply;

  /// Sends the mutated value to the server and returns the confirmed value.
  ///
  /// This function is called asynchronously after [apply]. The returned
  /// value replaces the optimistic value in the cache, ensuring eventual
  /// consistency with the server.
  ///
  /// If this function throws, the mutation remains queued for retry.
  final Future<T> Function(T value) send;

  /// Creates a [Mutation] with the given [apply] and [send] functions.
  const Mutation({required this.apply, required this.send});
}
