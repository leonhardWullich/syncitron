# Sync Orchestration Strategy - Advanced Control

> **Advanced topic for customizing synchronization workflows**

**Version**: 0.5.1 | **Last Updated**: March 9, 2026

---

## 📚 Overview

The `SyncOrchestrationStrategy` interface provides complete control over how Replicore executes synchronization. Instead of using the built-in sync methods, you can implement custom orchestrations to handle domain-specific requirements, priority-based syncing, error recovery patterns, and complex multi-step workflows.

### When to Use

Use custom orchestrations when:
- ✅ Certain tables must sync before others (priority-based)
- ✅ Network errors need graceful degradation
- ✅ Complex pre/post-sync validations are needed
- ✅ You need custom retry logic or error recovery
- ✅ Sync timing must follow business events (e.g., after user login)
- ✅ You need analytics or monitoring hooks

### Quick Start Example

```dart
import 'package:replicore/replicore.dart';

// Custom orchestration: Sync critical tables first
class CriticalFirstOrchestration extends SyncOrchestrationStrategy {
  @override
  Future<SyncSessionMetrics> execute(SyncOrchestrationContext context) async {
    // Sync critical tables first (e.g., users, auth)
    await context.managedSyncTable('users');
    await context.managedSyncTable('auth_tokens');
    
    // Then sync everything else
    final metrics = await context.managedSyncAll();
    
    return metrics;
  }
}

// Use it
final engine = SyncEngine(...);
final metrics = await engine.syncWithOrchestration(
  CriticalFirstOrchestration()
);
```

---

## 📖 Core Concepts

### The SyncOrchestrationStrategy Interface

The abstract base interface defines the contract for all orchestrations:

```dart
abstract class SyncOrchestrationStrategy {
  /// Execute the custom sync orchestration logic.
  /// Returns aggregated SyncSessionMetrics.
  Future<SyncSessionMetrics> execute(SyncOrchestrationContext context);

  /// Called before sync starts. Override to execute pre-sync hooks.
  Future<void> beforeSync(SyncOrchestrationContext context) async {}

  /// Called after sync completes (success or failure).
  Future<void> afterSync(
    SyncOrchestrationContext context,
    SyncSessionMetrics metrics,
  ) async {}
}
```

### The SyncOrchestrationContext

The context parameter provides utilities for safe, controlled syncing:

```dart
abstract class SyncOrchestrationContext {
  /// Structured logger for sync execution logging
  Logger get logger;

  /// Metrics collector for performance tracking
  MetricsCollector get metricsCollector;

  /// All registered table names in execution order
  List<String> get tableNames;

  /// Sync start time (for duration calculations)
  DateTime get startTime;

  /// Sync a single table with automatic error handling
  Future<SyncMetrics> managedSyncTable(String tableName);

  /// Sync all tables with automatic error handling
  Future<SyncSessionMetrics> managedSyncAll();

  /// Check if sync should continue (respects cancellation/timeout)
  bool shouldContinue();

  /// Cancel the ongoing sync operation
  void cancel();
}
```

---

## 🎯 Built-In Orchestrations

Replicore provides five production-ready orchestrations for common patterns:

### 1. StandardSyncOrchestration (Default)

Syncs all tables in sequence using the standard pull-push-conflict pattern.

**Use when**: You want the default behavior (most cases).

```dart
final engine = SyncEngine(...);

// These are equivalent:
final metrics1 = await engine.syncAll();
final metrics2 = await engine.syncWithOrchestration(
  StandardSyncOrchestration()
);

// Behavior:
// 1. Pull remote changes for all tables
// 2. Push local changes for all tables
// 3. Resolve conflicts
// 4. Return aggregated metrics
```

**Characteristics**:
- ✅ Simplest orchestration
- ✅ Predictable behavior
- ✅ 0 configuration needed
- ❌ All tables treated equally
- ❌ One table error stops all sync

---

### 2. OfflineFirstSyncOrchestration

Tolerates network errors gracefully and continues with remaining tables. Perfect for unreliable networks where partial sync is acceptable.

**Use when**: Network is unreliable or you have LTE devices.

```dart
final engine = SyncEngine(...);

final metrics = await engine.syncWithOrchestration(
  OfflineFirstSyncOrchestration(maxNetworkErrors: 3)
);

// Behavior:
// 1. Sync each table in sequence
// 2. On network error: log warning, increment error counter, continue
// 3. If network errors exceed threshold: stop attempting to sync
// 4. Return partial metrics with successful table syncs
```

**Characteristics**:
- ✅ Continues even with network errors
- ✅ Configurable error threshold
- ✅ Caches partial sync
- ❌ May leave some tables unsynced
- ❌ No automatic retry

**Configuration**:
```dart
// Default: stop after 3 network errors
OfflineFirstSyncOrchestration()

// More aggressive: tolerate 10 network errors
OfflineFirstSyncOrchestration(maxNetworkErrors: 10)

// Conservative: stop after 1 network error
OfflineFirstSyncOrchestration(maxNetworkErrors: 1)
```

---

### 3. StrictManualOrchestration

Never retries automatically; preserves all errors for explicit user handling. Use when you need absolute control.

**Use when**: You implement your own error handling and retry logic.

```dart
final engine = SyncEngine(...);

try {
  final metrics = await engine.syncWithOrchestration(
    StrictManualOrchestration()
  );
} on ConflictException catch (e) {
  // Handle conflicts explicitly
  await showConflictDialog(e.conflicts);
} on SyncNetworkException catch (e) {
  // Handle network errors explicitly
  await showNetworkError(e.message);
} on ReplicoreException catch (e) {
  // Handle other sync errors
  logError(e);
}

// Behavior:
// 1. Sync all tables in sequence
// 2. On ANY error: immediately rethrow (no recovery)
// 3. No automatic retry or error suppression
```

**Characteristics**:
- ✅ Explicit error handling
- ✅ No hidden behavior
- ✅ Full control over retry logic
- ❌ Requires error handling code
- ❌ More boilerplate

---

### 4. PrioritySyncOrchestration

Syncs tables in priority order. Critical tables fail-fast, optional tables tolerate errors.

**Use when**: Some tables are more important than others (e.g., user data before preferences).

```dart
final engine = SyncEngine(...);

final priorities = {
  'users': 100,          // Critical: sync first, fail-fast
  'auth_tokens': 100,
  'subscriptions': 50,   // Important: sync second
  'todos': 10,           // Nice-to-have: tolerates errors
  'preferences': 5,      // Optional: skip on error
};

final metrics = await engine.syncWithOrchestration(
  PrioritySyncOrchestration(priorities)
);

// Behavior:
// 1. Sort tables by priority (100 → 10 → 5)
// 2. Sync each table in order
// 3. Critical table error (priority >= 100): stop, rethrow
// 4. Optional table error (priority < 100): log, continue
// 5. Return metrics with partially synced tables
```

**Characteristics**:
- ✅ Guarantees critical tables sync first
- ✅ Isolates errors by table priority
- ✅ Configurable priority levels
- ⚠️ Stops on critical table errors
- ⚠️ Requires priority mapping

**Priority Levels** (recommended):
- `100+` → Critical (e.g., user, auth, security data)
- `50-99` → Important (e.g., subscriptions, configuration)
- `1-49` → Optional (e.g., preferences, cache, analytics)
- `0` → Default/Undefined (treated as optional)

---

### 5. CompositeSyncOrchestration

Composes multiple orchestrations sequentially with pre/post hooks. Enables advanced pipelines.

**Use when**: You need to combine multiple strategies or custom hooks.

```dart
final engine = SyncEngine(...);

final pipeline = CompositeSyncOrchestration([
  PreSyncValidationHook(),         // Custom validation
  StandardSyncOrchestration(),     // Core sync
  PostSyncAnalyticsHook(),         // Custom analytics
]);

final metrics = await engine.syncWithOrchestration(pipeline);

// Behavior:
// 1. PreSyncValidationHook.beforeSync() + execute() + afterSync()
// 2. StandardSyncOrchestration.beforeSync() + execute() + afterSync()
// 3. PostSyncAnalyticsHook.beforeSync() + execute() + afterSync()
// 4. Return aggregated metrics
```

**Characteristics**:
- ✅ Enables complex pipelines
- ✅ Composes multiple strategies
- ✅ Pre/post hooks per strategy
- ⚠️ More moving parts
- ⚠️ Order matters

---

## 🛠️ Creating Custom Orchestrations

### Example 1: Sync Critical Tables First

```dart
class CriticalFirstOrchestration extends SyncOrchestrationStrategy {
  final Set<String> criticalTables;

  CriticalFirstOrchestration({
    this.criticalTables = const {'users', 'auth', 'config'},
  });

  @override
  Future<SyncSessionMetrics> execute(SyncOrchestrationContext context) async {
    final metricsPerTable = <SyncMetrics>[];

    // Sync critical tables first
    for (final tableName in context.tableNames) {
      if (criticalTables.contains(tableName) && context.shouldContinue()) {
        try {
          final metrics = await context.managedSyncTable(tableName);
          metricsPerTable.add(metrics);
        } catch (e) {
          context.logger.error(
            'Critical table $tableName failed to sync',
            error: e,
          );
          rethrow; // Stop if critical table fails
        }
      }
    }

    // Then sync remaining tables
    for (final tableName in context.tableNames) {
      if (!criticalTables.contains(tableName) && context.shouldContinue()) {
        try {
          final metrics = await context.managedSyncTable(tableName);
          metricsPerTable.add(metrics);
        } catch (e) {
          context.logger.warning(
            'Optional table $tableName failed to sync',
            error: e,
          );
          // Continue on error for non-critical tables
        }
      }
    }

    final session = SyncSessionMetrics();
    for (final metric in metricsPerTable) {
      session.addTableMetrics(metric);
    }
    return session;
  }
}
```

**Usage**:
```dart
final metrics = await engine.syncWithOrchestration(
  CriticalFirstOrchestration(
    criticalTables: {'users', 'subscriptions'},
  )
);
```

---

### Example 2: Custom Retry Logic

```dart
class ExponentialBackoffOrchestration extends SyncOrchestrationStrategy {
  final int maxRetries;
  final Duration initialDelay;

  ExponentialBackoffOrchestration({
    this.maxRetries = 3,
    this.initialDelay = const Duration(milliseconds: 100),
  });

  @override
  Future<SyncSessionMetrics> execute(SyncOrchestrationContext context) async {
    final metricsPerTable = <SyncMetrics>[];

    for (final tableName in context.tableNames) {
      if (!context.shouldContinue()) break;

      SyncMetrics? metrics;
      Duration delay = initialDelay;

      for (int attempt = 0; attempt <= maxRetries; attempt++) {
        try {
          context.logger.info(
            'Syncing $tableName (attempt ${attempt + 1}/$maxRetries)',
          );
          metrics = await context.managedSyncTable(tableName);
          break; // Success, exit retry loop
        } on SyncNetworkException catch (e) {
          if (attempt < maxRetries) {
            context.logger.warning(
              'Sync failed, retrying in ${delay.inMilliseconds}ms',
              error: e,
            );
            await Future.delayed(delay);
            delay *= 2; // Exponential backoff
          } else {
            context.logger.error('Max retries exceeded for $tableName');
            rethrow;
          }
        }
      }

      if (metrics != null) {
        metricsPerTable.add(metrics);
      }
    }

    final session = SyncSessionMetrics();
    for (final metric in metricsPerTable) {
      session.addTableMetrics(metric);
    }
    return session;
  }
}
```

**Usage**:
```dart
final metrics = await engine.syncWithOrchestration(
  ExponentialBackoffOrchestration(
    maxRetries: 5,
    initialDelay: Duration(milliseconds: 500),
  )
);
```

---

### Example 3: Analytics & Monitoring Hooks

```dart
class AnalyticsOrchestration extends SyncOrchestrationStrategy {
  final void Function(SyncSessionMetrics) onSyncComplete;

  AnalyticsOrchestration({required this.onSyncComplete});

  @override
  Future<void> beforeSync(SyncOrchestrationContext context) async {
    context.logger.info('Sync started - Tables: ${context.tableNames.join(", ")}');
    // Validate network, check storage, etc.
  }

  @override
  Future<SyncSessionMetrics> execute(SyncOrchestrationContext context) async {
    return context.managedSyncAll();
  }

  @override
  Future<void> afterSync(
    SyncOrchestrationContext context,
    SyncSessionMetrics metrics,
  ) async {
    context.logger.info(
      'Sync completed - Pulled: ${metrics.totalRecordsPulled}, '
      'Pushed: ${metrics.totalRecordsPushed}',
    );

    // Send to analytics
    onSyncComplete(metrics);

    // Could also cache metrics to local storage
    // or send to backend monitoring system
  }
}
```

**Usage**:
```dart
final metrics = await engine.syncWithOrchestration(
  AnalyticsOrchestration(
    onSyncComplete: (metrics) {
      _analyticsService.logSync(
        recordsPulled: metrics.totalRecordsPulled,
        recordsPushed: metrics.totalRecordsPushed,
        duration: metrics.duration,
        success: metrics.overallSuccess,
      );
    },
  )
);
```

---

### Example 4: Conditional Table Syncing

```dart
class SelectiveOrchestration extends SyncOrchestrationStrategy {
  final Set<String> tablesToSync;

  SelectiveOrchestration(this.tablesToSync);

  @override
  Future<SyncSessionMetrics> execute(SyncOrchestrationContext context) async {
    final metricsPerTable = <SyncMetrics>[];

    for (final tableName in context.tableNames) {
      if (!tablesToSync.contains(tableName)) {
        context.logger.debug('Skipping table: $tableName');
        continue;
      }

      if (!context.shouldContinue()) break;

      try {
        final metrics = await context.managedSyncTable(tableName);
        metricsPerTable.add(metrics);
      } catch (e) {
        context.logger.error('Failed to sync $tableName', error: e);
        rethrow;
      }
    }

    final session = SyncSessionMetrics();
    for (final metric in metricsPerTable) {
      session.addTableMetrics(metric);
    }
    return session;
  }
}
```

**Usage**:
```dart
// Only sync these tables
final metrics = await engine.syncWithOrchestration(
  SelectiveOrchestration({'users', 'todos'})
);
```

---

## 🔄 Combining with beforeSync/afterSync

The lifecycle methods `beforeSync()` and `afterSync()` provide hooks for validation and cleanup:

```dart
class AdvancedOrchestration extends SyncOrchestrationStrategy {
  @override
  Future<void> beforeSync(SyncOrchestrationContext context) async {
    // Pre-sync validation
    if (!await _validateNetworkConnectivity()) {
      throw SyncNetworkException('No network available');
    }

    if (!await _hasStorageSpace()) {
      throw ReplicoreException('Insufficient storage space');
    }

    context.logger.info('Pre-sync validation passed');
  }

  @override
  Future<SyncSessionMetrics> execute(SyncOrchestrationContext context) async {
    return context.managedSyncAll();
  }

  @override
  Future<void> afterSync(
    SyncOrchestrationContext context,
    SyncSessionMetrics metrics,
  ) async {
    // Post-sync cleanup and persistence
    if (metrics.overallSuccess) {
      await _persistLastSyncTime();
      await _clearSyncCache();
      
      context.logger.info(
        'Sync completed successfully in ${metrics.duration.inSeconds}s'
      );
    } else {
      context.logger.warning('Sync completed with errors');
    }
  }

  Future<bool> _validateNetworkConnectivity() => Future.value(true);
  Future<bool> _hasStorageSpace() => Future.value(true);
  Future<void> _persistLastSyncTime() async {}
  Future<void> _clearSyncCache() async {}
}
```

---

## 📊 Working with Metrics

Access sync metrics and performance data:

```dart
final metrics = await engine.syncWithOrchestration(strategy);

// Session-level metrics
print('Overall success: ${metrics.overallSuccess}');
print('Total records pulled: ${metrics.totalRecordsPulled}');
print('Total records pushed: ${metrics.totalRecordsPushed}');
print('Total duration: ${metrics.duration.inSeconds}s');
print('Conflicts encountered: ${metrics.conflictsEncountered}');

// Per-table metrics
for (final tableMetrics in metrics.metrics) {
  print('Table: ${tableMetrics.tableName}');
  print('  - Pulled: ${tableMetrics.recordsPulled}');
  print('  - Pushed: ${tableMetrics.recordsPushed}');
  print('  - Duration: ${tableMetrics.duration.inMilliseconds}ms');
}
```

---

## ✅ Best Practices

1. **Always check `context.shouldContinue()`**
   - Respects cancellation and timeout flags
   - Prevents unnecessary sync operations

2. **Use `context.logger` for diagnostics**
   - Structured logging integrates with APM tools
   - Essential for debugging sync issues

3. **Aggregate metrics properly**
   - Return `SyncSessionMetrics()` not individual table metrics
   - Use `session.addTableMetrics(metric)` to combine results

4. **Handle errors appropriately**
   - Critical tables: rethrow to stop sync
   - Optional tables: log and continue

5. **Keep orchestrations testable**
   - Avoid hard dependencies
   - Accept tables/priorities as constructor arguments
   - Use context for all sync operations

6. **Profile before optimizing**
   - Measure sync duration and record counts
   - Use metrics to identify bottlenecks
   - Compare strategies with benchmarks

---

## 🎓 Advanced Patterns

### Pattern 1: Timeout-Based Orchestration

```dart
class TimeoutOrchestration extends SyncOrchestrationStrategy {
  final Duration syncTimeout;

  TimeoutOrchestration(this.syncTimeout);

  @override
  Future<SyncSessionMetrics> execute(SyncOrchestrationContext context) async {
    final startTime = DateTime.now();

    final metricsPerTable = <SyncMetrics>[];
    for (final tableName in context.tableNames) {
      if (!context.shouldContinue()) break;

      final elapsed = DateTime.now().difference(startTime);
      if (elapsed > syncTimeout) {
        context.logger.warning('Sync timeout reached');
        break;
      }

      try {
        final metrics = await context.managedSyncTable(tableName);
        metricsPerTable.add(metrics);
      } catch (e) {
        context.logger.error('Failed to sync $tableName', error: e);
      }
    }

    final session = SyncSessionMetrics();
    for (final metric in metricsPerTable) {
      session.addTableMetrics(metric);
    }
    return session;
  }
}
```

### Pattern 2: Queue-Based Orchestration

```dart
class QueuedOrchestration extends SyncOrchestrationStrategy {
  final Queue<String> syncQueue;

  QueuedOrchestration(List<String> initialQueue)
      : syncQueue = Queue<String>.from(initialQueue);

  @override
  Future<SyncSessionMetrics> execute(SyncOrchestrationContext context) async {
    final metricsPerTable = <SyncMetrics>[];

    while (syncQueue.isNotEmpty && context.shouldContinue()) {
      final tableName = syncQueue.removeFirst();

      try {
        final metrics = await context.managedSyncTable(tableName);
        metricsPerTable.add(metrics);
      } catch (e) {
        context.logger.error('Failed to sync $tableName', error: e);
        // Re-queue for retry
        syncQueue.add(tableName);
      }
    }

    final session = SyncSessionMetrics();
    for (final metric in metricsPerTable) {
      session.addTableMetrics(metric);
    }
    return session;
  }
}
```

---

## 📋 Summary Table

| Strategy | Use Case | Error Handling | Requires Config |
|----------|----------|----------------|-----------------|
| **Standard** | General purpose sync | Fail-fast | No |
| **OfflineFirst** | Unreliable networks | Tolerates N errors | Yes (threshold) |
| **StrictManual** | Full control needed | User handles | No |
| **Priority** | Mixed importance tables | By priority level | Yes (map) |
| **Composite** | Complex pipelines | Per-sub-strategy | Depends |

---

## 🔗 Related Documentation

- [Architecture Overview](./02_ARCHITECTURE.md) - System design
- [Error Handling](./12_ERROR_HANDLING.md) - Exception types and recovery
- [Performance Optimization](./10_PERFORMANCE_OPTIMIZATION.md) - Sync tuning
- [Configuration](./11_CONFIGURATION.md) - Replicore config options

---

## 📞 Support

For help with custom orchestrations:
- Check [Troubleshooting](./17_TROUBLESHOOTING.md)
- Review [API Reference](./14_API_REFERENCE.md)
- Open an issue on GitHub with your use case
