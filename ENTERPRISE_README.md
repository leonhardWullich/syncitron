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

### Orchestration vs. Conflict Resolution: What's the Difference?

In enterprise environments, you need **two levels of control**:

1. **Conflict Resolution** (Row-level): When the same record is modified locally AND remotely, which version wins? (Covered in earlier section)
2. **Sync Orchestration** (Flow-level): In what order should tables sync? How should the system behave when one table fails? What hooks do we need for pre/post-processing?

While Conflict Resolution answers "how to merge data," Sync Orchestration answers "how to orchestrate the entire sync workflow."

### Core Concept: Orchestration Strategies

The `SyncOrchestrationStrategy` interface allows you to implement custom sync workflows. Replicore provides five production-ready strategies, but you can build your own.

```dart
abstract class SyncOrchestrationStrategy {
  Future<SyncSessionMetrics> execute(SyncEngine engine);
}
```

---

## 📊 Built-in Orchestration Strategies

### 1. **StandardSyncOrchestration** (Default)

Simple, predictable sync: push all local changes first, then pull all remote changes. Best for most applications.

```dart
final metrics = await engine.syncWithOrchestration(
  StandardSyncOrchestration(),
);

// Flow:
// 1. Push local changes for all tables (batched)
// 2. Pull remote changes for all tables (batched)
// 3. Return metrics (conflicts, errors, duration)
```

**When to use:**
- Simple CRUD apps with occasional conflicts
- All tables have equal importance
- Network is relatively stable
- You don't need pre/post-sync hooks

**Characteristics:**
- Fast and straightforward
- Treats all tables equally
- Fails on first critical error
- Minimal overhead

---

### 2. **PrioritySyncOrchestration**

Enterprise favorite! Syncs tables in priority order and fails-fast on high-priority data, while gracefully degrading on lower-priority data.

```dart
final metrics = await engine.syncWithOrchestration(
  PrioritySyncOrchestration({
    'users': 100,              // Critical: Must succeed
    'subscriptions': 90,       // High: Fail-fast
    'order_items': 80,         // Medium: Warn on error
    'cache_images': 10,        // Low: Skip gracefully
    'analytics_events': 1,     // Lowest: Best-effort only
  }),
);

// Flow:
// 1. Sort tables by priority (descending)
// 2. Push each table (prioritized)
// 3. Pull each table (prioritized)
// 4. High-priority failures → stop immediately
// 5. Low-priority failures → log warning, continue
```

**When to use:**
- Enterprise applications with dependent data hierarchies
- Some tables are more critical than others
- Need fail-fast semantics for core data
- Want graceful degradation for secondary data

**Example: E-commerce Platform**
```dart
final ecommercePriorities = {
  'users': 100,              // Must have users
  'accounts': 95,            // Must have accounts
  'orders': 90,              // Core business data
  'order_items': 85,         // Detail lines
  'inventory': 80,           // Important but can retry
  'reviews': 50,             // Nice to have
  'recommendations': 20,     // Best-effort only
};

final metrics = await engine.syncWithOrchestration(
  PrioritySyncOrchestration(ecommercePriorities),
);

// If 'orders' fails: entire sync stops (critical data)
// If 'reviews' fails: logged as warning, sync continues
```

**Error Behavior Chart:**

| Priority | 100-80 | 79-30 | 29-1 |
|----------|--------|-------|------|
| Error Handling | Fail-fast (stop) | Warn & continue | Log & ignore |
| Retry Count | 5 | 3 | 1 |
| Impact | Blocks release | User sees warning | Invisible to user |

---

### 3. **OfflineFirstSyncOrchestration**

Designed for unreliable networks, poor connectivity zones, and battery-conscious apps. Tolerates a specific number of transient errors before gracefully backing off.

```dart
final metrics = await engine.syncWithOrchestration(
  OfflineFirstSyncOrchestration(
    maxNetworkErrors: 3,      // Abort after 3 timeouts
    backoffMultiplier: 2.0,   // 1s → 2s → 4s delays
    maxBackoffDuration: Duration(seconds: 30),
  ),
);

// Flow:
// 1. Attempt sync with normal retry logic
// 2. Count network timeouts/connection failures
// 3. If count reaches maxNetworkErrors → abort gracefully
// 4. User gets "last synced X minutes ago" message
// 5. Next manual sync starts fresh retry count
```

**When to use:**
- Field-service apps (delivery drivers, technicians)
- Emerging markets with spotty connectivity
- Rural/remote deployments
- Battery-critical scenarios (drones, IoT)
- Apps running on shaky 2G/3G networks

**Real-World Example: Delivery Driver App**
```dart
// Driver is in rural area with poor signal
// Their phone might go offline multiple times

final driverSyncConfig = OfflineFirstSyncOrchestration(
  maxNetworkErrors: 5,  // Allow 5 timeout attempts within sync window
  backoffMultiplier: 1.5,
  maxBackoffDuration: Duration(minutes: 2),
);

final result = await engine.syncWithOrchestration(driverSyncConfig);

if (!result.overallSuccess) {
  // Instead of angry error, show graceful message:
  showMessage(
    'Last synced at ${result.lastSyncTime}. '
    'Will retry when connection improves.'
  );
}
```

**Network Behavior:**
```
Attempt 1: Timeout (1s backoff)
Attempt 2: Timeout (1.5s backoff)
Attempt 3: Timeout (2.25s backoff)
Attempt 4: Timeout (3.375s backoff)
Attempt 5: Timeout (5s backoff) → STOP
Result: "We'll try again later" (graceful)
```

---

### 4. **StrictManualOrchestration**

Zero automatic retries. Every error surfaces immediately to your code, giving complete control over failure handling.

```dart
final metrics = await engine.syncWithOrchestration(
  StrictManualOrchestration(
    autoRetry: false,         // NEVER retry automatically
    throwOnError: true,       // Throw exception on any error
  ),
);
```

**When to use:**
- Payment processing (never auto-retry payment syncs)
- PII/Healthcare data (strict audit trail needed)
- Financial transactions
- Compliance-sensitive workflows
- You want explicit error handling in your code

**Medical Records Example:**
```dart
try {
  final metrics = await engine.syncWithOrchestration(
    StrictManualOrchestration(),
  );
  // Log: "Patient records synced successfully"
  auditLog.logSuccess(userId, metrics);
} on SyncError catch (e) {
  // NEVER ignore! Explicitly handle:
  if (e is AuthenticationError) {
    navigateToReLoginScreen();
  } else if (e is NetworkError) {
    // Don't auto-retry; ask user permission first
    showErrorDialog('Network failed. Retry?', onRetry: () {
      // User explicitly chose to retry
      engine.syncAll();
    });
  } else if (e is ConflictError) {
    // Medical records shouldn't auto-merge; escalate to clinician
    notifyClinicianOfConflict(e.conflictedRecords);
  }
  auditLog.logError(userId, e);
}
```

**Contrast with StandardSyncOrchestration:**
```dart
// Standard: Logs errors, continues app, tries to recover
final metrics = await engine.syncWithOrchestration(
  StandardSyncOrchestration(),
);

// Strict: Throws immediately, puts responsibility on you
try {
  final metrics = await engine.syncWithOrchestration(
    StrictManualOrchestration(),
  );
} on SyncError catch (e) {
  // YOU decide how to handle this
}
```

---

### 5. **CompositeSyncOrchestration** (Pipelines)

Chain multiple strategies and lifecycle hooks together to build complex workflows.

```dart
final pipeline = CompositeSyncOrchestration([
  // Phase 1: Pre-sync validation
  CustomHook(
    beforeSync: () async {
      // Check disk space
      final space = await getDiskFreeSpace();
      if (space < 100 * 1024 * 1024) {
        throw InsufficientStorageError();
      }
      
      // Validate auth token
      if (!await isAuthTokenValid()) {
        throw AuthenticationError();
      }
      
      // Pause background tasks
      await backgroundTaskManager.pauseAll();
    },
  ),
  
  // Phase 2: The actual sync (with priorities)
  PrioritySyncOrchestration({
    'users': 100,
    'subscriptions': 90,
    'messages': 70,
    'analytics': 10,
  }),
  
  // Phase 3: Post-sync analytics
  CustomHook(
    afterSync: (metrics) async {
      // Upload metrics to analytics backend
      await analyticsService.reportSync(metrics);
      
      // Trigger dependent operations
      await indexSearchDatabase();
      await preloadCriticalImages();
      
      // Resume background tasks
      await backgroundTaskManager.resumeAll();
      
      // Notify listeners
      notificationService.notifyApp('Sync complete!');
    },
  ),
]);

final result = await engine.syncWithOrchestration(pipeline);
```

**Creating Custom Hooks:**
```dart
class CustomHook extends SyncOrchestrationStrategy {
  final Future<void> Function()? beforeSync;
  final Future<void> Function(SyncSessionMetrics)? afterSync;
  
  CustomHook({this.beforeSync, this.afterSync});
  
  @override
  Future<SyncSessionMetrics> execute(SyncEngine engine) async {
    // Run pre-sync hook
    if (beforeSync != null) {
      await beforeSync!();
    }
    
    // Do the actual sync
    final metrics = await StandardSyncOrchestration().execute(engine);
    
    // Run post-sync hook
    if (afterSync != null) {
      await afterSync!(metrics);
    }
    
    return metrics;
  }
}
```

**When to use:**
- Complex multi-phase sync workflows
- Need pre-sync validation or setup
- Need post-sync cleanup or analytics
- Want to implement custom strategies

---

## 🎯 Orchestration Strategy Comparison Matrix

| Feature | Standard | OfflineFirst | Strict | Priority | Composite |
|---------|----------|--------------|--------|----------|-----------|
| **Auto Retry** | Yes (5x) | Yes, limited | No | Yes | Configurable |
| **Table Priority** | Equal | Equal | Equal | **Configurable** | Via nesting |
| **Network Tolerance** | Low | **High** | None | Medium | Custom |
| **Error Behavior** | Log & continue | Graceful backoff | Throw immediately | Tiered fail-fast | Custom hooks |
| **Lifecycle Hooks** | No | No | No | No | **Yes** |
| **Complexity** | Low | Low | Low | Medium | **High** |
| **Best For** | Most apps | Field service | Compliance | Enterprise | Complex pipelines |

---

## 📋 Decision Tree: Choosing the Right Strategy

```
Start: Choosing your sync strategy?
  │
  ├─ Do you need pre/post-sync hooks?
  │  └─ YES → CompositeSyncOrchestration
  │  └─ NO → Continue
  │
  ├─ Is automatic retry dangerous?
  │  └─ YES → StrictManualOrchestration
  │  └─ NO → Continue
  │
  ├─ Are some tables more important than others?
  │  └─ YES → PrioritySyncOrchestration
  │  └─ NO → Continue
  │
  ├─ Do you work in low-connectivity environments?
  │  └─ YES → OfflineFirstSyncOrchestration
  │  └─ NO → StandardSyncOrchestration (DEFAULT)
```

---

## 🏗️ Real-World Use Cases

### Use Case 1: Healthcare Platform
**Challenge**: Patient records (PII) must not auto-merge. Strict audit trail required.

```dart
final healthcarePipeline = CompositeSyncOrchestration([
  CustomHook(
    beforeSync: () async {
      // Validate HIPAA compliance
      await hipaaComplianceManager.validateSyncEnv();
    },
  ),
  StrictManualOrchestration(
    throwOnError: true,  // Never silent failures
  ),
  CustomHook(
    afterSync: (metrics) async {
      // Log every sync for compliance
      await auditLog.recordSync(metrics);
    },
  ),
]);

final result = await engine.syncWithOrchestration(healthcarePipeline);
```

### Use Case 2: Field Service (Delivery/Technicians)
**Challenge**: Drivers work offline frequently. Battery-critical. Graceful degradation needed.

```dart
final fieldServiceConfig = OfflineFirstSyncOrchestration(
  maxNetworkErrors: 8,    // Very tolerant
  backoffMultiplier: 2.0, // Exponential backoff
  maxBackoffDuration: Duration(minutes: 5),
);

// Wrap in composite for pre-sync setup
final fieldServicePipeline = CompositeSyncOrchestration([
  CustomHook(
    beforeSync: () async {
      // Reduce update frequency to save battery
      await wifiManager.reduceUpdateFrequency();
      await backgroundTaskManager.pause();
    },
  ),
  fieldServiceConfig,
  CustomHook(
    afterSync: (metrics) async {
      // Resume after sync complete
      await backgroundTaskManager.resume();
    },
  ),
]);
```

### Use Case 3: E-commerce Platform
**Challenge**: Order-related data is critical and must sync first. Recommendations are nice-to-have.

```dart
final ecommercePipeline = CompositeSyncOrchestration([
  CustomHook(
    beforeSync: () async {
      // Clear stale cache
      await cacheManager.clearExpiredEntries();
    },
  ),
  PrioritySyncOrchestration({
    'users': 100,           // Identity data
    'accounts': 95,         // Payment info
    'orders': 90,           // Core business
    'order_items': 88,      // Order details
    'inventory': 85,        // Stock
    'reviews': 50,          // Social features
    'recommendations': 20,  // AI/ML
  }),
  CustomHook(
    afterSync: (metrics) async {
      // Recompute recommendations
      await recommendationEngine.refresh();
      
      // Update inventory UI
      notifyInventoryUpdated();
      
      // Log to analytics
      await analytics.logSync(metrics);
    },
  ),
]);
```

### Use Case 4: Financial Application
**Challenge**: Transactions cannot auto-retry. Every error must be logged and verified.

```dart
final financialPipeline = CompositeSyncOrchestration([
  StrictManualOrchestration(throwOnError: true),
  CustomHook(
    afterSync: (metrics) async {
      // Verify transaction integrity
      await transactionValidator.validateAll();
      
      // Log for compliance
      await complianceLog.record(
        syncTime: DateTime.now(),
        recordsProcessed: metrics.recordsPushed + metrics.recordsPulled,
        conflicts: metrics.conflicts,
      );
      
      // Notify finance team of anomalies
      if (metrics.conflicts > 0) {
        await notifyFinanceTeam(metrics.conflicts);
      }
    },
  ),
]);
```

---

## 🛠️ Implementing Custom Orchestration Strategies

For truly unique workflows, implement the `SyncOrchestrationStrategy` interface directly:

```dart
class CustomRetryOrchestration implements SyncOrchestrationStrategy {
  final int maxRetries;
  final Duration initialDelay;
  final double exponentialBase;
  
  CustomRetryOrchestration({
    this.maxRetries = 5,
    this.initialDelay = const Duration(seconds: 1),
    this.exponentialBase = 2.0,
  });
  
  @override
  Future<SyncSessionMetrics> execute(SyncEngine engine) async {
    int attempt = 0;
    Duration delay = initialDelay;
    
    while (attempt < maxRetries) {
      try {
        // Attempt sync
        return await engine.pushAll()
            .then((_) => engine.pullAll());
      } on NetworkError {
        attempt++;
        if (attempt >= maxRetries) rethrow;
        
        // Exponential backoff
        await Future.delayed(delay);
        delay = Duration(
          milliseconds: (delay.inMilliseconds * exponentialBase).toInt(),
        );
      }
    }
    
    throw SyncError('Max retries exceeded');
  }
}

// Usage
final metrics = await engine.syncWithOrchestration(
  CustomRetryOrchestration(maxRetries: 10),
);
```

---

## 🔗 Orchestration Lifecycle Hooks

Every orchestration strategy has access to lifecycle hooks:

```dart
class AdvancedCustomOrchestration extends SyncOrchestrationStrategy {
  @override
  Future<SyncSessionMetrics> execute(SyncEngine engine) async {
    final startTime = DateTime.now();
    
    try {
      // BEFORE SYNC: Prepare
      await onBeforeSync(engine);
      
      // DURING SYNC: Execute
      final metrics = await engine.pushAll()
          .then((_) => engine.pullAll());
      
      // AFTER SYNC (SUCCESS): Finalize
      await onAfterSyncSuccess(engine, metrics);
      
      return metrics;
    } on SyncError catch (e) {
      // AFTER SYNC (ERROR): Handle failure
      await onAfterSyncError(engine, e);
      rethrow;
    } finally {
      // CLEANUP: Always runs
      final duration = DateTime.now().difference(startTime);
      await onSyncComplete(duration);
    }
  }
  
  Future<void> onBeforeSync(SyncEngine engine) async {
    // Override in subclass
  }
  
  Future<void> onAfterSyncSuccess(
    SyncEngine engine,
    SyncSessionMetrics metrics,
  ) async {
    // Override in subclass
  }
  
  Future<void> onAfterSyncError(SyncEngine engine, SyncError error) async {
    // Override in subclass
  }
  
  Future<void> onSyncComplete(Duration duration) async {
    // Override in subclass
  }
}
```

---

## ✅ Testing Orchestration Strategies

```dart
void main() {
  group('CustomOrchestration', () {
    late MockSyncEngine mockEngine;
    
    setUp(() {
      mockEngine = MockSyncEngine();
    });
    
    test('retries on transient error', () async {
      // Setup mocks
      when(mockEngine.pushAll())
          .thenThrow(NetworkError('timeout'))  // First call fails
          .thenReturn(SyncSessionMetrics());   // Second call succeeds
      
      final orchestration = CustomRetryOrchestration(maxRetries: 2);
      final metrics = await orchestration.execute(mockEngine);
      
      expect(metrics, isNotNull);
      verify(mockEngine.pushAll()).called(2);  // Called twice
    });
    
    test('respects max retry limit', () async {
      when(mockEngine.pushAll())
          .thenThrow(NetworkError('timeout'));
      
      final orchestration = CustomRetryOrchestration(maxRetries: 3);
      
      expect(
        () => orchestration.execute(mockEngine),
        throwsA(isA<SyncError>()),
      );
      
      verify(mockEngine.pushAll()).called(3);  // Failed 3 times, then gives up
    });
  });
}
```

---

## Integration with Flutter Lifecycle

Orchestration strategies should respect app lifecycle events:

```dart
class LifecycleAwareOrchestration extends SyncOrchestrationStrategy {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: WidgetsBindingObserver(
        didChangeAppLifecycleState: (state) async {
          switch (state) {
            case AppLifecycleState.paused:
              // App backgrounded; stop heavy sync operations
              await engine.pauseSyncOrchestration();
              break;
            case AppLifecycleState.resumed:
              // App foregrounded; resume or start fresh sync
              await engine.resumeSyncOrchestration();
              break;
            case AppLifecycleState.detached:
              // App closed; cleanup
              await engine.stopSyncOrchestration();
              break;
            default:
              break;
          }
        },
        child: YourApp(),
      ),
    );
  }
}
```

This allows orchestrations to adjust behavior based on whether the app is in the foreground (aggressive sync) or background (conservative, battery-friendly sync).

---

## Key Takeaways

✅ **Standard**: Default, works for most apps  
✅ **PrioritySyncOrchestration**: Enterprise with hierarchical data  
✅ **OfflineFirstSyncOrchestration**: Field service, unreliable networks  
✅ **StrictManualOrchestration**: Compliance, payment, healthcare  
✅ **CompositeSyncOrchestration**: Complex workflows with hooks  
✅ **Custom**: Implement `SyncOrchestrationStrategy` for unique needs

Choose based on your data dependencies, network reliability, and error tolerance! 🚀


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
