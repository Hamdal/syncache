/// A simple todo item model for demonstrating syncache.
class Todo {
  final int id;
  final String title;
  final bool completed;
  final DateTime createdAt;

  const Todo({
    required this.id,
    required this.title,
    required this.completed,
    required this.createdAt,
  });

  Todo copyWith({
    int? id,
    String? title,
    bool? completed,
    DateTime? createdAt,
  }) {
    return Todo(
      id: id ?? this.id,
      title: title ?? this.title,
      completed: completed ?? this.completed,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() => 'Todo(id: $id, title: $title, completed: $completed)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Todo &&
        other.id == id &&
        other.title == title &&
        other.completed == completed;
  }

  @override
  int get hashCode => Object.hash(id, title, completed);
}

/// A list of todos wrapper for caching.
class TodoList {
  final List<Todo> items;
  final DateTime fetchedAt;

  const TodoList({required this.items, required this.fetchedAt});

  TodoList copyWith({List<Todo>? items, DateTime? fetchedAt}) {
    return TodoList(
      items: items ?? this.items,
      fetchedAt: fetchedAt ?? this.fetchedAt,
    );
  }

  /// Toggles the completion status of a todo by id.
  TodoList toggleTodo(int id) {
    return copyWith(
      items: items.map((todo) {
        if (todo.id == id) {
          return todo.copyWith(completed: !todo.completed);
        }
        return todo;
      }).toList(),
    );
  }

  /// Adds a new todo to the list.
  TodoList addTodo(Todo todo) {
    return copyWith(items: [...items, todo]);
  }
}
