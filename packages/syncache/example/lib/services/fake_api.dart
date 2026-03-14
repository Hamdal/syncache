import 'dart:async';
import 'dart:math';

import '../models/todo.dart';
import '../models/user.dart';

/// A simulated API service that mimics network requests with delays.
///
/// This service demonstrates how syncache would work with real API calls.
/// In production, you would replace these with actual HTTP requests.
class FakeApiService {
  final Random _random = Random();

  /// Simulated network delay range (min, max) in milliseconds.
  final int minDelay;
  final int maxDelay;

  /// Whether the API should randomly fail (for testing error handling).
  bool simulateErrors;

  /// Error probability (0.0 to 1.0) when simulateErrors is true.
  double errorProbability;

  FakeApiService({
    this.minDelay = 500,
    this.maxDelay = 2000,
    this.simulateErrors = false,
    this.errorProbability = 0.3,
  });

  /// Simulates network delay.
  Future<void> _delay() async {
    final delay = minDelay + _random.nextInt(maxDelay - minDelay);
    await Future.delayed(Duration(milliseconds: delay));
  }

  /// Possibly throws an error to simulate network failures.
  void _maybeThrow() {
    if (simulateErrors && _random.nextDouble() < errorProbability) {
      throw Exception('Simulated network error');
    }
  }

  /// Fetches the current user profile.
  Future<User> fetchUser() async {
    await _delay();
    _maybeThrow();

    return User(
      id: 1,
      name: 'John Doe',
      email: 'john.doe@example.com',
      avatarUrl: 'https://i.pravatar.cc/150?u=1',
    );
  }

  /// Updates the user profile and returns the updated user.
  Future<User> updateUser(User user) async {
    await _delay();
    _maybeThrow();

    // Simulate server returning the updated user
    return user;
  }

  /// Fetches the list of todos.
  Future<TodoList> fetchTodos() async {
    await _delay();
    _maybeThrow();

    final now = DateTime.now();
    return TodoList(
      fetchedAt: now,
      items: [
        Todo(
          id: 1,
          title: 'Learn about syncache',
          completed: true,
          createdAt: now.subtract(const Duration(days: 2)),
        ),
        Todo(
          id: 2,
          title: 'Build an offline-first app',
          completed: false,
          createdAt: now.subtract(const Duration(days: 1)),
        ),
        Todo(
          id: 3,
          title: 'Implement optimistic mutations',
          completed: false,
          createdAt: now.subtract(const Duration(hours: 12)),
        ),
        Todo(
          id: 4,
          title: 'Test with different cache policies',
          completed: false,
          createdAt: now.subtract(const Duration(hours: 6)),
        ),
        Todo(
          id: 5,
          title: 'Deploy the app',
          completed: false,
          createdAt: now.subtract(const Duration(hours: 1)),
        ),
      ],
    );
  }

  /// Updates a todo (toggle completion) and returns the updated list.
  Future<TodoList> updateTodos(TodoList todos) async {
    await _delay();
    _maybeThrow();

    // Simulate server returning the updated list
    return todos;
  }

  /// Adds a new todo and returns the updated list.
  Future<TodoList> addTodo(TodoList todos, String title) async {
    await _delay();
    _maybeThrow();

    final newTodo = Todo(
      id: todos.items.length + 1,
      title: title,
      completed: false,
      createdAt: DateTime.now(),
    );

    return todos.addTodo(newTodo);
  }
}

/// Global instance of the fake API service.
final fakeApi = FakeApiService();
