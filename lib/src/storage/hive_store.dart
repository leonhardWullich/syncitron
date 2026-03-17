import 'dart:convert';

import '../core/exceptions.dart';
import '../core/models.dart';
import 'local_store.dart';

/// Hive (NoSQL) implementation of [LocalStore].
///
/// Hive is a lightweight, embeddable key-value store written in pure Dart.
/// Perfect for simpler sync scenarios without complex querying requirements.
///
/// Example setup:
/// ```dart
/// await Hive.initFlutter();
/// final box = await Hive.openBox('syncitron_sync');
///
/// final store = HiveStore(
///   metadataBox: box,
///   dataBoxFactory: (table) => Hive.openBox(table),
/// );
/// ```
class HiveStore implements LocalStore {
  final String isSyncedColumn;
  final String operationIdColumn;

  /// Hive box for storing sync metadata (cursors, operation IDs).
  final dynamic metadataBox;

  /// Factory function to get/open Hive boxes for data tables.
  /// Signature: Future<Box> Function(String tableName)
  final Function(String) dataBoxFactory;

  /// Cache of opened data boxes to avoid repeated openings.
  final Map<String, dynamic> _boxCache = {};

  HiveStore({
    required this.metadataBox,
    required this.dataBoxFactory,
    this.isSyncedColumn = 'is_synced',
    this.operationIdColumn = 'op_id',
  });

  /// Get or open a data box for the given table.
  Future<dynamic> _getDataBox(String table) async {
    if (_boxCache.containsKey(table)) {
      return _boxCache[table];
    }

    try {
      final box = await dataBoxFactory(table);
      _boxCache[table] = box;
      return box;
    } catch (e) {
      throw LocalStoreException(
        table: table,
        message: 'Failed to open Hive box for table "$table".',
        cause: e,
      );
    }
  }

  // ── Schema management ──────────────────────────────────────────────────────

  /// Hive is schema-less; this is a no-op.
  @override
  Future<void> ensureSyncColumns(
    String table,
    String updatedAtColumn,
    String deletedAtColumn,
  ) async {
    // Hive doesn't require schema definition; all operations succeed
  }

  // ── Cursor persistence ─────────────────────────────────────────────────────

  @override
  Future<SyncCursor?> readCursor(String table) async {
    try {
      final key = 'cursor_$table';
      final value = metadataBox.get(key);

      if (value == null) return null;

      final decoded = jsonDecode(value as String);
      return SyncCursor.fromJson(Map<String, dynamic>.from(decoded as Map));
    } catch (_) {
      await clearCursor(table);
      return null;
    }
  }

  @override
  Future<void> writeCursor(String table, SyncCursor cursor) async {
    try {
      final key = 'cursor_$table';
      await metadataBox.put(key, jsonEncode(cursor.toJson()));
    } catch (e) {
      throw LocalStoreException(
        table: table,
        message: 'Failed to write cursor for table "$table" in Hive store.',
        cause: e,
      );
    }
  }

  @override
  Future<void> clearCursor(String table) async {
    try {
      final key = 'cursor_$table';
      await metadataBox.delete(key);
    } catch (e) {
      throw LocalStoreException(
        table: table,
        message: 'Failed to clear cursor for table "$table" in Hive store.',
        cause: e,
      );
    }
  }

  // ── Dirty-record queries ───────────────────────────────────────────────────

  @override
  Future<List<Map<String, dynamic>>> queryDirty(String table) async {
    try {
      final box = await _getDataBox(table);
      final results = <Map<String, dynamic>>[];

      // Hive's key-value interface requires scanning all keys.
      for (var i = 0; i < box.length; i++) {
        final record = box.getAt(i) as Map;
        final mapRecord = Map<String, dynamic>.from(record);

        // Check if record is marked as not synced.
        if ((mapRecord[isSyncedColumn] as bool?) == false) {
          results.add(mapRecord);
        }
      }

      return results;
    } catch (e) {
      throw LocalStoreException(
        table: table,
        message: 'Failed to query dirty records from Hive store.',
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
      final box = await _getDataBox(table);

      // Hive stores by primary key; assume 'id' is the key unless overridden.
      for (final record in records) {
        final id = record['id'] ?? record.keys.first;
        await box.put(id, record);
      }
    } catch (e) {
      throw LocalStoreException(
        table: table,
        message: 'Batch upsert failed in Hive store.',
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
      final box = await _getDataBox(table);
      final record = box.get(primaryKey) as Map?;

      if (record != null) {
        final updated = Map<String, dynamic>.from(record)
          ..[isSyncedColumn] = true;
        await box.put(primaryKey, updated);
      }
    } catch (e) {
      throw LocalStoreException(
        table: table,
        message: 'Failed to mark record as synced in Hive store.',
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
      final box = await _getDataBox(table);
      final record = box.get(primaryKey) as Map?;

      if (record != null) {
        final updated = Map<String, dynamic>.from(record)
          ..[operationIdColumn] = operationId;
        await box.put(primaryKey, updated);
      }
    } catch (e) {
      throw LocalStoreException(
        table: table,
        message: 'Failed to set operation ID in Hive store.',
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
      final box = await _getDataBox(table);
      final record = box.get(id);

      if (record == null) return null;
      return Map<String, dynamic>.from(record as Map);
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
      final box = await _getDataBox(table);
      final results = <Map<String, dynamic>>[];

      for (final id in ids) {
        final record = box.get(id);
        if (record != null) {
          results.add(Map<String, dynamic>.from(record as Map));
        }
      }

      return results;
    } catch (e) {
      throw LocalStoreException(
        table: table,
        message: 'Failed to find records by IDs in Hive store.',
        cause: e,
      );
    }
  }
}
