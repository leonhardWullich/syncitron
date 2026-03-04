# Flutter Local First ⚡️

**The missing link between Supabase and SQLite for Flutter apps.**

Turn your online-only Supabase app into a robust Offline-First application. replicore handles the complexity of data synchronization, conflict resolution, difference tracking, and local caching, so you can focus on building your UI.

It connects your existing sqflite database with your supabase_flutter project using a fluent, easy-to-use API.

## ✨ Features

🔌 Agnostic & Flexible: Works with any SQLite table structure. It uses reflection to discover columns automatically.

🪄 Auto-Migration: Automatically adds required columns (is_synced, updated_at, deleted_at) to your SQLite tables if they are missing.

🧠 Smart Conflict Resolution: Choose between ServerWins, LocalWins, LastWriteWins or write your own CustomMerge logic.

🚀 High Performance: Uses Bulk Reads/Writes and Batch transactions to sync thousands of records in milliseconds.

🔄 Two-Way Sync: Pulls updates from the server and pushes local dirty changes back.

🗑 Soft Delete Support: Handles deletions gracefully across devices.

## ⚙️ Prerequisites

Your Supabase (Remote) tables need a few standard columns to track state.

id (or any other Primary Key): Unique identifier.
updated_at (timestamp): To track modification time.
deleted_at (timestamp, nullable): To track soft deletes.

Note: You do NOT need to add is_synced to Supabase. This is a local-only column managed automatically by this package.

## 📦 Installation

Add the dependencies to your code with running:

flutter pub add replicore

## 🏁 Getting Started

### 1. Initialize the Service

Initialize the service once (e.g., in your main.dart or a provider) by passing your Database instance and defining the tables you want to sync.

```dart
import 'package:replicore/replicore.dart';

void main() async {
  // 1. Open your SQLite database
  final db = await openDatabase('my_app.db', version: 1, onCreate: ...);

  // 2. Configure FlutterLocalFirst
  final syncService = FlutterLocalFirst()
    .setDatabase(db)
    
    // Optional: Configure global column names if yours differ
    .setConfig(const FlutterLocalFirstConfig(
      batchSize: 500,
    ))

    // 3. Register Tables
    // Simple table: Server always wins on conflict
    .addTable(TableDefinition(
      'tags', 
      primaryKey: 'id'
    ))

    // Complex table: Last edit wins (Time based)
    .addTable(TableDefinition(
      'user_settings',
      primaryKey: 'uuid', // Custom PK name
      strategy: SyncStrategy.lastWriteWins,
    ))

    // Advanced: Custom Merge Logic with Async support
    .addTable(TableDefinition(
      'notes',
      strategy: SyncStrategy.customMerge,
      customMerge: (local, remote) async {
        // Example: Keep the longer text
        final localContent = local['content'] as String;
        final remoteContent = remote['content'] as String;
        
        if (localContent.length > remoteContent.length) {
          return local; 
        }
        return remote;
      },
      onSynced: (record) {
        print("Note synced: ${record['id']}");
      }
    ));

  // 4. Start the Service (Triggers Auto-Migration)
  await syncService.start();
  
  runApp(MyApp());
}
```

### 2. Trigger a Sync

Call runFullSync() whenever you want to synchronize. Good places to call this are:

App Start

When internet connection is restored (e.g. using connectivity_plus)

User explicitly triggers "Pull to refresh"

```dart
// Syncs all registered tables
await FlutterLocalFirst().runFullSync();

// OR sync a specific table manually
await FlutterLocalFirst().syncTable('notes');
```


### 3. Listen to Status Updates

You can show a loading indicator or status text in your UI by listening to the stream.

```dart
StreamBuilder<String>(
  stream: FlutterLocalFirst().statusStream,
  builder: (context, snapshot) {
    return Text(snapshot.data ?? "Idle");
  },
)
```

### 🧩 Conflict Strategies

When a record has been modified both locally (offline) and remotely (server), a conflict occurs. replicore offers 4 strategies to handle this:

Strategy

Description

Use Case

SyncStrategy.serverWins

Remote data always overwrites local data. Local changes are lost if they conflict.

Read-heavy data, News feeds, Catalogs.

SyncStrategy.localWins

Local dirty data is kept. Remote updates are ignored until local changes are pushed.

User drafts, private notes where losing work is unacceptable.

SyncStrategy.lastWriteWins

Compares updated_at. The newer timestamp wins.

Collaborative editing (simple), User settings.

SyncStrategy.customMerge

You provide a callback function to manually merge the data.

Complex text, Lists, JSON blobs.

## 💡 How it works

Auto-Migration: When you call .start(), the package checks your SQLite tables. If columns like is_synced or updated_at are missing, it adds them via ALTER TABLE.

Dirty Tracking: When you update a record locally in your app, you should set is_synced = 0.

Note: You need to handle setting is_synced = 0 in your own CRUD operations, or use a trigger in SQLite.

Sync Process:

Pull: Downloads all records from Supabase that have a newer updated_at than the last sync.

Merge: Checks if the incoming record conflicts with a local "dirty" record. Applies the chosen strategy.

Push: Finds all local records with is_synced = 0. Uploads them to Supabase using upsert. Upon success, sets is_synced = 1.

## 📄 License

No public use allowed
