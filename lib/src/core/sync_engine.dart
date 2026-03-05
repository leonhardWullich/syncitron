import 'dart:async';

import '../adapters/remote_adapter.dart';
import '../storage/local_store.dart';
import '../utils/retry.dart';
import 'config.dart';
import 'exceptions.dart';
import 'logger.dart';
import 'metrics.dart';
import 'models.dart';
import 'sync_strategy.dart';
import 'sync_strategy_custom.dart';
import 'table_config.dart';

/// Enterprise-grade synchronization engine for local-first Flutter applications.
///
/// The SyncEngine orchestrates bidirectional data synchronization between
/// a local SQLite database and a remote backend (Supabase, REST APIs, etc.).
///
/// Key features:
/// - Configurable conflict resolution strategies
/// - Automatic retry with exponential backoff
/// - Comprehensive metrics and diagnostics
/// - Structured logging for analytics
/// - Custom sync strategies for domain-specific logic
/// - Prevents overlapping sync runs
/// - Thread-safe initialization
class SyncEngine {
  final LocalStore localStore;
  final RemoteAdapter remoteAdapter;
  final ReplicoreConfig config;
  final Logger logger;
  final MetricsCollector metricsCollector;

  final List<TableConfig> _tables = [];

  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  // Cached Future makes init() thread-safe: concurrent callers share the
  // same in-flight Future instead of running migration logic multiple times.
  Future<void>? _initFuture;

  // Prevents overlapping sync runs (e.g. connectivity event + periodic timer).
  bool _isSyncing = false;

  SyncEngine({
    required this.localStore,
    required this.remoteAdapter,
    ReplicoreConfig? config,
    Logger? logger,
    MetricsCollector? metricsCollector,
  }) : config = config ?? ReplicoreConfig(),
       logger = logger ?? ConsoleLogger(),
       metricsCollector = metricsCollector ?? InMemoryMetricsCollector() {
    if (this.config.validateOnCreation) {
      this.config.validate();
    }
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Initialises the engine exactly once, even when called concurrently.
  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    _emit('Initializing local database schema...');
    logger.info(
      'Initializing Replicore SyncEngine',
      context: {
        'batch_size': config.batchSize,
        'max_retries': config.maxRetries,
      },
    );

    for (final table in _tables) {
      try {
        await localStore.ensureSyncColumns(
          table.name,
          table.updatedAtColumn,
          table.deletedAtColumn,
        );
      } catch (e) {
        logger.error(
          'Failed to initialize schema for table ${table.name}',
          error: e,
        );
        rethrow;
      }
    }

    _emit('Initialization complete.');
    logger.info(
      'SyncEngine initialized successfully',
      context: {'tables_registered': _tables.length},
    );
  }

  void dispose() {
    _statusController.close();
  }

  // ── Configuration ──────────────────────────────────────────────────────────

  SyncEngine registerTable(TableConfig config) {
    if (config.strategy == SyncStrategy.custom &&
        config.customResolver == null) {
      throw EngineConfigurationException(
        'Table "${config.name}" uses SyncStrategy.custom '
        'but no customResolver was provided in TableConfig.',
      );
    }
    _tables.add(config);
    return this;
  }

  // ── Public sync API ────────────────────────────────────────────────────────

  /// Syncs all registered tables sequentially.
  ///
  /// Individual table failures are caught, logged, and do not prevent
  /// subsequent tables from syncing.
  /// Returns immediately if a sync is already running.
  ///
  /// Returns metrics for the entire sync session.
  Future<SyncSessionMetrics> syncAll() async {
    if (_isSyncing) {
      logger.warning('syncAll() skipped — sync already in progress');
      _emit('Sync skipped: already in progress');
      return SyncSessionMetrics();
    }

    _isSyncing = true;
    final sessionMetrics = SyncSessionMetrics();
    _emit('Starting Full Sync...');
    logger.info('Full sync started', context: {'tables': _tables.length});

    try {
      for (final table in _tables) {
        try {
          final metrics = await _syncTableInternal(table);
          sessionMetrics.addTableMetrics(metrics);
        } on ReplicoreException catch (e) {
          logger.error('Sync failed for ${table.name}', error: e);
          _emit('Error syncing ${table.name}.');
        } catch (e, st) {
          logger.error(
            'Unexpected error syncing ${table.name}',
            error: e,
            stackTrace: st,
          );
          _emit('Error syncing ${table.name}.');
        }
      }

      sessionMetrics.endTime = DateTime.now().toUtc();
      metricsCollector.recordSessionMetrics(sessionMetrics);

      if (sessionMetrics.overallSuccess) {
        _emit('Sync completed successfully.');
        logger.info('Sync completed', context: sessionMetrics.toJson());
      } else {
        _emit('Sync completed with errors.');
        logger.warning(
          'Sync completed with errors',
          context: sessionMetrics.toJson(),
        );
      }
    } finally {
      _isSyncing = false;
    }

    return sessionMetrics;
  }

  /// Syncs a single table by its [TableConfig].
  ///
  /// Throws [ReplicoreException] subclasses on failure so the caller can
  /// react to the specific error type (network, auth, schema, etc.).
  /// Returns immediately if a sync is already running.
  Future<SyncMetrics> syncTable(TableConfig config) async {
    if (_isSyncing) {
      logger.warning(
        'syncTable(${config.name}) skipped — sync already in progress',
      );
      _emit('Sync skipped: already in progress');
      return SyncMetrics(tableName: config.name);
    }

    _isSyncing = true;
    try {
      return await _syncTableInternal(config);
    } finally {
      _isSyncing = false;
    }
  }

  /// Syncs using a custom strategy.
  ///
  /// Allows domain-specific sync logic beyond the standard pull-push pattern.
  /// The strategy receives a context enabling controlled access to sync operations.
  ///
  /// Example:
  /// ```dart
  /// final metrics = await engine.syncWithStrategy(
  ///   OfflineFirstSyncStrategy(),
  /// );
  /// ```
  ///
  /// Throws [ReplicoreException] subclasses on failure.
  /// Returns metrics for the entire sync session.
  Future<SyncSessionMetrics> syncWithStrategy(
    CustomSyncStrategy strategy,
  ) async {
    if (_isSyncing) {
      logger.warning('Custom sync skipped — sync already in progress');
      _emit('Sync skipped: already in progress');
      return SyncSessionMetrics();
    }

    _isSyncing = true;
    final context = _SyncStrategyContextImpl(
      engine: this,
      logger: logger,
      metricsCollector: metricsCollector,
      tableNames: _tables.map((t) => t.name).toList(),
    );

    try {
      await strategy.beforeSync(context);
      final metrics = await strategy.execute(context);
      await strategy.afterSync(context, metrics);
      return metrics;
    } finally {
      _isSyncing = false;
    }
  }

  // ── Internal sync logic ────────────────────────────────────────────────────

  Future<SyncMetrics> _syncTableInternal(TableConfig config) async {
    await init();

    final metrics = SyncMetrics(tableName: config.name);
    _emit('Syncing ${config.name}...');
    logger.info('Starting sync for ${config.name}');

    try {
      await _pull(config, metrics);
      await _push(config, metrics);
      metrics.endTime = DateTime.now().toUtc();
      metricsCollector.recordTableMetrics(metrics);
      logger.info(
        'Sync completed for ${config.name}',
        context: metrics.toJson(),
      );
    } catch (e) {
      metrics.endTime = DateTime.now().toUtc();
      metrics.recordError(e.toString());
      metricsCollector.recordTableMetrics(metrics);
      logger.error('Sync failed for ${config.name}', error: e);
      rethrow;
    }

    return metrics;
  }

  // ── Pull ───────────────────────────────────────────────────────────────────

  Future<void> _pull(TableConfig config, SyncMetrics metrics) async {
    _emit('Downloading ${config.name}...');
    logger.debug('Starting pull for ${config.name}');

    // Strip sync-internal columns from the remote SELECT list so they never
    // overwrite locally managed state.
    final safeColumns = config.columns
        .where(
          (c) => c != config.isSyncedColumn && c != config.operationIdColumn,
        )
        .toList();

    SyncCursor? cursor;

    while (true) {
      // SyncNetworkException / SyncAuthException bubble up from the adapter.
      final result = await retry(
        () {
          return remoteAdapter.pull(
            PullRequest(
              table: config.name,
              columns: safeColumns,
              primaryKey: config.primaryKey,
              updatedAtColumn: config.updatedAtColumn,
              cursor: cursor,
              limit: this.config.batchSize,
            ),
          );
        },
        retries: this.config.maxRetries,
        initialDelay: this.config.initialRetryDelay,
        maxDelay: this.config.maxRetryDelay,
        logger: logger,
      );

      if (result.records.isEmpty) break;

      metrics.recordsPulled += result.records.length;
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
          merged.add({...remote, config.isSyncedColumn: 1});
          continue;
        }

        metrics.recordsWithConflicts++;
        final resolved = await _resolveConflict(config, local, remote);
        if (resolved != null) {
          metrics.conflictsResolved++;
          merged.add({...resolved, config.isSyncedColumn: 1});
        }
      }

      // LocalStoreException bubbles up from upsertBatch.
      await localStore.upsertBatch(config.name, merged);

      cursor = result.nextCursor;
      if (cursor == null) break;
    }

    logger.debug(
      'Pull completed for ${config.name}',
      context: {'records_pulled': metrics.recordsPulled},
    );
  }

  // ── Push ───────────────────────────────────────────────────────────────────

  Future<void> _push(TableConfig config, SyncMetrics metrics) async {
    final dirty = await localStore.queryDirty(config.name);

    if (dirty.isNotEmpty) {
      _emit('Uploading ${dirty.length} changes for ${config.name}...');
      metrics.recordsPushed = dirty.length;
      logger.debug(
        'Starting push for ${config.name}',
        context: {'dirty_records': dirty.length},
      );
    }

    for (final row in dirty) {
      try {
        final pkValue = row[config.primaryKey];
        if (pkValue == null) continue;

        var operationId = row[config.operationIdColumn]?.toString();
        operationId ??= _buildOperationId(config, row);
        await localStore.setOperationId(
          config.name,
          config.primaryKey,
          pkValue,
          operationId,
        );

        final uploadData = Map<String, dynamic>.from(row)
          ..remove(config.isSyncedColumn)
          ..remove(config.operationIdColumn);

        final isSoftDeleted = row[config.deletedAtColumn] != null;

        // SyncNetworkException / SyncAuthException thrown by the adapter
        // propagate through retry() and are caught in the per-row catch below.
        await retry(
          () async {
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
          },
          retries: this.config.maxRetries,
          initialDelay: this.config.initialRetryDelay,
          maxDelay: this.config.maxRetryDelay,
          logger: logger,
        );

        await localStore.markAsSynced(config.name, config.primaryKey, pkValue);
      } on SyncAuthException {
        // Auth errors affect all records — no point continuing the push loop.
        metrics.recordError('Auth error: session may have expired');
        rethrow;
      } on ReplicoreException catch (e) {
        // Per-row network/store error: log and keep the record dirty for the
        // next sync attempt.
        final errorMsg =
            'Push failed for ${config.name} (ID: ${row[config.primaryKey]}): $e';
        metrics.recordError(errorMsg);
        logger.warning(errorMsg, error: e);
      }
    }

    logger.debug('Push completed for ${config.name}');
  }

  // ── Conflict resolution ────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _resolveConflict(
    TableConfig config,
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) async {
    final localDirty =
        local[config.isSyncedColumn] == 0 ||
        local[config.isSyncedColumn] == false;

    if (!localDirty) return remote;

    switch (config.strategy) {
      case SyncStrategy.serverWins:
        return remote;

      case SyncStrategy.localWins:
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
        // registerTable() already guarantees customResolver is non-null here.
        try {
          final resolution = await config.customResolver!(local, remote);
          return switch (resolution) {
            UseLocal() => null,
            UseRemote(data: final d) => d,
            UseMerged(data: final d) => d,
          };
        } catch (e, st) {
          logger.error(
            'Custom conflict resolver failed',
            error: e,
            stackTrace: st,
          );
          throw ConflictResolutionException(
            table: config.name,
            primaryKey: remote[config.primaryKey],
            cause: e,
          );
        }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _emit(String message) {
    _statusController.add(message);
    _log(message);
  }

  void _log(String message) {
    logger.debug(message);
  }

  String _buildOperationId(TableConfig config, Map<String, dynamic> row) {
    final pk = row[config.primaryKey]?.toString() ?? 'unknown';
    final updatedAt = row[config.updatedAtColumn]?.toString() ?? '';
    final deletedAt = row[config.deletedAtColumn]?.toString() ?? '';
    return '${config.name}:$pk:$updatedAt:$deletedAt';
  }

  DateTime? _tryParseDate(String? value) =>
      value != null ? DateTime.tryParse(value) : null;
}

/// Internal implementation of SyncStrategyContext.
///
/// Provides safe, controlled access to sync operations for custom strategies.
class _SyncStrategyContextImpl extends SyncStrategyContext {
  final SyncEngine engine;
  @override
  final Logger logger;
  @override
  final MetricsCollector metricsCollector;
  @override
  final List<String> tableNames;
  @override
  final DateTime startTime;

  bool _cancelled = false;

  _SyncStrategyContextImpl({
    required this.engine,
    required this.logger,
    required this.metricsCollector,
    required this.tableNames,
  }) : startTime = DateTime.now().toUtc();

  @override
  Future<SyncMetrics> managedSyncTable(String tableName) async {
    final config = engine._tables.firstWhere(
      (t) => t.name == tableName,
      orElse: () => throw EngineConfigurationException(
        'Table "$tableName" not registered with this engine',
      ),
    );

    return engine._syncTableInternal(config);
  }

  @override
  Future<SyncSessionMetrics> managedSyncAll() async {
    final sessionMetrics = SyncSessionMetrics();

    for (final table in engine._tables) {
      if (!shouldContinue()) break;

      try {
        final metrics = await managedSyncTable(table.name);
        sessionMetrics.addTableMetrics(metrics);
      } catch (e, st) {
        logger.error('Failed to sync ${table.name}', error: e, stackTrace: st);
        sessionMetrics.totalErrors++;
      }
    }

    sessionMetrics.endTime = DateTime.now().toUtc();
    return sessionMetrics;
  }

  @override
  bool shouldContinue() => !_cancelled;

  @override
  void cancel() {
    _cancelled = true;
    logger.info('Sync strategy cancelled');
  }
}
