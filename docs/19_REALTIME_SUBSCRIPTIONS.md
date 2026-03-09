# Real-Time Subscriptions

> **Event-driven synchronization for instant updates**

---

## 🎯 Why Real-Time?

Real-time subscriptions keep your app instantly updated when **server data changes**, without waiting for manual sync.

### ✅ Benefits

- **Instant updates**: See changes immediately
- **Less polling**: No need for periodic sync intervals
- **Better UX**: Users see latest data instantly
- **Scalable**: Server pushes changes, not pull-based

---

## 🏗️ Architecture

```
Server          Network          App
  │                │              │
  │─── Change ────→│             │
  │                │────Event────→│
  │                │         (push)
  │                │              │
  │                │          ┌──────────┐
  │                │          │ Update UI│
  │                │          │ Sync data│
  │                │          └──────────┘
```

---

## Firebase Real-Time

### Setup Subscription

```dart
class FirebaseAdapter extends RemoteAdapter {
  @override
  Stream<DataChange>? subscribe({required String table}) {
    return FirebaseFirestore.instance
        .collection(table)
        .snapshots()
        .map((snapshot) {
          // Convert Firebase snapshot to DataChange
          return snapshot.docChanges.map((change) {
            return DataChange(
              table: table,
              primaryKey: change.doc.id,
              operation: change.type == DocumentChangeType.removed
                  ? ChangeType.delete
                  : change.type == DocumentChangeType.added
                      ? ChangeType.insert
                      : ChangeType.update,
              data: change.doc.data() ?? {},
            );
          }).first;
        });
  }
}
```

### In Replicore

```dart
final adapter = FirebaseAdapter(firestore);

// Subscribe to changes
adapter.subscribe(table: 'todos')?.listen((change) {
  print('Real-time update: ${change.operation}');
  // Pull latest data
  engine.sync(table: 'todos');
});
```

---

## Supabase Real-Time

### Setup Subscription

```dart
final supabase = SupabaseClient(url, key);

class SupabaseAdapter extends RemoteAdapter {
  @override
  Stream<DataChange>? subscribe({required String table}) {
    return supabase
        .from(table)
        .on(PostgresChangeEvent.all, ...)
        .limit(10)
        .asStream()
        .map((payload) {
          return DataChange(
            table: table,
            primaryKey: payload['record']['uuid'],
            operation: ChangeType.update,
            data: payload['record'],
          );
        });
  }
}
```

### Row-Level Security

Make sure your RLS policy allows real-time subscriptions:

```sql
CREATE POLICY "Users can subscribe to their data"
ON todos
FOR SELECT
USING (auth.uid() = user_id);
```

---

## Appwrite Real-Time

### Subscribe via WebSocket

```dart
class AppwriteAdapter extends RemoteAdapter {
  late final appwrite = Appwrite();
  
  @override
  Stream<DataChange>? subscribe({required String table}) {
    final channel = StreamController<DataChange>();
    
    appwrite.client
        .subscribe('collections.$collectionId.documents')
        .stream
        .listen((message) {
          if (message.payload is DocumentEvent) {
            final event = message.payload as DocumentEvent;
            
            channel.add(DataChange(
              table: table,
              primaryKey: event.documentId,
              operation: ChangeType.update,
              data: event.data,
            ));
          }
        });
    
    return channel.stream;
  }
}
```

---

## GraphQL Subscriptions

### Setup with hasura-connect

```dart
class GraphQLAdapter extends RemoteAdapter {
  @override
  Stream<DataChange>? subscribe({required String table}) {
    final subscription = gql('''
      subscription on${table.toUpperCase()} {
        ${table} {
          uuid
          title
          updated_at
        }
      }
    ''');
    
    return graphqlClient
        .subscribe(subscription)
        .map((result) {
          final data = result.data?[table] as Map;
          return DataChange(
            table: table,
            primaryKey: data['uuid'],
            operation: ChangeType.update,
            data: data,
          );
        });
  }
}
```

---

## 🔄 Auto-Sync on Real-Time

### Listen and Sync

```dart
final adapter = MyAdapter();

// Subscribe to real-time
adapter.subscribe(table: 'todos')?.listen((change) {
  print('Real-time: ${change.operation}');
  
  // Trigger sync to pull latest
  engine.syncTable('todos');
  
  // Rebuild UI if using Flutter
  if (mounted) {
    setState(() {});
  }
});

// Also monitor general sync status
engine.statusStream.listen((status) {
  if (status.contains('complete')) {
    if (mounted) {
      setState(() {}); // Refresh after sync completes
    }
  }
});
```
```

---

## 🔌 Connection Management

### Auto-Reconnect

```dart
class RealTimeManager {
  StreamSubscription? _subscription;
  
  void connect(RemoteAdapter adapter) {
    _subscription = adapter
        .subscribe(table: 'todos')
        ?.listen(
          (change) => _handleChange(change),
          onError: (error) => _handleError(error),
        );
  }
  
  void _handleError(dynamic error) {
    print('⚠️  Subscription error: $error');
    
    // Reconnect after 5 seconds
    Future.delayed(
      Duration(seconds: 5),
      () => connect(adapter),
    );
  }
  
  void disconnect() {
    _subscription?.cancel();
  }
}
```

### Lifecycle Management

```dart
@override
void initState() {
  super.initState();
  realTimeManager.connect(adapter);
  
  // Listen for sync status changes
  engine.statusStream.listen((status) {
    if (mounted) {
      setState(() {}); // Rebuild on sync updates
    }
  });
}

@override
void dispose() {
  realTimeManager.disconnect();
  super.dispose();
}
```

---

## 🎯 When to Use Real-Time

### ✅ Use Real-Time When:

- Collaboration is important (multiple users editing)
- You need instant updates
- Network is reliable
- You want to reduce server load

### ❌ Don't Use When:

- Updates are infrequent
- Network is unreliable
- You want simple sync
- Battery is critical (real-time uses more battery)

---

## 💡 Best Practice: Hybrid Approach

Combine real-time with periodic sync:

```dart
final config = ReplicoreConfig(
  autoSync: true,
  syncInterval: Duration(minutes: 5),  // Fallback
);

// Also subscribe to real-time
adapter.subscribe(table: 'todos')?.listen((change) {
  engine.sync(table: 'todos');  // Immediate
});
```

**Result**: Instant updates when changes happen, fallback sync as safety net.

---

## 📊 Real-Time Data Flow

```
Firebase
   │
   ├─ DocA changed
   │
   └─→ Subscription Stream
        │
        └─→ DataChange event
             │
             └─→ Engine.sync()
                  │
                  └─→ Pull changes
                       │
                       └─→ Update local store
                            │
                            └─→ onDataChanged
                                 │
                                 └─→ UI Update
```

---

## 🧪 Testing Real-Time

Mock subscriptions:

```dart
class MockAdapter extends RemoteAdapter {
  @override
  Stream<DataChange>? subscribe({required String table}) {
    return Stream.fromIterable([
      DataChange(
        table: table,
        primaryKey: '1',
        operation: ChangeType.update,
        data: {'title': 'Updated'},
      ),
    ]);
  }
}

test('real-time subscription works', () async {
  final adapter = MockAdapter();
  
  final changes = <DataChange>[];
  adapter.subscribe(table: 'todos')?.listen((change) {
    changes.add(change);
  });
  
  await Future.delayed(Duration(milliseconds: 100));
  
  expect(changes, hasLength(1));
  expect(changes[0].operation, ChangeType.update);
});
```

---

## ⚡ Performance Considerations

### Bandwidth

Real-time subscriptions use **persistent connections** (WebSocket):
- More bandwidth than periodic polling for **very frequent** updates
- Less bandwidth for **infrequent** updates
- Good for **collaboration** scenarios

### Battery

Real-time keeps connection alive:
- More battery drain on mobile
- Less battery than constant polling

### CPU

Real-time events processed immediately:
- No background sync thread needed
- Instant response to changes

---

## 🔐 Security

### Authenticate Subscription

```dart
// Firebase: Rules apply automatically
final rules = '''
match /todos/{document=**} {
  allow read: if request.auth != null;
}
''';

// Supabase RLS: Automatic based on user
// Appwrite: Collections have permissions
// GraphQL: JWT token validates subscription
```

### No Sensitive Data

Don't send sensitive data in real-time events:

```dart
// ❌ WRONG
subscription {
  users {
    name
    email
    password  // ❌ Sensitive!
  }
}

// ✅ CORRECT
subscription {
  users {
    name
    email
    // No sensitive fields
  }
}
```

---

## 📱 UI Pattern

```dart
class TodoList extends StatefulWidget {
  @override
  State<TodoList> createState() => _TodoListState();
}

class _TodoListState extends State<TodoList> {
  late RealTimeManager realTime;
  late List<Todo> todos = [];
  
  @override
  void initState() {
    super.initState();
    
    realTime = RealTimeManager();
    realTime.connect(adapter);
    
    // Load initial data
    _loadTodos();
    
    // Listen for sync status changes to reload data
    engine.statusStream.listen((status) {
      if (status.contains('complete')) {
        _loadTodos();
      }
    });
  }
  
  Future<void> _loadTodos() async {
    final loaded = await engine.readLocalWhere('todos');
    if (mounted) {
      setState(() {
        todos = loaded.cast<Todo>();
      });
    }
  }
  
  @override
  void dispose() {
    realTime.disconnect();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: todos.length,
      itemBuilder: (context, index) =>
        TodoTile(todo: todos[index]),
    );
  }
}
```

---

**Real-time subscriptions create the best user experience!** ✨
