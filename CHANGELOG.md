# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-03-10 (Multi-Engine Management & UI Helpers)

### Added

#### UI Widget Library

New Flutter widgets for seamless sync UI integration:

- **SyncStatusWidget**: Displays current sync status with manual sync button
  - Customizable builder for complete UI control
  - Progress indicator during sync
  - Perfect for app bar integration

- **SyncMetricsCard**: Compact card showing sync metrics (pulled, pushed, duration, errors)
  - One-line integration
  - Configurable elevation and background color
  - Automatically hides when empty

- **SyncErrorBanner**: Context-aware error banner with retry/dismiss actions
  - Automatic color coding by error type (network, auth, schema)
  - Network/offline detection
  - Auth expiry detection

- **OfflineIndicator**: Chip showing offline status
  - Only visible when offline
  - Customizable icon and label

- **SyncButton**: Filled button with automatic loading state
  - Disables during sync
  - Custom loading indicator support
  - Perfect for manual sync triggers

- **SyncStatusPanel**: Comprehensive panel combining all sync UI elements
  - Status, metrics, errors, and button in one widget
  - Highly configurable visibility
  - Dashboard/settings screen ready

#### Enhanced SyncManager

- Per-engine status tracking and metrics aggregation
- Coordinated multi-engine sync with unified error handling
- Shared logger and metrics across engines
- System health aggregation across all engines
- Health status per engine with detailed diagnostics

### Changed

- Improved SyncManager API for better ergonomics
- Enhanced documentation with UI widget examples
- Better error context in widget error banners

### Documentation

- New comprehensive guide: `docs/V0.3_V0.4_RELEASE.md`
- UI widget examples in main README
- SyncManager multi-engine coordination patterns
- Complete widget API reference and examples

---

## [0.3.0] - 2026-03-08 (Custom Sync Strategies & API Cleanup)

### Removed

#### Deprecated APIs

- **Removed onLog callback** from SyncEngine constructor
  - Breaking change requiring migration to Logger interface
  - All logging now goes through structured Logger

#### Cleanup

- Removed all @Deprecated annotations from v0.2.0
- Simplified SyncEngine constructor signature

### Added

#### Custom Sync Strategies

New extensible strategy system for domain-specific sync logic:

- **SyncOrchestrationStrategy** abstract base class
  - Implement `execute()` for core sync logic
  - Implement `beforeSync()` for pre-sync hooks
  - Implement `afterSync()` for post-sync processing

- **SyncStrategyContext**: Controlled access to sync operations
  - `managedSyncTable(tableName)`: Sync single table with metrics
  - `managedSyncAll()`: Sync all tables with aggregation  
  - `shouldContinue()`: Check cancellation/timeout status
  - `cancel()`: Stop ongoing sync
  - Access to logger and metrics collector

- **Built-in Strategies**:

  1. **StandardSyncStrategy**: Default pull-push-conflicts pattern
     - Optimal for most applications
     - Recommended starting point

  2. **OfflineFirstSyncStrategy**: Graceful degradation for unreliable networks
     - Tolerates configurable network errors
     - Caches results for retry
     - Perfect for emerging markets

  3. **ManualSyncStrategy**: Strict error handling without retry
     - Every error surfaces immediately
     - For critical operations
     - Explicit approval workflows

  4. **PrioritySyncStrategy**: Priority-based table syncing
     - Critical tables fail-fast
     - Optional tables tolerate errors
     - Configurable per-table priority levels

  5. **CompositeSyncStrategy**: Chain strategies sequentially
     - Pre/post-processing hooks
     - Complex workflow support
     - Composable architecture

#### Usage Example

```dart
final metrics = await engine.syncWithOrchestration(
  OfflineFirstSyncStrategy(maxNetworkErrors: 3),
);
```

### Changed

#### SyncEngine

- New `syncWithOrchestration(SyncOrchestrationStrategy)` method
- Maintains backward compatibility with `syncAll()`
- Improved documentation

### Migration Guide

See `docs/V0.3_V0.4_RELEASE.md` for detailed migration instructions.

**Key change:**
```dart
// Before (v0.2.0)
SyncEngine(..., onLog: callback)

// After (v0.3.0)
SyncEngine(..., logger: ConsoleLogger())
```

### Documentation

- New `docs/V0.3_V0.4_RELEASE.md` with complete guide
- Custom strategy examples (batch sync, health checks, analytics)
- Built-in strategy comparisons and use cases

---

## [0.2.0] - 2026-03-05 (Enterprise Release)

### Added

#### New Enterprise Features

- **Comprehensive Logging Framework** (`Logger`, `LogLevel`, `LogEntry`)
  - Abstract logger interface for dependency injection
  - Console, NoOp, and Multi-logger implementations
  - Structured logging for APM integrations (Sentry, Datadog, etc.)
  - Log level filtering and context support

- **Metrics & Monitoring** (`SyncMetrics`, `SyncSessionMetrics`, `MetricsCollector`)
  - Per-table sync metrics with detailed statistics
  - Session-level aggregation and performance tracking
  - InMemory and NoOp metric collectors
  - JSON export for external analytics systems

- **Configuration Management** (`ReplicoreConfig`)
  - Factory methods for Production, Development, and Testing configs
  - Validation on creation with detailed error messages
  - Configurable retry strategies with exponential backoff
  - Batch size, timeout, and column name customization
  - Periodic sync interval configuration

- **Health Checks & Diagnostics** (`DiagnosticsProvider`, `HealthCheckResult`, `SystemHealth`)
  - Database diagnostics with table and row counting
  - Sync diagnostics tracking last sync status
  - System health aggregation across components
  - Extensible architecture for custom diagnostics

#### Core Improvements

- **Enhanced SyncEngine**
  - Returns metrics from `syncAll()` and `syncTable()`
  - Integrated logger for structured logging
  - Metrics collection throughout sync process
  - Improved error tracking with per-record details
  - Better conflict resolution logging

- **Improved Retry Logic**
  - Enhanced `retry()` utility with logger integration
  - Configurable max delay for exponential backoff
  - Better logging of retry attempts
  - Support for custom retry strategies

### Changed

#### Breaking Changes

- **SyncEngine Constructor Changes**
  - Removed individual parameters: `batchSize`, `isSyncedColumn`, `operationIdColumn`
  - Now accepts `ReplicoreConfig` object for all configuration
  - Added `logger` and `metricsCollector` parameters
  - Migration: Use `ReplicoreConfig` and pass to `config` parameter

- **Method Return Types**
  - `syncAll()` now returns `SyncSessionMetrics` instead of `void`
  - `syncTable()` now returns `SyncMetrics` instead of `void`

#### Improvements

- pubspec.yaml: Flutter requirement bumped to ^3.0.0
- Added repository, documentation, and issue tracker links
- Comprehensive API documentation
- Production-ready error handling

#### Deprecated

- `SyncEngine.onLog` callback - Use `Logger` interface instead

### Documentation

- New `ENTERPRISE_README.md` with complete guide
- Enhanced inline documentation
- Configuration examples
- Error handling patterns
- Custom adapter implementation guide

## [0.1.0] - 2024-12-20 (Initial Release)

### Added

- Initial Replicore package release
- SyncEngine for bidirectional synchronization
- Multiple conflict resolution strategies
- SQLite/sqflite storage implementation
- Supabase remote adapter
- Automatic schema migrations
- Soft delete support
- Keyset pagination
- Status streaming
- Retry logic with exponential backoff

---

## Migration Guides

### v0.2.0 → v0.3.0

See `docs/V0.3_V0.4_RELEASE.md#migration-guide-v020--v030`.

Key change: Remove `onLog` callback, use `Logger` interface.

### v0.3.0 → v0.4.0

See `docs/V0.3_V0.4_RELEASE.md#migration-guide-v030--v040`.

New UI widgets available; no breaking changes.

---

## Planned Features (Roadmap)

- v0.5.0: Advanced conflict resolution, custom persistence layers
- v1.0.0: Stable public API, enterprise support SLA

### Added

#### New Enterprise Features

- **Comprehensive Logging Framework** (`Logger`, `LogLevel`, `LogEntry`)
  - Abstract logger interface for dependency injection
  - Console, NoOp, and Multi-logger implementations
  - Structured logging for APM integrations (Sentry, Datadog, etc.)
  - Log level filtering and context support

- **Metrics & Monitoring** (`SyncMetrics`, `SyncSessionMetrics`, `MetricsCollector`)
  - Per-table sync metrics with detailed statistics
  - Session-level aggregation and performance tracking
  - InMemory and NoOp metric collectors
  - JSON export for external analytics systems

- **Configuration Management** (`ReplicoreConfig`)
  - Factory methods for Production, Development, and Testing configs
  - Validation on creation with detailed error messages
  - Configurable retry strategies with exponential backoff
  - Batch size, timeout, and column name customization
  - Periodic sync interval configuration

- **Health Checks & Diagnostics** (`DiagnosticsProvider`, `HealthCheckResult`, `SystemHealth`)
  - Database diagnostics with table and row counting
  - Sync diagnostics tracking last sync status
  - System health aggregation across components
  - Extensible architecture for custom diagnostics

#### Core Improvements

- **Enhanced SyncEngine**
  - Returns metrics from `syncAll()` and `syncTable()`
  - Integrated logger for structured logging
  - Metrics collection throughout sync process
  - Improved error tracking with per-record details
  - Better conflict resolution logging

- **Improved Retry Logic**
  - Enhanced `retry()` utility with logger integration
  - Configurable max delay for exponential backoff
  - Better logging of retry attempts
  - Support for custom retry strategies

### Changed

#### Breaking Changes

- **SyncEngine Constructor Changes**
  - Removed individual parameters: `batchSize`, `isSyncedColumn`, `operationIdColumn`
  - Now accepts `ReplicoreConfig` object for all configuration
  - Added `logger` and `metricsCollector` parameters
  - Migration: Use `ReplicoreConfig` and pass to `config` parameter

- **Method Return Types**
  - `syncAll()` now returns `SyncSessionMetrics` instead of `void`
  - `syncTable()` now returns `SyncMetrics` instead of `void`

#### Improvements

- pubspec.yaml: Flutter requirement bumped to ^3.0.0
- Added repository, documentation, and issue tracker links
- Comprehensive API documentation
- Production-ready error handling

#### Deprecated

- `SyncEngine.onLog` callback - Use `Logger` interface instead

### Documentation

- New `ENTERPRISE_README.md` with complete guide
- Enhanced inline documentation
- Configuration examples
- Error handling patterns
- Custom adapter implementation guide

## [0.1.0] - 2024-12-20 (Initial Release)

### Added

- Initial Replicore package release
- SyncEngine for bidirectional synchronization
- Multiple conflict resolution strategies
- SQLite/sqflite storage implementation
- Supabase remote adapter
- Automatic schema migrations
- Soft delete support
- Keyset pagination
- Status streaming
- Retry logic with exponential backoff

---

## Migration Guide from 0.1.0 to 0.2.0

### 1. Update Imports

```dart
// No breaking imports, but new modules available:
import 'package:replicore/replicore.dart';
// Now includes: Logger, ReplicoreConfig, SyncMetrics, etc.
```

### 2. Update SyncEngine Initialization

**Before:**
```dart
final engine = SyncEngine(
  localStore: store,
  remoteAdapter: adapter,
  batchSize: 500,
);
```

**After:**
```dart
final engine = SyncEngine(
  localStore: store,
  remoteAdapter: adapter,
  config: ReplicoreConfig.production(),
  logger: ConsoleLogger(),
);
```

### 3. Handle Returned Metrics

**Before:**
```dart
await engine.syncAll();
```

**After:**
```dart
final metrics = await engine.syncAll();
print('Success: ${metrics.overallSuccess}');
```

### 4. Replace onLog Callback

**Before:**
```dart
SyncEngine(
  ...
  onLog: (msg) => print(msg),
)
```

**After:**
```dart
SyncEngine(
  ...
  logger: ConsoleLogger(minLevel: LogLevel.debug),
)
```

---

## Planned Features (Roadmap)

[0.5.0] - Ecosystem Expansion
- New LocalStores: Support for Drift (typed SQLite) and NoSQL options like Hive or Isar.
- New RemoteAdapters: Built-in adapters for Firebase Firestore, Appwrite, and generic GraphQL.
- Refactoring of custom persistence layers for easier integration.

[0.6.0] - Realtime & Background Sync
- Realtime Subscriptions: Listen to remote backend changes (e.g., Supabase/Firebase realtime events) to trigger immediate targeted pulls without polling.
- Background Sync: Integration with OS background execution (e.g., via workmanager) to sync data while the app is closed or in the background.

[1.0.0] - Enterprise Stable & Performance
- Isolate Offloading: Move heavy JSON parsing and data merging to background isolates to guarantee 60/120fps UI performance during massive initial syncs.
- Relational Integrity: Advanced support for syncing complex parent-child relationships and maintaining foreign key constraints across devices.
- Delta Updates: Partial row syncing (only uploading changed columns) to save bandwidth.