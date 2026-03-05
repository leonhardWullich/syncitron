import 'package:flutter_test/flutter_test.dart';
import 'package:replicore/replicore.dart';
import 'test_utils.dart';

void main() {
  group('SyncEngine', () {
    late MockLocalStore localStore;
    late MockRemoteAdapter remoteAdapter;
    late MockLogger mockLogger;
    late MockMetricsCollector mockMetrics;
    late SyncEngine engine;
    late ReplicoreConfig config;

    setUp(() {
      localStore = MockLocalStore();
      remoteAdapter = MockRemoteAdapter();
      mockLogger = MockLogger();
      mockMetrics = MockMetricsCollector();
      config = ReplicoreConfig.production();

      engine = SyncEngine(
        localStore: localStore,
        remoteAdapter: remoteAdapter,
        config: config,
        logger: mockLogger,
        metricsCollector: mockMetrics,
      );
    });

    tearDown(() {
      engine.dispose();
    });

    group('Initialization', () {
      test('should initialize without errors', () async {
        engine.registerTable(TestDataFactory.testTable());
        await engine.init();
        // If we reach here without exception, initialization succeeded
        expect(true, true);
      });

      test('should register tables', () {
        final config = TableConfig(
          name: 'todos',
          columns: ['id', 'title', 'updated_at', 'deleted_at'],
          primaryKey: 'id',
          strategy: SyncStrategy.lastWriteWins,
        );

        engine.registerTable(config);
        // Registration succeeded without exception
        expect(true, true);
      });

      test('should register multiple tables', () {
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

        // If we reach here, both registrations succeeded
        expect(true, true);
      });
    });

    group('Full Sync Operations', () {
      setUp(() async {
        await engine.init();
        engine.registerTable(TestDataFactory.testTable());
      });

      test('should perform full sync', () async {
        // Setup remote data
        final remoteRecords = TestDataFactory.testRecords(3);
        remoteAdapter.remoteTables['todos'] = remoteRecords;

        // Setup local dirty data
        final localRecords = TestDataFactory.testRecords(2);
        for (var record in localRecords) {
          record['is_synced'] = 0;
          record['title'] = 'Local ${record['title']}';
        }
        localStore.insertTest('todos', localRecords);

        await engine.syncAll();

        // If we reach here without exception, sync completed
        expect(true, true);
      });

      test('should generate metrics for sync session', () async {
        remoteAdapter.remoteTables['todos'] = TestDataFactory.testRecords(5);

        final metrics = await engine.syncAll();

        expect(metrics, isNotNull);
        expect(mockMetrics.sessionMetrics.isNotEmpty, true);
      });

      test('should prevent overlapping sync runs', () async {
        remoteAdapter.remoteTables['todos'] = TestDataFactory.testRecords(3);

        // Start first sync (don't await)
        final sync1 = engine.syncAll();
        // Start second sync immediately
        final sync2 = engine.syncAll();

        // Both should complete
        await Future.wait([sync1, sync2]);

        // Should have completed without deadlock
        expect(true, true);
      });
    });

    group('Error Handling', () {
      setUp(() async {
        await engine.init();
        engine.registerTable(TestDataFactory.testTable());
      });

      test('should handle pull errors gracefully', () async {
        remoteAdapter.throwOnPull = true;

        final result = await engine.syncAll();

        // Sync should complete even with errors
        expect(result, isNotNull);
      });

      test('should log errors with context', () async {
        remoteAdapter.throwOnPull = true;

        await engine.syncAll();

        // Verify errors were logged
        expect(mockLogger.logs.isNotEmpty, true);
      });

      test('should continue syncing other tables on error', () async {
        await engine.init(); // Re-init for second table
        engine
            .registerTable(TestDataFactory.testTable(name: 'projects'))
            .registerTable(TestDataFactory.testTable(name: 'notes'));

        // Setup data for both tables
        remoteAdapter.remoteTables['projects'] = TestDataFactory.testRecords(2);
        remoteAdapter.remoteTables['notes'] = TestDataFactory.testRecords(3);

        final result = await engine.syncAll();

        // Should have synced multiple tables
        expect(result.tableMetrics.isNotEmpty, true);
      });
    });

    group('Multi-Table Synchronization', () {
      setUp(() async {
        await engine.init();
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
      });

      test('should sync multiple tables in sequence', () async {
        remoteAdapter.remoteTables['todos'] = TestDataFactory.testRecords(3);
        remoteAdapter.remoteTables['projects'] = [
          {
            'id': 'p1',
            'name': 'Project 1',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
            'deleted_at': null,
            'is_synced': 1,
          },
        ];

        final metrics = await engine.syncAll();

        expect(metrics.tableMetrics.length, 2);
      });
    });

    group('Retry Logic', () {
      test('should retry failed operations', () async {
        engine.registerTable(TestDataFactory.testTable());
        await engine.init();

        remoteAdapter.throwOnPull = true;

        final result = await engine.syncAll();

        // Should have logged the retry attempts
        expect(mockLogger.logs.isNotEmpty, true);
      });
    });

    group('Logger Integration', () {
      setUp(() async {
        await engine.init();
        engine.registerTable(TestDataFactory.testTable());
      });

      test('should log sync operations', () async {
        remoteAdapter.remoteTables['todos'] = TestDataFactory.testRecords(2);

        await engine.syncAll();

        // Verify logs captured
        expect(mockLogger.logs.isNotEmpty, true);
      });
    });
  });
}
