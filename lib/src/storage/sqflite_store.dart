import 'package:sqflite/sqflite.dart';
import 'local_store.dart';

class SqfliteStore implements LocalStore {
  final Database db;
  final String isSyncedColumn;

  SqfliteStore(this.db, {this.isSyncedColumn = 'is_synced'});

  @override
  Future<void> ensureSyncColumns(
    String table,
    String updatedAtColumn,
    String deletedAtColumn,
  ) async {
    final result = await db.rawQuery("PRAGMA table_info($table)");
    final existingColumns = result.map((row) => row['name'] as String).toList();

    final requiredColumns = [
      {'name': isSyncedColumn, 'type': 'INTEGER', 'default': '1'},
      {'name': updatedAtColumn, 'type': 'TEXT', 'default': 'NULL'},
      {'name': deletedAtColumn, 'type': 'TEXT', 'default': 'NULL'},
    ];

    for (var col in requiredColumns) {
      if (!existingColumns.contains(col['name'])) {
        try {
          await db.execute(
            "ALTER TABLE $table ADD COLUMN ${col['name']} ${col['type']} DEFAULT ${col['default']}",
          );
          print("🪄 Auto-Migration: Added '${col['name']}' to '$table'");
        } catch (e) {
          print("⚠️ Migration Warning for $table.${col['name']}: $e");
        }
      }
    }
  }

  @override
  Future<List<Map<String, dynamic>>> queryDirty(String table) {
    return db.query(table, where: '$isSyncedColumn = ?', whereArgs: [0]);
  }

  @override
  Future<void> upsertBatch(
    String table,
    List<Map<String, dynamic>> records,
  ) async {
    if (records.isEmpty) return;
    final batch = db.batch();
    for (final record in records) {
      batch.insert(table, record, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> markAsSynced(
    String table,
    String pkColumn,
    dynamic primaryKey,
  ) async {
    await db.update(
      table,
      {isSyncedColumn: 1},
      where: '$pkColumn = ?',
      whereArgs: [primaryKey],
    );
  }

  @override
  Future<Map<String, dynamic>?> findById(
    String table,
    String pkColumn,
    dynamic id,
  ) async {
    final result = await db.query(
      table,
      where: '$pkColumn = ?',
      whereArgs: [id],
      limit: 1,
    );
    return result.isEmpty ? null : result.first;
  }

  @override
  Future<List<Map<String, dynamic>>> findManyByIds(
    String table,
    String pkColumn,
    List<dynamic> ids,
  ) async {
    if (ids.isEmpty) return [];
    final List<Map<String, dynamic>> results = [];

    // Chunk IDs into batches of 900 to avoid SQLite limits
    for (var i = 0; i < ids.length; i += 900) {
      final chunk = ids.sublist(i, i + 900 > ids.length ? ids.length : i + 900);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final res = await db.query(
        table,
        where: '$pkColumn IN ($placeholders)',
        whereArgs: chunk,
      );
      results.addAll(res);
    }
    return results;
  }
}
