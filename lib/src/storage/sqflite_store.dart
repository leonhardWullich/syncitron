import 'package:sqflite/sqflite.dart';
import 'local_store.dart';

class SqfliteStore implements LocalStore {
  final Database db;
  final String isSyncedColumn;
  final String operationIdColumn;

  SqfliteStore(
    this.db, {
    this.isSyncedColumn = 'is_synced',
    this.operationIdColumn = 'op_id',
  });

  @override
  Future<void> ensureSyncColumns(
    String table,
    String updatedAtColumn,
    String deletedAtColumn,
  ) async {
    final result = await db.rawQuery('PRAGMA table_info($table)');
    final existingColumns = result.map((row) => row['name'] as String).toList();

    final requiredColumns = [
      {'name': isSyncedColumn, 'type': 'INTEGER', 'default': '1'},
      {'name': updatedAtColumn, 'type': 'TEXT', 'default': 'NULL'},
      {'name': deletedAtColumn, 'type': 'TEXT', 'default': 'NULL'},
      {'name': operationIdColumn, 'type': 'TEXT', 'default': 'NULL'},
    ];

    for (final col in requiredColumns) {
      if (!existingColumns.contains(col['name'])) {
        try {
          await db.execute(
            'ALTER TABLE $table ADD COLUMN ${col['name']} ${col['type']} DEFAULT ${col['default']}',
          );
        } catch (e) {
          // Column may have been added by a concurrent call — safe to ignore.
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
      {isSyncedColumn: 1, operationIdColumn: null},
      where: '$pkColumn = ?',
      whereArgs: [primaryKey],
    );
  }

  @override
  Future<void> setOperationId(
    String table,
    String pkColumn,
    dynamic primaryKey,
    String operationId,
  ) async {
    await db.update(
      table,
      {operationIdColumn: operationId},
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
    final results = <Map<String, dynamic>>[];

    // SQLite has a max of 999 host parameters — chunk to stay safe.
    for (var i = 0; i < ids.length; i += 900) {
      final chunk = ids.sublist(
        i,
        (i + 900) > ids.length ? ids.length : (i + 900),
      );
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
