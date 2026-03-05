# Real-Time Subscriptions in Replicore v0.5.0

Replicore v0.5.0 introduces **real-time event-driven synchronization** - automatically pull changes from your backend the moment they occur, without polling!

## 🎯 What Problem Does This Solve?

### Before (v0.4.0)
```dart
// Manual polling every 30 seconds
Timer.periodic(Duration(seconds: 30), (_) async {
  await engine.syncAll();  // Syncs ALL tables, even if nothing changed
});

// Problems:
// ❌ Battery drain from constant polling
// ❌ Latency: Changes delayed up to 30 seconds
// ❌ Wasted bandwidth: Syncs even when nothing changed
// ❌ User experience: Stale data until next poll
```

### After (v0.5.0)
```dart
// Real-time listening - syncs ONLY when data changes
final realtimeManager = RealtimeSubscriptionManager(
  config: RealtimeSubscriptionConfig.production(),
  provider: adapter.getRealtimeProvider()!,
  engine: engine,
  logger: logger,
);

await realtimeManager.initialize();

// Benefits:
// ✅ Instant updates (sub-second latency)
// ✅ No polling (battery friendly)
// ✅ Only syncs affected tables
// ✅ Always fresh data
```

---

## 🚀 Quick Start

### Step 1: Choose a Backend with Real-Time Support

**Firebase Firestore** (built-in real-time provider):
```dart
final adapter = FirebaseFirestoreAdapter(
  firestore: FirebaseFirestore.instance,
  localStore: store,
);

// Firestore real-time is automatically available
final provider = adapter.getRealtimeProvider();
assert(provider != null);  // ✅ Has real-time provider
```

**Supabase** (real-time coming in v0.6.0):
```dart
final adapter = SupabaseAdapter(
  client: Supabase.instance.client,
  localStore: store,
);

// Not yet in v0.5.0, but will be supported in v0.6.0
final provider = adapter.getRealtimeProvider();
// Currently null; use manual polling instead
```

**GraphQL** (with subscriptions):
```dart
final adapter = GraphQLAdapter(
  graphqlClient: graphqlClient,
  localStore: store,
  queryBuilder: (req) => '...',
  mutationBuilder: (table, data) => '...',
  softDeleteMutationBuilder: (table, id) => '...',
);

// GraphQL subscriptions coming in v0.6.0
```

### Step 2: Initialize Real-Time Manager

```dart
import 'package:replicore/replicore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ... initialize SyncEngine as normal ...
  final engine = SyncEngine(
    localStore: store,
    remoteAdapter: adapter,
    config: ReplicoreConfig.production(),
    logger: ConsoleLogger(),
  );

  await engine.init();

  // Register tables
  engine.registerTable(TableConfig(
    name: 'todos',
    columns: ['id', 'title', 'completed', 'updated_at', 'deleted_at'],
    strategy: SyncStrategy.lastWriteWins,
  ));

  // Get real-time provider from adapter
  final realtimeProvider = adapter.getRealtimeProvider();
  if (realtimeProvider != null) {
    // Create and initialize real-time manager
    final realtimeManager = RealtimeSubscriptionManager(
      config: RealtimeSubscriptionConfig.production(),
      provider: realtimeProvider,
      engine: engine,
      logger: ConsoleLogger(),
    );

    await realtimeManager.initialize();

    runApp(MyApp(
      engine: engine,
      realtimeManager: realtimeManager,
    ));
  } else {
    // Fallback to manual polling
    runApp(MyApp(
      engine: engine,
      realtimeManager: null,
    ));
  }
}
```

### Step 3: Use in Your App

```dart
class MyApp extends StatefulWidget {
  final SyncEngine engine;
  final RealtimeSubscriptionManager? realtimeManager;

  const MyApp({
    required this.engine,
    this.realtimeManager,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void dispose() {
    // Clean up real-time subscriptions on app close
    widget.realtimeManager?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: TodosScreen(engine: widget.engine),
    );
  }
}
```

---

## ⚙️ Configuration

### Preset Configurations

**Production (Recommended)**
```dart
final config = RealtimeSubscriptionConfig.production();
// ✓ Auto-sync enabled
// ✓ 2-second debounce
// ✓ Auto-reconnect with exponential backoff
// ✓ 5 max reconnection attempts
```

**Development**
```dart
final config = RealtimeSubscriptionConfig.development();
// ✓ Auto-sync enabled
// ✓ 1-second debounce (faster feedback during dev)
// ✓ Lenient timeouts (60s instead of 30s)
// ✓ 10 max reconnection attempts
```

**Disabled**
```dart
final config = RealtimeSubscriptionConfig.disabled();
// Real-time listening is disabled; use manual polling
```

### Custom Configuration

```dart
final config = RealtimeSubscriptionConfig(
  enabled: true,
  
  // Subscribe only to specific tables
  tables: {'todos', 'projects'},  // Empty = all tables
  
  // Automatically pull changes when real-time event received
  autoSync: true,
  
  // Debounce multiple rapid changes (e.g., batch operations)
  debounce: Duration(milliseconds: 500),  // Faster for mobile
  
  // Timeout for establishing real-time connection
  connectionTimeout: Duration(seconds: 30),
  
  // Auto-reconnect when connection drops
  autoReconnect: true,
  maxReconnectAttempts: 5,
  backoffMultiplier: 2.0,  // 1s, 2s, 4s, 8s, 16s delays
);

final manager = RealtimeSubscriptionManager(
  config: config,
  provider: provider,
  engine: engine,
  logger: logger,
);

await manager.initialize();
```

---

## 🔄 How It Works

### Event Flow

```
┌─────────────────────────────────────────┐
│   Remote Backend (Firebase, etc.)       │
│   User updates a todo in another app    │
└─────────────────┬───────────────────────┘
                  │
                  ↓ Real-time Event
┌─────────────────────────────────────────┐
│   Replicore Real-Time Listener          │
│   Detects: "todos" table changed        │
└─────────────────┬───────────────────────┘
                  │
                  ↓ (Debounced)
┌─────────────────────────────────────────┐
│   Replicore SyncEngine                  │
│   Syncs only "todos" table              │
└─────────────────┬───────────────────────┘
                  │
                  ↓ Updated Data
┌─────────────────────────────────────────┐
│   LocalStore (Sqflite/Hive/Drift/Isar) │
│   Records merged with conflict resolution
└─────────────────┬───────────────────────┘
                  │
                  ↓ Data Changed
┌─────────────────────────────────────────┐
│   Your UI                               │
│   Automatically reflects new data       │
└─────────────────────────────────────────┘
```

### Example: Multi-User Collaboration

**Scenario**: Two users editing a shared document

```
User A (Device 1)          Server          User B (Device 2)
    │                         │                    │
    │──── Write Title ────────>│                    │
    │                         │────> Event ───────>│
    │                         │   (Realtime)       │
    │                         │<─────── Sync ──────│
    │<────────── Sync ────────│                    │
    │                         │                    │
    │             (Both devices now have latest!)             │
```

**Without real-time** (v0.4.0):
- User B's change appears 30 seconds later (during next poll)
- Poor user experience

**With real-time** (v0.5.0):
- User B's change appears within 100ms
- Feels instant and seamless

---

## 📊 Monitoring Real-Time Status

```dart
class TodosScreen extends StatefulWidget {
  final RealtimeSubscriptionManager? realtimeManager;

  const TodosScreen({this.realtimeManager});

  @override
  State<TodosScreen> createState() => _TodosScreenState();
}

class _TodosScreenState extends State<TodosScreen> {
  @override
  Widget build(BuildContext context) {
    final manager = widget.realtimeManager;

    if (manager == null) {
      return Text('Real-time not available');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Todos'),
        actions: [
          // Show connection status
          Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: manager.isConnected
                  ? Chip(
                      label: Text('🟢 Real-Time Active'),
                      backgroundColor: Colors.green.shade100,
                    )
                  : Chip(
                      label: Text('🔴 Offline'),
                      backgroundColor: Colors.red.shade100,
                    ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Show subscribed tables
          Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Syncing: ${manager.subscribedTables.join(", ")}',
              style: TextStyle(fontSize: 12),
            ),
          ),

          // Your todo list
          Expanded(child: TodoList()),
        ],
      ),
    );
  }
}
```

---

## 🎯 When to Use Manual Polling vs Real-Time

| Feature | Manual Polling | Real-Time |
|---------|---|---|
| **Latency** | 30-60 seconds | Sub-second ✅ |
| **Battery** | High drain | Low ✅ |
| **Bandwidth** | Wasted syncs | Efficient ✅ |
| **Backend Support** | All | Firestore, GraphQL, Supabase (v0.6.0) |
| **Complexity** | Simple | Moderate |
| **Cost** | High polling costs | Low event costs |

**Use Real-Time if:**
- ✅ Collaborative app (multiple users)
- ✅ Battery-critical (mobile)
- ✅ Backend supports it (Firestore, GraphQL)
- ✅ Want instant updates

**Fallback to Polling if:**
- ❌ Backend doesn't support real-time
- ❌ Infrequent updates OK
- ❌ Simple implementation preferred

---

## 🔌 Implementing Real-Time for Custom Backends

If your backend supports real-time but isn't yet in Replicore, implement `RealtimeSubscriptionProvider`:

```dart
import 'package:replicore/replicore.dart';

class CustomBackendRealtimeProvider 
    implements RealtimeSubscriptionProvider {
  final CustomClient client;
  bool _isConnected = false;
  late StreamController<bool> _connectionStatus;

  CustomBackendRealtimeProvider(this.client) {
    _connectionStatus = StreamController<bool>.broadcast();
  }

  @override
  Stream<RealtimeChangeEvent> subscribe(String table) {
    return client.subscribeToTable(table).map((event) {
      return RealtimeChangeEvent(
        table: table,
        operation: _parseOperation(event.type),
        record: event.data,
        metadata: event.metadata,
        timestamp: event.timestamp,
      );
    });
  }

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<bool> get connectionStatusStream => _connectionStatus.stream;

  @override
  Future<void> close() async {
    await client.disconnect();
    _connectionStatus.close();
  }

  RealtimeOperation _parseOperation(String type) {
    return switch (type) {
      'INSERT' => RealtimeOperation.insert,
      'UPDATE' => RealtimeOperation.update,
      'DELETE' => RealtimeOperation.delete,
      _ => RealtimeOperation.update,
    };
  }
}

// Then implement in your RemoteAdapter:
class CustomBackendAdapter implements RemoteAdapter {
  // ... other methods ...

  late CustomBackendRealtimeProvider _realtimeProvider;

  @override
  RealtimeSubscriptionProvider? getRealtimeProvider() {
    return _realtimeProvider;
  }
}
```

---

## ⚠️ Common Issues & Troubleshooting

### Issue: Real-time works but then stops syncing

**Cause**: Connection lost, not reconnecting  
**Solution**: Check `autoReconnect: true` in config

```dart
final config = RealtimeSubscriptionConfig(
  autoReconnect: true,  // Ensure this is true
  maxReconnectAttempts: 10,
);
```

### Issue: Real-time events causing sync storms

**Cause**: Too many rapid events triggering syncs  
**Solution**: Increase debounce duration

```dart
final config = RealtimeSubscriptionConfig(
  debounce: Duration(seconds: 3),  // Increase from 2s
);
```

### Issue: Real-time not working, fallback to polling

**Cause**: Backend doesn't provide real-time or provider is null  
**Solution**: Fallback to manual polling

```dart
final realtimeProvider = adapter.getRealtimeProvider();

if (realtimeProvider != null) {
  // Use real-time
  final manager = RealtimeSubscriptionManager(...);
  await manager.initialize();
} else {
  // Fallback to manual polling
  Timer.periodic(Duration(seconds: 30), (_) {
    engine.syncAll();
  });
}
```

---

## 📚 Next Steps

1. **Enable for your app**: Follow Quick Start above
2. **Monitor connection**: Track `isConnected` status
3. **Customize config**: Tune debounce, timeouts, etc.
4. **Test multi-device**: Verify changes sync across devices
5. **Monitor battery**: Check if real-time improves battery life
6. **Implement custom backend**: If needed, extend `RealtimeSubscriptionProvider`

---

## 🎉 Pro Tips

1. **Combine with UI streams**: Use `StreamBuilder` to auto-update UI on sync
2. **Toast notifications**: Show user when syncing
3. **Connection badges**: Display real-time status in app bar
4. **Analytics tracking**: Log real-time events for debugging
5. **Gradual rollout**: Enable real-time for subset initially, monitor

---

Enjoy instant, battery-friendly synchronization! 🚀
