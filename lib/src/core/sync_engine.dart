import '../adapters/remote_adapter.dart';
import '../storage/local_store.dart';
import '../utils/retry.dart';
import 'models.dart';
import 'table_config.dart';
import 'sync_strategy.dart';

class SyncEngine {
  final LocalStore localStore;
  final RemoteAdapter remoteAdapter;
  final int batchSize;

  final List<TableConfig> _tables = [];

  SyncEngine({
    required this.localStore,
    required this.remoteAdapter,
    this.batchSize = 500,
  });

  SyncEngine registerTable(TableConfig config) {
    _tables.add(config);
    return this;
  }

  Future<void> syncAll() async {
    for (final table in _tables) {
      await syncTable(table);
    }
  }

  Future<void> syncTable(TableConfig config) async {
    await _pull(config);
    await _push(config);
  }

  Future<void> _pull(TableConfig config) async {
    SyncCursor? cursor;

    while (true) {
      final result = await retry(() {
        return remoteAdapter.pull(
          PullRequest(
            table: config.name,
            columns: config.columns,
            cursor: cursor,
            limit: batchSize,
          ),
        );
      });

      if (result.records.isEmpty) break;

      final merged = <Map<String, dynamic>>[];

      for (final remote in result.records) {
        final local = await localStore.findById(
          config.name,
          remote[config.primaryKey],
        );

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

    for (final row in dirty) {
      await retry(() {
        return remoteAdapter.upsert(table: config.name, data: row);
      });

      await localStore.markAsSynced(config.name, row[config.primaryKey]);
    }
  }

  Future<Map<String, dynamic>?> _resolveConflict(
    TableConfig config,
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) async {
    switch (config.strategy) {
      case SyncStrategy.serverWins:
        return remote;

      case SyncStrategy.localWins:
        return null;

      case SyncStrategy.lastWriteWins:
        final localDate = DateTime.tryParse(local['updated_at'] ?? '');
        final remoteDate = DateTime.tryParse(remote['updated_at'] ?? '');

        if (remoteDate != null &&
            localDate != null &&
            remoteDate.isAfter(localDate)) {
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
