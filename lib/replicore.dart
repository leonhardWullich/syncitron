export 'src/core/sync_engine.dart';
export 'src/core/sync_strategy.dart';
export 'src/core/models.dart';
export 'src/core/table_config.dart';

export 'src/adapters/remote_adapter.dart';
export 'src/adapters/supabase_adapter.dart';

export 'src/storage/local_store.dart';
export 'src/storage/sqflite_store.dart';

/*import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:shared_preferences/shared_preferences.dart';

// =============================================================================
// ENUMS & TYPES
// =============================================================================

/// Defines how conflicts between local and remote data are resolved during synchronization.
enum SyncStrategy {
  /// **Server Wins (Default)**
  ///
  /// The server is considered the absolute source of truth.
  /// If a conflict occurs, the local data is discarded and replaced by the server version,
  /// **even if** the local version has unsaved changes (`is_synced = 0`).
  ///
  /// **Use case:** Read-only data (e.g., product catalogs, news feeds) or
  /// scenarios where concurrent editing is not allowed.
  serverWins,

  /// **Local Wins (Client Wins)**
  ///
  /// Prioritizes local changes to prevent data loss.
  /// If the local record is marked as 'dirty' (`is_synced = 0`), the incoming
  /// server update is ignored (skipped). The local version persists until it is
  /// successfully pushed to the server.
  ///
  /// **Use case:** User-generated content (e.g., personal notes, drafts) where
  /// preserving offline work is the highest priority.
  localWins,

  /// **Last Write Wins (Time Based)**
  ///
  /// Resolves the conflict by comparing the `updated_at` timestamps.
  /// * If **Remote is newer**: The local record is overwritten.
  /// * If **Local is newer**: The local record is kept and remains marked for upload.
  ///
  /// **Use case:** Collaborative editing or settings synced across multiple devices,
  /// where the most recent change should always apply.
  lastWriteWins,

  /// **Custom Merge**
  ///
  /// Delegates the conflict resolution to a user-defined callback function.
  /// You must provide a `customMerge` callback in the [TableDefinition].
  ///
  /// The callback receives both the `local` and `remote` data maps and must return
  /// the resolved map to be saved locally.
  ///
  /// **Use case:** Complex data merging (e.g., combining items in a shopping list,
  /// appending text to a log, JSON merging) instead of simple overwriting.
  customMerge,
}

/// Callback definition for custom merge logic.
/// Must return a Future containing the merged Map to be saved locally.
typedef MergeCallback =
    Future<Map<String, dynamic>> Function(
      Map<String, dynamic> local,
      Map<String, dynamic> remote,
    );

/// Callback triggered when a record is successfully synced (inserted/updated locally).
typedef RecordCallback = void Function(Map<String, dynamic> record);

// =============================================================================
// CONFIGURATION
// =============================================================================

/// Global configuration for the synchronization framework.
/// Defines the column names used for tracking state and sync metadata.
class FlutterLocalFirstConfig {
  /// Column name for soft deletes (e.g., 'deleted_at').
  final String deletedAtColumn;

  /// Column name for the last modification timestamp (e.g., 'updated_at').
  final String updatedAtColumn;

  /// Column name for the synchronization status (e.g., 'is_synced').
  /// Should be an INTEGER (0 = dirty, 1 = synced).
  final String isSyncedColumn;

  /// Number of records to download in one batch.
  /// Lower this if you experience memory issues or timeouts.
  final int batchSize;

  const FlutterLocalFirstConfig({
    this.deletedAtColumn = 'deleted_at',
    this.updatedAtColumn = 'updated_at',
    this.isSyncedColumn = 'is_synced',
    this.batchSize = 1000,
  });
}

/// Defines a specific table to be synchronized.
class TableDefinition {
  /// The table name (must match in SQLite and Supabase).
  final String name;

  /// The primary key column name (e.g., 'id', 'uuid', 'uid').
  final String primaryKey;

  /// The strategy used when a record exists both locally (dirty) and remotely.
  final SyncStrategy strategy;

  /// Optional: Custom logic to merge data when [SyncStrategy.customMerge] is used.
  final MergeCallback? customMerge;

  /// Optional: Callback fired after a record is written to the local database.
  final RecordCallback? onSynced;

  TableDefinition(
    this.name, {
    this.primaryKey = 'id',
    this.strategy = SyncStrategy.serverWins,
    this.customMerge,
    this.onSynced,
  });
}

// =============================================================================
// CORE SERVICE
// =============================================================================

class FlutterLocalFirst {
  // Singleton Pattern
  static final FlutterLocalFirst _instance = FlutterLocalFirst._internal();
  factory FlutterLocalFirst() => _instance;
  FlutterLocalFirst._internal();

  Database? _db;
  FlutterLocalFirstConfig _config = const FlutterLocalFirstConfig();
  final List<TableDefinition> _tables = [];

  // Stream controller to broadcast sync status messages to the UI.
  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  bool _isStarted = false;
  bool _isSyncing = false;

  /// Accessor for the Supabase client instance.
  supa.SupabaseClient get _client => supa.Supabase.instance.client;

  // Internal reference to SharedPreferences
  SharedPreferences? _prefs;

  // ---------------------------------------------------------------------------
  // FLUENT SETUP API
  // ---------------------------------------------------------------------------

  /// Sets the SQLite database instance.
  FlutterLocalFirst setDatabase(Database db) {
    _db = db;
    return this;
  }

  /// Sets the global configuration (optional).
  FlutterLocalFirst setConfig(FlutterLocalFirstConfig config) {
    _config = config;
    return this;
  }

  /// Adds a table to the synchronization process.
  FlutterLocalFirst addTable(TableDefinition tableDef) {
    _tables.add(tableDef);
    return this;
  }

  /// Initializes the framework.
  ///
  /// Checks for necessary columns in the SQLite tables and performs
  /// auto-migrations (adding `is_synced`, `updated_at` and `deleted_at` if missing).
  Future<void> start() async {
    if (_db == null) {
      throw Exception(
        "FlutterLocalFirst: Database not set. Call setDatabase() first.",
      );
    }

    _statusController.add("Initializing...");

    // Load SharedPreferences once during start
    _prefs = await SharedPreferences.getInstance();

    for (var table in _tables) {
      await _ensureMagicColumnExists(table);
    }

    _isStarted = true;
    _statusController.add("Ready.");
    if (kDebugMode) {
      print("✅ FlutterLocalFirst initialized with ${_tables.length} tables.");
    }
  }

  // ---------------------------------------------------------------------------
  // AUTO MIGRATION
  // ---------------------------------------------------------------------------

  /// Ensures that the required columns exist in the local SQLite table.
  /// If not, it executes an ALTER TABLE command.
  Future<void> _ensureMagicColumnExists(TableDefinition table) async {
    final result = await _db!.rawQuery("PRAGMA table_info(${table.name})");
    final existingColumns = result.map((row) => row['name'] as String).toList();

    final requiredColumns = [
      // Column: is_synced | Type: INTEGER | Default: 1 (Synced)
      _ColumnConfig(_config.isSyncedColumn, 'INTEGER', '1'),
      // Column: updated_at | Type: TEXT | Default: NULL
      _ColumnConfig(_config.updatedAtColumn, 'TEXT', 'NULL'),
      // Column: deleted_at | Type: TEXT | Default: NULL
      _ColumnConfig(_config.deletedAtColumn, 'TEXT', 'NULL'),
    ];

    for (var col in requiredColumns) {
      if (!existingColumns.contains(col.name)) {
        if (kDebugMode) {
          print("🪄 Auto-Migration: Adding '${col.name}' to '${table.name}'");
        }
        try {
          await _db!.execute(
            "ALTER TABLE ${table.name} ADD COLUMN ${col.name} ${col.type} DEFAULT ${col.defaultValue}",
          );
        } catch (e) {
          print("⚠️ Migration Warning for ${table.name}.${col.name}: $e");
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // PUBLIC SYNC API
  // ---------------------------------------------------------------------------

  /// Triggers the full synchronization process for all registered tables sequentially.
  Future<void> runFullSync() async {
    if (_isSyncing || _db == null || !_isStarted) return;
    _isSyncing = true;
    _statusController.add("Starting Full Sync...");

    try {
      for (var table in _tables) {
        // We wrap each table sync in a try-catch to ensure that if one table
        // fails (e.g. schema mismatch), the others still try to sync.
        try {
          await _performSyncForTable(table);
        } catch (e, stack) {
          print("❌ Error syncing table '${table.name}': $e");
          if (kDebugMode) print(stack);
        }
      }

      _statusController.add("Sync finished.");
    } catch (e) {
      print("❌ Critical Sync Error: $e");
      _statusController.add("Sync Error.");
    } finally {
      _isSyncing = false;
    }
  }

  /// Syncs a single table by its name.
  /// Useful for manual refresh actions (e.g., Pull-to-Refresh on a list).
  ///
  /// Throws an [ArgumentError] if the table was not added via [addTable].
  Future<void> syncTable(String tableName) async {
    if (!_isStarted) {
      throw Exception("FlutterLocalFirst not started. Call start() first.");
    }

    final tableDef = _tables.firstWhere(
      (t) => t.name == tableName,
      orElse: () => throw ArgumentError("Table '$tableName' not registered."),
    );

    if (_isSyncing) {
      if (kDebugMode) {
        print(
          "⚠️ Sync already in progress. Skipping manual sync for $tableName.",
        );
      }
      return;
    }

    _isSyncing = true;
    try {
      await _performSyncForTable(tableDef);
    } catch (e) {
      print("❌ Error syncing table '$tableName': $e");
    } finally {
      _isSyncing = false;
    }
  }

  // ---------------------------------------------------------------------------
  // INTERNAL SYNC LOGIC
  // ---------------------------------------------------------------------------

  Future<void> _performSyncForTable(TableDefinition table) async {
    final tableName = table.name;
    final pk = table.primaryKey;
    _statusController.add("Syncing: $tableName");

    // Load last sync timestamp using internal _prefs
    final lastSyncKey = 'replicore_last_$tableName';
    final lastSyncStr = _prefs!.getString(lastSyncKey);
    final lastSync = lastSyncStr != null ? DateTime.parse(lastSyncStr) : null;
    final now = DateTime.now().toUtc();

    // 1. Get Local Columns (Reflection) to avoid selecting non-existent columns
    final localColumns = await _getLocalTableColumns(tableName);
    final selectCols = {
      ...localColumns,
      _config.updatedAtColumn,
      _config.deletedAtColumn,
    }.where((c) => c != _config.isSyncedColumn).join(',');

    // =========================================================================
    // STEP A: PULL (Download with Pagination & Optimization)
    // =========================================================================

    int offset = 0;
    bool hasMore = true;

    var queryBuilder = _client.from(tableName).select(selectCols);
    if (lastSync != null) {
      queryBuilder = queryBuilder.gt(
        _config.updatedAtColumn,
        lastSync.toIso8601String(),
      );
    }

    // Order is crucial for stable pagination
    final orderedBuilder = queryBuilder.order(
      _config.updatedAtColumn,
      ascending: true,
    );

    while (hasMore) {
      // Fetch batch from Supabase
      final List<dynamic> batchData = await orderedBuilder.range(
        offset,
        offset + _config.batchSize - 1,
      );

      if (batchData.isEmpty) {
        hasMore = false;
        break;
      }

      // --- PERFORMANCE OPTIMIZATION START ---
      // Instead of querying the DB for every single row in the loop (N queries),
      // we fetch all local counterparts in ONE query (1 query).

      final remoteIds = batchData
          .map((e) => e[pk])
          .where((e) => e != null)
          .toList();

      // Fetch local rows matching these IDs
      // Note: We need to handle quoting for Strings vs No-Quotes for Integers
      final localRowsMap = <String, Map<String, dynamic>>{};

      if (remoteIds.isNotEmpty) {
        final whereClause = _buildWhereInClause(pk, remoteIds);
        final localRows = await _db!.query(tableName, where: whereClause);
        for (var row in localRows) {
          localRowsMap[row[pk].toString()] = row;
        }
      }
      // --- PERFORMANCE OPTIMIZATION END ---

      final batch = _db!.batch();

      // Process records in memory
      for (var remoteRow in batchData) {
        final idVal = remoteRow[pk];
        final localRow = localRowsMap[idVal.toString()];

        await _processIncomingRecord(remoteRow, localRow, table, batch);
      }

      // Commit all changes for this batch transactionally
      await batch.commit(noResult: true);

      if (batchData.length < _config.batchSize) {
        hasMore = false;
      } else {
        offset += _config.batchSize;
        _statusController.add("Loading $tableName ($offset)...");
      }
    }

    // Save timestamp only after successful pull
    await _prefs!.setString(lastSyncKey, now.toIso8601String());

    // =========================================================================
    // STEP B: PUSH (Upload)
    // =========================================================================

    // Find all local records marked as 'dirty'
    final dirtyRows = await _db!.query(
      tableName,
      where: '${_config.isSyncedColumn} = ?',
      whereArgs: [0],
    );

    if (dirtyRows.isNotEmpty) {
      _statusController.add("Uploading: $tableName (${dirtyRows.length})");

      // Batch for marking records as synced locally after upload
      final localUpdateBatch = _db!.batch();

      for (var row in dirtyRows) {
        final idValue = row[pk];
        if (idValue == null) {
          if (kDebugMode) {
            print(
              "⚠️ Error: Primary Key '$pk' is NULL in '$tableName'. Skipping.",
            );
          }
          continue;
        }

        try {
          // Prepare data: remove local-only 'is_synced' column
          final uploadData = Map<String, dynamic>.from(row);
          uploadData.remove(_config.isSyncedColumn);

          // Check if it is a Soft Delete
          if (row[_config.deletedAtColumn] != null) {
            // It's a delete -> Update the timestamp and deleted_at flag in Supabase
            await _client
                .from(tableName)
                .update({
                  _config.deletedAtColumn: row[_config.deletedAtColumn],
                  _config.updatedAtColumn:
                      row[_config.updatedAtColumn] ?? now.toIso8601String(),
                })
                .eq(pk, idValue);
          } else {
            // It's an Insert/Update -> Upsert
            // Supabase Upsert automatically handles Insert if ID is new, or Update if ID exists
            await _client.from(tableName).upsert(uploadData);
          }

          // Queue the local status update (mark as synced)
          localUpdateBatch.update(
            tableName,
            {_config.isSyncedColumn: 1},
            where: '$pk = ?',
            whereArgs: [idValue],
          );
        } catch (e) {
          print("⚠️ Upload failed for $tableName PK $idValue: $e");
          // If upload fails, we DO NOT add it to localUpdateBatch,
          // so it stays dirty and tries again next time.
        }
      }

      // Commit all local status updates at once
      await localUpdateBatch.commit(noResult: true);
    }
  }

  // ---------------------------------------------------------------------------
  // CONFLICT RESOLUTION
  // ---------------------------------------------------------------------------

  Future<void> _processIncomingRecord(
    Map<String, dynamic> remoteRow,
    Map<String, dynamic>? localRow, // Optimization: Passed from bulk query
    TableDefinition table,
    Batch batch,
  ) async {
    Map<String, dynamic>? dataToSave;

    if (localRow == null) {
      // Case 1: Record does not exist locally -> Insert it
      dataToSave = remoteRow;
    } else {
      // Case 2: Record exists locally -> Check for conflict
      final isLocalDirty = (localRow[_config.isSyncedColumn] ?? 1) == 0;

      if (!isLocalDirty) {
        // Local is clean (synced) -> Server update wins (Overwrite)
        dataToSave = remoteRow;
      } else {
        // Local is dirty (unsaved changes) -> Conflict Resolution needed
        dataToSave = await _resolveConflict(localRow, remoteRow, table);
      }
    }

    if (dataToSave != null) {
      // Ensure the record is marked as synced (1) because it comes from the server
      final finalData = Map<String, dynamic>.from(dataToSave);
      finalData[_config.isSyncedColumn] = 1;

      batch.insert(
        table.name,
        finalData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      if (table.onSynced != null) table.onSynced!(finalData);
    }
  }

  /// Determines which version of the data should be saved based on the [TableDefinition.strategy].
  Future<Map<String, dynamic>?> _resolveConflict(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
    TableDefinition table,
  ) async {
    final remoteDate = _parseDate(remote[_config.updatedAtColumn]);
    final localDate = _parseDate(local[_config.updatedAtColumn]);

    switch (table.strategy) {
      case SyncStrategy.serverWins:
        return remote;

      case SyncStrategy.localWins:
        return null; // Keep local dirty version (ignore remote)

      case SyncStrategy.lastWriteWins:
        return remoteDate.isAfter(localDate) ? remote : null;

      case SyncStrategy.customMerge:
        if (table.customMerge != null) {
          return await table.customMerge!(local, remote);
        }
        return remote; // Fallback
    }
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  /// Retrieves the list of column names for a local SQLite table.
  Future<List<String>> _getLocalTableColumns(String tableName) async {
    final result = await _db!.rawQuery("PRAGMA table_info($tableName)");
    return result.map((row) => row['name'] as String).toList();
  }

  /// Builds a SQL "WHERE IN" clause safely handling string vs integer IDs.
  String _buildWhereInClause(String column, List<dynamic> ids) {
    if (ids.isEmpty) return "1=0"; // Fail safe

    final buffer = StringBuffer("$column IN (");
    for (int i = 0; i < ids.length; i++) {
      final id = ids[i];
      if (id is String) {
        // Simple sanitization for string IDs to prevent basic SQL injection
        buffer.write("'${id.replaceAll("'", "''")}'");
      } else {
        buffer.write(id);
      }
      if (i < ids.length - 1) buffer.write(",");
    }
    buffer.write(")");
    return buffer.toString();
  }

  /// Safely parses a date string to DateTime. Returns Epoch 0 if null or invalid.
  DateTime _parseDate(dynamic val) {
    if (val == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (val is String) {
      return DateTime.tryParse(val) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

/// Helper class to define column structure for auto-migration.
class _ColumnConfig {
  final String name;
  final String type;
  final String defaultValue;
  _ColumnConfig(this.name, this.type, this.defaultValue);
}*/
