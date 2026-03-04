import 'package:sqflite/sqflite.dart';
import 'local_store.dart';

class SqfliteStore implements LocalStore {
  final Database db;
  final String isSyncedColumn;

  SqfliteStore(this.db, {this.isSyncedColumn = 'is_synced'});

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

    final placeholders = List.filled(ids.length, '?').join(',');
    return await db.query(
      table,
      where: '$pkColumn IN ($placeholders)',
      whereArgs: ids,
    );
  }
}
