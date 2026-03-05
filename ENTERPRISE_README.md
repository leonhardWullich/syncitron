# Replicore - Enterprise Local-First Sync Framework for Flutter

**Production-ready synchronization engine for offline-capable Flutter applications.**

Replicore is a battle-tested, enterprise-grade framework that transforms your online-only Supabase/REST API app into a robust offline-first platform. It handles the complexity of bidirectional data synchronization, conflict resolution, incremental syncing, comprehensive error recovery, and production monitoring—so your team can focus on building great user experiences.

**Status**: Enterprise Release | **Maturity**: Production-Ready | **License**: MIT

## 🎯 Why Replicore

Building offline-capable apps is hard. Most developers struggle with:

- ❌ Data consistency across devices
- ❌ Conflict resolution logic
- ❌ Network retry strategies
- ❌ Monitoring and debugging
- ❌ Idempotent operations
- ❌ Graceful degradation

**Replicore fixes all of this.**

## ✨ Enterprise Features

### Core Sync Capabilities

- 🔌 **Pluggable Architecture**: Works with Supabase, REST APIs, Firebase, or any backend
- 📱 **True Offline-First**: Seamless transitions between online/offline states
- 🧠 **Smart Conflict Resolution**: ServerWins, LocalWins, LastWriteWins, Custom strategies
- ⚡ **High Performance**: Keyset pagination, batch operations, transaction-based writes
- 🔄 **Bidirectional Sync**: Pull updates from server, push local changes back
- 🗑️ **Soft Delete Support**: Graceful deletion handling across devices
- ♻️ **Automatic Migrations**: Adds required columns if missing

### Enterprise Requirements

- 📊 **Comprehensive Monitoring**: Structured logging, metrics collection, health checks
- 🔐 **Idempotent Operations**: Prevents duplicate writes on network retries
- 📈 **Flexible Configuration**: Production, Development, and Testing presets
- 🎛️ **Dependency Injection**: Fully composable, testable architecture
- 📝 **Detailed Logging**: Structured logging for APM integrations (Sentry, Datadog, New Relic)
- 🔍 **Diagnostics**: Built-in health checks and system diagnostics
- 🛡️ **Error Recovery**: Comprehensive exception hierarchy with recovery strategies

## 📦 Installation

Add to your `pubspec.yaml`:

```bash
flutter pub add replicore
```

## 🚀 Quick Start (5 minutes)

### 1. Setup Database & Replicore

```dart
import 'package:flutter/material.dart';
import 'package:replicore/replicore.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await Supabase.initialize(
    url: 'YOUR_SUPABASE_URL',
    anonKey: 'YOUR_SUPABASE_ANON_KEY',
  );

  // Open local SQLite database
  final database = await openDatabase(
    join(await getDatabasesPath(), 'myapp.db'),
    version: 1,
    onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE todos (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          completed INTEGER DEFAULT 0,
          updated_at TEXT,
          deleted_at TEXT
        )
      ''');
    },
  );

  // Initialize Replicore with production config
  final engine = SyncEngine(
    localStore: SqfliteStore(database),
    remoteAdapter: SupabaseAdapter(
      client: Supabase.instance.client,
      localStore: SqfliteStore(database),
    ),
    config: ReplicoreConfig.production(),
    logger: ConsoleLogger(minLevel: LogLevel.info),
  );

  runApp(MyApp(engine: engine));
}
```

### 2. Register Tables & Initialize Sync

```dart
class MyApp extends StatefulWidget {
  final SyncEngine engine;
  const MyApp({required this.engine});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    _setupSync();
  }

  Future<void> _setupSync() async {
    // Register tables with conflict strategies
    engine.registerTable(TableConfig(
      name: 'todos',
      columns: ['id', 'title', 'completed', 'updated_at', 'deleted_at'],
      strategy: SyncStrategy.lastWriteWins,
    ));

    // Initialize engine (idempotent, safe to call multiple times)
    await engine.init();

    // Perform initial sync
    final metrics = await engine.syncAll();
    print(metrics); // Pretty-printed summary
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: TodosScreen(engine: engine),
    );
  }
}
```

### 3. Use in Your UI

```dart
class TodosScreen extends StatelessWidget {
  final SyncEngine engine;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<String>(
          stream: engine.statusStream,
          builder: (context, snapshot) {
            return Text(snapshot.data ?? 'Ready');
          },
        ),
      ),
      body: // Your todo list UI
    );
  }
}
```

Done! Your app now has offline-first capabilities.

## ⚙️ Configuration Guide

### Production Configuration (Recommended)

```dart
final config = ReplicoreConfig.production();
// Features:
// - Batch size: 1000 records
// - Max retries: 5 attempts
// - Longer retry backoff (up to 5 minutes)
// - Periodic sync: every 5 minutes
// - Metrics enabled, detailed logging disabled
// - Best for production releases
```

### Development Configuration

```dart
final config = ReplicoreConfig.development();
// Features:
// - Batch size: 100 records (for quick testing)
// - Max retries: 2 attempts (fail fast)
// - Detailed logging enabled
// - Shorter timeouts (easier debugging)
// - Best for development and testing
```

### Testing Configuration

```dart
final config = ReplicoreConfig.testing();
// Features:
// - No metrics collection (faster tests)
// - No logging overhead
// - Short timeouts
// - Minimal batch sizes
// - Best for unit and integration tests
```

### Custom Configuration

```dart
final config = ReplicoreConfig(
  // Sync behavior
  batchSize: 500,
  maxConcurrentSyncs: 1,
  operationTimeout: Duration(seconds: 30),
  
  // Retry strategy (exponential backoff)
  maxRetries: 3,
  initialRetryDelay: Duration(seconds: 1),
  maxRetryDelay: Duration(minutes: 2),
  
  // Column names (if different from defaults)
  isSyncedColumn: 'is_synced',
  operationIdColumn: 'op_id',
  
  // Features
  autoSyncOnStartup: false,
  periodicSyncInterval: Duration(minutes: 5),
  enableDetailedLogging: false,
  collectMetrics: true,
  validateOnCreation: true,
);

final engine = SyncEngine(
  localStore: store,
  remoteAdapter: adapter,
  config: config,
);
```

## 🧬 Conflict Resolution Strategies

### ServerWins (Default)

Remote data always wins. Local changes discarded on conflict.

**Use for**: Reference data, administrative settings, read-heavy content

```dart
TableConfig(
  name: 'settings',
  strategy: SyncStrategy.serverWins,
  columns: ['id', 'key', 'value', 'updated_at', 'deleted_at'],
)
```

### LocalWins

Local changes always win. Remote updates ignored.

**Use for**: User drafts, private notes, user preferences

```dart
TableConfig(
  name: 'user_notes',
  strategy: SyncStrategy.localWins,
  columns: ['id', 'content', 'updated_at', 'deleted_at'],
)
```

### LastWriteWins

Latest modification time wins (based on `updated_at`).

**Use for**: General collaborative data, user-generated content

```dart
TableConfig(
  name: 'todos',
  strategy: SyncStrategy.lastWriteWins,
  columns: ['id', 'title', 'completed', 'updated_at', 'deleted_at'],
)
```

### Custom Resolver

Application-specific merge logic.

**Use for**: Complex data, weighted merging, business logic

```dart
TableConfig(
  name: 'shopping_lists',
  strategy: SyncStrategy.custom,
  customResolver: (local, remote) async {
    // Example: Merge items from both lists
    final merged = {
      ...remote,
      'items': [
        ...?remote['items'] as List,
        ...?local['items'] as List,
      ].toSet().toList(),
    };
    return UseMerged(merged);
  },
  columns: ['id', 'name', 'items', 'updated_at', 'deleted_at'],
)
```

## 🎼 Sync Orchestration (Macro-Level Flow)

While Conflict Resolution handles row-level data merges (`SyncStrategy`), the **SyncOrchestrationStrategy** controls the macro-level flow of your synchronization process. 

In enterprise environments, you rarely want to treat all tables equally during a sync. You need fine-grained control over execution order, fault tolerance, and lifecycle hooks (e.g., pre-sync validation or post-sync analytics). Replicore allows you to orchestrate the entire sync lifecycle.

### Priority-Based Orchestration
Ensures critical business data is synchronized first and fails-fast on errors, while optional data gracefully degrades on poor connections.

```dart
final metrics = await engine.syncWithOrchestration(
  PrioritySyncOrchestration({
    'users': 100,        // Critical: Syncs first, fails fast on error
    'subscriptions': 90, 
    'cache_assets': 10,  // Optional: Tolerates network errors and skips gracefully
  }),
);
```

### Offline-First Orchestration

Designed for field-service apps or environments with unreliable networks (e.g., edge computing, emerging markets). It tolerates a specific number of network timeouts before cleanly aborting the sync loop, preventing infinite retries and battery drain.

```dart
final metrics = await engine.syncWithOrchestration(
  OfflineFirstSyncOrchestration(maxNetworkErrors: 3),
);
```

### Composite Orchestration (Pipelines)

Enterprise architectures often require complex sync pipelines. You can chain multiple strategies together to create custom workflows with pre- and post-processing hooks.

```dart
final pipeline = CompositeSyncOrchestration([
  PreSyncValidationHook(),       // e.g., check disk space or auth token validity
  StandardSyncOrchestration(),   // The actual push/pull data sync
  PostSyncAnalyticsHook(),       // e.g., flush metrics to Datadog/Sentry
]);

final metrics = await engine.syncWithOrchestration(pipeline);
```

### Strict Manual Orchestration

For highly sensitive operations where automated retries are dangerous. Every error surfaces immediately to the caller, giving the UI or the background service explicit control over how to handle the failure.

```dart
final metrics = await engine.syncWithOrchestration(
  StrictManualOrchestration(),
);
```

## 📊 Monitoring & Observability

### Sync Metrics

```dart
final metrics = await engine.syncAll();

// Check overall success
print('Success: ${metrics.overallSuccess}');

// Performance metrics
print('Duration: ${metrics.totalDuration.inMilliseconds}ms');
print('Tables synced: ${metrics.totalTablesSynced}');

// Data metrics
print('Records pulled: ${metrics.totalRecordsPulled}');
print('Records pushed: ${metrics.totalRecordsPushed}');
print('Conflicts: ${metrics.totalConflicts}');
print('Errors: ${metrics.totalErrors}');

// Pretty-printed summary
print(metrics);
```

### Structured Logging

```dart
// Console logger (development)
final logger = ConsoleLogger(minLevel: LogLevel.debug);

// Production logging (integrate with APM)
class SentryLogger implements Logger {
  @override
  void error(String message, {Object? error, StackTrace? stackTrace, Map<String, dynamic>? context}) {
    Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) {
        scope.setContext('replicore', context ?? {});
      },
    );
  }
  
  // ... implement other methods
}

final logger = SentryLogger();

final engine = SyncEngine(
  localStore: store,
  remoteAdapter: adapter,
  logger: logger,
);
```

### Health Checks & Diagnostics

```dart
// Setup diagnostic providers
final dbDiagnostics = DatabaseDiagnosticsProvider(database);
final syncDiagnostics = SyncDiagnosticsProvider(
  lastSyncSuccessful: lastSyncMetrics?.overallSuccess ?? false,
  lastSyncTime: lastSyncTime,
);

final systemDiagnostics = SystemDiagnosticsProvider([
  dbDiagnostics,
  syncDiagnostics,
]);

// Check system health
final health = await systemDiagnostics.checkHealth();
print('Overall: ${health.status}'); // healthy, degraded, unhealthy
print(health);

// Get detailed diagnostics
final diagnostics = await systemDiagnostics.getDiagnostics();
print(diagnostics);
```

## 🔄 Sync Patterns

### Manual Sync

```dart
// Sync all tables
await engine.syncAll();

// Sync specific table
await engine.syncTable(tableConfig);
```

### Periodic Sync

```dart
// Setup periodic background sync
Timer.periodic(Duration(minutes: 5), (_) async {
  final metrics = await engine.syncAll();
  if (!metrics.overallSuccess) {
    logger.warning('Periodic sync failed', context: metrics.toJson());
  }
});
```

### Connectivity-Driven Sync

```dart
import 'package:connectivity_plus/connectivity_plus.dart';

// Listen to connectivity changes
Connectivity().onConnectivityChanged.listen((result) {
  if (result != ConnectivityResult.none) {
    // Connection restored, sync immediately
    engine.syncAll();
  }
});
```

### User-Triggered Sync

```dart
FloatingActionButton(
  onPressed: () async {
    final metrics = await engine.syncAll();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          metrics.overallSuccess 
            ? '✓ Synced ${metrics.totalRecordsPulled} changes'
            : '✗ Sync failed: ${metrics.totalErrors} errors',
        ),
      ),
    );
  },
  child: Icon(Icons.sync),
)
```

## 🛡️ Error Handling

```dart
try {
  await engine.syncAll();
} on SyncNetworkException catch (e) {
  // Network error (offline, timeout, connection failed)
  if (e.isOffline) {
    showMessage('You appear to be offline');
  } else {
    showMessage('Network error: ${e.statusCode}');
  }
} on SyncAuthException catch (e) {
  // Authentication error (session expired, unauthorized)
  redirectToLogin();
} on SchemaMigrationException catch (e) {
  // Schema error (database corruption or conflict)
  reportFatalError(e);
} on ConflictResolutionException catch (e) {
  // Custom conflict resolver failed
  logger.error('Conflict resolution failed for ${e.table}', error: e);
} on LocalStoreException catch (e) {
  // Local database error
  showMessage('Database error: ${e.message}');
} on ReplicoreException catch (e) {
  // Catch-all for all Replicore errors
  showMessage('Sync error: ${e.message}');
}
```

## 🏗️ Architecture & Extensibility

### Component Overview

```
┌─────────────────────────────────────┐
│        Your Flutter App              │
├─────────────────────────────────────┤
│         SyncEngine                   │
│  (Orchestrates bidirectional sync)   │
├──────────────┬──────────────────────┤
│              │                       │
│ LocalStore   │   RemoteAdapter      │
│              │                       │
│ SQLiteStore  │   SupabaseAdapter    │
│ (sqflite)    │   (restful APIs)     │
│              │   CustomAdapter      │
└──────────────┴──────────────────────┘

Logger             MetricsCollector
(structured logs)  (sync metrics)

DiagnosticsProvider
(health checks)
```

### Custom Remote Adapter

```dart
class RestApiAdapter implements RemoteAdapter {
  final HttpClient client;
  final LocalStore localStore;
  final String apiUrl;

  RestApiAdapter({
    required this.client,
    required this.localStore,
    required this.apiUrl,
  });

  @override
  Future<PullResult> pull(PullRequest request) async {
    try {
      final queryParams = {
        'table': request.table,
        'limit': request.limit.toString(),
      };

      if (request.cursor != null) {
        queryParams['cursor'] = jsonEncode(request.cursor!.toJson());
      }

      final uri = Uri.parse(apiUrl).replace(
        path: '/sync/pull',
        queryParameters: queryParams,
      );

      final response = await client.get(uri);

      if (response.statusCode == 401) {
        throw SyncAuthException(table: request.table);
      }

      if (response.statusCode != 200) {
        throw SyncNetworkException(
          table: request.table,
          message: 'Failed to pull',
          statusCode: response.statusCode,
        );
      }

      final body = jsonDecode(response.body);
      final records = List<Map<String, dynamic>>.from(body['records']);
      final nextCursor = body['nextCursor'] != null
          ? SyncCursor.fromJson(body['nextCursor'])
          : null;

      return PullResult(records: records, nextCursor: nextCursor);
    } catch (e) {
      throw SyncNetworkException(
        table: request.table,
        message: 'Pull failed: $e',
        cause: e,
      );
    }
  }

  @override
  Future<void> upsert({
    required String table,
    required Map<String, dynamic> data,
    String? idempotencyKey,
  }) async {
    // Implementation
  }

  @override
  Future<void> softDelete({
    required String table,
    required String primaryKeyColumn,
    required dynamic id,
    required Map<String, dynamic> payload,
    String? idempotencyKey,
  }) async {
    // Implementation
  }
}
```

### Custom Logger Integration

```dart
class DatadogLogger implements Logger {
  final Datadog datadog;

  DatadogLogger(this.datadog);

  @override
  void log(LogEntry entry) {
    datadog.logs?.add(
      LogEntry(
        message: entry.message,
        level: _mapLevel(entry.level),
        attributes: {
          ...?entry.context,
          'error': entry.error?.toString(),
          'stack_trace': entry.stackTrace?.toString(),
        },
      ),
    );
  }

  LogLevel _mapLevel(LogLevel level) {
    return switch (level) {
      LogLevel.debug => LogLevel.debug,
      LogLevel.info => LogLevel.info,
      LogLevel.warning => LogLevel.warning,
      LogLevel.error => LogLevel.error,
      LogLevel.critical => LogLevel.critical,
    };
  }

  // ... implement other methods
}
```

## 📋 Database Schema Requirements

### Required Columns

All Supabase tables must have these columns:

```sql
CREATE TABLE todos (
  -- Your application columns
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  completed BOOLEAN DEFAULT false,
  
  -- Required by Replicore
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  deleted_at TIMESTAMP WITH TIME ZONE NULL,
);

-- Highly recommended: Add index for sync performance
CREATE INDEX idx_todos_updated_at ON todos(updated_at);
```

### Local SQLite Columns

Replicore automatically adds these to your SQLite tables:

- `is_synced` (INTEGER) - Tracks if record has been synced (0=dirty, 1=clean)
- `op_id` (TEXT) - Operation ID for idempotency

These are added via `ALTER TABLE` during engine initialization.

## 🔒 Security Considerations

1. **RLS Policies**: Enforce row-level security in Supabase

```sql
-- Only users can see their own todos
CREATE POLICY select_own_todos ON todos
  FOR SELECT USING (user_id = auth.uid());
```

2. **Idempotency Keys**: Prevent duplicate operations on network retries

3. **Session Management**: Handle auth token refresh

```dart
Supabase.instance.auth.onAuthStateChange.listen((data) {
  if (data.session == null) {
    // User logged out, stop syncing
    engine.dispose();
  }
});
```

4. **Encryption**: Consider encrypting sensitive data at rest

## 🧪 Testing

### Unit Tests

```dart
test('conflict resolution works correctly', () async {
  final config = ReplicoreConfig.testing();
  
  final mockStore = MockLocalStore();
  final mockAdapter = MockRemoteAdapter();
  
  final engine = SyncEngine(
    localStore: mockStore,
    remoteAdapter: mockAdapter,
    config: config,
  );
  
  engine.registerTable(TableConfig(
    name: 'test_table',
    columns: ['id', 'value', 'updated_at', 'deleted_at'],
    strategy: SyncStrategy.lastWriteWins,
  ));
  
  // Test sync behavior
  await engine.init();
  final metrics = await engine.syncAll();
  
  expect(metrics.overallSuccess, true);
});
```

## 📈 Performance Tuning

1. **Batch Size**: Increase for large datasets, decrease for memory-constrained devices

```dart
config: ReplicoreConfig(
  batchSize: 2000, // Large batches for fast networks
)
```

2. **Indexes**: Add database indexes for better query performance

```sql
CREATE INDEX idx_table_column ON table(column);
```

3. **Periodic Sync Interval**: Balance between freshness and battery drain

```dart
periodicSyncInterval: Duration(minutes: 10), // Less frequent = longer battery life
```

## 🐛 Troubleshooting

### Sync completes but data not showing

1. Check if `is_synced` column exists in local database
2. Verify table is registered with `registerTable()`
3. Check network connectivity and authentication

### Conflicts not being resolved

1. Enable detailed logging to see conflict details
2. Verify custom resolver doesn't throw exceptions
3. Check that `updated_at` columns are being populated

### Memory usage growing

1. Reduce `batchSize` if processing large datasets
2. Call `engine.dispose()` to clean up resources
3. Monitor metrics to find bottlenecks

## 📚 Migration Guide

### From Manual Sync

If you currently manage sync manually:

```dart
// Before
Future<void> syncTodos() async {
  final remote = await supabase.from('todos').select();
  for (var item in remote) {
    await db.insert('todos', item);
  }
}

// After
await engine.syncAll();
```

### Version Upgrades

See CHANGELOG.md for breaking changes and migration steps.

## 📄 License

MIT - See LICENSE file

## Getting Help

- **Documentation**: https://github.com/leonhardWullich/replicore/docs
- **Issues**: https://github.com/leonhardWullich/replicore/issues
- **Discussions**: https://github.com/leonhardWullich/replicore/discussions
- **Enterprise Support**: contact@replicore.dev

---

**Built for teams who demand reliability, observability, and performance.**
