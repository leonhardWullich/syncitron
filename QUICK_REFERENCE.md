# Replicore v0.2.0 - Quick Reference

## Installation

```bash
flutter pub add replicore
```

## Basic Setup (5 minutes)

```dart
import 'package:replicore/replicore.dart';

// 1. Create config
final config = ReplicoreConfig.production();

// 2. Create engine
final engine = SyncEngine(
  localStore: SqfliteStore(database),
  remoteAdapter: SupabaseAdapter(
    client: Supabase.instance.client,
    localStore: SqfliteStore(database),
  ),
  config: config,
  logger: ConsoleLogger(),
);

// 3. Register tables
engine.registerTable(TableConfig(
  name: 'todos',
  columns: ['id', 'title', 'completed', 'updated_at', 'deleted_at'],
  strategy: SyncStrategy.lastWriteWins,
));

// 4. Initialize & sync
await engine.init();
final metrics = await engine.syncAll();
print(metrics);
```

## Common Tasks

### Sync All Tables
```dart
final metrics = await engine.syncAll();
print('Success: ${metrics.overallSuccess}');
print('Pulled: ${metrics.totalRecordsPulled}');
print('Pushed: ${metrics.totalRecordsPushed}');
```

### Sync Specific Table
```dart
final metrics = await engine.syncTable(tableConfig);
```

### Listen to Sync Status
```dart
engine.statusStream.listen((status) {
  print('Status: $status');
});
```

### Setup Periodic Sync
```dart
Timer.periodic(Duration(minutes: 5), (_) {
  engine.syncAll();
});
```

### Handle Errors
```dart
try {
  await engine.syncAll();
} on SyncNetworkException catch (e) {
  print('Network error: $e');
} on SyncAuthException catch (e) {
  print('Auth error: $e');
} on ReplicoreException catch (e) {
  print('Sync error: $e');
}
```

### Check System Health
```dart
final health = await systemDiagnostics.checkHealth();
if (health.isHealthy) {
  print('System is healthy');
}
```

### Get Metrics
```dart
final metrics = await engine.syncAll();
print(metrics.toJson()); // Export for analytics
```

## Configuration Presets

### Production (Recommended)
```dart
final config = ReplicoreConfig.production();
// - Large batches (1000 records)
// - Aggressive retries (5 attempts)
// - Longer backoff (up to 5 minutes)
// - Periodic sync enabled (5 minutes)
// - No detailed logging
// - Metrics enabled
```

### Development
```dart
final config = ReplicoreConfig.development();
// - Small batches (100 records)
// - Few retries (2 attempts)
// - Detailed logging enabled
// - Metrics enabled
// - Shorter timeouts
```

### Testing
```dart
final config = ReplicoreConfig.testing();
// - Minimal batch sizes (50 records)
// - No metrics overhead
// - No logging
// - Fast initialization
```

### Custom
```dart
final config = ReplicoreConfig(
  batchSize: 500,
  maxRetries: 3,
  initialRetryDelay: Duration(seconds: 1),
  maxRetryDelay: Duration(minutes: 2),
  enableDetailedLogging: true,
  periodicSyncInterval: Duration(minutes: 10),
);
```

## Conflict Resolution Strategies

| Strategy | Behavior | Use Case |
|----------|----------|----------|
| `serverWins` | Remote always wins | Reference data, settings |
| `localWins` | Local always wins | User drafts, preferences |
| `lastWriteWins` | Latest timestamp wins | General collaborative data |
| `custom` | Your logic | Complex merges |

```dart
// Server Wins
TableConfig(name: 'settings', strategy: SyncStrategy.serverWins, columns: [...])

// Local Wins
TableConfig(name: 'drafts', strategy: SyncStrategy.localWins, columns: [...])

// Last Write Wins
TableConfig(name: 'todos', strategy: SyncStrategy.lastWriteWins, columns: [...])

// Custom
TableConfig(
  name: 'lists',
  strategy: SyncStrategy.custom,
  customResolver: (local, remote) async {
    return UseMerged({...remote, ...local});
  },
  columns: [...],
)
```

## Logging

### Console Logger
```dart
final logger = ConsoleLogger(minLevel: LogLevel.info);

final engine = SyncEngine(
  localStore: store,
  remoteAdapter: adapter,
  logger: logger,
);
```

### Custom Logger Integration
```dart
class SentryLogger implements Logger {
  @override
  void error(String message, {Object? error, StackTrace? stackTrace, Map<String, dynamic>? context}) {
    Sentry.captureException(error, stackTrace: stackTrace);
  }
  // ... implement other methods
}
```

### Multi-Logger
```dart
final logger = MultiLogger([
  ConsoleLogger(),
  SentryLogger(),
  CustomAnalyticsLogger(),
]);
```

## Log Levels

- `LogLevel.debug` - Verbose information (development)
- `LogLevel.info` - General informational (default)
- `LogLevel.warning` - Warning conditions
- `LogLevel.error` - Error conditions
- `LogLevel.critical` - Critical failures

## Metrics

### SyncMetrics (Per-Table)
```dart
final tableMetrics = metrics.tableMetrics[0];
print('Table: ${tableMetrics.tableName}');
print('Duration: ${tableMetrics.duration.inMilliseconds}ms');
print('Pulled: ${tableMetrics.recordsPulled}');
print('Pushed: ${tableMetrics.recordsPushed}');
print('Conflicts: ${tableMetrics.recordsWithConflicts}');
print('Success: ${tableMetrics.success}');
```

### SyncSessionMetrics (Overall)
```dart
final sessionMetrics = await engine.syncAll();
print('Total Duration: ${sessionMetrics.totalDuration.inMilliseconds}ms');
print('Total Tables: ${sessionMetrics.totalTablesSynced}');
print('Total Pulled: ${sessionMetrics.totalRecordsPulled}');
print('Total Pushed: ${sessionMetrics.totalRecordsPushed}');
print('Total Conflicts: ${sessionMetrics.totalConflicts}');
print('Overall Success: ${sessionMetrics.overallSuccess}');
```

## Database Schema

Required columns in Supabase tables:
```sql
CREATE TABLE todos (
  id UUID PRIMARY KEY,
  title TEXT,
  completed BOOLEAN DEFAULT false,
  updated_at TIMESTAMP DEFAULT now(),
  deleted_at TIMESTAMP NULL
);

-- Index for performance
CREATE INDEX idx_updated_at ON todos(updated_at);
```

Local SQLite tables automatically get:
- `is_synced` (INTEGER) - Sync status flag
- `op_id` (TEXT) - Operation ID for idempotency

## Troubleshooting

### Sync Hangs
```dart
// Enable detailed logging
final logger = ConsoleLogger(minLevel: LogLevel.debug);
final metrics = await engine.syncAll();
print(metrics); // Shows timing and bottlenecks
```

### Data Not Syncing
- Check `is_synced` column exists in SQLite
- Verify `updated_at` column exists in Supabase
- Confirm table is registered with `registerTable()`
- Check network connectivity

### Conflicts Not Resolved
- Verify custom resolver doesn't throw
- Check `updated_at` values are populated
- Ensure correct strategy selected

## Version Compatibility

- **Dart**: ^3.10.8
- **Flutter**: ^3.0.0
- **sqflite**: ^2.4.2
- **supabase_flutter**: ^2.12.0

## Migration from v0.1.0

```dart
// OLD (v0.1.0)
SyncEngine(
  localStore: store,
  remoteAdapter: adapter,
  batchSize: 500,
  onLog: (msg) => print(msg),
)

// NEW (v0.2.0)
SyncEngine(
  localStore: store,
  remoteAdapter: adapter,
  config: ReplicoreConfig.production(),
  logger: ConsoleLogger(),
  metricsCollector: InMemoryMetricsCollector(),
)
```

Breaking changes:
- Constructor parameters changed
- `syncAll()` now returns metrics
- `onLog` callback deprecated

## Performance Tips

1. **Batch Size**: Increase for better networks, decrease for constrained devices
2. **Indexes**: Add `updated_at` index in Supabase for faster queries
3. **Sync Interval**: Balance between freshness and battery drain
4. **Conflict Resolver**: Keep logic simple and fast
5. **Logging**: Use appropriate log level for production

## Security Checklist

- [ ] Use RLS policies in Supabase
- [ ] Don't log sensitive data
- [ ] Validate user input before syncing
- [ ] Update dependencies regularly
- [ ] Handle auth token refresh
- [ ] Implement proper session management

## Resources

- **Full Documentation**: `ENTERPRISE_README.md`
- **Best Practices**: `docs/ENTERPRISE_PATTERNS.md`
- **Contributing**: `CONTRIBUTING.md`
- **Changelog**: `CHANGELOG.md`
- **GitHub**: https://github.com/leonhardWullich/replicore

## Version

Current: **0.2.0** (2026-03-05)

- Logging framework ✓
- Metrics & monitoring ✓
- Configuration management ✓
- Health checks ✓
- SyncManager ✓
- Enterprise documentation ✓
