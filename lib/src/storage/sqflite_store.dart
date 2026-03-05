import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/exceptions.dart';
import '../core/models.dart';
import 'local_store.dart';

/// SQLite implementation of [LocalStore] backed by `sqflite`.
///
/// Sync cursors are stored in a dedicated `_replicore_meta` table that is
/// created automatically on first use. This guarantees that cursor data is
/// evicted only when the SQLite database itself is deleted — never when the
/// user clears app cache or the OS purges SharedPreferences / NSUserDefaults.
class SqfliteStore implements LocalStore {
  final Database db;
  final String isSyncedColumn;
  final String operationIdColumn;

  /// Name of the internal meta-table used to persist sync cursors.
  static const _metaTable = '_replicore_meta';

  SqfliteStore(
    this.db, {
    this.isSyncedColumn = 'is_synced',
    this.operationIdColumn = 'op_id',
  });

  // ── Schema management ──────────────────────────────────────────────────────

  /// Ensures the internal `_replicore_meta` table exists.
  /// Called lazily before any cursor read/write.
  Future<void> _ensureMetaTable() async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_metaTable (
        key   TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL
      )
    ''');
  }

  @override
  Future<void> ensureSyncColumns(
    String table,
    String updatedAtColumn,
    String deletedAtColumn,
  ) async {
    final result = await db.rawQuery('PRAGMA table_info($table)');
    final existingColumns = result.map((row) => row['name'] as String).toSet();

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
            'ALTER TABLE $table '
            'ADD COLUMN ${col['name']} ${col['type']} DEFAULT ${col['default']}',
          );
        } catch (e) {
          throw SchemaMigrationException(
            table: table,
            column: col['name']!,
            message:
                'Failed to add column "${col['name']}" to table "$table". '
                'The database may be locked or the schema is unexpected.',
            cause: e,
          );
        }
      }
    }
  }

  // ── Cursor persistence (SQLite-backed) ─────────────────────────────────────

  @override
  Future<SyncCursor?> readCursor(String table) async {
    await _ensureMetaTable();

    final rows = await db.query(
      _metaTable,
      where: 'key = ?',
      whereArgs: ['cursor_$table'],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    try {
      final decoded = jsonDecode(rows.first['value'] as String);
      return SyncCursor.fromJson(Map<String, dynamic>.from(decoded as Map));
    } catch (_) {
      // Corrupted cursor entry — treat as missing so we do a fresh full sync.
      await clearCursor(table);
      return null;
    }
  }

  @override
  Future<void> writeCursor(String table, SyncCursor cursor) async {
    await _ensureMetaTable();

    await db.insert(_metaTable, {
      'key': 'cursor_$table',
      'value': jsonEncode(cursor.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> clearCursor(String table) async {
    await _ensureMetaTable();

    await db.delete(_metaTable, where: 'key = ?', whereArgs: ['cursor_$table']);
  }

  // ── Dirty-record queries ───────────────────────────────────────────────────

  @override
  Future<List<Map<String, dynamic>>> queryDirty(String table) {
    return db.query(table, where: '$isSyncedColumn = ?', whereArgs: [0]);
  }

  // ── Batch write ────────────────────────────────────────────────────────────

  @override
  Future<void> upsertBatch(
    String table,
    List<Map<String, dynamic>> records,
  ) async {
    if (records.isEmpty) return;

    try {
      final batch = db.batch();
      for (final record in records) {
        batch.insert(
          table,
          record,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    } catch (e) {
      throw LocalStoreException(
        table: table,
        message: 'Batch upsert failed for table "$table".',
        cause: e,
      );
    }
  }

  // ── Status updates ─────────────────────────────────────────────────────────

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

  // ── Lookups ────────────────────────────────────────────────────────────────

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

    // SQLite limits host parameters to 999 — chunk to stay safe.
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
