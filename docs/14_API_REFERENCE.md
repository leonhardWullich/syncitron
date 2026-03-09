# API Reference

> **Complete API documentation for Replicore**

---

## 📚 SyncEngine

The main synchronization orchestrator.

### Initialization

```dart
final engine = SyncEngine(
  localStore: sqfliteStore,
  remoteAdapter: firebaseAdapter,
  config: config,
);

await engine.initialize();
```

#### Constructor Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `localStore` | `LocalStore` | Yes | Local data storage |
| `remoteAdapter` | `RemoteAdapter` | Yes | Remote backend adapter |
| `config` | `ReplicoreConfig` | No | Configuration |

---

### Core Methods

#### `sync()`

Synchronizes local and remote data.

```dart
Future<SyncResult> sync({
  String? table,  // Optional: sync specific table
}) async {
  return await engine.sync(table: 'todos');
}

// Returns: SyncResult {
//   recordsPulled: 10,
//   recordsPushed: 5,
//   conflictsResolved: 2,
//   duration: Duration(milliseconds: 150),
// }
```

**When to use**: After network restored, on app launch, before critical operations

---

#### `readLocal()`

Read single record from local storage.

```dart
final todo = await engine.readLocal<Map>('todos', '1');

if (todo != null) {
  print('Title: ${todo['title']}');
}
```

**Parameters**:
- `table`: Table name
- `primaryKey`: Record ID

**Returns**: `Map?` - Record or null if not found

---

#### `readLocalWhere()`

Query local records with conditions.

```dart
final activeTodos = await engine.readLocalWhere(
  'todos',
  where: 'completed = ?',
  whereArgs: [0],
  orderBy: 'updated_at DESC',
  limit: 10,
);

// Returns: List<Map>
```

**Parameters**:
- `table`: Table name
- `where`: SQL WHERE clause
- `whereArgs`: WHERE clause arguments
- `orderBy`: Order clause
- `limit`: Result limit
- `offset`: Result offset

---

#### `writeLocal()`

Write or update a local record.

```dart
await engine.writeLocal('todos', {
  'uuid': generateUuid(),
  'title': 'Buy milk',
  'completed': false,
  'updated_at': DateTime.now().toIso8601String(),
});

// Automatically marked dirty for sync
```

**Parameters**:
- `table`: Table name
- `data`: Record data as Map
- `conflictAlgorithm`: SQLite conflict resolution

**Automatically**:
- Generates UUID if not provided
- Sets `updated_at` to current time
- Marks record as dirty

---

#### `deleteLocal()`

Delete a record (hard or soft delete).

```dart
// Hard delete (removes from database)
await engine.deleteLocal('todos', '1');

// Soft delete (keeps record, marks deleted)
await engine.writeLocal('todos', {
  'uuid': '1',
  'deleted_at': DateTime.now().toIso8601String(),
});
```

**Parameters**:
- `table`: Table name
- `primaryKey`: Record ID

---

#### `getDirtyRecords()`

Get records pending synchronization.

```dart
final dirty = await engine.getDirtyRecords('todos');

print('${dirty.length} records pending sync');
// [{uuid: '1', title: 'Buy milk', ...}]
```

**Parameters**:
- `table`: Table name

**Returns**: `List<Map>` - Dirty records

---

### Bulk Operations

#### `bulkWrite()`

Write multiple records efficiently.

```dart
final records = List.generate(100, (i) => {
  'uuid': generateUuid(),
  'title': 'Todo $i',
  'completed': false,
});

await engine.bulkWrite('todos', records);
```

**Parameters**:
- `table`: Table name
- `records`: List of record maps

**Performance**: O(1) instead of O(n)

---

#### `bulkDelete()`

Delete multiple records.

```dart
final ids = ['1', '2', '3', '4', '5'];

await engine.bulkDelete('todos', ids);
```

**Parameters**:
- `table`: Table name
- `ids`: List of primary keys

---

### Status Monitoring & Streams

#### `statusStream`

Emitted for all sync status updates.

```dart
engine.statusStream.listen((status) {
  print('Status: $status');
  
  if (status == 'Starting Full Sync...') {
    showProgressIndicator();
  } else if (status.contains('complete') || status.contains('Error')) {
    hideProgressIndicator();
  }
});
```

**Examples**:
```
'Starting Full Sync...'
'Syncing users...'
'Syncing todos...'
'Error syncing todos.'
'Sync complete'
```

---

#### Sync Metrics (Returned from syncAll)

After sync completes, get detailed metrics:

```dart
final metrics = await engine.syncAll();

print('Overall success: ${metrics.overallSuccess}');
print('Records pulled: ${metrics.totalRecordsPulled}');
print('Records pushed: ${metrics.totalRecordsPushed}');
print('Conflicts: ${metrics.conflictsEncountered}');
print('Duration: ${metrics.duration}');

// Per-table metrics
for (final table in metrics.metrics) {
  print('${table.tableName}:');
  print('  Pulled: ${table.recordsPulled}');
  print('  Pushed: ${table.recordsPushed}');
  print('  Duration: ${table.duration}');
}
```

**SyncSessionMetrics**:
```dart
class SyncSessionMetrics {
  final List<SyncMetrics> metrics;
  final DateTime startTime;
  
  bool get overallSuccess;
  int get totalRecordsPulled;
  int get totalRecordsPushed;
  int get conflictsEncountered;
  Duration get duration;
}
```

---

#### Error Handling via Try-Catch

For detailed error handling, catch exceptions:

```dart
try {
  final metrics = await engine.syncAll();
  print('Sync successful: ${metrics.overallSuccess}');
} on NetworkException catch (e) {
  print('Network error: ${e.message}');
  showRetryButton();
} on ConflictException catch (e) {
  print('Conflict on ${e.table}: ${e.message}');
} on ReplicoreException catch (e) {
  print('Sync error: ${e.message}');
}
```

---

## 🗄️ LocalStore Interface

### Must Implement

```dart
abstract class LocalStore {
  // Initialization
  Future<void> initialize();
  
  // CRUD
  Future<Map?> read(String table, String primaryKey);
  Future<List<Map>> readAll(String table);
  Future<List<Map>> readWhere({
    required String table,
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  });
  
  // Write
  Future<void> upsert({
    required String table,
    required Map<String, Object?> data,
  });
  
  Future<void> delete(String table, String primaryKey);
  
  // Dirty tracking
  Future<void> markDirty(
    String table,
    String primaryKey,
    SyncDirection direction,
  );
  
  Future<List<Map>> getDirtyRecords(String table);
  
  // Sync metadata
  Future<DateTime> getLastSyncTime(String table);
  Future<void> setLastSyncTime(String table, DateTime time);
}
```

### Sqflite Implementation

```dart
final store = SqfliteLocalStore(database);

await store.initialize();

final todo = await store.read('todos', '1');

await store.upsert(
  table: 'todos',
  data: {'uuid': '1', 'title': 'Test'},
);
```

---

## 🌐 RemoteAdapter Interface

### Must Implement

```dart
abstract class RemoteAdapter {
  // Health check
  Future<bool> ping();
  
  // Pull operations
  Future<List<Map>> pull({
    required String table,
    required DateTime since,
  });
  
  // Push operations
  Future<void> upsert({
    required String table,
    required List<Map> records,
  });
  
  Future<void> delete({
    required String table,
    required List<String> ids,
  });
  
  // Real-time subscription (optional)
  Stream<DataChange>? subscribe({
    required String table,
  });
}
```

### Firebase Implementation

```dart
final adapter = FirebaseAdapter(firebaseInstance);

final records = await adapter.pull(
  table: 'todos',
  since: DateTime.now().subtract(Duration(days: 1)),
);

await adapter.upsert(
  table: 'todos',
  records: [{'uuid': '1', 'title': 'New'}],
);
```

---

## ⚙️ ReplicoreConfig

Configuration object for SyncEngine.

```dart
final config = ReplicoreConfig(
  // Sync behavior
  syncInterval: Duration(minutes: 5),
  autoSync: true,
  
  // Batch operations
  batchSize: 25,
  usesBatching: true,
  
  // Retry behavior
  maxRetries: 3,
  retryDelay: Duration(seconds: 2),
  
  // Server sync
  serverOffset: Duration(minutes: 5),
  
  // Logging
  showLogs: true,
  logLevel: 'info',
  
  // Conflict resolution
  conflictResolution: ConflictResolution.lastWriteWins,
  customResolver: customResolver,
  
  // Tables to exclude
  excludedTables: ['internal_table'],

);

final engine = SyncEngine(
  localStore: store,
  remoteAdapter: adapter,
  config: config,
);
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `syncInterval` | Duration | 5 min | Auto-sync frequency |
| `autoSync` | bool | true | Enable auto-sync |
| `batchSize` | int | 25 | Records per batch |
| `maxRetries` | int | 3 | Retry attempts |
| `retryDelay` | Duration | 2s | Initial retry delay |
| `showLogs` | bool | false | Enable logging |

---

## 📊 Metrics API

Monitor performance and health.

```dart
final metrics = engine.getMetrics();

print('Total syncs: ${metrics.totalSyncs}');
print('Successful: ${metrics.successfulSyncs}');
print('Failed: ${metrics.failedSyncs}');
print('Avg duration: ${metrics.avgDuration}');
print('Error rate: ${metrics.errorRate * 100}%');
```

**Metrics Object**:
```dart
class SyncMetrics {
  final int totalSyncs;
  final int successfulSyncs;
  final int failedSyncs;
  final Duration avgDuration;
  final Duration minDuration;
  final Duration maxDuration;
  final double errorRate;
  final int totalRecordsPulled;
  final int totalRecordsPushed;
  final Map<String, int> errorCounts;
}
```

---

## 🔄 Data Models

### SyncConflict

Represents conflicting versions.

```dart
class SyncConflict {
  final String table;
  final String primaryKey;
  final dynamic localVersion;
  final dynamic remoteVersion;
  final DateTime localUpdated;
  final DateTime remoteUpdated;
}
```

### SyncResult

Result of a sync operation.

```dart
class SyncResult {
  final int recordsPulled;
  final int recordsPushed;
  final int conflictsResolved;
  final Duration duration;
  final bool success;
  final String? error;
}
```

### DataChange

Local data change notification.

```dart
class DataChange {
  final String table;
  final String primaryKey;
  final ChangeType operation;  // insert/update/delete
  final Map data;
}
```

---

## 🎯 Enums

### ConflictResolution

```dart
enum ConflictResolution {
  lastWriteWins,    // Use record with newest timestamp
  serverWins,        // Always prefer server
  localWins,         // Always prefer local
  custom,            // Use custom resolver
}
```

### SyncDirection

```dart
enum SyncDirection {
  push,              // Uploading to server
  pull,              // Downloading from server
}
```

### ChangeType

```dart
enum ChangeType {
  insert,            // New record created
  update,            // Existing record modified
  delete,            // Record deleted
}
```

---

## 🚀 Examples

### Complete CRUD Cycle

```dart
// Create
await engine.writeLocal('todos', {
  'uuid': '1',
  'title': 'Buy milk',
  'completed': false,
});

// Read
final todo = await engine.readLocal('todos', '1');

// Update
await engine.writeLocal('todos', {
  'uuid': '1',
  'title': 'Buy organic milk',
  'completed': false,
});

// Sync
await engine.syncAll();

// Delete
await engine.deleteLocal('todos', '1');

// Sync again
final metrics = await engine.syncAll();
print('Synced ${metrics.totalRecordsPushed} records');
```

### Monitoring Sync Progress

```dart
// Listen to real-time status updates
engine.statusStream.listen((status) {
  print('Sync status: $status');
  
  if (status == 'Starting Full Sync...') {
    setState(() { isSyncing = true; });
  } else if (status.contains('complete') || status.contains('Error')) {
    setState(() { isSyncing = false; });
  }
});

// After sync, check metrics
try {
  final metrics = await engine.syncAll();
  print('Successfully synced ${metrics.totalRecordsPushed} records');
} catch (e) {
  print('Sync error: $e');
}
```

### Error Handling

```dart
try {
  await engine.sync();
} on NetworkException {
  showSnackbar('No internet connection');
} on SyncException catch (e) {
  showSnackbar('Sync failed: ${e.message}');
} catch (e) {
  showSnackbar('Unknown error');
}
```

---

**API is small but powerful!** 🎯
