import 'package:sqflite/sqflite.dart';

import 'todo.dart';

/// All local database access for the [Todo] feature.
///
/// The [Database] instance is injected via the constructor — no global
/// singleton needed. This also makes the repository trivially testable:
/// just pass an in-memory database in tests.
///
/// This class knows nothing about Replicore. It only needs to:
///   1. Set `is_synced = 0` on every write (marks the record as dirty).
///   2. Set `updated_at` on every write (used by lastWriteWins resolution).
///
/// Both are already handled inside [Todo.create] and [Todo.copyWith].
class TodoRepository {
  final Database _db;

  const TodoRepository(this._db);

  // ── Queries ────────────────────────────────────────────────────────────────

  /// Returns all non-deleted todos for [userId], newest first.
  Future<List<Todo>> fetchAll(String userId) async {
    final rows = await _db.query(
      'todos',
      where: 'user_id = ? AND deleted_at IS NULL',
      whereArgs: [userId],
      orderBy: 'updated_at DESC',
    );
    return rows.map(Todo.fromMap).toList();
  }

  // ── Writes ─────────────────────────────────────────────────────────────────

  /// Inserts a new todo.
  ///
  /// [Todo.create] already sets `is_synced = 0` and `updated_at = now()`,
  /// so Replicore will push this record on the next sync.
  Future<void> insert(Todo todo) async {
    await _db.insert(
      'todos',
      todo.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Persists changes to an existing todo.
  ///
  /// [Todo.copyWith] bumps `updated_at` and resets `is_synced = 0`.
  Future<void> update(Todo todo) async {
    await _db.update(
      'todos',
      todo.toMap(),
      where: 'id = ?',
      whereArgs: [todo.id],
    );
  }

  /// Soft-deletes a todo by setting `deleted_at`.
  ///
  /// The record stays in SQLite so Replicore can push the deletion to
  /// Supabase on the next sync. Other clients pull the `deleted_at` value
  /// and filter it out.
  Future<void> softDelete(Todo todo) async {
    final deleted = todo.copyWith(deletedAt: DateTime.now().toUtc());
    await update(deleted);
  }
}
