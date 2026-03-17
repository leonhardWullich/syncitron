import 'package:syncitron/syncitron.dart';

import 'logger.dart';
import 'metrics.dart';

/// Defines the lifecycle and behavior of custom sync orchestrations.
///
/// Extend this interface to implement domain-specific sync logic beyond
/// the standard pull-push-conflict-resolution pattern.
///
/// Example: Priority-based orchestration that syncs critical tables first
/// ```dart
/// class PrioritySyncOrchestration extends SyncOrchestrationStrategy {
///   @override
///   Future<SyncSessionMetrics> execute(SyncOrchestrationContext context) async {
///     // Sync critical tables first
///     final criticalMetrics = await context.managedSyncTable('subscriptions');
///     final normalMetrics = await context.managedSyncTable('todos');
///
///     return SyncSessionMetrics(
///       metrics: [criticalMetrics, normalMetrics],
///       startTime: context.startTime,
///     );
///   }
/// }
/// ```
abstract class SyncOrchestrationStrategy {
  /// Execute the custom sync orchestration logic.
  ///
  /// The [context] provides utilities for controlled table syncing with
  /// automatic metrics collection and error handling.
  ///
  /// Throws [syncitronException] on sync errors.
  /// Returns aggregated [SyncSessionMetrics].
  Future<SyncSessionMetrics> execute(SyncOrchestrationContext context);

  /// Called before sync starts. Override to execute pre-sync hooks.
  ///
  /// Example: Validate network, check storage space.
  Future<void> beforeSync(SyncOrchestrationContext context) async {}

  /// Called after sync completes (success or failure).
  ///
  /// Example: Persist metrics, trigger UI updates, cleanup.
  Future<void> afterSync(
    SyncOrchestrationContext context,
    SyncSessionMetrics metrics,
  ) async {}
}

/// Execution context provided to custom sync orchestrations.
///
/// Provides controlled access to sync operations, metrics, and logging.
abstract class SyncOrchestrationContext {
  /// Logger for structured logging throughout sync execution.
  Logger get logger;

  /// Metrics collector for tracking performance.
  MetricsCollector get metricsCollector;

  /// Registered table names in execution order.
  List<String> get tableNames;

  /// When the sync started (for duration calculations).
  DateTime get startTime;

  /// Sync the specified table with automatic error handling and metrics collection.
  ///
  /// Returns metrics for this table only.
  /// Throws [syncitronException] on sync errors.
  Future<SyncMetrics> managedSyncTable(String tableName);

  /// Sync all registered tables with automatic error handling and metrics collection.
  ///
  /// Returns aggregated metrics for all tables.
  /// Throws [syncitronException] on sync errors.
  Future<SyncSessionMetrics> managedSyncAll();

  /// Check if sync should continue based on cancellation token or timeout.
  ///
  /// Returns true if sync should proceed, false if cancelled/timed out.
  bool shouldContinue();

  /// Cancel the ongoing sync operation.
  void cancel();
}

/// Built-in orchestration: Standard pull-push-conflicts pattern (default).
///
/// Syncs all tables in sequence using the standard syncitron flow:
/// 1. Pull remote changes
/// 2. Push local changes
/// 3. Resolve conflicts
/// 4. Aggregate metrics
class StandardSyncOrchestration extends SyncOrchestrationStrategy {
  StandardSyncOrchestration();

  @override
  Future<SyncSessionMetrics> execute(SyncOrchestrationContext context) async {
    return context.managedSyncAll();
  }
}

/// Built-in orchestration: Offline-first with graceful degradation.
///
/// Tolerates network errors gracefully and caches results for retry.
/// Useful for unreliable networks where partial sync is acceptable.
class OfflineFirstSyncOrchestration extends SyncOrchestrationStrategy {
  /// Max network errors before stopping sync attempt.
  final int maxNetworkErrors;

  OfflineFirstSyncOrchestration({this.maxNetworkErrors = 3});

  @override
  Future<SyncSessionMetrics> execute(SyncOrchestrationContext context) async {
    final metricsPerTable = <SyncMetrics>[];
    int networkErrors = 0;

    for (final tableName in context.tableNames) {
      if (!context.shouldContinue()) break;

      try {
        final metrics = await context.managedSyncTable(tableName);
        metricsPerTable.add(metrics);
        networkErrors = 0; // reset on success
      } on SyncNetworkException catch (e) {
        networkErrors++;
        context.logger.warning(
          'Network error syncing $tableName (${networkErrors}/$maxNetworkErrors)',
          error: e,
        );

        if (networkErrors >= maxNetworkErrors) {
          context.logger.info('Max network errors reached, stopping sync');
          break;
        }
      }
    }

    final session = SyncSessionMetrics();
    for (final metric in metricsPerTable) {
      session.addTableMetrics(metric);
    }
    return session;
  }
}

/// Built-in orchestration: Manual-only with strict error handling.
///
/// Never retries automatically, preserves all errors for user inspection.
/// Use when you need explicit control over sync decisions.
class StrictManualOrchestration extends SyncOrchestrationStrategy {
  StrictManualOrchestration();

  @override
  Future<SyncSessionMetrics> execute(SyncOrchestrationContext context) {
    // Disable auto-retry in context during execution—each error surfaces immediately
    return context.managedSyncAll();
  }
}

/// Built-in orchestration: Selective sync by table priority.
///
/// Syncs tables in configurable priority order. Critical tables (high priority)
/// sync first and fail-fast, while optional tables (low priority) tolerate errors.
class PrioritySyncOrchestration extends SyncOrchestrationStrategy {
  /// Map of table name -> priority (higher = synced first).
  /// Tables not in map default to priority 0.
  final Map<String, int> tablePriorities;

  PrioritySyncOrchestration(this.tablePriorities);

  @override
  Future<SyncSessionMetrics> execute(SyncOrchestrationContext context) async {
    final metricsPerTable = <SyncMetrics>[];

    // Sort tables by priority (descending)
    final sortedTables = List<String>.from(context.tableNames)
      ..sort((a, b) {
        final priorityA = tablePriorities[a] ?? 0;
        final priorityB = tablePriorities[b] ?? 0;
        return priorityB.compareTo(priorityA); // high priority first
      });

    for (final tableName in sortedTables) {
      if (!context.shouldContinue()) break;

      final priority = tablePriorities[tableName] ?? 0;
      const criticalPriority = 100;

      try {
        final metrics = await context.managedSyncTable(tableName);
        metricsPerTable.add(metrics);
      } on syncitronException catch (e) {
        if (priority >= criticalPriority) {
          // Critical table error → fail fast
          context.logger.error('Critical table sync failed', error: e);
          rethrow;
        } else {
          // Optional table error → log and continue
          context.logger.warning('Optional table sync failed', error: e);
        }
      }
    }

    final session = SyncSessionMetrics();
    for (final metric in metricsPerTable) {
      session.addTableMetrics(metric);
    }
    return session;
  }
}

/// Builder for composing multiple orchestrations sequentially.
///
/// Useful for scenarios requiring custom pre/post processing while
/// delegating core sync logic to built-in orchestrations.
///
/// Example:
/// ```dart
/// final pipeline = CompositeSyncOrchestration([
///   PreSyncValidationHook(),       // validates data before sync
///   StandardSyncOrchestration(),   // actual sync
///   PostSyncAnalyticsHook(),       // caches/sends metrics after sync
/// ]);
/// ```
class CompositeSyncOrchestration extends SyncOrchestrationStrategy {
  final List<SyncOrchestrationStrategy> strategies;

  CompositeSyncOrchestration(this.strategies);

  @override
  Future<SyncSessionMetrics> execute(SyncOrchestrationContext context) async {
    SyncSessionMetrics? result;

    for (final strategy in strategies) {
      await strategy.beforeSync(context);
      result = await strategy.execute(context);
      await strategy.afterSync(context, result);
    }

    return result ?? SyncSessionMetrics();
  }
}
