# syncitron Example: Todo App

A fully-featured Flutter example demonstrating syncitron v0.5.1 (Performance Release) with offline-first synchronization, real-time updates, batch operations, structured logging, metrics collection, and comprehensive error handling.

## 📋 Project Structure

```
lib/
├── main.dart                     # App entry point with syncitron v0.5.0 setup
├── data/
│   ├── todo.dart                 # Data model with sync metadata
│   └── todo_repository.dart      # Database abstraction layer
├── sync/
│   └── sync_service.dart         # Background sync orchestration & connectivity handling
└── ui/
    ├── login_screen.dart         # Supabase authentication
    └── todo_list_screen.dart     # Main UI with sync metrics & logging integration
```

## 🚀 What This Example Demonstrates

### 1. **syncitron v0.5.0 Setup** (`main.dart`)
- ✅ Creating `syncitronConfig` with production preset
- ✅ Structured logging with `ConsoleLogger`
- ✅ Metrics collection with `InMemoryMetricsCollector`
- ✅ Error handling during initialization
- ✅ Multi-table configuration with conflict resolution
- ✅ Real-time subscription setup with RealtimeSubscriptionManager

### 2. **Sync Service Architecture** (`sync/sync_service.dart`)
- ✅ Connectivity-triggered sync (auto-sync on reconnect)
- ✅ Periodic background sync (60-second intervals)
- ✅ Real-time event handling with RealtimeSubscriptionManager
- ✅ Typed exception handling with specialized error types
- ✅ Status streaming for UI updates

### 3. **Structured Logging** (`ui/todo_list_screen.dart`)
```dart
widget.logger.info('Todo created', context: {'title': title});
widget.logger.warning('Network error during sync', error: e);
widget.logger.error('Failed to load todos', error: e);
widget.logger.debug('Loaded ${todos.length} todos');
```

### 4. **Metrics Collection & Display**
- ✅ Automatic sync metrics (pulled, pushed, duration)
- ✅ Metrics card in UI showing last sync details
- ✅ Metrics dialog accessible from app bar
- ✅ Performance monitoring integration

### 5. **Comprehensive Error Handling**
```dart
try {
  await _onRefresh();
} on SyncNetworkException catch (e) {
  // Network errors (offline, unreachable)
} on SyncAuthException catch (e) {
  // Session expired → redirect to login
} catch (e) {
  // Generic sync errors
}
```

### 6. **Data Persistence & Sync**
- ✅ SQLite with soft delete pattern
- ✅ User-scoped queries (multi-tenant)
- ✅ Sync metadata columns (`is_synced`, `op_id`, `synced_at`)
- ✅ Optimistic UI updates

---

## 📱 Getting Started

### Prerequisites
- Flutter 3.0+ and Dart 3.10.8+
- Supabase project (free at supabase.com)
- Environment variables (or defaults in `main.dart`):
  ```bash
  export SUPABASE_URL="your-url"
  export SUPABASE_ANON_KEY="your-key"
  ```

### Steps

1. **Initialize dependencies**:
   ```bash
   flutter pub get
   ```

2. **Create Supabase tables**:
   Run `supabase_schema.sql` in your Supabase SQL editor

3. **Configure credentials** in `main.dart`:
   ```dart
   final supabaseUrl = String.fromEnvironment(
     'SUPABASE_URL',
     defaultValue: 'https://your-project.supabase.co',
   );
   ```

4. **Run the app**:
   ```bash
   flutter run
   ```

---

## 🔧 Key Configuration Options

### syncitronConfig Presets

```dart
// Production: Conservative settings, structured logging
final config = syncitronConfig.production();

// Development: Verbose logging, faster retries
final config = syncitronConfig.development();

// Testing: In-memory, no network I/O
final config = syncitronConfig.testing();

// Custom: Full control
final config = syncitronConfig(
  batchSize: 100,
  retryStrategy: ExponentialBackoff(maxDelaySeconds: 300),
  conflictResolution: ConflictResolution.lastWriteWins,
);
```

### Logger Setup

```dart
// Console output (development)
final logger = ConsoleLogger(minLevel: LogLevel.info);

// No-op (production)
final logger = NoOpLogger();

// Multiple backends
final logger = MultiLogger([
  ConsoleLogger(),
  SentryLogger(), // custom implementation
  DatadogLogger(), // custom implementation
]);
```

### Metrics Collection

```dart
// In-memory collection
final metrics = InMemoryMetricsCollector();

// Access sync statistics
final sessionMetrics = await engine.syncAll();
print('Pulled: ${sessionMetrics.totalRecordsPulled}');
print('Pushed: ${sessionMetrics.totalRecordsPushed}');
print('Duration: ${sessionMetrics.totalDuration}');
```

---

## 📊 Sync Flow

```
┌─────────────────────────────────────────────────────────┐
│                    App Lifecycle                         │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
            ┌──────────────────────────┐
            │ Initialize syncitron     │
            │ - Config: production()   │
            │ - Logger: ConsoleLogger  │
            │ - Metrics: collector     │
            └──────────────────────────┘
                           │
                           ▼
            ┌──────────────────────────┐
            │ SyncService.start()      │
            │ - Periodic: 60s          │
            │ - On reconnect           │
            └──────────────────────────┘
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
         ▼                 ▼                 ▼
    Pull Phase       Push Phase         Conflict
    ┌────────┐     ┌────────┐          Resolution
    │ Remote │────▶│ Local  │         ┌────────┐
    │ Data   │     │ Updates│────────▶│ Strategy│
    └────────┘     └────────┘         └────────┘
         │                 │                 │
         └─────────────────┼─────────────────┘
                           │
                           ▼
            ┌──────────────────────────┐
            │ SyncSessionMetrics       │
            │ - records pulled/pushed  │
            │ - errors                 │
            │ - duration               │
            └──────────────────────────┘
                           │
                           ▼
            ┌──────────────────────────┐
            │ UI Updates from Metrics  │
            │ - Display card           │
            │ - Show error banners     │
            │ - Refresh todo list      │
            └──────────────────────────┘
```

---

## 🔐 Security Best Practices in Example

1. **Row-Level Security**: Supabase RLS restricts todos to authenticated user
2. **Auth State**: Session expiry handled with auto-redirect
3. **Credentials**: Environment variables (not hardcoded)
4. **Soft Delete**: Logical deletes preserve data integrity
5. **Error Handling**: Errors logged but not leaked to user

---

## 🧪 Testing Scenarios

### Offline Behavior
1. Enable airplane mode mid-sync
2. Observe error banner + "Retrying soon" message
3. Disable airplane mode
4. Auto-sync triggers and succeeds

### Network Error
1. Throttle network in DevTools
2. Trigger sync
3. Exponential backoff retries automatically

### Auth Expiry
1. Manually revoke token in Supabase
2. Trigger sync
3. `SyncAuthException` caught
4. Auto-redirect to login screen

### Metrics Display
1. Open app, trigger manual sync
2. View metrics card (pulled/pushed/duration)
3. Tap app bar menu → "View Sync Metrics"
4. See detailed `SyncSessionMetrics` dialog

---

## 📚 Further Reading

- **Main README**: [../README.md](../README.md)
- **Enterprise Guide**: [../ENTERPRISE_README.md](../ENTERPRISE_README.md)
- **Quick Reference**: [../QUICK_REFERENCE.md](../QUICK_REFERENCE.md)
- **Patterns & Best Practices**: [../docs/ENTERPRISE_PATTERNS.md](../docs/ENTERPRISE_PATTERNS.md)

---

## 🤝 Customization Ideas

1. **Add filtering** in `todo_repository.dart` (by status, date)
2. **Integrate analytics** with `metricsCollector`
3. **Wire observability** (Sentry, Datadog) to `logger`
4. **Add offline UI** with custom sync status widget
5. **Implement custom conflict resolution** for team scenarios

---

## 📝 License

This example is part of syncitron and is currently available free of charge
under the MIT License. See [../LICENSE](../LICENSE).

Roadmap note: as syncitron grows, future releases may also be offered under a
dual-license model.

Replace the two placeholders in `lib/main.dart`:
```dart
url: 'https://YOUR_PROJECT.supabase.co',
anonKey: 'YOUR_ANON_KEY',
```

### 3. Run

```bash
flutter run
```

---

## Key concepts demonstrated

### Optimistic UI
Writes go directly to SQLite with `is_synced = 0`. The UI reloads from
SQLite immediately so the user sees their changes without waiting for the
network. syncitron pushes dirty records to Supabase on the next sync.

### Offline banner
`SyncService.syncError` is a `ValueNotifier<syncitronException?>`.
The UI uses a `ValueListenableBuilder` to react to typed errors:

```dart
switch (error) {
  SyncNetworkException e when e.isOffline => showOfflineBanner(),
  SyncAuthException()                     => redirectToLogin(),
  _                                       => showGenericError(),
}
```

No try/catch needed in widget code.

### Sync-status indicator
`SyncService.syncStatus` forwards every message from
`SyncEngine.statusStream`. Use it to show a spinner or a "Last synced" label.

### Cursor persistence
Sync cursors live in a `_syncitron_meta` SQLite table — not in
SharedPreferences. They survive "Clear Cache" and OS-level preference
eviction because they share the same file as the app data.

### Soft deletes
`TodoRepository.softDelete` sets `deleted_at` and `is_synced = 0`.
On the next sync syncitron calls `remoteAdapter.softDelete`, which updates
the Supabase row. Other devices pull the `deleted_at` value and filter it out.

### Conflict resolution
The `todos` table uses `SyncStrategy.lastWriteWins`. If the same todo is
edited on two devices while offline, the version with the newer `updated_at`
wins when they both come back online.

To use server-always-wins (e.g. for admin-managed content):
```dart
strategy: SyncStrategy.serverWins,
```

To implement custom merge logic (e.g. merging a list of tags):
```dart
TableConfig(
  name: 'todos',
  columns: [...],
  strategy: SyncStrategy.custom,
  customResolver: (local, remote) async {
    // Merge the tags arrays from both versions.
    final localTags  = List<String>.from(local['tags']  ?? []);
    final remoteTags = List<String>.from(remote['tags'] ?? []);
    final merged = {...localTags, ...remoteTags}.toList();
    return UseMerged({...remote, 'tags': merged});
  },
),
```

---

## Production checklist

- [ ] Replace `get_it` stubs in `login_screen.dart` with real DI
- [ ] Add `flutter_secure_storage` or similar for token storage
- [ ] Handle `SyncAuthException` globally (e.g. via a root navigator key)
- [ ] Add indexes for `user_id` in SQLite for large datasets
- [ ] Consider Sentry / Crashlytics for the `onLog` callback
