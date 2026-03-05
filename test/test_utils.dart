import 'package:replicore/replicore.dart';

/// Mock LocalStore for testing
class MockLocalStore implements LocalStore {
  final Map<String, List<Map<String, dynamic>>> _tables = {};
  final Map<String, SyncCursor?> _cursors = {};
  bool throwOnQuery = false;
  bool throwOnUpsert = false;

  @override
  Future<void> ensureSyncColumns(
    String table,
    String updatedAtColumn,
    String deletedAtColumn,
  ) async {
    if (throwOnQuery) throw Exception('Mock error');
    _tables[table] ??= [];
  }

  @override
  Future<SyncCursor?> readCursor(String table) async {
    if (throwOnQuery) throw Exception('Mock error');
    return _cursors[table];
  }

  @override
  Future<void> writeCursor(String table, SyncCursor cursor) async {
    if (throwOnUpsert) throw Exception('Mock error');
    _cursors[table] = cursor;
  }

  @override
  Future<void> clearCursor(String table) async {
    _cursors[table] = null;
  }

  @override
  Future<List<Map<String, dynamic>>> queryDirty(String table) async {
    if (throwOnQuery) throw Exception('Mock error');
    final tableData = _tables[table] ?? [];
    return tableData.where((row) => (row['is_synced'] as int?) == 0).toList();
  }

  @override
  Future<void> upsertBatch(
    String table,
    List<Map<String, dynamic>> records,
  ) async {
    if (throwOnUpsert) throw Exception('Mock error');
    _tables[table] ??= [];
    for (final record in records) {
      final idx = _tables[table]!.indexWhere((r) => r['id'] == record['id']);
      if (idx >= 0) {
        _tables[table]![idx] = record;
      } else {
        _tables[table]!.add(record);
      }
    }
  }

  @override
  Future<void> markAsSynced(
    String table,
    String pkColumn,
    dynamic primaryKey,
  ) async {
    if (throwOnUpsert) throw Exception('Mock error');
    final tableData = _tables[table] ?? [];
    for (final row in tableData) {
      if (row[pkColumn] == primaryKey) {
        row['is_synced'] = 1;
      }
    }
  }

  @override
  Future<void> setOperationId(
    String table,
    String pkColumn,
    dynamic primaryKey,
    String operationId,
  ) async {
    if (throwOnUpsert) throw Exception('Mock error');
  }

  @override
  Future<Map<String, dynamic>?> findById(
    String table,
    String pkColumn,
    dynamic id,
  ) async {
    if (throwOnQuery) throw Exception('Mock error');
    final tableData = _tables[table] ?? [];
    try {
      return tableData.firstWhere((row) => row[pkColumn] == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> findManyByIds(
    String table,
    String pkColumn,
    List<dynamic> ids,
  ) async {
    if (throwOnQuery) throw Exception('Mock error');
    final tableData = _tables[table] ?? [];
    return tableData.where((row) => ids.contains(row[pkColumn])).toList();
  }

  // Test helper to insert data without sync
  void insertTest(String tableName, List<Map<String, dynamic>> records) {
    _tables[tableName] ??= [];
    _tables[tableName]!.addAll(records);
  }

  // Test helper to get table
  List<Map<String, dynamic>> table(String name) => _tables[name] ?? [];
}

/// Mock RemoteAdapter for testing
class MockRemoteAdapter implements RemoteAdapter {
  final Map<String, List<Map<String, dynamic>>> remoteTables = {};
  final List<PullRequest> pullRequests = [];
  final List<Map<String, dynamic>> upsertedData = [];
  final List<Map<String, dynamic>> deletedData = [];
  bool throwOnPull = false;
  bool throwOnUpsert = false;

  @override
  RealtimeSubscriptionProvider? getRealtimeProvider() => null;

  @override
  Future<PullResult> pull(PullRequest request) async {
    if (throwOnPull) {
      throw SyncNetworkException(
        table: request.table,
        message: 'Mock network error',
      );
    }
    pullRequests.add(request);

    final table = remoteTables[request.table] ?? [];
    final records = table.take(request.limit).toList();

    return PullResult(
      records: records,
      nextCursor: records.length >= request.limit
          ? SyncCursor(
              updatedAt: DateTime.now().toUtc(),
              primaryKey: 'next_cursor',
            )
          : null,
    );
  }

  @override
  Future<void> upsert({
    required String table,
    required Map<String, dynamic> data,
    String? idempotencyKey,
  }) async {
    if (throwOnUpsert) {
      throw SyncNetworkException(table: table, message: 'Mock network error');
    }
    upsertedData.add(data);
    remoteTables[table] ??= [];
    final idx = remoteTables[table]!.indexWhere((r) => r['id'] == data['id']);
    if (idx >= 0) {
      remoteTables[table]![idx] = data;
    } else {
      remoteTables[table]!.add(data);
    }
  }

  @override
  Future<void> softDelete({
    required String table,
    required String primaryKeyColumn,
    required dynamic id,
    required Map<String, dynamic> payload,
    String? idempotencyKey,
  }) async {
    if (throwOnUpsert) {
      throw SyncNetworkException(table: table, message: 'Mock network error');
    }
    deletedData.add(payload);
    final tableData = remoteTables[table] ?? [];
    for (final row in tableData) {
      if (row[primaryKeyColumn] == id) {
        row['deleted_at'] = payload['deleted_at'];
        row['updated_at'] = payload['updated_at'];
      }
    }
  }
}

/// Mock Logger for testing
class MockLogger implements Logger {
  final List<LogEntry> logs = [];
  bool captureAll = true;

  @override
  void info(String message, {Map<String, dynamic>? context}) {
    if (captureAll) {
      logs.add(
        LogEntry(level: LogLevel.info, message: message, context: context),
      );
    }
  }

  @override
  void warning(
    String message, {
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    if (captureAll || message.contains('Warning')) {
      logs.add(
        LogEntry(
          level: LogLevel.warning,
          message: message,
          error: error,
          context: context,
        ),
      );
    }
  }

  @override
  void error(
    String message, {
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    if (captureAll) {
      logs.add(
        LogEntry(
          level: LogLevel.error,
          message: message,
          error: error,
          context: context,
        ),
      );
    }
  }

  @override
  void debug(String message, {Map<String, dynamic>? context}) {
    if (captureAll) {
      logs.add(
        LogEntry(level: LogLevel.debug, message: message, context: context),
      );
    }
  }

  @override
  void critical(String message, {Object? error, StackTrace? stackTrace}) {
    logs.add(
      LogEntry(
        level: LogLevel.critical,
        message: message,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  void log(LogEntry entry) {
    logs.add(entry);
  }

  // Test helper
  List<LogEntry> getKeywordLogs(String keyword) =>
      logs.where((l) => l.message.contains(keyword)).toList();

  int countByLevel(LogLevel level) =>
      logs.where((l) => l.level == level).length;
}

/// Mock MetricsCollector for testing
class MockMetricsCollector implements MetricsCollector {
  final List<SyncMetrics> tableMetrics = [];
  final List<SyncSessionMetrics> sessionMetrics = [];

  @override
  void recordTableMetrics(SyncMetrics metrics) {
    tableMetrics.add(metrics);
  }

  @override
  void recordSessionMetrics(SyncSessionMetrics metrics) {
    sessionMetrics.add(metrics);
  }

  @override
  SyncSessionMetrics? getLastSessionMetrics() =>
      sessionMetrics.isNotEmpty ? sessionMetrics.last : null;

  SyncMetrics? lastTableMetrics() =>
      tableMetrics.isNotEmpty ? tableMetrics.last : null;
}

/// Test data factory
class TestDataFactory {
  static TableConfig testTable({
    String name = 'todos',
    String primaryKey = 'id',
  }) {
    return TableConfig(
      name: name,
      columns: [
        primaryKey,
        'title',
        'is_done',
        'created_at',
        'updated_at',
        'deleted_at',
      ],
      primaryKey: primaryKey,
      strategy: SyncStrategy.lastWriteWins,
    );
  }

  static Map<String, dynamic> testRecord({
    String id = '1',
    String title = 'Test Todo',
    bool isDone = false,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    return {
      'id': id,
      'title': title,
      'is_done': isDone,
      'is_synced': 1,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
    };
  }

  static List<Map<String, dynamic>> testRecords(int count) {
    return [
      for (int i = 0; i < count; i++) testRecord(id: 'id_$i', title: 'Todo $i'),
    ];
  }
}
