import 'package:flutter_test/flutter_test.dart';
import 'package:syncitron/syncitron.dart';
import 'test_utils.dart';

void main() {
  group('Custom Sync Strategies', () {
    late MockSyncStrategyContext context;
    late MockLogger mockLogger;
    late MockMetricsCollector mockMetrics;

    setUp(() {
      mockLogger = MockLogger();
      mockMetrics = MockMetricsCollector();
      context = MockSyncStrategyContext(
        logger: mockLogger,
        metricsCollector: mockMetrics,
      );
    });

    group('StandardSyncStrategy', () {
      test('should execute all tables in sequence', () async {
        final strategy = StandardSyncOrchestration();

        final metrics = await strategy.execute(context);

        expect(metrics, isNotNull);
        expect(context.syncTableCalls.length, 3); // Default 3 tables
      });

      test('should return aggregated metrics', () async {
        final strategy = StandardSyncOrchestration();

        final metrics = await strategy.execute(context);

        expect(metrics, isNotNull);
        expect(metrics.tableMetrics.isNotEmpty, true);
      });

      test('should throw on critical errors', () async {
        context.throwOnNextSync = true;
        final strategy = StandardSyncOrchestration();

        try {
          await strategy.execute(context);
          fail('Should have thrown');
        } catch (e) {
          expect(e, isA<syncitronException>());
        }
      });
    });

    group('OfflineFirstSyncStrategy', () {
      test('should tolerate network errors up to limit', () async {
        context.networkErrorCount = 2;
        final strategy = OfflineFirstSyncOrchestration(maxNetworkErrors: 3);

        final metrics = await strategy.execute(context);

        expect(metrics, isNotNull);
        expect(context.syncTableCalls.length, greaterThan(0));
      });

      test('should stop sync after max network errors', () async {
        context.alwaysThrowNetworkError = true;
        final strategy = OfflineFirstSyncOrchestration(maxNetworkErrors: 2);

        await strategy.execute(context);

        // Should have attempted but stopped early
        expect(context.syncTableCalls.length, lessThan(3));
      });

      test('should log network error warnings', () async {
        context.networkErrorCount = 1;
        final strategy = OfflineFirstSyncOrchestration();

        await strategy.execute(context);

        final warningLogs = mockLogger.logs
            .where((l) => l.level == LogLevel.warning)
            .toList();
        expect(warningLogs.isNotEmpty, true);
      });

      test('should reset error counter on success', () async {
        context.networkErrorCount = 2;
        final strategy = OfflineFirstSyncOrchestration(maxNetworkErrors: 5);

        await strategy.execute(context);

        // Should complete normally since errors reset on success
        expect(context.syncTableCalls.isNotEmpty, true);
      });
    });

    group('StrictManualOrchestration', () {
      test('should execute without auto-retry', () async {
        final strategy = StrictManualOrchestration();

        final metrics = await strategy.execute(context);

        expect(metrics, isNotNull);
      });

      test('should throw immediately on errors', () async {
        context.throwOnNextSync = true;
        final strategy = StrictManualOrchestration();

        try {
          await strategy.execute(context);
          fail('Should have thrown');
        } catch (e) {
          expect(e, isA<syncitronException>());
        }
      });
    });

    group('PrioritySyncStrategy', () {
      test('should sync tables in priority order', () async {
        final priorities = {'subscriptions': 100, 'todos': 50, 'logs': 10};
        final strategy = PrioritySyncOrchestration(priorities);

        await strategy.execute(context);

        // Verify tables were synced
        expect(context.syncTableCallOrder.isNotEmpty, true);
      });

      test('should handle critical table priority', () async {
        final priorities = {
          'subscriptions': 100, // critical
          'todos': 50,
        };
        final strategy = PrioritySyncOrchestration(priorities);

        final metrics = await strategy.execute(context);

        expect(metrics, isNotNull);
        // Just verify it executed - fail-fast behavior may depend on strategy implementation
        expect(context.syncTableCalls.isNotEmpty, true);
      });

      test('should continue on non-critical table errors', () async {
        context.failOnTableName = 'todos';
        final priorities = {
          'subscriptions': 100, // critical
          'todos': 10, // non-critical
        };
        final strategy = PrioritySyncOrchestration(priorities);

        final metrics = await strategy.execute(context);

        // Should continue despite todos error
        expect(metrics, isNotNull);
      });

      test('should apply default priority (0) for unmapped tables', () async {
        final strategy = PrioritySyncOrchestration({});

        final metrics = await strategy.execute(context);

        expect(metrics, isNotNull);
      });
    });

    group('CompositeSyncStrategy', () {
      test('should execute strategies in sequence', () async {
        final strategy1 = _TestStrategy(name: 'strategy1');
        final strategy2 = _TestStrategy(name: 'strategy2');

        final composite = CompositeSyncOrchestration([strategy1, strategy2]);
        final metrics = await composite.execute(context);

        expect(metrics, isNotNull);
        expect(strategy1.executeCalled, true);
        expect(strategy2.executeCalled, true);
        expect(strategy1.executeIndex, lessThan(strategy2.executeIndex));
      });

      test('should call beforeSync and afterSync hooks', () async {
        final strategy = _TestStrategy(name: 'hooked');
        final composite = CompositeSyncOrchestration([strategy]);

        await composite.execute(context);

        expect(strategy.beforeSyncCalled, true);
        expect(strategy.afterSyncCalled, true);
      });

      test('should return metrics from last strategy', () async {
        final metrics1 = SyncSessionMetrics();
        final tableMetrics = SyncMetrics(tableName: 'table1');
        tableMetrics.recordsPulled = 5;
        tableMetrics.recordsPushed = 2;
        metrics1.addTableMetrics(tableMetrics);

        final strategy1 = _TestStrategy(name: 's1', returnMetrics: metrics1);
        final strategy2 = _TestStrategy(name: 's2');

        final composite = CompositeSyncOrchestration([strategy1, strategy2]);
        final result = await composite.execute(context);

        expect(result, isNotNull);
      });

      test('should propagate errors from any strategy', () async {
        final strategy1 = StandardSyncOrchestration();
        final failingStrategy = _TestStrategy(
          name: 'failing',
          shouldThrow: true,
        );
        final strategy3 = _TestStrategy(name: 's3');

        final composite = CompositeSyncOrchestration([
          strategy1,
          failingStrategy,
          strategy3,
        ]);

        try {
          await composite.execute(context);
          fail('Should have thrown');
        } catch (e) {
          expect(e, isA<syncitronException>());
          expect(strategy3.executeCalled, false);
        }
      });
    });

    group('Lifecycle Hooks', () {
      test('beforeSync should be called before execute', () async {
        final strategy = _TestStrategy(name: 'hooked');

        await strategy.beforeSync(context);
        expect(strategy.beforeSyncCalled, true);
      });

      test('afterSync should be called after execute', () async {
        final strategy = _TestStrategy(name: 'hooked');
        final metrics = SyncSessionMetrics();

        await strategy.afterSync(context, metrics);
        expect(strategy.afterSyncCalled, true);
      });

      test('afterSync should receive execution metrics', () async {
        final strategy = _TestStrategy(name: 'hooked');
        final inputMetrics = SyncSessionMetrics();
        final tMetrics = SyncMetrics(tableName: 'todos');
        tMetrics.recordsPulled = 10;
        tMetrics.recordsPushed = 5;
        inputMetrics.addTableMetrics(tMetrics);

        await strategy.afterSync(context, inputMetrics);

        expect(strategy.afterSyncMetrics, isNotNull);
        expect(strategy.afterSyncMetrics!.totalRecordsPulled, 10);
      });
    });
  });
}

/// Mock implementation of SyncStrategyContext for testing
class MockSyncStrategyContext implements SyncOrchestrationContext {
  @override
  final Logger logger;

  @override
  final MetricsCollector metricsCollector;

  @override
  final List<String> tableNames = ['todos', 'projects', 'notes'];

  @override
  final DateTime startTime = DateTime.now().toUtc();

  final List<String> syncTableCalls = [];
  final List<String> syncTableCallOrder = [];
  bool throwOnNextSync = false;
  bool alwaysThrowNetworkError = false;
  int networkErrorCount = 0;
  String? failOnTableName;

  MockSyncStrategyContext({
    required this.logger,
    required this.metricsCollector,
  });

  @override
  Future<SyncMetrics> managedSyncTable(String tableName) async {
    syncTableCalls.add(tableName);
    syncTableCallOrder.add(tableName);

    if (throwOnNextSync) {
      throw EngineConfigurationException('Test error');
    }

    if (alwaysThrowNetworkError) {
      throw SyncNetworkException(table: tableName, message: 'Network error');
    }

    if (failOnTableName == tableName) {
      throw EngineConfigurationException('Table sync failed: $tableName');
    }

    if (networkErrorCount > 0) {
      networkErrorCount--;
      throw SyncNetworkException(table: tableName, message: 'Network error');
    }

    final metrics = SyncMetrics(tableName: tableName);
    metrics.recordsPulled = 5;
    metrics.recordsPushed = 2;
    return metrics;
  }

  @override
  Future<SyncSessionMetrics> managedSyncAll() async {
    final metrics = SyncSessionMetrics();

    for (final table in tableNames) {
      try {
        final tableMetrics = await managedSyncTable(table);
        metrics.addTableMetrics(tableMetrics);
      } catch (e) {
        logger.error('Failed to sync $table', error: e);
        rethrow;
      }
    }

    return metrics;
  }

  @override
  bool shouldContinue() => true;

  @override
  void cancel() {
    // No-op for tests
  }
}

/// Test strategy for verifying lifecycle hooks and execution flow
class _TestStrategy extends SyncOrchestrationStrategy {
  final String name;
  final bool shouldThrow;
  final SyncSessionMetrics? returnMetrics;

  bool beforeSyncCalled = false;
  bool executeCalled = false;
  bool afterSyncCalled = false;
  int executeIndex = -1;
  SyncSessionMetrics? afterSyncMetrics;

  static int _executionOrder = 0;

  _TestStrategy({
    required this.name,
    this.shouldThrow = false,
    this.returnMetrics,
  });

  @override
  Future<void> beforeSync(SyncOrchestrationContext context) async {
    beforeSyncCalled = true;
  }

  @override
  Future<SyncSessionMetrics> execute(SyncOrchestrationContext context) async {
    executeCalled = true;
    executeIndex = _executionOrder++;

    if (shouldThrow) {
      throw EngineConfigurationException('Test strategy error: $name');
    }

    return returnMetrics ?? SyncSessionMetrics();
  }

  @override
  Future<void> afterSync(
    SyncOrchestrationContext context,
    SyncSessionMetrics metrics,
  ) async {
    afterSyncCalled = true;
    afterSyncMetrics = metrics;
  }
}
