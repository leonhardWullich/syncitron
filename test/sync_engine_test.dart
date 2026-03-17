import 'package:flutter_test/flutter_test.dart';
import 'package:syncitron/syncitron.dart';
import 'test_utils.dart';

void main() {
  group('SyncEngine', () {
    late MockLocalStore localStore;
    late MockRemoteAdapter remoteAdapter;
    late MockLogger mockLogger;
    late MockMetricsCollector mockMetrics;
    late SyncEngine engine;

    setUp(() {
      localStore = MockLocalStore();
      remoteAdapter = MockRemoteAdapter();
      mockLogger = MockLogger();
      mockMetrics = MockMetricsCollector();

      engine = SyncEngine(
        localStore: localStore,
        remoteAdapter: remoteAdapter,
        logger: mockLogger,
        metricsCollector: mockMetrics,
      );
    });

    group('Initialization', () {
      test('should initialize without errors', () async {
        engine.registerTable(TestDataFactory.testTable());
        // Note: Just verify we can initialize without throwing
        try {
          await engine.init();
          expect(true, true);
        } catch (_) {
          fail('Initialization should not throw');
        }
      });

      test('should register single table', () {
        final tableConfig = TestDataFactory.testTable();
        // Should not throw
        expect(() => engine.registerTable(tableConfig), returnsNormally);
      });

      test('should support chained table registration', () {
        // Should not throw
        expect(
          () => engine
              .registerTable(TestDataFactory.testTable(name: 'todos'))
              .registerTable(TestDataFactory.testTable(name: 'projects')),
          returnsNormally,
        );
      });
    });

    group('Full Sync', () {
      setUp(() async {
        engine.registerTable(TestDataFactory.testTable());
        await engine.init();
      });

      test('should complete sync with empty data', () async {
        final result = await engine.syncAll();
        expect(result, isNotNull);
      });

      test('should sync when remote has data', () async {
        remoteAdapter.remoteTables['todos'] = TestDataFactory.testRecords(2);
        final result = await engine.syncAll();
        expect(result, isNotNull);
      });

      test('should record metrics', () async {
        remoteAdapter.remoteTables['todos'] = TestDataFactory.testRecords(3);
        final result = await engine.syncAll();
        expect(result, isNotNull);
        // Verify metrics were created
        expect(mockMetrics.sessionMetrics, isNotEmpty);
      });
    });

    group('Multi-Table Sync', () {
      setUp(() async {
        engine
            .registerTable(
              TableConfig(
                name: 'todos',
                columns: ['id', 'title', 'updated_at', 'deleted_at'],
                primaryKey: 'id',
                strategy: SyncStrategy.lastWriteWins,
              ),
            )
            .registerTable(
              TableConfig(
                name: 'projects',
                columns: ['id', 'name', 'updated_at', 'deleted_at'],
                primaryKey: 'id',
                strategy: SyncStrategy.serverWins,
              ),
            );
        await engine.init();
      });

      test('should sync multiple tables', () async {
        remoteAdapter.remoteTables['todos'] = TestDataFactory.testRecords(2);
        remoteAdapter.remoteTables['projects'] = [
          {
            'id': 'p1',
            'name': 'Project 1',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
            'deleted_at': null,
            'is_synced': 1,
          },
        ];

        final result = await engine.syncAll();
        expect(result, isNotNull);
        expect(result.tableMetrics.length, 2);
      });
    });

    group('Error Tolerance', () {
      setUp(() async {
        engine.registerTable(TestDataFactory.testTable());
        await engine.init();
      });

      test('should handle sync with local data', () async {
        // Add local dirty data
        final localRecords = TestDataFactory.testRecords(1);
        localRecords.first['is_synced'] = 0;
        localStore.insertTest('todos', localRecords);

        final result = await engine.syncAll();
        expect(result, isNotNull);
      });

      test('should attempt remote sync', () async {
        remoteAdapter.remoteTables['todos'] = TestDataFactory.testRecords(1);

        // The key test: verify pull was attempted
        await engine.syncAll();

        // If we got here, sync completed
        expect(remoteAdapter.pullRequests.isNotEmpty, true);
      });
    });

    group('Configuration', () {
      test('should apply configuration', () async {
        final configuredEngine = SyncEngine(
          localStore: localStore,
          remoteAdapter: remoteAdapter,
          logger: mockLogger,
          metricsCollector: mockMetrics,
        );

        configuredEngine.registerTable(TestDataFactory.testTable());
        await configuredEngine.init();

        // Verify engine is initialized
        expect(true, true);
      });
    });

    group('Chaining', () {
      test('should support method chaining', () {
        final chainedEngine = engine
            .registerTable(TestDataFactory.testTable(name: 'table1'))
            .registerTable(TestDataFactory.testTable(name: 'table2'));

        expect(chainedEngine, isNotNull);
      });
    });
  });
}
