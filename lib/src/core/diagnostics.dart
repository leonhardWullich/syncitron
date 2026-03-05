import 'package:sqflite/sqflite.dart';

/// Represents the health status of a component.
enum HealthStatus { healthy, degraded, unhealthy }

/// Health check result for a single component.
class HealthCheckResult {
  final String component;
  final HealthStatus status;
  final String message;
  final DateTime timestamp;
  final Map<String, dynamic>? details;

  HealthCheckResult({
    required this.component,
    required this.status,
    required this.message,
    this.details,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
    'component': component,
    'status': status.name,
    'message': message,
    'timestamp': timestamp.toIso8601String(),
    'details': details,
  };

  @override
  String toString() {
    final statusStr = switch (status) {
      HealthStatus.healthy => '✓',
      HealthStatus.degraded => '⚠',
      HealthStatus.unhealthy => '✗',
    };
    return '$statusStr $component: $message';
  }
}

/// Aggregation of health checks for the entire system.
class SystemHealth {
  final DateTime timestamp;
  final Map<String, HealthCheckResult> results;

  SystemHealth({required this.results, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now().toUtc();

  HealthStatus get overallStatus {
    if (results.values.any((r) => r.status == HealthStatus.unhealthy)) {
      return HealthStatus.unhealthy;
    }
    if (results.values.any((r) => r.status == HealthStatus.degraded)) {
      return HealthStatus.degraded;
    }
    return HealthStatus.healthy;
  }

  bool get isHealthy => overallStatus == HealthStatus.healthy;

  Map<String, dynamic> toJson() => {
    'overall_status': overallStatus.name,
    'timestamp': timestamp.toIso8601String(),
    'checks': {
      for (var entry in results.entries) entry.key: entry.value.toJson(),
    },
  };

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('═══ SYSTEM HEALTH ═══');
    buffer.writeln('Status: ${overallStatus.name.toUpperCase()}');
    buffer.writeln('Timestamp: ${timestamp.toIso8601String()}');
    buffer.writeln('');
    for (var result in results.values) {
      buffer.writeln(result.toString());
    }
    return buffer.toString();
  }
}

/// Interface for providing diagnostic information.
abstract class DiagnosticsProvider {
  Future<HealthCheckResult> checkHealth();
  Future<Map<String, dynamic>> getDiagnostics();
}

/// Local database diagnostics.
class DatabaseDiagnosticsProvider implements DiagnosticsProvider {
  final Database database;

  DatabaseDiagnosticsProvider(this.database);

  @override
  Future<HealthCheckResult> checkHealth() async {
    try {
      await database.rawQuery('PRAGMA database_list');
      return HealthCheckResult(
        component: 'Database',
        status: HealthStatus.healthy,
        message: 'Database connection is healthy',
      );
    } catch (e) {
      return HealthCheckResult(
        component: 'Database',
        status: HealthStatus.unhealthy,
        message: 'Database connection failed',
        details: {'error': e.toString()},
      );
    }
  }

  @override
  Future<Map<String, dynamic>> getDiagnostics() async {
    try {
      final tableList = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );

      int totalRows = 0;
      final tableSizes = <String, int>{};

      for (var table in tableList) {
        final tableName = table['name'] as String;
        try {
          final result = await database.rawQuery(
            'SELECT COUNT(*) as count FROM $tableName',
          );
          final count = (result.first['count'] as int?) ?? 0;
          tableSizes[tableName] = count;
          totalRows += count;
        } catch (_) {
          // Skip system tables
        }
      }

      return {
        'database_type': 'SQLite',
        'status': 'healthy',
        'tables': tableList.length,
        'total_rows': totalRows,
        'table_details': tableSizes,
      };
    } catch (e) {
      return {'status': 'error', 'error': e.toString()};
    }
  }
}

/// Sync diagnostics provider.
class SyncDiagnosticsProvider implements DiagnosticsProvider {
  final bool _lastSyncSuccessful;
  final DateTime? _lastSyncTime;
  final Map<String, dynamic>? _lastSyncMetrics;

  SyncDiagnosticsProvider({
    bool lastSyncSuccessful = true,
    DateTime? lastSyncTime,
    Map<String, dynamic>? lastSyncMetrics,
  }) : _lastSyncSuccessful = lastSyncSuccessful,
       _lastSyncTime = lastSyncTime,
       _lastSyncMetrics = lastSyncMetrics;

  @override
  Future<HealthCheckResult> checkHealth() async {
    if (!_lastSyncSuccessful) {
      return HealthCheckResult(
        component: 'Sync Engine',
        status: HealthStatus.degraded,
        message: 'Last sync failed',
        details: _lastSyncMetrics,
      );
    }

    if (_lastSyncTime == null) {
      return HealthCheckResult(
        component: 'Sync Engine',
        status: HealthStatus.degraded,
        message: 'No sync has been performed yet',
      );
    }

    final timeSinceLastSync = DateTime.now().difference(_lastSyncTime);
    if (timeSinceLastSync.inHours > 24) {
      return HealthCheckResult(
        component: 'Sync Engine',
        status: HealthStatus.degraded,
        message: 'Last sync was ${timeSinceLastSync.inHours} hours ago',
      );
    }

    return HealthCheckResult(
      component: 'Sync Engine',
      status: HealthStatus.healthy,
      message: 'Sync engine is healthy',
    );
  }

  @override
  Future<Map<String, dynamic>> getDiagnostics() async {
    return {
      'last_sync_successful': _lastSyncSuccessful,
      'last_sync_time': _lastSyncTime?.toIso8601String(),
      if (_lastSyncMetrics != null) 'last_sync_metrics': _lastSyncMetrics,
    };
  }
}

/// Comprehensive system diagnostics provider.
class SystemDiagnosticsProvider implements DiagnosticsProvider {
  final List<DiagnosticsProvider> providers;

  SystemDiagnosticsProvider(this.providers);

  @override
  Future<HealthCheckResult> checkHealth() async {
    final results = <HealthCheckResult>[];
    for (var provider in providers) {
      results.add(await provider.checkHealth());
    }

    final hasUnhealthy = results.any((r) => r.status == HealthStatus.unhealthy);
    final hasDegraded = results.any((r) => r.status == HealthStatus.degraded);

    final status = hasUnhealthy
        ? HealthStatus.unhealthy
        : hasDegraded
        ? HealthStatus.degraded
        : HealthStatus.healthy;

    return HealthCheckResult(
      component: 'System',
      status: status,
      message: switch (status) {
        HealthStatus.healthy => 'All systems operational',
        HealthStatus.degraded =>
          '${results.where((r) => r.status == HealthStatus.degraded).length} components degraded',
        HealthStatus.unhealthy =>
          '${results.where((r) => r.status == HealthStatus.unhealthy).length} components unhealthy',
      },
      details: {
        'checks': {
          for (var result in results) result.component: result.toJson(),
        },
      },
    );
  }

  @override
  Future<Map<String, dynamic>> getDiagnostics() async {
    final diagnostics = <String, dynamic>{};
    for (var provider in providers) {
      final diag = await provider.getDiagnostics();
      diagnostics.addAll(diag);
    }
    return diagnostics;
  }
}
