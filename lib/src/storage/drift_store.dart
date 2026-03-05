import 'dart:convert';

import '../core/exceptions.dart';
import '../core/models.dart';
import 'local_store.dart';

/// Drift (typed SQLite) implementation of [LocalStore].
///
/// Provides compile-time type safety and generated code for database access.
/// Drift tables must be manually defined in your app and passed to this store.
/// Sync metadata is stored alongside application data.
///
/// Example setup:
/// ```dart
/// @DataClassName('ReplicoreMeta')
/// class ReplicoreMetas extends Table {
///   TextColumn get key => text()();
///   TextColumn get value => text()();
///   @override
///   Set<Column> get primaryKey => {key};
/// }
///
/// final store = DriftStore(
///   queryBuilder: (query) => database.replicoreMetas
///     .byKey(query)
///     .getSingleOrNull(),
///   upsertBuilder: (table, records) => database.into(database.replicoreMetas)
///     .insertAll(records),
/// );
/// ```
class DriftStore implements LocalStore {
  final String isSyncedColumn;
  final String operationIdColumn;

  /// Map of table names to their Drift representations for querying.
  /// Used for accessing generated Drift tables at runtime.
  final Map<String, dynamic> tables;

  /// Custom query function for metadata retrieval.
  /// Signature: Future<Map<String, dynamic>?> Function(String key)
  final Function(String) readMetadataQuery;

  /// Custom upsert function for metadata persistence.
  /// Signature: Future<void> Function(String key, String value)
  final Function(String, String) writeMetadataQuery;

  /// Custom delete function for metadata cleanup.
  /// Signature: Future<void> Function(String key)
  final Function(String) deleteMetadataQuery;

  DriftStore({
    required this.tables,
    required this.readMetadataQuery,
    required this.writeMetadataQuery,
    required this.deleteMetadataQuery,
    this.isSyncedColumn = 'is_synced',
    this.operationIdColumn = 'op_id',
  });

  // ── Schema management ──────────────────────────────────────────────────────

  /// Drift handles schema management through generated code.
  /// This method ensures sync columns exist (must be done via Drift migration).
  @override
  Future<void> ensureSyncColumns(
    String table,
    String updatedAtColumn,
    String deletedAtColumn,
  ) async {
    // Drift migrations are handled through the database schema definition.
    // This is a no-op for Drift as columns must be defined at compile time.
  }

  // ── Cursor persistence ─────────────────────────────────────────────────────

  @override
  Future<SyncCursor?> readCursor(String table) async {
    try {
      final result = await readMetadataQuery('cursor_$table');
      if (result == null) return null;

      final decoded = jsonDecode(
        result is String ? result : (result as Map)['value'] as String,
      );
      return SyncCursor.fromJson(Map<String, dynamic>.from(decoded as Map));
    } catch (_) {
      await clearCursor(table);
      return null;
    }
  }

  @override
  Future<void> writeCursor(String table, SyncCursor cursor) async {
    try {
      await writeMetadataQuery('cursor_$table', jsonEncode(cursor.toJson()));
    } catch (e) {
      throw LocalStoreException(
        table: table,
        message: 'Failed to write cursor for table "$table" in Drift store.',
        cause: e,
      );
    }
  }

  @override
  Future<void> clearCursor(String table) async {
    try {
      await deleteMetadataQuery('cursor_$table');
    } catch (e) {
      throw LocalStoreException(
        table: table,
        message: 'Failed to clear cursor for table "$table" in Drift store.',
        cause: e,
      );
    }
  }

  // ── Dirty-record queries ───────────────────────────────────────────────────

  @override
  Future<List<Map<String, dynamic>>> queryDirty(String table) async {
    try {
      final driftTable = tables[table];
      if (driftTable == null) {
        throw LocalStoreException(
          table: table,
          message:
              'Table "$table" not registered in DriftStore. Register via constructor.',
        );
      }

      // Access Drift's generated query methods.
      // This is a simplified version; actual implementation depends on Drift schema.
      final results = await (driftTable as dynamic)
          .where((t) => t.isSynced.equals(false))
          .get();

      return List<Map<String, dynamic>>.from(
        results.map((r) => r.toCompanion(false).toJson()),
      );
    } catch (e) {
      throw LocalStoreException(
        table: table,
        message: 'Failed to query dirty records from Drift store.',
        cause: e,
      );
    }
  }

  // ── Batch write ────────────────────────────────────────────────────────────

  @override
  Future<void> upsertBatch(
    String table,
    List<Map<String, dynamic>> records,
  ) async {
    if (records.isEmpty) return;

    try {
      final driftTable = tables[table];
      if (driftTable == null) {
        throw LocalStoreException(
          table: table,
          message: 'Table "$table" not registered in DriftStore.',
        );
      }

      // Use Drift's insertAll or into().insertAll()
      await (driftTable as dynamic).insertAll(
        records.map((r) => (driftTable as dynamic).fromJson(r)),
      );
    } catch (e) {
      throw LocalStoreException(
        table: table,
        message: 'Batch upsert failed in Drift store.',
        cause: e,
      );
    }
  }

  // ── Individual record operations ───────────────────────────────────────────

  @override
  Future<void> markAsSynced(
    String table,
    String pkColumn,
    dynamic primaryKey,
  ) async {
    try {
      final driftTable = tables[table];
      if (driftTable == null) {
        throw LocalStoreException(table: table, message: 'Table not found.');
      }

      final pk = driftTable.primaryKey.first;
      await (driftTable as dynamic)
          .update()
          .where((t) => t[pk].equals(primaryKey))
          .write({isSyncedColumn: true});
    } catch (e) {
      throw LocalStoreException(
        table: table,
        message: 'Failed to mark record as synced in Drift store.',
        cause: e,
      );
    }
  }

  @override
  Future<void> setOperationId(
    String table,
    String pkColumn,
    dynamic primaryKey,
    String operationId,
  ) async {
    try {
      final driftTable = tables[table];
      if (driftTable == null) {
        throw LocalStoreException(table: table, message: 'Table not found.');
      }

      await (driftTable as dynamic).update().write({
        operationIdColumn: operationId,
      });
    } catch (e) {
      throw LocalStoreException(
        table: table,
        message: 'Failed to set operation ID in Drift store.',
        cause: e,
      );
    }
  }

  @override
  Future<Map<String, dynamic>?> findById(
    String table,
    String pkColumn,
    dynamic id,
  ) async {
    try {
      final driftTable = tables[table];
      if (driftTable == null) return null;

      final result = await (driftTable as dynamic)
          .where((t) => t[pkColumn].equals(id))
          .getSingleOrNull();

      return result?.toJson() as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> findManyByIds(
    String table,
    String pkColumn,
    List<dynamic> ids,
  ) async {
    try {
      final driftTable = tables[table];
      if (driftTable == null) return [];

      final results = await (driftTable as dynamic)
          .where((t) => t[pkColumn].isIn(ids))
          .get();

      return results.map((r) => r.toJson() as Map<String, dynamic>).toList();
    } catch (e) {
      throw LocalStoreException(
        table: table,
        message: 'Failed to find records by IDs in Drift store.',
        cause: e,
      );
    }
  }
}
