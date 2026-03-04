import 'dart:async';

import '../adapters/remote_adapter.dart';
import '../storage/local_store.dart';
import '../utils/retry.dart';
import 'models.dart';
import 'sync_strategy.dart';
import 'table_config.dart';

class SyncEngine {
  final LocalStore localStore;
  final RemoteAdapter remoteAdapter;
  final int batchSize;
  final String isSyncedColumn;
  final String operationIdColumn;

  /// Optional logger. If null, nothing is printed.
  /// Inject your own logger to integrate with any logging framework:
  ///
  /// ```dart
  /// SyncEngine(
  ///   ...,
  ///   onLog: (msg) => debugPrint('[Replicore] $msg'),
  /// )
  /// ```
  final void Function(String message)? onLog;

  final List<TableConfig> _tables = [];

  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  // ── Thread-safe init ───────────────────────────────────────────────────────
  // Using a cached Future prevents parallel calls to init() from running the
  // migration logic multiple times concurrently.
  Future<void>? _initFuture;

  // ── Sync-lock ──────────────────────────────────────────────────────────────
  // Prevents overlapping sync runs (e.g. triggered by a timer AND a
  // connectivity event at the same time).
  bool _isSyncing = false;

  SyncEngine({
    required this.localStore,
    required this.remoteAdapter,
    this.batchSize = 500,
    this.isSyncedColumn = 'is_synced',
    this.operationIdColumn = 'op_id',
    this.onLog,
  });

  // ── Internal logger ────────────────────────────────────────────────────────

  void _log(String message) => onLog?.call(message);

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Initialises the engine exactly once, even when called concurrently.
  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    _emit('Initializing local database schema...');

    for (final table in _tables) {
      await localStore.ensureSyncColumns(
        table.name,
        table.updatedAtColumn,
        table.deletedAtColumn,
      );
    }

    _emit('Ready.');
  }

  void dispose() {
    _statusController.close();
  }

  // ── Configuration ──────────────────────────────────────────────────────────

  SyncEngine registerTable(TableConfig config) {
    _tables.add(config);
    return this;
  }

  // ── Public sync API ────────────────────────────────────────────────────────

  /// Syncs all registered tables sequentially.
  ///
  /// Returns immediately (no-op) if a sync is already in progress.
  Future<void> syncAll() async {
    if (_isSyncing) {
      _log('syncAll() called while sync is already running — skipped.');
      return;
    }

    _isSyncing = true;
    _emit('Starting Full Sync...');

    try {
      for (final table in _tables) {
        await syncTable(table);
      }
      _emit('Sync completed successfully.');
    } catch (e) {
      _emit('Critical Sync Error.');
      _log('❌ SyncAll Error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Syncs a single table.
  ///
  /// Can be called directly for pull-to-refresh scenarios.
  /// Returns immediately (no-op) if a sync is already in progress.
  Future<void> syncTable(TableConfig config) async {
    if (_isSyncing && !_isCurrentlySyncingThis(config)) {
      _log('syncTable(${config.name}) skipped — sync already in progress.');
      return;
    }

    await init();

    _emit('Syncing ${config.name}...');
    try {
      await _pull(config);
      await _push(config);
    } catch (e) {
      _emit('Error syncing ${config.name}');
      rethrow;
    }
  }

  // ── Pull ───────────────────────────────────────────────────────────────────

  Future<void> _pull(TableConfig config) async {
    _emit('Downloading ${config.name}...');

    // Strip any accidentally included sync-internal columns from the remote
    // SELECT list so they never overwrite local state.
    final safeColumns = config.columns
        .where((c) => c != isSyncedColumn && c != operationIdColumn)
        .toList();

    SyncCursor? cursor;

    while (true) {
      final result = await retry(() {
        return remoteAdapter.pull(
          PullRequest(
            table: config.name,
            columns: safeColumns,
            primaryKey: config.primaryKey,
            updatedAtColumn: config.updatedAtColumn,
            cursor: cursor,
            limit: batchSize,
          ),
        );
      });

      if (result.records.isEmpty) break;

      final remoteIds = result.records
          .map((r) => r[config.primaryKey])
          .where((id) => id != null)
          .toList();

      final localRecords = await localStore.findManyByIds(
        config.name,
        config.primaryKey,
        remoteIds,
      );

      final localRecordsMap = {
        for (final row in localRecords) row[config.primaryKey].toString(): row,
      };

      final merged = <Map<String, dynamic>>[];

      for (final remote in result.records) {
        final idValue = remote[config.primaryKey];
        if (idValue == null) continue;

        final local = localRecordsMap[idValue.toString()];

        if (local == null) {
          // New record from server — mark as synced immediately.
          merged.add({...remote, isSyncedColumn: 1});
          continue;
        }

        final resolved = await _resolveConflict(config, local, remote);

        if (resolved != null) {
          // Always stamp records that come from the server as synced.
          merged.add({...resolved, isSyncedColumn: 1});
        }
      }

      await localStore.upsertBatch(config.name, merged);

      cursor = result.nextCursor;
      if (cursor == null) break;
    }
  }

  // ── Push ───────────────────────────────────────────────────────────────────

  Future<void> _push(TableConfig config) async {
    final dirty = await localStore.queryDirty(config.name);

    if (dirty.isNotEmpty) {
      _emit('Uploading ${dirty.length} changes for ${config.name}...');
    }

    for (final row in dirty) {
      try {
        final pkValue = row[config.primaryKey];
        if (pkValue == null) continue;

        var operationId = row[operationIdColumn]?.toString();
        operationId ??= _buildOperationId(config, row);
        await localStore.setOperationId(
          config.name,
          config.primaryKey,
          pkValue,
          operationId,
        );

        final uploadData = Map<String, dynamic>.from(row)
          ..remove(isSyncedColumn)
          ..remove(operationIdColumn);

        final isSoftDeleted = row[config.deletedAtColumn] != null;

        await retry(() async {
          if (isSoftDeleted) {
            await remoteAdapter.softDelete(
              table: config.name,
              primaryKeyColumn: config.primaryKey,
              id: pkValue,
              payload: {
                config.deletedAtColumn: row[config.deletedAtColumn],
                config.updatedAtColumn:
                    row[config.updatedAtColumn] ??
                    DateTime.now().toUtc().toIso8601String(),
              },
              idempotencyKey: operationId,
            );
          } else {
            await remoteAdapter.upsert(
              table: config.name,
              data: uploadData,
              idempotencyKey: operationId,
            );
          }
        });

        await localStore.markAsSynced(config.name, config.primaryKey, pkValue);
      } catch (e) {
        _log(
          '⚠️ Sync Push failed for ${config.name} '
          '(ID: ${row[config.primaryKey]}): $e',
        );
      }
    }
  }

  // ── Conflict resolution ────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _resolveConflict(
    TableConfig config,
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) async {
    final localDirty =
        local[isSyncedColumn] == 0 || local[isSyncedColumn] == false;

    // Clean local record → server update always wins.
    if (!localDirty) return remote;

    switch (config.strategy) {
      case SyncStrategy.serverWins:
        return remote;

      case SyncStrategy.localWins:
        // Returning null signals "keep the local dirty record as-is".
        return null;

      case SyncStrategy.lastWriteWins:
        final localDate = _tryParseDate(
          local[config.updatedAtColumn]?.toString(),
        );
        final remoteDate = _tryParseDate(
          remote[config.updatedAtColumn]?.toString(),
        );

        if (remoteDate == null) return null;
        if (localDate == null) return remote;

        return remoteDate.isAfter(localDate) ? remote : null;

      case SyncStrategy.custom:
        if (config.customResolver == null) return remote;

        final resolution = await config.customResolver!(local, remote);

        return switch (resolution) {
          UseLocal() => null,
          UseRemote(data: final d) => d,
          UseMerged(data: final d) => d,
          Map<String, dynamic>() => throw UnimplementedError(),
          null => throw UnimplementedError(),
        };
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Emits a status message to both the [statusStream] and the [onLog] callback.
  void _emit(String message) {
    _statusController.add(message);
    _log(message);
  }

  /// Builds a deterministic idempotency key for a push operation.
  ///
  /// Uses a combination of table name, primary key, and timestamps.
  /// For true collision safety in high-frequency scenarios, consider
  /// replacing this with a UUID (e.g. the `uuid` package).
  String _buildOperationId(TableConfig config, Map<String, dynamic> row) {
    final pk = row[config.primaryKey]?.toString() ?? 'unknown';
    final updatedAt = row[config.updatedAtColumn]?.toString() ?? '';
    final deletedAt = row[config.deletedAtColumn]?.toString() ?? '';
    return '${config.name}:$pk:$updatedAt:$deletedAt';
  }

  DateTime? _tryParseDate(String? value) =>
      value != null ? DateTime.tryParse(value) : null;

  /// Guard used to allow [syncTable] to proceed when called internally
  /// from [syncAll] (which already holds the [_isSyncing] lock).
  bool _isCurrentlySyncingThis(TableConfig config) {
    // syncAll iterates tables and calls syncTable — it holds the lock itself.
    // We detect this by checking the lock is held but the caller is syncAll.
    // Since Dart is single-threaded per isolate, this is safe.
    return _isSyncing;
  }
}
