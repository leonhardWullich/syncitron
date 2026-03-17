import 'package:uuid/uuid.dart';

/// Domain model for a single Todo item.
///
/// The [isSynced] and [deletedAt] fields are managed by syncitron —
/// your UI code should generally ignore them.
class Todo {
  final String id;
  final String userId;
  final String title;
  final bool isDone;
  final DateTime updatedAt;

  /// Set by syncitron. 0 = dirty (not yet pushed), 1 = synced.
  final int isSynced;

  /// Non-null when the record is soft-deleted.
  final DateTime? deletedAt;

  const Todo({
    required this.id,
    required this.userId,
    required this.title,
    required this.isDone,
    required this.updatedAt,
    this.isSynced = 0,
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;

  /// Creates a brand-new Todo with a client-generated UUID.
  /// [isSynced] defaults to 0 so syncitron picks it up on the next push.
  factory Todo.create({required String userId, required String title}) {
    return Todo(
      id: const Uuid().v4(),
      userId: userId,
      title: title,
      isDone: false,
      updatedAt: DateTime.now().toUtc(),
      isSynced: 0,
    );
  }

  Todo copyWith({
    String? title,
    bool? isDone,
    DateTime? deletedAt,
  }) {
    return Todo(
      id: id,
      userId: userId,
      title: title ?? this.title,
      isDone: isDone ?? this.isDone,
      // Always bump updatedAt and mark dirty when something changes.
      updatedAt: DateTime.now().toUtc(),
      isSynced: 0,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  // ── SQLite serialisation ──────────────────────────────────────────────────

  factory Todo.fromMap(Map<String, dynamic> map) {
    return Todo(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      title: map['title'] as String,
      isDone: (map['is_done'] as int?) == 1,
      updatedAt: DateTime.parse(map['updated_at'] as String),
      isSynced: (map['is_synced'] as int?) ?? 1,
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'title': title,
        'is_done': isDone ? 1 : 0,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'is_synced': isSynced,
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
      };
}
