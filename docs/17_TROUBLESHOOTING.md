# Troubleshooting Guide

> **Solutions to common problems and issues**

---

## 🔍 Diagnostic Process

### Step 1: Enable Logs

```dart
final config = ReplicoreConfig(
  showLogs: true,
  logLevel: 'debug',  // Show all messages
);

final engine = SyncEngine(
  localStore: store,
  remoteAdapter: adapter,
  config: config,
);
```

### Step 2: Monitor Status & Errors

```dart
// Monitor all status updates
engine.statusStream.listen((status) {
  print('📊 Status: $status');
});

// Check detailed metrics after sync
try {
  final metrics = await engine.syncAll();
  print('✅ Pulled: ${metrics.totalRecordsPulled}');
  print('✅ Pushed: ${metrics.totalRecordsPushed}');
  print('✅ Duration: ${metrics.duration.inMilliseconds}ms');
  print('✅ Success: ${metrics.overallSuccess}');
} on ReplicoreException catch (e) {
  print('❌ Error Type: ${e.runtimeType}');
  print('❌ Message: ${e.message}');
  print('❌ Stack: ${e.stackTrace}');
}
```

---

## 🚨 Common Issues

### Issue 1: "SyncEngine not initialized"

**Symptom**: `StateError: SyncEngine not initialized`

**Cause**: Using engine before calling `initialize()`

**Fix**:

```dart
// ❌ WRONG
final engine = SyncEngine(...);
await engine.sync();  // ERROR!

// ✅ CORRECT
final engine = SyncEngine(...);
await engine.initialize();  // FIRST!
await engine.sync();
```

---

### Issue 2: "No internet" Errors

**Symptom**: `NetworkException: Network unavailable`

**Cause**: Device is offline

**Fix**:

```dart
// Check connectivity first
final connectivity = Connectivity();
final result = await connectivity.checkConnectivity();

if (result == ConnectivityResult.none) {
  print('📵 Offline - using local mode');
  // Local operations still work!
  await engine.writeLocal('todos', {...});
} else {
  await engine.sync();
}
```

---

### Issue 3: Sync Takes Too Long

**Symptom**: Sync takes >5 seconds for normal data

**Cause**: Batching not enabled or wrong batch size

**Fix**:

```dart
// ✅ Ensure batching enabled
final config = ReplicoreConfig(
  usesBatching: true,
  batchSize: 25,  // Adjust if needed
);

// Check logs
// ✅ [Replicore] Batching 25 records
```

**Also check**:
```dart
// Are you on a slow network?
// Try larger batches
batchSize: 50,

// Or smaller if memory constrained
batchSize: 10,
```

---

### Issue 4: Data Not Syncing

**Symptom**: Changes made locally, but not on server

**Cause**: Records not marked dirty, or sync not called

**Fix**:

```dart
// 1. Check if records are dirty
final dirty = await engine.getDirtyRecords('todos');
print('Dirty records: $dirty');

if (dirty.isEmpty) {
  print('❌ No dirty records!');
  // Make sure you're calling writeLocal
}

// 2. Monitor sync status
engine.statusStream.listen((status) {
  if (status.contains('Syncing')) {
    print('✅ Sync in progress');
  }
});

// 3. Verify changes are local first
final todo = await engine.readLocal('todos', '1');
```
if (todo != null) {
  print('✅ Data in local storage: $todo');
} else {
  print('❌ Data not in local storage!');
}
```

---

### Issue 5: Conflicts Not Resolving

**Symptom**: Same record has different local and server versions

**Cause**: Custom resolver not handling all cases, or wrong strategy

**Fix**:

```dart
// 1. Use built-in resolver first
final config = ReplicoreConfig(
  conflictResolution: ConflictResolution.lastWriteWins,
);

// 2. Monitor conflicts
engine.onSyncComplete.listen((result) {
  if (result.conflictsResolved > 0) {
    print('⚠️  ${result.conflictsResolved} conflicts resolved');
  }
});

// 3. Implement comprehensive custom resolver
final resolver = CustomResolver((conflict) {
  final local = conflict.localVersion;
  final remote = conflict.remoteVersion;
  
  // Handle all fields
  return {
    'uuid': local['uuid'],
    'title': remote['title'],  // Server wins
    'completed': local['completed'],  // Local wins
    'updated_at': 
      DateTime.parse(remote['updated_at'])
        .isAfter(DateTime.parse(local['updated_at']))
      ? remote['updated_at']
      : local['updated_at'],
  };
});
```

---

### Issue 6: SQLite Database Locked

**Symptom**: `DatabaseException: database is locked`

**Cause**: Multiple concurrent database operations

**Fix**:

```dart
import 'package:sqflite/sqflite.dart';

// Use singleInstance and openDatabase with proper settings
final database = await openDatabase(
  'app.db',
  version: 1,
  // IMPORTANT: Allow concurrent access
  singleInstance: true,
);

// Use transactions for atomic operations
await database.transaction((txn) async {
  await txn.insert('todos', data);
});

// Don't do this:
// ❌ Multiple openDatabase() calls
// ❌ Blocking operations on UI thread
```

---

### Issue 7: OutOfMemoryError

**Symptom**: `OutOfMemoryError` when syncing large datasets

**Cause**: Batch size too large, processing too many records

**Fix**:

```dart
// ✅ Use smaller batches
final config = ReplicoreConfig(
  batchSize: 10,  // Smaller batches
);

// Or process in pages
Future<void> syncLargeDataset(String table) async {
  const pageSize = 100;
  var offset = 0;
  
  while (true) {
    final dirty = await engine.getDirtyRecords(table);
    if (dirty.isEmpty) break;
    
    final page = dirty.skip(offset).take(pageSize).toList();
    if (page.isEmpty) break;
    
    // Sync page
    await engine.sync();
    
    offset += pageSize;
  }
}
```

---

### Issue 8: Auth Token Expired

**Symptom**: `401 Unauthorized` errors during sync

**Cause**: Auth token expired between app launch and sync

**Fix**:

```dart
// 1. Refresh token before sync
Future<void> syncWithTokenRefresh() async {
  try {
    await refreshAuthToken();
    await engine.sync();
  } on AuthException catch (e) {
    print('❌ Auth failed: ${e.message}');
    await logout();
    // Navigate to login
  }
}

// 2. In adapter, always use current token
class MyRemoteAdapter extends RemoteAdapter {
  @override
  Future<List<Map>> pull({required table, required since}) async {
    final token = await authService.getCurrentToken();
    // Add to headers: Authorization: Bearer $token
  }
}

// 3. Handle token refresh automatically
class TokenRefreshingAdapter extends RemoteAdapter {
  @override
  Future<void> push({required records, required table}) async {
    try {
      await super.push(records: records, table: table);
    } on AuthException catch (_) {
      await authService.refreshToken();
      // Retry
      return super.push(records: records, table: table);
    }
  }
}
```

---

### Issue 9: Duplicate Records After Sync

**Symptom**: Same record appears multiple times

**Cause**: No primary key enforcement, or duplicates in pull

**Fix**:

```dart
// 1. Always use unique IDs
await engine.writeLocal('todos', {
  'uuid': 'unique-id-${DateTime.now().millisecondsSinceEpoch}',
  // NOT: 'id': 'unique-id'
  'title': 'Test',
});

// 2. Create unique index on server
// PostgreSQL:
CREATE UNIQUE INDEX ON todos(uuid);

// 3. Use UPSERT pattern
await engine.writeLocal('todos', {
  'uuid': '1',  // Will update if exists
  'title': 'Updated',
});

// 4. Check for duplicates
final todos = await engine.readLocalWhere('todos');
final ids = todos.map((t) => t['uuid']).toList();
if (ids.length != ids.toSet().length) {
  print('❌ Duplicates found!');
  // Clean up duplicates manually
}
```

---

### Issue 10: Real-time Updates Not Working

**Symptom**: Server changes don't appear in app

**Cause**: Real-time subscription not set up, or disabled

**Fix**:

```dart
// 1. Check if adapter supports real-time
if (adapter.subscribe == null) {
  print('❌ Adapter does not support real-time');
  // Implement polling instead
}

// 2. Subscribe to changes
adapter.subscribe(table: 'todos')?.listen((change) {
  print('✅ Real-time update: $change');
  // Rebuild UI
});

// 3. Ensure auto-sync is enabled
final config = ReplicoreConfig(
  autoSync: true,
  syncInterval: Duration(minutes: 5),
);

// 4. Fallback to polling if no real-time
Timer.periodic(Duration(minutes: 1), (timer) {
  engine.sync();
});
```

---

## SQLite-Specific Issues

### Issue: "Table already exists"

```dart
// The table schema might have changed
// Safe approach:

await database.execute('''
  CREATE TABLE IF NOT EXISTS todos (
    uuid TEXT PRIMARY KEY,
    title TEXT,
    completed INTEGER DEFAULT 0,
    updated_at TEXT,
    dirty INTEGER DEFAULT 0
  );
''');
```

### Issue: Corrupted Database

```dart
// Delete and recreate
import 'package:sqflite/sqflite.dart';

await deleteDatabase('app.db');  // Delete corrupted DB

// Re-open (creates fresh)
final database = await openDatabase('app.db');
```

### Issue: Slow Queries

```dart
// Add indexes
await database.execute('''
  CREATE INDEX IF NOT EXISTS idx_updated_at
  ON todos(updated_at);
''');

await database.execute('''
  CREATE INDEX IF NOT EXISTS idx_dirty
  ON todos(dirty);
''');
```

---

## Firebase-Specific Issues

### Issue: Quota Exceeded

```dart
// Firebase has rate limits
// Implement exponential backoff

Future<void> syncWithBackoff() async {
  int delay = 1;
  for (int attempt = 0; attempt < 5; attempt++) {
    try {
      await engine.sync();
      return;
    } on FirebaseException catch (e) {
      if (e.message?.contains('quota') ?? false) {
        delay *= 2;
        await Future.delayed(Duration(seconds: delay));
      } else {
        rethrow;
      }
    }
  }
}
```

### Issue: Firestore Rules Blocking

```dart
// Permission denied errors
// Check Firestore security rules

// ✅ Allow authenticated users to read/write own data
match /todos/{documents=**} {
  allow read, write: if request.auth != null;
}

// ✅ Or more restrictive:
match /todos/{document=**} {
  allow read, write: if request.auth.uid == resource.data.owner_id;
}
```

---

## Performance Issues

### Issue: High Memory Usage

```dart
// Reduce batch size
batchSize: 5,

// Or limit query results
final todos = await engine.readLocalWhere(
  'todos',
  limit: 50,  // Don't fetch all at once
);
```

### Issue: High CPU Usage

```dart
// Reduce sync frequency
syncInterval: Duration(minutes: 10),

// Or manual sync control
autoSync: false,
// Then: await engine.sync() when needed
```

---

## 📞 Getting Help

### Provide This Info

When reporting a bug, include:

```
1. Error message (full)
2. Stack trace
3. Code snippet (minimal reproduction)
4. Logs (with debug level enabled)
5. Backend being used (Firebase, Supabase, etc)
6. Replicore version
7. Flutter version
8. OS and device
```

### Debug Template

```dart
// Enable full debugging
final config = ReplicoreConfig(
  showLogs: true,
  logLevel: 'debug',
);

// Print diagnostic info
void printDiagnostics() async {
  print('=== Replicore Diagnostics ===');
  print('Is initialized: ${engine.isInitialized}');
  
  final dirty = await engine.getDirtyRecords('todos');
  print('Dirty records: ${dirty.length}');
  
  final metrics = engine.getMetrics();
  print('Total syncs: ${metrics.totalSyncs}');
  print('Error rate: ${metrics.errorRate}');
  
  print('==============================');
}
```

---

**Most issues are solved by enabling logs!** 🔍
