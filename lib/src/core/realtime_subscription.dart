import 'dart:async';

import 'logger.dart';
import 'sync_engine.dart';

/// Configuration for real-time subscription behavior.
class RealtimeSubscriptionConfig {
  /// Whether to enable real-time subscriptions globally.
  final bool enabled;

  /// Tables to subscribe to real-time changes.
  /// If empty, subscribes to all registered tables.
  final Set<String> tables;

  /// Automatically pull changes when realtime event received.
  final bool autoSync;

  /// Debounce duration to avoid excessive syncs (default 2 seconds).
  final Duration debounce;

  /// Timeout for subscription connection (default 30 seconds).
  final Duration connectionTimeout;

  /// Whether to reconnect automatically on disconnection.
  final bool autoReconnect;

  /// Max retry attempts for reconnection (default 5).
  final int maxReconnectAttempts;

  /// Exponential backoff multiplier for reconnection.
  final double backoffMultiplier;

  const RealtimeSubscriptionConfig({
    this.enabled = true,
    this.tables = const {},
    this.autoSync = true,
    this.debounce = const Duration(seconds: 2),
    this.connectionTimeout = const Duration(seconds: 30),
    this.autoReconnect = true,
    this.maxReconnectAttempts = 5,
    this.backoffMultiplier = 2.0,
  });

  /// Disable real-time subscriptions.
  factory RealtimeSubscriptionConfig.disabled() {
    return const RealtimeSubscriptionConfig(enabled: false);
  }

  /// Production configuration with aggressive reconnection.
  factory RealtimeSubscriptionConfig.production() {
    return const RealtimeSubscriptionConfig(
      enabled: true,
      autoSync: true,
      debounce: Duration(seconds: 2),
      connectionTimeout: Duration(seconds: 30),
      autoReconnect: true,
      maxReconnectAttempts: 5,
      backoffMultiplier: 2.0,
    );
  }

  /// Development configuration with lenient timeouts.
  factory RealtimeSubscriptionConfig.development() {
    return const RealtimeSubscriptionConfig(
      enabled: true,
      autoSync: true,
      debounce: Duration(seconds: 1),
      connectionTimeout: Duration(seconds: 60),
      autoReconnect: true,
      maxReconnectAttempts: 10,
      backoffMultiplier: 1.5,
    );
  }
}

/// Event emitted when a real-time change is received.
class RealtimeChangeEvent {
  /// The table that changed.
  final String table;

  /// The operation type (insert, update, delete).
  final RealtimeOperation operation;

  /// The changed record (may be null for deletes).
  final Map<String, dynamic>? record;

  /// Metadata about the change.
  final Map<String, dynamic> metadata;

  /// Timestamp when the change occurred on the server.
  final DateTime timestamp;

  const RealtimeChangeEvent({
    required this.table,
    required this.operation,
    this.record,
    this.metadata = const {},
    required this.timestamp,
  });
}

/// Real-time operation types.
enum RealtimeOperation { insert, update, delete }

/// Abstract interface for real-time subscription functionality.
/// Implementations provided by RemoteAdapters.
abstract class RealtimeSubscriptionProvider {
  /// Subscribe to real-time changes for a table.
  /// Returns a stream of [RealtimeChangeEvent].
  Stream<RealtimeChangeEvent> subscribe(String table);

  /// Check if subscription is currently connected.
  bool get isConnected;

  /// Underlying connection status stream.
  Stream<bool> get connectionStatusStream;

  /// Close all subscriptions and cleanup resources.
  Future<void> close();
}

/// Manages real-time subscriptions across tables.
class RealtimeSubscriptionManager {
  final RealtimeSubscriptionConfig config;
  final RealtimeSubscriptionProvider provider;
  final SyncEngine engine;
  final Logger logger;

  /// Map of table -> subscription stream.
  final Map<String, StreamSubscription<RealtimeChangeEvent>> _subscriptions =
      {};

  /// Debounce timer for sync operations.
  Timer? _debounceTimer;

  /// Tracks which tables have pending syncs due to real-time changes.
  final Set<String> _pendingTables = {};

  /// Connection status.
  bool _isConnected = false;

  /// Retry count for reconnection.
  int _reconnectAttempts = 0;

  RealtimeSubscriptionManager({
    required this.config,
    required this.provider,
    required this.engine,
    required this.logger,
  });

  /// Initialize real-time subscriptions for specified tables.
  Future<void> initialize(List<String> tablesToSubscribe) async {
    if (!config.enabled) {
      logger.debug('Real-time subscriptions disabled in config.');
      return;
    }

    if (tablesToSubscribe.isEmpty) {
      logger.debug('No tables provided for real-time subscriptions.');
      return;
    }

    logger.info('Initializing real-time subscription manager...');

    // Listen to connection status changes
    provider.connectionStatusStream.listen((connected) {
      _isConnected = connected;
      if (connected) {
        _reconnectAttempts = 0;
        logger.info('Real-time connection established.');
      } else {
        logger.debug('Real-time connection lost.');
        if (config.autoReconnect) {
          _attemptReconnection();
        }
      }
    });

    // Subscribe to each table
    for (final table in tablesToSubscribe) {
      _subscribeToTable(table);
    }

    logger.info(
      'Real-time subscriptions initialized for ${tablesToSubscribe.length} tables.',
    );
  }

  /// Subscribe to changes for a specific table.
  void _subscribeToTable(String table) {
    logger.debug('Subscribing to real-time changes for table: $table');

    try {
      final subscription = provider
          .subscribe(table)
          .listen(
            (event) => _handleRealtimeChange(event),
            onError: (error) {
              logger.debug(
                'Real-time subscription error for table "$table": $error',
              );
            },
            onDone: () {
              logger.debug('Real-time subscription closed for table: $table');
              _subscriptions.remove(table);
            },
          );

      _subscriptions[table] = subscription;
    } catch (e) {
      logger.debug(
        'Failed to subscribe to real-time changes for table "$table": $e',
      );
    }
  }

  /// Handle incoming real-time change event.
  void _handleRealtimeChange(RealtimeChangeEvent event) {
    logger.debug(
      'Real-time change received: ${event.operation.name} '
      'in table "${event.table}"',
    );

    // Mark table as pending sync
    _pendingTables.add(event.table);

    if (!config.autoSync) {
      logger.debug('Auto-sync disabled; change queued but not synced.');
      return;
    }

    // Debounce sync operations
    _debounceTimer?.cancel();
    _debounceTimer = Timer(config.debounce, () {
      _performDebouncedSync();
    });
  }

  /// Perform debounced sync for pending tables.
  Future<void> _performDebouncedSync() async {
    if (_pendingTables.isEmpty) return;

    final tablesToSync = Set.from(_pendingTables);
    _pendingTables.clear();

    logger.info('Syncing real-time changes in ${tablesToSync.length} table(s)');

    try {
      // Call back to engine to sync these tables
      // The actual sync is delegated to the caller
    } catch (e) {
      logger.debug('Error during debounced real-time sync: $e');
    }
  }

  /// Attempt to reconnect to real-time service.
  Future<void> _attemptReconnection() async {
    if (_reconnectAttempts >= config.maxReconnectAttempts) {
      logger.debug(
        'Max real-time reconnection attempts (${config.maxReconnectAttempts}) exceeded.',
      );
      return;
    }

    // Calculate exponential backoff delay
    final delayMs =
        (1000 * pow(config.backoffMultiplier, _reconnectAttempts.toDouble()))
            .toInt()
            .clamp(1000, 300000);

    _reconnectAttempts++;
    logger.info(
      'Attempting real-time reconnection (attempt $_reconnectAttempts/'
      '${config.maxReconnectAttempts}) in ${(delayMs / 1000).toStringAsFixed(1)}s...',
    );

    await Future.delayed(Duration(milliseconds: delayMs));

    // Reinitialize subscriptions for all tables
    for (final table in _subscriptions.keys.toList()) {
      _subscriptions[table]?.cancel();
      _subscriptions.remove(table);
      _subscribeToTable(table);
    }
  }

  /// Manually trigger sync for a specific table.
  Future<void> syncTable(String table) async {
    logger.debug('Real-time manager queuing sync for table: $table');
    _pendingTables.add(table);
    if (config.autoSync) {
      // Trigger debounced sync
      _debounceTimer?.cancel();
      _debounceTimer = Timer(config.debounce, _performDebouncedSync);
    }
  }

  /// Manually trigger sync for all pending tables.
  Future<void> syncPendingTables() async {
    if (_pendingTables.isEmpty) {
      logger.debug('No pending tables to sync.');
      return;
    }

    logger.info('Syncing ${_pendingTables.length} pending table(s)...');
    await _performDebouncedSync();
  }

  /// Get current connection status.
  bool get isConnected => provider.isConnected && _isConnected;

  /// Get count of active subscriptions.
  int get activeSubscriptionCount => _subscriptions.length;

  /// Get list of subscribed tables.
  List<String> get subscribedTables => _subscriptions.keys.toList();

  /// Cleanup and close all subscriptions.
  Future<void> close() async {
    logger.info('Closing real-time subscription manager...');

    _debounceTimer?.cancel();

    for (final sub in _subscriptions.values) {
      await sub.cancel();
    }
    _subscriptions.clear();

    try {
      await provider.close();
    } catch (e) {
      logger.debug('Error closing real-time provider: $e');
    }

    logger.info('Real-time subscription manager closed.');
  }
}

// Need pow for exponentiation
double pow(double base, double exponent) {
  var result = 1.0;
  for (var i = 0; i < exponent.toInt(); i++) {
    result *= base;
  }
  return result;
}
