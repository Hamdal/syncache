import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:syncache/syncache.dart';

/// Builds a widget from a [PaginatedCache]'s current [PagedViewState].
///
/// [loadMore] fetches the next page; the app decides when to call it from
/// its own scroll wiring.
typedef PaginatedViewBuilder<T> = Widget Function(
  BuildContext context,
  PagedViewState<T> state,
  VoidCallback loadMore,
);

/// A widget that builds itself from a [PaginatedCache]'s windowed state.
///
/// Deliberately thin: it subscribes to `paginated.watch`, rebuilds on
/// [PagedViewState] changes (structural equality keeps this cheap), and
/// hands the builder the current [PagedViewState] plus a `loadMore`
/// callback. **No scroll listeners are attached** — apps own their
/// ScrollController / NotificationListener and decide when to fetch.
///
/// ## Basic Usage
///
/// ```dart
/// PaginatedCacheBuilder<Post>(
///   paginated: posts,
///   builder: (context, state, loadMore) {
///     if (state.error != null && state.items.isEmpty) {
///       return ErrorWidget(state.error!);
///     }
///     if (state.isLoading) {
///       return const CircularProgressIndicator();
///     }
///     return ListView.builder(
///       itemCount: state.items.length + (state.hasMore ? 1 : 0),
///       itemBuilder: (context, index) {
///         if (index >= state.items.length) {
///           // Triggered from whatever scroll wiring you own.
///           loadMore();
///           return const PostTileSkeleton();
///         }
///         return PostTile(state.items[index]);
///       },
///     );
///   },
/// )
/// ```
///
/// If [paginated] changes, the widget resubscribes and rebuilds from the
/// new instance's current state. The subscription is cancelled on dispose;
/// the underlying [PaginatedCache] is not disposed — its owner does that.
class PaginatedCacheBuilder<T> extends StatefulWidget {
  /// The paginated cache whose state drives this widget.
  final PaginatedCache<T> paginated;

  /// Builds with the current state and a callback to fetch the next page.
  final PaginatedViewBuilder<T> builder;

  /// Creates a [PaginatedCacheBuilder].
  const PaginatedCacheBuilder({
    super.key,
    required this.paginated,
    required this.builder,
  });

  @override
  State<PaginatedCacheBuilder<T>> createState() =>
      _PaginatedCacheBuilderState<T>();
}

class _PaginatedCacheBuilderState<T> extends State<PaginatedCacheBuilder<T>> {
  StreamSubscription<PagedViewState<T>>? _subscription;
  late PagedViewState<T> _state;

  @override
  void initState() {
    super.initState();
    _state = widget.paginated.state;
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant PaginatedCacheBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.paginated, widget.paginated)) {
      _subscription?.cancel();
      _state = widget.paginated.state;
      _subscribe();
    }
  }

  void _subscribe() {
    _subscription = widget.paginated.watch.listen((state) {
      if (mounted) {
        setState(() => _state = state);
      }
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _state, widget.paginated.loadMore);
}
