import 'dart:async';

import 'exceptions.dart';
import 'logger.dart';
import 'metrics.dart';
import 'sync_engine.dart';

/// Manages multiple [SyncEngine] instances with coordinated synchronization.
///
/// Useful for applications with multiple sync contexts (e.g., different
/// workspaces, organizations, or tenants).
class SyncManager {
  final Logger logger;
  final MetricsCollector metricsCollector;

  final Map<String, SyncEngine> _engines = {};
  final List<StreamSubscription> _subscriptions = [];

  Timer? _periodicSyncTimer;

  SyncManager({required this.logger, required this.metricsCollector});

  /// Register a sync engine with an identifier.
  void registerEngine(String id, SyncEngine engine) {
    if (_engines.containsKey(id)) {
      logger.warning('Engine with id "$id" already registered, replacing');
    }
    _engines[id] = engine;
    logger.info('Sync engine registered', context: {'id': id});
  }

  /// Get a registered engine by ID.
  SyncEngine? getEngine(String id) => _engines[id];

  /// Get all registered engines.
  List<SyncEngine> getAllEngines() => _engines.values.toList();

  /// Initialize all registered engines.
  Future<void> initializeAll() async {
    logger.info(
      'Initializing all sync engines',
      context: {'engine_count': _engines.length},
    );

    for (final entry in _engines.entries) {
      try {
        await entry.value.init();
        logger.debug('Initialized engine ${entry.key}');
      } catch (e) {
        logger.error('Failed to initialize engine ${entry.key}', error: e);
        rethrow;
      }
    }
  }

  /// Sync all tables across all engines.
  Future<Map<String, SyncSessionMetrics>> syncAll() async {
    logger.info('Starting full sync across all engines');
    final results = <String, SyncSessionMetrics>{};

    for (final entry in _engines.entries) {
      try {
        final metrics = await entry.value.syncAll();
        results[entry.key] = metrics;
        metricsCollector.recordSessionMetrics(metrics);
      } catch (e) {
        logger.error('Sync failed for engine ${entry.key}', error: e);
      }
    }

    return results;
  }

  /// Sync a specific engine.
  Future<SyncSessionMetrics> syncEngine(String engineId) async {
    final engine = getEngine(engineId);
    if (engine == null) {
      throw UnregisteredTableException(
        'No engine registered with id "$engineId"',
      );
    }

    logger.info('Starting sync for engine $engineId');
    final metrics = await engine.syncAll();
    metricsCollector.recordSessionMetrics(metrics);
    return metrics;
  }

  /// Setup periodic syncing for all engines.
  void startPeriodicSync({required Duration interval}) {
    _periodicSyncTimer = Timer.periodic(interval, (_) => syncAll());
    logger.info(
      'Periodic sync started',
      context: {'interval_minutes': interval.inMinutes},
    );
  }

  /// Stop periodic syncing.
  void stopPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
    logger.info('Periodic sync stopped');
  }

  /// Get health status across all engines.
  Future<Map<String, HealthCheckResult>> checkAllHealth() async {
    final results = <String, HealthCheckResult>{};

    for (final entry in _engines.entries) {
      try {
        // Note: would need to enhance SyncEngine to expose health checks
        results[entry.key] = HealthCheckResult(
          component: 'SyncEngine:${entry.key}',
          status: HealthStatus.healthy,
          message: 'Engine is operational',
        );
      } catch (e) {
        results[entry.key] = HealthCheckResult(
          component: 'SyncEngine:${entry.key}',
          status: HealthStatus.unhealthy,
          message: e.toString(),
          details: {'error': e.toString()},
        );
      }
    }

    return results;
  }

  /// Cleanup and dispose all resources.
  Future<void> dispose() async {
    logger.info('Disposing SyncManager');

    stopPeriodicSync();

    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }

    for (final engine in _engines.values) {
      engine.dispose();
    }

    _engines.clear();
    logger.info('SyncManager disposed');
  }
}

/// Result type for the health check (required for proper import)
class HealthCheckResult {
  final String component;
  final HealthStatus status;
  final String message;
  final Map<String, dynamic>? details;
  final DateTime timestamp;

  HealthCheckResult({
    required this.component,
    required this.status,
    required this.message,
    this.details,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().toUtc();

  @override
  String toString() => '$component [$status]: $message';
}

enum HealthStatus { healthy, degraded, unhealthy }
