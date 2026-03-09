# Architecture Overview

> **Deep dive into Replicore's elegant system design for bidirectional synchronization**

---

## 🏗️ Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        Flutter Application                       │
│      (Your Business Logic, UI, State Management)                 │
└──────────────────────┬──────────────────────────────────────────┘
                       │
        ┌──────────────┴──────────────┐
        │                             │
        ▼                             ▼
┌──────────────────┐        ┌─────────────────────┐
│    SyncEngine    │◄──────►│  LocalStore (SQL)   │
│   (Orchestrator) │        │  ├─ Sqflite         │
└────────┬─────────┘        │  ├─ Drift           │
         │                  │  ├─ Hive            │
         │                  │  └─ Isar            │
         │                  └─────────────────────┘
         │
         │     Conflict Resolution
    ┌────┴─────────────────┐
    │                      │
    ▼                      ▼
┌──────────────────┐  ┌─────────────────────┐
│    Pull Logic    │  │   Push Logic        │
│                  │  │  ├─ Batch Operations│
│  ├─ Fetch delta  │  │  ├─ Dirty tracking  │
│  ├─ Pagination   │  │  └─ Retries         │
│  └─ Merge Data   │  └─────────────────────┘
└────────┬─────────┘           │
         │                     │
         └──────────┬──────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │  RemoteAdapter       │
         │  ├─ Supabase         │
         │  ├─ Firebase         │
         │  ├─ Appwrite         │
         │  └─ GraphQL          │
         └──────────┬───────────┘
                    │
        ┌───────────┴───────────┐
        │                       │
        ▼                       ▼
   ┌─────────┐            ┌──────────────────┐
   │ Network │            │ Real-Time Events │
   └─────────┘            │ ├─ Firestore     │
                          │ ├─ Supabase      │
                          │ ├─ Appwrite      │
                          │ └─ GraphQL Subs  │
                          └──────────────────┘
```

---

## 📦 Core Components

### 1. SyncEngine (Orchestrator)

**Location**: `lib/src/core/sync_engine.dart`

**Responsibilities**:
- Coordinates the entire sync process
- Manages table registrations
- Orchestrates pull and push operations
- Handles conflict resolution
- Manages auto-sync timing
- Emits events and metrics

**Key Methods**:
```dart
Future<void> init()                    // Initialize engine
void registerTable(TableConfig)        // Register a table
Future<SyncResult> sync([...])         // Manual sync
Future<List<Map>> getRecords(table)    // Read from local
Future<void> writeLocal(table, data)   // Write to local
void startAutoSync({...})              // Enable auto-sync
```

**State Management**:
```
[Initialized] ──registerTable──> [Tables Registered]
     │                                  │
     │                         startAutoSync
     │                                  │
  init() ◄─────────────────────────────┘
     │
     ▼
[Ready for Sync]
     │
     ├──────sync() ──────────────┐
     │                           │
     ▼                           ▼
  [Pulling]                   [Pushing]
     │                           │
     ├─► [Synced] ◄─────────────┤
     │
     └─► [Error] ◄──────────────┘
```

### 2. LocalStore (Persistence Layer)

**Location**: `lib/src/storage/local_store.dart`

**Purpose**: Abstract interface for local data persistence

**Implementations**:
- `SqfliteStore` - SQLite (default, battle-tested)
- `DriftStore` - Drift (type-safe SQL)
- `HiveStore` - In-memory NoSQL
- `IsarStore` - High-performance Rust-backed

**Key Operations**:
```dart
// Writing
Future<void> insert(table, record)
Future<void> update(table, record)
Future<void> upsert(table, record)
Future<List<Map>> markManyAsSynced(table, ids)

// Reading
Future<List<Map>> getRecords(table, [query])
Future<int> count(table)
Future<bool> exists(table, id)

// Tracking
Future<List<Map>> getDirtyRecords(table)
Future<void> setOperationId(...)
Future<void> setOperationIds(...)

// Management
Future<void> deleteTable(table)
Future<void> dropAll()
```

**Data Model per Record**:
```
{
  'uuid': 'abc-123',              // Primary key
  'title': 'My Todo',             // User data
  'updated_at': '2024-01-01...',  // For sync cursor
  'deleted_at': null,             // Soft delete marker
  'is_synced': true,              // 0=dirty, 1=clean
  '_operation_id': 'op-uuid-...',  // For retry safety
}
```

### 3. RemoteAdapter (Backend Interface)

**Location**: `lib/src/adapters/remote_adapter.dart`

**Purpose**: Abstract backend implementation

**Implementations**:
- `SupabaseAdapter` - PostgreSQL via Supabase
- `FirebaseAdapter` - Firestore
- `AppwriteAdapter` - Self-hosted BaaS
- `GraphQLAdapter` - Any GraphQL server

**Key Methods**:
```dart
// Pull changes from server
Future<PullResult> pull(PullRequest request)

// Push changes to server
Future<void> upsert(...)
Future<void> softDelete(...)
Future<List<dynamic>> batchUpsert(...)      // v0.5.1+
Future<List<dynamic>> batchSoftDelete(...)  // v0.5.1+

// Real-time
RealtimeSubscriptionProvider? getRealtimeProvider()
```

**Adapter Pattern**: Each backend implements platform-specific logic:
- Supabase: Native SQL UPSERT
- Firebase: Firestore batch API
- Appwrite: REST API with document IDs
- GraphQL: Mutations and subscriptions

---

## 🔄 Sync Flow (Detailed)

### Phase 1: Pull (Download Server Changes)

```
1. Read Cursor
   └─ Get last sync timestamp & PK
   
2. Build PullRequest
   └─ table, cursor (or null for first)
   
3. Call remoteAdapter.pull()
   └─ Adapter fetches records after cursor
   
4. Process Results
   ├─ Records received
   ├─ nextCursor returned
   └─ Store in local
   
5. Repeat Until Complete
   └─ While nextCursor exists
      └─ Continue pulling next page
      
6. Conflict Resolution
   └─ For each pulled record:
      ├─ Check if local record exists
      ├─ Check if local is dirty
      ├─ Apply resolution strategy
      └─ Store resolved version
      
7. Update Cursor
   └─ Save cursor for next pull
```

**Keyset Pagination** (Anti-Pattern to OFFSET):
```
First Pull:
  GET /api/records?limit=100&sort=updated_at,id
  
Returns:
  [{id: 1, updated_at: '2024-01-01'}, ...]
  + nextCursor: {updated_at: '2024-01-01', id: 456}

Second Pull:
  GET /api/records
    ?limit=100
    &sort=updated_at,id
    &after_updated_at=2024-01-01
    &after_id=456 (if same timestamp)
```

**Why Keyset Pagination?**
- ✅ Consistent across deletes
- ✅ No OFFSET performance degradation
- ✅ Real-time friendly
- ❌ Requires ordering columns at backend

### Phase 2: Push (Upload Local Changes)

```
1. Get Dirty Records
   └─ Find all records with is_synced=0
   
2. Prepare for Sync
   └─ Generate operation IDs
      (UUID format: deterministic)
      
3. Set Operation IDs (Batch)
   └─ Write operation IDs to local DB
      (prevents duplicate retries)
      
4. Group by Operation Type
   ├─ Upserts: records with no deleted_at
   └─ Deletes: records with deleted_at
   
5. Batch Upsert (NEW v0.5.1!)
   └─ remoteAdapter.batchUpsert([...])
      ├─ Supabase: 1 SQL UPSERT
      ├─ Firebase: 1 batch commit
      ├─ Appwrite: Parallel requests
      └─ GraphQL: Parallel mutations
      
6. Batch Delete (NEW v0.5.1!)
   └─ remoteAdapter.batchSoftDelete([...])
      └─ Same optimization as upsert
      
7. Mark as Synced (Batch)
   └─ localStore.markManyAsSynced([...])
      ├─ Supabase: IN() query
      ├─ Others: individual updates
      
8. Error Handling
   ├─ Partial Success Allowed
   │  └─ Failed records stay dirty for retry
   ├─ Automatic Retry
   │  └─ Failed records retried on next sync
   └─ Fallback to Individual Ops
      └─ If batch fails, retry individually
```

**Operation ID Generation** (Deterministic):
```dart
// Ensures same operation ID for retries
final opId = sha256.convert(utf8.encode(
  '${table}:${pk}:${jsonEncode(data)}'
)).toString();

// Benefits:
// ✅ Same ID on retry (idempotent)
// ✅ Server deduplicates (prevents double write)
// ✅ Safe across network failures
```

### Phase 3: Real-Time (Auto-Sync on Change)

```
1. Setup Subscription
   └─ remoteAdapter.getRealtimeProvider()
      └─ Returns provider if supported
      
2. Listen for Changes
   └─ On backend change event:
      ├─ Record created/updated
      ├─ Record deleted
      └─ Record hard deleted
      
3. Trigger Auto-Sync
   └─ Debounce (prevent sync storms)
      └─ Pull updates from server
      └─ Emit events
      
4. Connection Management
   ├─ On disconnect: Stop listening
   ├─ On reconnect: Resume subscription
   └─ Exponential backoff on failure
```

**Real-Time Providers**:
```
Supabase ──────► PostgreSQL Logical Replication
                  ↓
              Real-Time Server
                  ↓
            WebSocket to Client

Firebase ──────► Firestore Real-Time Listeners
                  ↓
            Real-time Document Updates
                  ↓
            Direct to Client

Appwrite ──────► WebSocket Events
                  (document.update, etc.)

GraphQL ──────► Subscriptions Protocol
                  (Apollo, etc.)
```

---

## 🎯 Conflict Resolution Strategies

### 1. ServerWins (Default)

**Logic**: Remote version always wins

```dart
if (isDirty && pullReceived) {
  useRemoteVersion()  // Discard local changes
}
```

**Use Case**: 
- Server is source of truth
- Local changes are "draft"
- e.g., TODO app with server-side sharing

### 2. LocalWins

**Logic**: Local version always wins

```dart
if (isDirty && pullReceived) {
  keepLocalVersion()  // Keep unsync'd changes
  retryPush()         // Push again
}
```

**Use Case**:
- Local is source of truth
- User changes are urgent
- e.g., Offline document editor

### 3. LastWriteWins

**Logic**: Newest by timestamp wins

```dart
if (localUpdatedAt > remoteUpdatedAt) {
  keepLocalVersion()
} else {
  useRemoteVersion()
}
```

**Use Case**:
- Single user, time-based preference
- Simple app with infrequent conflicts
- Not safe for concurrent users!

### 4. CustomResolver

**Logic**: Your custom function decides

```dart
Future<Map> resolve(local, remote) async {
  // Your logic here
  return mergedRecord;
}
```

**Use Case**:
- Complex business logic
- Merge strategies
- Field-level resolution
- Machine learning based

---

## 📊 Data Models

### TableConfig (Registration)

```dart
TableConfig(
  name: 'todos',                        // Table name
  primaryKey: 'uuid',                   // PK column
  updatedAtColumn: 'updated_at',        // Sync cursor
  deletedAtColumn: 'deleted_at',        // Soft delete
  columns: ['uuid', 'title', ...],      // All columns
  strategy: SyncStrategy.serverWins,    // Conflict handling
  customResolver: null,                 // Or your function
)
```

### PullRequest (Pull Parameters)

```dart
PullRequest(
  table: 'todos',
  primaryKey: 'uuid',
  updatedAtColumn: 'updated_at',
  cursor: SyncCursor(...),  // null for first pull
  limit: 100,               // Batch size
)
```

### PullResult (Pull Response)

```dart
PullResult(
  records: [{id: 1, title: '...', ...}],
  nextCursor: SyncCursor(...),  // null if no more
)
```

### SyncResult (Sync outcome)

```dart
SyncResult(
  table: 'todos',
  success: true,
  recordsPulled: 10,
  recordsPushed: 5,
  conflicts: 2,
  conflictsResolved: 2,
  errors: 0,
  durationMs: 250,
)
```

---

## 🔌 Plugin System

### Adding Your Own LocalStore

```dart
class MyCustomStore implements LocalStore {
  @override
  Future<List<Map>> getRecords(String table) async {
    // Your implementation
  }
  
  // Implement all abstract methods...
}

// Use it:
final engine = SyncEngine(
  localStore: MyCustomStore(),
  remoteAdapter: adapter,
);
```

### Adding Your Own RemoteAdapter

```dart
class MyBackendAdapter implements RemoteAdapter {
  @override
  Future<PullResult> pull(PullRequest request) async {
    // Fetch from your backend
    final response = await http.get(
      Uri.parse('${apiUrl}/tables/${request.table}'),
    );
    return PullResult(
      records: jsonDecode(response.body),
      nextCursor: ...,
    );
  }
  
  // Implement all abstract methods...
}

// Use it:
final engine = SyncEngine(
  localStore: localStore,
  remoteAdapter: MyBackendAdapter(),
);
```

---

## 🎨 Status Monitoring

Monitor sync progress and status updates:

```dart
// Listen to all sync status updates
engine.statusStream.listen((status) {
  print('Sync status: $status');
});

// Example output:
// "Starting Full Sync..."
// "Syncing users..."
// "Syncing todos..."
// "Error syncing todos."
// "Sync complete"
```

For detailed metrics after sync completes, use the returned `SyncSessionMetrics`:

```dart
final metrics = await engine.syncAll();

print('Overall success: ${metrics.overallSuccess}');
print('Records pulled: ${metrics.totalRecordsPulled}');
print('Records pushed: ${metrics.totalRecordsPushed}');
print('Conflicts: ${metrics.conflictsEncountered}');
print('Duration: ${metrics.duration.inSeconds}s');

// Per-table metrics
for (final tableMetrics in metrics.metrics) {
  print('${tableMetrics.tableName}:');
  print('  - Pulled: ${tableMetrics.recordsPulled}');
  print('  - Pushed: ${tableMetrics.recordsPushed}');
  print('  - Duration: ${tableMetrics.duration.inMilliseconds}ms');
  print('  - Conflicts: ${tableMetrics.conflicts}');
}
```

For detailed event tracking and custom logging, use structured logger integration:

```dart
// Configure with structured logging
final engine = SyncEngine(
  localStore: store,
  remoteAdapter: adapter,
  logger: ConsoleLogger(), // Or custom logger
);

// Logger receives all sync events automatically
// with structured context like table names, record counts, etc.
```

---

## 🚀 Performance Characteristics

### Pull Performance
- Time: O(n) where n = number of new records
- Network: Single request per page (not per record)
- Storage: Batch inserts (fast)

### Push Performance (v0.5.1+)
- Time: O(1) relative to number of records (linear in backends)
- Network: Single request per batch, not per record
- Storage: Batch updates (fast)
- Old (v0.5.0): O(n) with N individual requests

### Memory
- Streaming: Records processed one page at a time
- No full scan to memory
- Suitable for millions of records

---

## 🔐 Security Notes

### Operation ID Prevents Duplicates

```
Scenario: Network fails during push
Request 1: POST /api/todos [opId: abc-123]
  └─ Times out
Request 2: Retry with [opId: abc-123]
  └─ Server recognizes duplicate
  └─ Returns success without creating duplicate
```

### Soft Deletes Preserve Data

```
User deletes record locally:
  └─ Set deleted_at = now()
  └─ Mark as dirty
  └─ Push to server
  
Server receives:
  "uuid": "123",
  "deleted_at": "2024-01-01T12:00:00Z"
  
Result:
  ✅ Data preserved (audit trail)
  ✅ Can be restored (undo)
  ✅ Filtered from UI (not deleted_at IS NULL)
```

---

## 📈 Scalability

### Tested at Scale

- **Records**: 100,000+ per table
- **Tables**: Dozens simultaneously
- **Dirty Records**: 10,000+ per sync
- **Throughput**: 1000+ records/second per backend

### Optimization Techniques

1. **Batch Operations** (v0.5.1+) - Eliminate N+1
2. **Keyset Pagination** - No O(n²) queries
3. **Soft Deletes** - No hard deletes needed
4. **Stateless Design** - Can be distributed

---

## 🎓 Learning Path

1. **Read this document** - Understand architecture
2. [Getting Started](./01_GETTING_STARTED.md) - Build first app
3. [Sync Concepts](./03_SYNC_CONCEPTS.md) - Deep dive
4. [Integration Patterns](./v0_5_0_INTEGRATION_PATTERNS.md) - Best practices
5. Example app code - See it in action

---

**Replicore's architecture is elegant, efficient, and production-proven** ✨
