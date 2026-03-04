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

  final List<TableConfig> _tables = [];

  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  bool _initialized = false;

  SyncEngine({
    required this.localStore,
    required this.remoteAdapter,
    this.batchSize = 500,
    this.isSyncedColumn = 'is_synced',
    this.operationIdColumn = 'op_id',
  });

  Future<void> init() async {
    if (_initialized) return;

    _statusController.add('Initializing local database schema...');

    for (final table in _tables) {
      await localStore.ensureSyncColumns(
        table.name,
        table.updatedAtColumn,
        table.deletedAtColumn,
      );
    }

    _initialized = true;
    _statusController.add('Ready.');
  }

  void dispose() {
    _statusController.close();
  }

  SyncEngine registerTable(TableConfig config) {
    _tables.add(config);
    return this;
  }

  Future<void> syncAll() async {
    _statusController.add('Starting Full Sync...');
    try {
      for (final table in _tables) {
        await syncTable(table);
      }
      _statusController.add('Sync completed successfully.');
    } catch (e) {
      _statusController.add('Critical Sync Error.');
      print('❌ SyncAll Error: $e');
    }
  }

  Future<void> syncTable(TableConfig config) async {
    await init();

    _statusController.add('Syncing ${config.name}...');
    try {
      await _pull(config);
      await _push(config);
    } catch (e) {
      _statusController.add('Error syncing ${config.name}');
      rethrow;
    }
  }

  Future<void> _pull(TableConfig config) async {
    _statusController.add('Downloading ${config.name}...');
    SyncCursor? cursor;

    while (true) {
      final result = await retry(() {
        return remoteAdapter.pull(
          PullRequest(
            table: config.name,
            columns: config.columns,
            primaryKey: config.primaryKey,
            updatedAtColumn: config.updatedAtColumn,
            cursor: cursor,
            limit: batchSize,
          ),
        );
      });

      if (result.records.isEmpty) break;

      final merged = <Map<String, dynamic>>[];

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

      for (final remote in result.records) {
        final idValue = remote[config.primaryKey];
        if (idValue == null) continue;

        final local = localRecordsMap[idValue.toString()];

        if (local == null) {
          merged.add(remote);
          continue;
        }

        final resolved = await _resolveConflict(config, local, remote);

        if (resolved != null) {
          merged.add(resolved);
        }
      }

      await localStore.upsertBatch(config.name, merged);

      cursor = result.nextCursor;
      if (cursor == null) break;
    }
  }

  Future<void> _push(TableConfig config) async {
    final dirty = await localStore.queryDirty(config.name);

    if (dirty.isNotEmpty) {
      _statusController.add('Uploading ${dirty.length} changes for ${config.name}...');
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
                config.updatedAtColumn: row[config.updatedAtColumn] ??
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
        print('⚠️ Sync Push failed for ${config.name} (ID: ${row[config.primaryKey]}): $e');
      }
    }
  }

  String _buildOperationId(TableConfig config, Map<String, dynamic> row) {
    final pk = row[config.primaryKey]?.toString() ?? 'unknown';
    final updatedAt = row[config.updatedAtColumn]?.toString() ?? '';
    final deletedAt = row[config.deletedAtColumn]?.toString() ?? '';
    return '${config.name}:$pk:$updatedAt:$deletedAt';
  }

  Future<Map<String, dynamic>?> _resolveConflict(
    TableConfig config,
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) async {
    final localDirty = local[isSyncedColumn] == 0 || local[isSyncedColumn] == false;
    if (!localDirty) {
      return remote;
    }

    switch (config.strategy) {
      case SyncStrategy.serverWins:
        return remote;
      case SyncStrategy.localWins:
        return null;
      case SyncStrategy.lastWriteWins:
        final localDateStr = local[config.updatedAtColumn]?.toString();
        final remoteDateStr = remote[config.updatedAtColumn]?.toString();

        final localDate = localDateStr != null ? DateTime.tryParse(localDateStr) : null;
        final remoteDate = remoteDateStr != null ? DateTime.tryParse(remoteDateStr) : null;

        if (remoteDate == null) return null;
        if (localDate == null) return remote;

        if (remoteDate.isAfter(localDate)) {
          return remote;
        }
        return null;
      case SyncStrategy.custom:
        if (config.customResolver != null) {
          return config.customResolver!(local, remote);
        }
        return remote;
    }
  }
}
