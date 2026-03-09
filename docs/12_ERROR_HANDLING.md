# Error Handling & Recovery

> **Comprehensive exception handling and recovery strategies**

---

## 🎯 Exception Hierarchy

```
ReplicoreException
├── SyncException
│   ├── PullException
│   ├── PushException
│   └── ConflictException
├── StorageException
│   ├── RecordNotFoundException
│   └── DatabaseException
├── NetworkException
│   ├── TimeoutException
│   └── ConnectionException
└── ConfigurationException
    ├── TableNotRegisteredException
    └── InvalidConfigException
```

---

## 🛡️ Error Handling Patterns

### Try-Catch Pattern

```dart
try {
  await engine.sync();
} on PullException catch (e) {
  logger.error('Pull failed', error: e);
  // Handle pull-specific error
} on PushException catch (e) {
  logger.error('Push failed', error: e);
  // Handle push-specific error
} on NetworkException catch (e) {
  logger.warning('Network error', error: e);
  // Retry later
} catch (e) {
  logger.error('Unknown error', error: e);
}
```

### Exception Handling in Try-Catch

```dart
try {
  await engine.syncAll();
} on NetworkException catch (error) {
  // Show retry UI
  showNetworkError(error);
} on SyncException catch (error) {
  // Alert user
  showSyncError(error);
} on ReplicoreException catch (error) {
  // Handle unexpected errors
  logger.error('Sync error', error: error);
}
```

---

## 📋 Specific Exceptions

### PullException

**When**: Downloading from server fails

```dart
try {
  await engine.sync();
} on PullException catch (e) {
  // Happens when:
  // - Network error
  // - Server returns error
  // - Invalid response

  if (e.statusCode == 429) {
    // Rate limited: wait longer
    await Future.delayed(Duration(minutes: 1));
    await engine.sync();
  } else if (e.isNetworkError) {
    // Connection lost: retry when online
    // Replicore auto-retries
  }
}
```

### PushException

**When**: Uploading to server fails

```dart
on PushException catch (e) {
  // Happens when:
  // - Network error
  // - Server rejects data
  // - Permissions issue

  final failedRecords = e.failedRecords;
  logger.error(
    'Push failed for ${failedRecords.length} records',
    context: {'table': e.table},
  );
  
  // Failed records stay dirty and retry next sync
}
```

### NetworkException

**When**: Network is unavailable

```dart
on NetworkException catch (e) {
  // App is offline
  logger.info('Network unavailable, using offline mode');
  
  // Local operations still work!
  // Sync retries when network returns
}
```

### ConflictException

**When**: Conflict resolution fails

```dart
on ConflictException catch (e) {
  logger.warning(
    'Conflict resolution failed',
    context: {
      'table': e.table,
      'record_id': e.primaryKey,
    },
  );
  
  // Use CustomResolver to handle
}
```

---

## 🔄 Retry Strategies

### Automatic Retry (Default)

```dart
final config = ReplicoreConfig(
  maxRetries: 3,  // Automatic retry up to 3 times
  retryDelay: Duration(seconds: 2),
);

// Retry schedule: 2s → 4s → 8s (exponential backoff)
```

### Manual Retry

```dart
Future<void> syncWithRetry() async {
  int attempts = 0;
  const maxAttempts = 3;
  
  while (attempts < maxAttempts) {
    try {
      await engine.sync();
      return;  // Success
    } catch (e) {
      attempts++;
      if (attempts < maxAttempts) {
        await Future.delayed(
          Duration(seconds: 2 * attempts),
        );
      }
    }
  }
  
  throw Exception('Sync failed after $maxAttempts attempts');
}
```

### Exponential Backoff

```dart
Future<void> syncWithBackoff() async {
  int delay = 1;  // Start with 1 second
  
  for (int i = 0; i < 5; i++) {
    try {
      await engine.sync();
      return;
    } catch (e) {
      delay *= 2;  // Double: 1s → 2s → 4s → 8s → 16s
      
      if (i < 4) {
        await Future.delayed(Duration(seconds: delay));
      } else {
        rethrow;
      }
    }
  }
}
```

---

## 🎯 Error Recovery

### Network Recovery

```dart
void _setupConnectivityMonitoring() {
  Connectivity().onConnectivityChanged.listen((result) {
    if (result == ConnectivityResult.none) {
      logger.info('Network lost');
      // Local operations continue
    } else {
      logger.info('Network restored');
      // Auto-sync triggered
      engine.sync();
    }
  });
}
```

### Status Monitoring

```dart
// Monitor sync status in real-time
engine.statusStream.listen((status) {
  print('Sync progress: $status');
  
  if (status.contains('Error')) {
    logger.error('Sync error detected: $status');
  }
});

// Check detailed metrics after sync
final metrics = await engine.syncAll();

if (!metrics.overallSuccess) {
  logger.warning(
    'Sync completed with errors: '
    '${metrics.totalRecordsPushed}/${metrics.totalRecordsPulled} processed',
  );
  print('Conflicts: ${metrics.conflictsEncountered}');
  print('Duration: ${metrics.duration}');
}
```

### Advanced Error Tracking

```dart
// For tracking permanently failed records
class SyncErrorTracker {
  final deadLetterQueue = <String>[];
  final Map<String, int> retryAttempts = {};
  
  void trackRetryAttempt(String recordId) {
    retryAttempts[recordId] = (retryAttempts[recordId] ?? 0) + 1;
    
    if (retryAttempts[recordId]! >= 10) {
      // Move to dead letter after 10 failures
      deadLetterQueue.add(recordId);
      logger.error('Record moved to DLQ', context: {'id': recordId});
    }
  }
}
```

---

## 📊 Error Monitoring

### Track Sync Metrics Over Time

```dart
class SyncMetricsTracker {
  final List<SyncSessionMetrics> history = [];
  
  void trackSync(SyncSessionMetrics metrics) {
    history.add(metrics);
  }
  
  double getSuccessRate() {
    if (history.isEmpty) return 0;
    final successful = history.where((m) => m.overallSuccess).length;
    return successful / history.length;
  }
  
  void printStats() {
    print('Success rate: ${getSuccessRate() * 100}%');
    print('Total syncs: ${history.length}');
    
    final avgPulled = history.isEmpty ? 0 : 
      history.fold<int>(0, (sum, m) => sum + m.totalRecordsPulled) / history.length;
    print('Avg records pulled: ${avgPulled.toStringAsFixed(2)}');
  }
}

final tracker = SyncMetricsTracker();

// After each sync
final metrics = await engine.syncAll();
tracker.trackSync(metrics);

if (tracker.getSuccessRate() < 0.9) {
  // <90% success rate
  sendAlert('Sync reliability below threshold');
}
```

---

## 🛡️ Defensive Programming

### Input Validation

```dart
Future<void> createTodo(String title) async {
  if (title.trim().isEmpty) {
    throw ArgumentError('Title cannot be empty');
  }
  
  if (title.length > 1000) {
    throw ArgumentError('Title too long');
  }
  
  await engine.writeLocal('todos', {
    'uuid': generateUuid(),
    'title': title.trim(),
    'updated_at': DateTime.now().toIso8601String(),
  });
}
```

### State Validation

```dart
Future<bool> isReadyForSync() async {
  if (!_isInitialized) {
    throw StateError('SyncEngine not initialized');
  }
  
  if (!await Connectivity().checkConnectivity()
      .then((r) => r != ConnectivityResult.none)) {
    return false;  // Not ready, but will retry
  }
  
  return true;
}
```

---

## 🧪 Testing Error Scenarios

### Mock Failures

```dart
class MockAdapterWithFailures extends RemoteAdapter {
  int attemptCount = 0;
  
  @override
  Future<void> upsert({required String table, ...}) async {
    attemptCount++;
    
    if (attemptCount < 3) {
      throw TimeoutException('Simulated timeout');
    }
    // Succeed on 3rd attempt
  }
}

test('retry on failure', () async {
  final engine = SyncEngine(
    remoteAdapter: MockAdapterWithFailures(),
    ...
  );
  
  await engine.sync();  // Should succeed after retries
});
```

---

## 🚀 Production Error Handling

```dart
Future<void> setupErrorHandling() async {
  // Catch all platform errors
  PlatformDispatcher.instance.onError = (error, stack) {
    logger.error(
      'Uncaught error',
      error: error,
      stackTrace: stack,
    );
    
    // Send to error tracking service
    sendToSentry(error, stack);
    
    return true;
  };
  
  // Catch all async errors
  runZonedGuarded(
    () => runApp(const MyApp()),
    (error, stack) {
      logger.error('Zone error', error: error, stackTrace: stack);
      sendToSentry(error, stack);
    },
  );
}
```

---

**Error handling is critical for production reliability!** 🛡️
