import 'dart:convert';

import '../core/exceptions.dart';
import '../core/models.dart';
import 'local_store.dart';

/// Isar (embedded NoSQL) implementation of [LocalStore].
///
/// Isar is a fast, type-safe embedded database for Flutter written in Rust.
/// Provides powerful querying with indexes and excellent performance.
///
/// Example setup:
/// ```dart
/// final isar = await Isar.open([
///   syncitronMetaSchema,
///   YourTableSchema,
/// ]);
///
/// final store = IsarStore(
///   isar: isar,
///   collectionFactory: (table) => isar.collection<YourType>(),
/// );
/// ```
class IsarStore implements LocalStore {
  final String isSyncedColumn;
  final String operationIdColumn;

  /// The Isar database instance.
  final dynamic isar;

  /// Factory function to get Isar collections for data tables.
  /// Signature: IsarCollection Function(String tableName)
  final Function(String) collectionFactory;

  /// Cache of opened collections to avoid repeated lookups.
  final Map<String, dynamic> _collectionCache = {};

  IsarStore({
    required this.isar,
    required this.collectionFactory,
    this.isSyncedColumn = 'is_synced',
    this.operationIdColumn = 'op_id',
  });

  /// Get or cache a collection for the given table.
  dynamic _getCollection(String table) {
    if (_collectionCache.containsKey(table)) {
      return _collectionCache[table];
    }

    try {
      final collection = collectionFactory(table);
      _collectionCache[table] = collection;
      return collection;
    } catch (e) {
      throw LocalStoreException(
        table: table,
        message: 'Failed to get Isar collection for table "$table".',
        cause: e,
      );
    }
  }

  // ── Schema management ──────────────────────────────────────────────────────

  /// Isar schemas are defined at compile time.
  /// This is a no-op for Isar as columns must be defined in the schema.
  @override
  Future<void> ensureSyncColumns(
    String table,
    String updatedAtColumn,
    String deletedAtColumn,
  ) async {
    // Isar schemas are compile-time; no dynamic schema changes
  }

  // ── Cursor persistence ─────────────────────────────────────────────────────

  @override
  Future<SyncCursor?> readCursor(String table) async {
    try {
      // Cursors stored in special Isar collection
      final metaCollection = _getCollection('_syncitron_meta');

      // Isar query syntax: metaCollection.where().key(cursor_$table).findFirst()
      final result = await (metaCollection as dynamic)
          .where()
          .keyEqualTo('cursor_$table')
          .findFirst();

      if (result == null) return null;

      final value = (result as dynamic).value as String?;
      if (value == null) return null;

      final decoded = jsonDecode(value);
      return SyncCursor.fromJson(Map<String, dynamic>.from(decoded as Map));
    } catch (_) {
      await clearCursor(table);
      return null;
    }
  }

  @override
  Future<void> writeCursor(String table, SyncCursor cursor) async {
    try {
      final metaCollection = _getCollection('_syncitron_meta');

      await isar.writeTxn(() async {
        await (metaCollection as dynamic).clear();
        await (metaCollection as dynamic).put(
          // Assuming a syncitronMeta object with key and value fields
          {'key': 'cursor_$table', 'value': jsonEncode(cursor.toJson())},
        );
      });
    } catch (e) {
      throw LocalStoreException(
        table: table,
        message: 'Failed to write cursor for table "$table" in Isar store.',
        cause: e,
      );
    }
  }

  @override
  Future<void> clearCursor(String table) async {
    try {
      final metaCollection = _getCollection('_syncitron_meta');

      await isar.writeTxn(() async {
        await (metaCollection as dynamic)
            .where()
            .keyEqualTo('cursor_$table')
            .deleteFirst();
      });
    } catch (e) {
      throw LocalStoreException(
        table: table,
        message: 'Failed to clear cursor for table "$table" in Isar store.',
        cause: e,
      );
    }
  }

  // ── Dirty-record queries ───────────────────────────────────────────────────

  @override
  Future<List<Map<String, dynamic>>> queryDirty(String table) async {
    try {
      final collection = _getCollection(table);

      // Query where is_synced == false
      final results = await (collection as dynamic)
          .where()
          .isSyncedEqualTo(false)
          .findAll();

      return results.map((r) => r.toJson() as Map<String, dynamic>).toList();
    } catch (e) {
      throw LocalStoreException(
        table: table,
        message: 'Failed to query dirty records from Isar store.',
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
      final collection = _getCollection(table);

      await isar.writeTxn(() async {
        // Isar's putAll for batch inserts
        await (collection as dynamic).putAll(records);
      });
    } catch (e) {
      throw LocalStoreException(
        table: table,
        message: 'Batch upsert failed in Isar store.',
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
      final collection = _getCollection(table);

      await isar.writeTxn(() async {
        // Isar query to find by ID and update
        final record = await (collection as dynamic)
            .where()
            .idEqualTo(primaryKey)
            .findFirst();

        if (record != null) {
          // Mark as synced
          record.isSynced = true;
          await (collection as dynamic).put(record);
        }
      });
    } catch (e) {
      throw LocalStoreException(
        table: table,
        message: 'Failed to mark record as synced in Isar store.',
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
      final collection = _getCollection(table);

      await isar.writeTxn(() async {
        final record = await (collection as dynamic)
            .where()
            .idEqualTo(primaryKey)
            .findFirst();

        if (record != null) {
          record.operationId = operationId;
          await (collection as dynamic).put(record);
        }
      });
    } catch (e) {
      throw LocalStoreException(
        table: table,
        message: 'Failed to set operation ID in Isar store.',
        cause: e,
      );
    }
  }

  /// Batch methods use default implementations (fallback to individual calls)
  @override
  Future<void> markManyAsSynced(
    String table,
    String pkColumn,
    List<dynamic> primaryKeys,
  ) async {
    for (final pk in primaryKeys) {
      await markAsSynced(table, pkColumn, pk);
    }
  }

  @override
  Future<void> setOperationIds(
    String table,
    String pkColumn,
    Map<dynamic, String> operationIds,
  ) async {
    for (final entry in operationIds.entries) {
      await setOperationId(table, pkColumn, entry.key, entry.value);
    }
  }

  @override
  Future<Map<String, dynamic>?> findById(
    String table,
    String pkColumn,
    dynamic id,
  ) async {
    try {
      final collection = _getCollection(table);

      final record = await (collection as dynamic)
          .where()
          .idEqualTo(id)
          .findFirst();

      if (record == null) return null;
      return (record as dynamic).toJson() as Map<String, dynamic>;
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
      final collection = _getCollection(table);

      // Isar batch query for multiple IDs
      final records = await (collection as dynamic)
          .where()
          .anyOf(ids, (q, id) => q.idEqualTo(id))
          .findAll();

      return records
          .map((r) => (r as dynamic).toJson() as Map<String, dynamic>)
          .toList();
    } catch (e) {
      throw LocalStoreException(
        table: table,
        message: 'Failed to find records by IDs in Isar store.',
        cause: e,
      );
    }
  }
}
