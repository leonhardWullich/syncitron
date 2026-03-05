/// # Enterprise Patterns & Best Practices

This file documents recommended patterns for using Replicore in production
enterprise applications.

/// ## 1. Dependency Injection Setup

/// Proper DI setup ensures testability and maintainability.

/// ### Service Locator Pattern (using GetIt)

```dart
// lib/services/sync_service_provider.dart
import 'package:get_it/get_it.dart';
import 'package:replicore/replicore.dart';

final getIt = GetIt.instance;

Future<void> setupSyncServices() async {
  // Initialize database
  final db = await openDatabase(
    join(await getDatabasesPath(), 'myapp.db'),
    version: 1,
  );

  // Create stores and adapters
  final localStore = SqfliteStore(db);
  final remoteAdapter = SupabaseAdapter(
    client: Supabase.instance.client,
    localStore: localStore,
  );

  // Create configuration appropriate for environment
  final config = _isProduction
      ? ReplicoreConfig.production()
      : ReplicoreConfig.development();

  // Create logger with APM integration
  final logger = _setupLogger();

  // Create metrics collector
  final metricsCollector = InMemoryMetricsCollector();

  // Create and register sync engine
  final engine = SyncEngine(
    localStore: localStore,
    remoteAdapter: remoteAdapter,
    config: config,
    logger: logger,
    metricsCollector: metricsCollector,
  );

  // Register all services for injection
  getIt.registerSingleton<Database>(db);
  getIt.registerSingleton<LocalStore>(localStore);
  getIt.registerSingleton<RemoteAdapter>(remoteAdapter);
  getIt.registerSingleton<Logger>(logger);
  getIt.registerSingleton<MetricsCollector>(metricsCollector);
  getIt.registerSingleton<SyncEngine>(engine);

  // Initialize engine (idempotent)
  await engine.init();
}

Logger _setupLogger() {
  final loggers = <Logger>[
    ConsoleLogger(minLevel: LogLevel.info),
  ];

  // Add Sentry integration in production
  if (_isProduction) {
    loggers.add(SentryLogger());
  }

  // Add Datadog integration for analytics
  if (_enableAnalytics) {
    loggers.add(DatadogLogger());
  }

  return MultiLogger(loggers);
}
```

/// ### Provider Pattern (using Riverpod)

```dart
// lib/providers/sync_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:replicore/replicore.dart';

final syncEngineProvider = FutureProvider<SyncEngine>((ref) async {
  final localStore = await ref.watch(localStoreProvider.future);
  final remoteAdapter = await ref.watch(remoteAdapterProvider.future);
  final logger = ref.watch(loggerProvider);
  final config = ref.watch(syncConfigProvider);

  final engine = SyncEngine(
    localStore: localStore,
    remoteAdapter: remoteAdapter,
    config: config,
    logger: logger,
  );

  await engine.init();
  return engine;
});

final syncMetricsProvider = StateNotifierProvider<
    SyncMetricsNotifier,
    AsyncValue<SyncSessionMetrics>
>((ref) {
  return SyncMetricsNotifier(ref.watch(syncEngineProvider));
});

class SyncMetricsNotifier extends StateNotifier<AsyncValue<SyncSessionMetrics>> {
  SyncMetricsNotifier(this._engineFuture) : super(const AsyncValue.loading());

  final Future<SyncEngine> _engineFuture;

  Future<void> syncAll() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final engine = await _engineFuture;
      return engine.syncAll();
    });
  }
}
```

/// ## 2. Error Boundary Pattern

/// Comprehensive error handling with recovery strategies.

```dart
// lib/utils/error_boundary.dart
class SyncErrorBoundary {
  final Logger logger;

  SyncErrorBoundary({required this.logger});

  Future<SyncSessionMetrics> executeWithRecovery(
    Future<SyncSessionMetrics> Function() action,
  ) async {
    try {
      return await action();
    } on SyncNetworkException catch (e) {
      logger.warning('Network error during sync', error: e);
      return SyncSessionMetrics(); // Return empty metrics
    } on SyncAuthException catch (e) {
      logger.error('Authentication failed', error: e);
      // Trigger logout flow
      await _handleAuthFailure();
      return SyncSessionMetrics();
    } on SchemaMigrationException catch (e) {
      logger.critical('Database schema error', error: e);
      // Report to error tracking service
      await _reportFatalError(e);
      rethrow;
    } on ReplicoreException catch (e) {
      logger.error('Sync failed', error: e);
      // Implement recovery (e.g., exponential backoff retry)
      return _executeWithBackoff(action);
    }
  }

  Future<SyncSessionMetrics> _executeWithBackoff(
    Future<SyncSessionMetrics> Function() action,
  ) async {
    int attempt = 0;
    const maxAttempts = 3;
    Duration delay = Duration(minutes: 1);

    while (attempt < maxAttempts) {
      try {
        await Future.delayed(delay);
        return await action();
      } catch (e) {
        attempt++;
        if (attempt >= maxAttempts) rethrow;
        delay *= 2; // Exponential backoff
        logger.info('Retrying sync attempt $attempt/$maxAttempts');
      }
    }
    return SyncSessionMetrics();
  }

  Future<void> _handleAuthFailure() async {
    // Navigate to login, clear user data, etc.
  }

  Future<void> _reportFatalError(Object error) async {
    // Send to APM system
  }
}
```

/// ## 3. Monitoring & Analytics Pattern

/// Track and analyze sync performance across your fleet.

```dart
// lib/services/sync_analytics.dart
class SyncAnalytics {
  final MetricsCollector collector;
  final AnalyticsService analytics;

  SyncAnalytics({
    required this.collector,
    required this.analytics,
  });

  Future<void> trackSync(SyncSessionMetrics metrics) async {
    // Log structured data for analysis
    await analytics.logEvent('sync_completed', {
      'success': metrics.overallSuccess,
      'duration_ms': metrics.totalDuration.inMilliseconds,
      'tables_synced': metrics.totalTablesSynced,
      'records_pulled': metrics.totalRecordsPulled,
      'records_pushed': metrics.totalRecordsPushed,
      'conflicts': metrics.totalConflicts,
      'errors': metrics.totalErrors,
    });

    // Track per-table metrics
    for (final tableMetrics in metrics.tableMetrics) {
      await analytics.logEvent('table_sync_completed', {
        'table': tableMetrics.tableName,
        'success': tableMetrics.success,
        'duration_ms': tableMetrics.duration.inMilliseconds,
        'records': tableMetrics.totalRecordsProcessed,
      });
    }
  }

  void trackError(ReplicoreException error) {
    analytics.logError(
      error,
      info: {
        'error_type': error.runtimeType.toString(),
        'message': error.message,
      },
    );
  }
}
```

/// ## 4. Sync Lifecycle Management Pattern

/// Properly manage sync lifecycle with proper initialization and cleanup.

```dart
// lib/services/sync_manager.dart
class SyncManager {
  final SyncEngine _engine;
  final Logger _logger;
  final SyncErrorBoundary _errorBoundary;

  Timer? _periodicSyncTimer;
  StreamSubscription? _connectivitySubscription;

  SyncManager({
    required SyncEngine engine,
    required Logger logger,
  })  : _engine = engine,
        _logger = logger,
        _errorBoundary = SyncErrorBoundary(logger: logger);

  Future<void> initialize() async {
    _logger.info('Initializing SyncManager');

    // Initialize engine (idempotent, safe to call multiple times)
    await _engine.init();

    // Register tables
    _registerTables();

    // Setup periodic syncing
    _setupPeriodicSync();

    // Setup connectivity-driven sync
    _setupConnectivitySync();

    _logger.info('SyncManager initialized');
  }

  void _registerTables() {
    _engine
        .registerTable(TableConfig(
          name: 'todos',
          columns: ['id', 'title', 'completed', 'updated_at', 'deleted_at'],
          strategy: SyncStrategy.lastWriteWins,
        ))
        .registerTable(TableConfig(
          name: 'projects',
          columns: ['id', 'name', 'updated_at', 'deleted_at'],
          strategy: SyncStrategy.serverWins,
        ));
  }

  void _setupPeriodicSync() {
    _periodicSyncTimer =
        Timer.periodic(Duration(minutes: 5), (_) => syncAll());
  }

  void _setupConnectivitySync() {
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        _logger.info('Connectivity restored, syncing now');
        syncAll();
      }
    });
  }

  Future<SyncSessionMetrics> syncAll() async {
    return _errorBoundary.executeWithRecovery(() => _engine.syncAll());
  }

  Future<SyncMetrics> syncTable(String tableName) async {
    final config = _engine.tables
        .firstWhere((t) => t.name == tableName);
    return _errorBoundary.executeWithRecovery(
      () => _engine.syncTable(config),
    );
  }

  Future<SystemHealth> checkHealth() async {
    final dbProvider = DatabaseDiagnosticsProvider(database);
    final syncProvider = SyncDiagnosticsProvider(
      lastSyncSuccessful: true,
    );

    final systemDiagnostics =
        SystemDiagnosticsProvider([dbProvider, syncProvider]);

    return systemDiagnostics.checkHealth();
  }

  void dispose() {
    _periodicSyncTimer?.cancel();
    _connectivitySubscription?.cancel();
    _engine.dispose();
    _logger.info('SyncManager disposed');
  }
}
```

/// ## 5. UI Integration Pattern

/// Properly display sync status and handle errors in UI.

```dart
// lib/screens/sync_status_screen.dart
class SyncStatusScreen extends StatefulWidget {
  @override
  State<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends State<SyncStatusScreen> {
  SyncSessionMetrics? _lastMetrics;
  bool _isSyncing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Status'),
        actions: [
          IconButton(
            onPressed: _isSyncing ? null : _performSync,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: Column(
        children: [
          // Sync status indicator
          _buildStatusIndicator(),

          // Metrics display
          if (_lastMetrics != null) _buildMetricsDisplay(),

          // Status stream
          _buildStatusStream(),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator() {
    final status = _lastMetrics?.overallSuccess ?? false;
    return Container(
      color: status ? Colors.green : Colors.red,
      padding: EdgeInsets.all(16),
      child: Text(
        status ? '✓ Synced' : '✗ Sync Failed',
        style: TextStyle(color: Colors.white),
      ),
    );
  }

  Widget _buildMetricsDisplay() {
    if (_lastMetrics == null) return SizedBox.shrink();

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_lastMetrics!.totalRecordsPulled} records pulled'),
            Text('${_lastMetrics!.totalRecordsPushed} records pushed'),
            Text('${_lastMetrics!.totalConflicts} conflicts resolved'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusStream() {
    return StreamBuilder<String>(
      stream: getIt<SyncEngine>().statusStream,
      builder: (context, snapshot) {
        return Padding(
          padding: EdgeInsets.all(16),
          child: Text(snapshot.data ?? 'Ready'),
        );
      },
    );
  }

  Future<void> _performSync() async {
    setState(() => _isSyncing = true);

    try {
      final metrics = await getIt<SyncManager>().syncAll();
      setState(() => _lastMetrics = metrics);

      if (!metrics.overallSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed with ${metrics.totalErrors} errors')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync error: $e')),
      );
    } finally {
      setState(() => _isSyncing = false);
    }
  }
}
```

/// ## 6. Testing Pattern

/// Comprehensive testing strategy for sync functionality.

```dart
// test/services/sync_manager_test.dart
void main() {
  group('SyncManager', () {
    late MockSyncEngine mockEngine;
    late MockLogger mockLogger;
    late SyncManager manager;

    setUp(() {
      mockEngine = MockSyncEngine();
      mockLogger = MockLogger();
      manager = SyncManager(
        engine: mockEngine,
        logger: mockLogger,
      );
    });

    test('initializes engine on startup', () async {
      await manager.initialize();
      verify(mockEngine.init).called(1);
    });

    test('handles sync errors gracefully', () async {
      when(mockEngine.syncAll())
          .thenThrow(SyncNetworkException(
            table: 'test',
            message: 'Network error',
          ));

      final metrics = await manager.syncAll();
      expect(metrics, isNotNull);
      verify(mockLogger.warning(any, error: any)).called(greaterThan(0));
    });

    test('performs periodic sync', () async {
      await manager.initialize();
      
      // Advance time by 5 minutes
      await Future.delayed(const Duration(minutes: 5));
      
      verify(mockEngine.syncAll()).called(greaterThan(0));
    });

    tearDown(() {
      manager.dispose();
    });
  });
}
```

/// ## 7. Configuration Management Pattern

/// Different configurations for different environments.

```dart
// lib/config/sync_config.dart
abstract class SyncConfigProvider {
  ReplicoreConfig getConfig();
}

class ProductionSyncConfig implements SyncConfigProvider {
  @override
  ReplicoreConfig getConfig() {
    return ReplicoreConfig.production().copyWith(
      periodicSyncInterval: Duration(minutes: 5),
      collectMetrics: true,
    );
  }
}

class StagingSyncConfig implements SyncConfigProvider {
  @override
  ReplicoreConfig getConfig() {
    return ReplicoreConfig.production().copyWith(
      periodicSyncInterval: Duration(minutes: 2),
      enableDetailedLogging: true,
    );
  }
}

class DevelopmentSyncConfig implements SyncConfigProvider {
  @override
  ReplicoreConfig getConfig() {
    return ReplicoreConfig.development();
  }
}
```

---

These patterns provide a solid foundation for production-grade Replicore
implementations. Adapt them to your specific needs and organizational practices.
