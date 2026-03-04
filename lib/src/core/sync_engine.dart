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

      // OPTIMIERUNG: N+1 Problem behoben! Alle lokalen Datensätze auf einmal laden.
      final remoteIds = result.records
          .map((r) => r[config.primaryKey])
          .where((id) => id != null)
          .toList();

      final localRecords = await localStore.findManyByIds(
        config.name,
        config.primaryKey,
        remoteIds,
      );

      // Für schnellen Lookup als Map konvertieren
      final localRecordsMap = {
        for (var row in localRecords) row[config.primaryKey].toString(): row,
      };

      for (final remote in result.records) {
        final idKey = remote[config.primaryKey].toString();
        final local = localRecordsMap[idKey];

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
      // FEHLERTOLERANZ: Fehler eines Datensatzes crasht nicht den ganzen Sync
      try {
        final pkValue = row[config.primaryKey];
        if (pkValue == null) continue;

        // Kopie erstellen und lokale Hilfsspalten entfernen, die nicht zum Server sollen
        final uploadData = Map<String, dynamic>.from(row);
        uploadData.remove('is_synced');

        final isSoftDeleted = row[config.deletedAtColumn] != null;

        await retry(() async {
          if (isSoftDeleted) {
            // SOFT DELETE SUPPORT
            await remoteAdapter.softDelete(
              table: config.name,
              id: pkValue,
              payload: {
                config.deletedAtColumn: row[config.deletedAtColumn],
                config.updatedAtColumn:
                    row[config.updatedAtColumn] ??
                    DateTime.now().toUtc().toIso8601String(),
              },
            );
          } else {
            // NORMALER UPSERT
            await remoteAdapter.upsert(table: config.name, data: uploadData);
          }
        });

        // Nach erfolgreichem Push lokal als gesynct markieren
        await localStore.markAsSynced(config.name, config.primaryKey, pkValue);
      } catch (e) {
        // Hier in Produktion loggen (z.B. Sentry oder Print)
        print(
          '⚠️ Sync Push failed for ${config.name} (ID: ${row[config.primaryKey]}): $e',
        );
      }
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
        // Dynamische Nutzung der konfigurierten Timestamps
        final localDateStr = local[config.updatedAtColumn]?.toString();
        final remoteDateStr = remote[config.updatedAtColumn]?.toString();

        final localDate = localDateStr != null
            ? DateTime.tryParse(localDateStr)
            : null;
        final remoteDate = remoteDateStr != null
            ? DateTime.tryParse(remoteDateStr)
            : null;

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
