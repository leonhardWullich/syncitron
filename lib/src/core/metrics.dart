/// Metrics for monitoring Replicore's sync performance.
class SyncMetrics {
  final String tableName;
  final DateTime startTime;
  late DateTime endTime;

  int recordsPulled = 0;
  int recordsPushed = 0;
  int recordsWithConflicts = 0;
  int conflictsResolved = 0;
  int errors = 0;

  List<String> errorMessages = [];

  SyncMetrics({required this.tableName, DateTime? startTime})
    : startTime = startTime ?? DateTime.now().toUtc() {
    endTime = this.startTime;
  }

  Duration get duration => endTime.difference(startTime);

  bool get success => errors == 0;

  int get totalRecordsProcessed => recordsPulled + recordsPushed;

  Map<String, dynamic> toJson() => {
    'table': tableName,
    'duration_ms': duration.inMilliseconds,
    'records_pulled': recordsPulled,
    'records_pushed': recordsPushed,
    'conflicts': recordsWithConflicts,
    'conflicts_resolved': conflictsResolved,
    'errors': errors,
    'total_processed': totalRecordsProcessed,
    'success': success,
  };

  void recordError(String message) {
    errors++;
    errorMessages.add(message);
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('Sync Metrics for $tableName:');
    buffer.writeln('  Duration: ${duration.inMilliseconds}ms');
    buffer.writeln('  Records Pulled: $recordsPulled');
    buffer.writeln('  Records Pushed: $recordsPushed');
    buffer.writeln('  Conflicts: $recordsWithConflicts');
    buffer.writeln('  Resolved: $conflictsResolved');
    buffer.writeln('  Errors: $errors');
    buffer.writeln('  Status: ${success ? "✓ SUCCESS" : "✗ FAILED"}');
    if (errorMessages.isNotEmpty) {
      buffer.writeln('  Error Details:');
      for (var msg in errorMessages) {
        buffer.writeln('    - $msg');
      }
    }
    return buffer.toString();
  }
}

/// Aggregated metrics for the entire sync session.
class SyncSessionMetrics {
  final DateTime startTime;
  late DateTime endTime;

  final List<SyncMetrics> tableMetrics = [];
  int totalErrors = 0;

  SyncSessionMetrics({DateTime? startTime})
    : startTime = startTime ?? DateTime.now().toUtc() {
    endTime = this.startTime;
  }

  Duration get totalDuration => endTime.difference(startTime);

  int get totalTablesSynced => tableMetrics.length;

  int get totalRecordsPulled =>
      tableMetrics.fold(0, (sum, m) => sum + m.recordsPulled);

  int get totalRecordsPushed =>
      tableMetrics.fold(0, (sum, m) => sum + m.recordsPushed);

  int get totalConflicts =>
      tableMetrics.fold(0, (sum, m) => sum + m.recordsWithConflicts);

  bool get overallSuccess =>
      totalErrors == 0 && tableMetrics.every((m) => m.success);

  void addTableMetrics(SyncMetrics metrics) {
    tableMetrics.add(metrics);
    totalErrors += metrics.errors;
  }

  Map<String, dynamic> toJson() => {
    'total_duration_ms': totalDuration.inMilliseconds,
    'tables_synced': totalTablesSynced,
    'total_records_pulled': totalRecordsPulled,
    'total_records_pushed': totalRecordsPushed,
    'total_conflicts': totalConflicts,
    'total_errors': totalErrors,
    'success': overallSuccess,
    'table_details': tableMetrics.map((m) => m.toJson()).toList(),
  };

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('═══ SYNC SESSION SUMMARY ═══');
    buffer.writeln('Duration: ${totalDuration.inMilliseconds}ms');
    buffer.writeln('Tables: $totalTablesSynced');
    buffer.writeln('Total Pulled: $totalRecordsPulled');
    buffer.writeln('Total Pushed: $totalRecordsPushed');
    buffer.writeln('Total Conflicts: $totalConflicts');
    buffer.writeln('Total Errors: $totalErrors');
    buffer.writeln('Status: ${overallSuccess ? "✓ SUCCESS" : "✗ FAILED"}');
    buffer.writeln('');
    for (var metrics in tableMetrics) {
      buffer.write(metrics.toString());
    }
    return buffer.toString();
  }
}

/// Abstract interface for metrics collection and reporting.
abstract class MetricsCollector {
  void recordTableMetrics(SyncMetrics metrics);
  void recordSessionMetrics(SyncSessionMetrics metrics);
  SyncSessionMetrics? getLastSessionMetrics();
}

/// Default in-memory metrics collector.
class InMemoryMetricsCollector implements MetricsCollector {
  final List<SyncSessionMetrics> _sessions = [];
  SyncSessionMetrics? _currentSession;

  @override
  void recordTableMetrics(SyncMetrics metrics) {
    _currentSession?.addTableMetrics(metrics);
  }

  @override
  void recordSessionMetrics(SyncSessionMetrics metrics) {
    _sessions.add(metrics);
    _currentSession = metrics;
  }

  @override
  SyncSessionMetrics? getLastSessionMetrics() => _currentSession;

  List<SyncSessionMetrics> getAllSessions() => _sessions;

  void clear() {
    _sessions.clear();
    _currentSession = null;
  }
}

/// No-op metrics collector for production (disable metrics).
class NoOpMetricsCollector implements MetricsCollector {
  const NoOpMetricsCollector();

  @override
  void recordTableMetrics(SyncMetrics metrics) {}

  @override
  void recordSessionMetrics(SyncSessionMetrics metrics) {}

  @override
  SyncSessionMetrics? getLastSessionMetrics() => null;
}
