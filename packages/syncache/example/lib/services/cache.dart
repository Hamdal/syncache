import 'package:syncache/syncache.dart';

import '../models/todo.dart';
import '../models/user.dart';
import 'network.dart';

/// Global cache instances for the example app.
///
/// In a real app, you might use dependency injection or a service locator
/// pattern to provide these caches to your widgets.

/// Cache for user profile data.
final userCache = Syncache<User>(
  store: MemoryStore<User>(),
  network: simulatedNetwork,
  observers: [LoggingObserver()],
);

/// Cache for todo list data.
final todoCache = Syncache<TodoList>(
  store: MemoryStore<TodoList>(),
  network: simulatedNetwork,
  observers: [LoggingObserver()],
);
