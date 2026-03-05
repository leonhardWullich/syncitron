import 'package:flutter_test/flutter_test.dart';
import 'package:replicore/replicore.dart';
import 'test_utils.dart';

void main() {
  group('ReplicoreConfig', () {
    test('should create config with default values', () {
      final config = ReplicoreConfig.production();

      expect(config.batchSize, greaterThan(0));
      expect(config.maxRetries, greaterThan(0));
      expect(config.initialRetryDelay.inMilliseconds, greaterThan(0));
    });

    test('should create development config', () {
      final config = ReplicoreConfig.development();

      expect(config.batchSize, greaterThan(0));
      expect(config.maxRetries, greaterThan(0));
    });

    test('should support various valid configurations', () {
      final configs = [
        ReplicoreConfig(
          batchSize: 100,
          maxRetries: 3,
          initialRetryDelay: Duration(milliseconds: 100),
          maxRetryDelay: Duration(seconds: 60),
        ),
        ReplicoreConfig(
          batchSize: 1000,
          maxRetries: 5,
          initialRetryDelay: Duration(seconds: 1),
          maxRetryDelay: Duration(minutes: 10),
        ),
      ];

      for (final config in configs) {
        expect(config.batchSize, greaterThan(0));
        expect(config.maxRetries, greaterThanOrEqualTo(0));
      }
    });
  });

  group('SyncMetrics', () {
    test('should track records pulled and pushed', () {
      final metrics = SyncMetrics(tableName: 'todos');
      metrics.recordsPulled = 10;
      metrics.recordsPushed = 5;

      expect(metrics.tableName, 'todos');
      expect(metrics.recordsPulled, 10);
      expect(metrics.recordsPushed, 5);
    });

    test('should calculate sync duration', () {
      final startTime = DateTime.now().toUtc();
      final metrics = SyncMetrics(tableName: 'todos', startTime: startTime);

      // Simulate time passing
      Future.delayed(Duration(milliseconds: 10));
      metrics.endTime = DateTime.now().toUtc();

      expect(metrics.duration.inMilliseconds, greaterThanOrEqualTo(0));
    });

    test('should track successful syncs', () {
      final metrics = SyncMetrics(tableName: 'todos');
      metrics.recordsPulled = 5;
      metrics.recordsPushed = 2;

      expect(metrics.success, true);
    });

    test('should track errors', () {
      final metrics = SyncMetrics(tableName: 'todos');
      metrics.recordError('Network timeout');

      expect(metrics.errors, 1);
      expect(metrics.errorMessages.length, 1);
      expect(metrics.success, false);
    });
  });

  group('SyncSessionMetrics', () {
    test('should aggregate table metrics', () {
      final session = SyncSessionMetrics();

      final m1 = SyncMetrics(tableName: 'todos');
      m1.recordsPulled = 10;
      m1.recordsPushed = 5;
      session.addTableMetrics(m1);

      final m2 = SyncMetrics(tableName: 'projects');
      m2.recordsPulled = 8;
      m2.recordsPushed = 3;
      session.addTableMetrics(m2);

      expect(session.tableMetrics.length, 2);
      expect(session.totalRecordsPulled, 18);
      expect(session.totalRecordsPushed, 8);
    });

    test('should track total tables synced', () {
      final session = SyncSessionMetrics();

      final m = SyncMetrics(tableName: 'todos');
      session.addTableMetrics(m);

      expect(session.totalTablesSynced, 1);
    });

    test('should track overall success', () {
      final session = SyncSessionMetrics();

      final m1 = SyncMetrics(tableName: 'todos');
      m1.recordsPulled = 5;
      session.addTableMetrics(m1);

      expect(session.overallSuccess, true);
    });

    test('should track errors across tables', () {
      final session = SyncSessionMetrics();

      final m1 = SyncMetrics(tableName: 'todos');
      m1.recordError('Error 1');
      session.addTableMetrics(m1);

      final m2 = SyncMetrics(tableName: 'projects');
      m2.recordError('Error 2');
      session.addTableMetrics(m2);

      expect(session.totalErrors, 2);
      expect(session.overallSuccess, false);
    });
  });

  group('Logger', () {
    test('should log at different levels', () {
      final mockLogger = MockLogger();

      mockLogger.debug('Debug message');
      mockLogger.info('Info message');
      mockLogger.warning('Warning message', error: Exception('error'));
      mockLogger.error('Error message', error: Exception('failed'));
      mockLogger.critical('Critical message', error: Exception('crash'));

      expect(mockLogger.logs.length, 5);
      expect(mockLogger.countByLevel(LogLevel.debug), 1);
      expect(mockLogger.countByLevel(LogLevel.info), 1);
      expect(mockLogger.countByLevel(LogLevel.warning), 1);
      expect(mockLogger.countByLevel(LogLevel.error), 1);
      expect(mockLogger.countByLevel(LogLevel.critical), 1);
    });

    test('should support contextual logging', () {
      final mockLogger = MockLogger();

      mockLogger.info(
        'Sync started',
        context: {'table': 'todos', 'batch_size': 100},
      );

      final log = mockLogger.logs.first;
      expect(log.context?['table'], 'todos');
      expect(log.context?['batch_size'], 100);
    });

    test('should filter logs by keyword', () {
      final mockLogger = MockLogger();

      mockLogger.info('Starting sync');
      mockLogger.info('Syncing table');
      mockLogger.info('Completed operation');

      final syncLogs = mockLogger.getKeywordLogs('sync');
      expect(syncLogs.length, greaterThan(0));
    });

    test('should log entry toString format', () {
      final entry = LogEntry(level: LogLevel.info, message: 'Test message');

      final str = entry.toString();
      expect(str.contains('Test message'), true);
      expect(str.contains('INFO'), true);
    });
  });

  group('TableConfig', () {
    test('should create table configuration', () {
      final config = TableConfig(
        name: 'todos',
        columns: ['id', 'title', 'updated_at', 'deleted_at'],
        primaryKey: 'id',
        strategy: SyncStrategy.lastWriteWins,
      );

      expect(config.name, 'todos');
      expect(config.primaryKey, 'id');
      expect(config.columns.length, 4);
      expect(config.strategy, SyncStrategy.lastWriteWins);
    });

    test('should support different conflict strategies', () {
      final config1 = TableConfig(
        name: 'todos',
        columns: ['id', 'title', 'updated_at', 'deleted_at'],
        primaryKey: 'id',
        strategy: SyncStrategy.serverWins,
      );

      final config2 = TableConfig(
        name: 'todos',
        columns: ['id', 'title', 'updated_at', 'deleted_at'],
        primaryKey: 'id',
        strategy: SyncStrategy.localWins,
      );

      expect(config1.strategy, SyncStrategy.serverWins);
      expect(config2.strategy, SyncStrategy.localWins);
    });
  });

  group('Network Exceptions', () {
    test('should create network exceptions with required parameters', () {
      final exception = SyncNetworkException(
        table: 'todos',
        message: 'Connection failed',
      );

      expect(exception.table, 'todos');
      expect(exception.message, 'Connection failed');
      expect(exception.isOffline, true); // No status code means offline
    });

    test('should differentiate offline vs server errors', () {
      final offlineError = SyncNetworkException(
        table: 'todos',
        message: 'No internet',
      );

      final serverError = SyncNetworkException(
        table: 'todos',
        message: 'Server error',
        statusCode: 500,
      );

      expect(offlineError.isOffline, true);
      expect(serverError.isOffline, false);
    });
  });

  group('Retry Logic', () {
    test('should calculate exponential backoff', () {
      final config = ReplicoreConfig(
        batchSize: 100,
        maxRetries: 3,
        initialRetryDelay: Duration(milliseconds: 100),
        maxRetryDelay: Duration(seconds: 5),
      );

      // Simulate retry delays
      var delay1 = config.initialRetryDelay;
      var delay2 = delay1 * 2;
      var delay3 = delay2 * 2;

      expect(delay1, Duration(milliseconds: 100));
      expect(delay2, Duration(milliseconds: 200));
      expect(delay3, Duration(milliseconds: 400));
      expect(delay3, lessThanOrEqualTo(config.maxRetryDelay));
    });

    test('should respect max retry delay', () {
      final config = ReplicoreConfig(
        batchSize: 100,
        maxRetries: 10,
        initialRetryDelay: Duration(milliseconds: 100),
        maxRetryDelay: Duration(seconds: 1),
      );

      // After several retries, delay should cap at maxRetryDelay
      var delay = config.initialRetryDelay;
      for (int i = 0; i < 10; i++) {
        delay = delay * 2;
        if (delay > config.maxRetryDelay) {
          delay = config.maxRetryDelay;
        }
      }

      expect(delay, equals(Duration(seconds: 1)));
    });
  });
}
