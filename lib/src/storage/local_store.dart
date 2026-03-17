import '../core/models.dart';

/// Abstraction over the local persistence layer.
///
/// Implementations must store both application data **and** sync metadata
/// (cursors, dirty flags, operation IDs) in the same durable store so that
/// metadata cannot be evicted independently of the data it describes.
abstract class LocalStore {
  // ── Schema management ──────────────────────────────────────────────────────

  Future<void> ensureSyncColumns(
    String table,
    String updatedAtColumn,
    String deletedAtColumn,
  );

  // ── Cursor persistence ─────────────────────────────────────────────────────
  //
  // Cursors are stored in the local store (e.g. a `_syncitron_meta` SQLite
  // table) rather than SharedPreferences / NSUserDefaults.
  //
  // Rationale: SharedPreferences can be cleared by the OS or by the user
  // ("Clear Cache") without touching the SQLite database. If that happens
  // the cursor is lost and the next sync performs a full re-download of all
  // data. Keeping the cursor co-located with the data guarantees they are
  // always in sync.

  /// Returns the persisted [SyncCursor] for [table], or `null` when no sync
  /// has been completed for that table yet.
  Future<SyncCursor?> readCursor(String table);

  /// Persists [cursor] for [table]. Called after every successful batch so
  /// that an interrupted sync can resume from the last processed record.
  Future<void> writeCursor(String table, SyncCursor cursor);

  /// Clears the cursor for [table], forcing the next sync to start from the
  /// beginning. Useful for a manual "force full sync" action.
  Future<void> clearCursor(String table);

  // ── Data access ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> queryDirty(String table);

  Future<void> upsertBatch(String table, List<Map<String, dynamic>> records);

  Future<void> markAsSynced(String table, String pkColumn, dynamic primaryKey);

  Future<void> setOperationId(
    String table,
    String pkColumn,
    dynamic primaryKey,
    String operationId,
  );

  /// Batch mark multiple records as synced (improves performance).
  /// If not overridden, falls back to individual markAsSynced calls.
  Future<void> markManyAsSynced(
    String table,
    String pkColumn,
    List<dynamic> primaryKeys,
  ) async {
    for (final pk in primaryKeys) {
      await markAsSynced(table, pkColumn, pk);
    }
  }

  /// Batch set operation IDs for multiple records (improves performance).
  /// If not overridden, falls back to individual setOperationId calls.
  Future<void> setOperationIds(
    String table,
    String pkColumn,
    Map<dynamic, String> operationIds,
  ) async {
    for (final entry in operationIds.entries) {
      await setOperationId(table, pkColumn, entry.key, entry.value);
    }
  }

  Future<Map<String, dynamic>?> findById(
    String table,
    String pkColumn,
    dynamic id,
  );

  Future<List<Map<String, dynamic>>> findManyByIds(
    String table,
    String pkColumn,
    List<dynamic> ids,
  );
}
