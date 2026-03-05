/// Configuration for the Replicore sync engine.
///
/// All parameters have sensible enterprise defaults:
/// - Automatic retry with exponential backoff
/// - Comprehensive logging
/// - Metrics collection
/// - Graceful degradation on network errors
class ReplicoreConfig {
  /// Maximum number of records to fetch in a single batch.
  final int batchSize;

  /// Maximum number of concurrent sync operations.
  final int maxConcurrentSyncs;

  /// Timeout for individual remote operations.
  final Duration operationTimeout;

  /// Maximum number of retry attempts for failed operations.
  final int maxRetries;

  /// Initial delay before first retry (exponential backoff).
  final Duration initialRetryDelay;

  /// Maximum delay between retries (prevents runaway backoff).
  final Duration maxRetryDelay;

  /// Name of the local column tracking sync status.
  final String isSyncedColumn;

  /// Name of the local column tracking operation IDs (for idempotency).
  final String operationIdColumn;

  /// Enable automatic sync on app startup.
  final bool autoSyncOnStartup;

  /// Interval for periodic background syncs.
  final Duration? periodicSyncInterval;

  /// Enable detailed logging (production should disable this).
  final bool enableDetailedLogging;

  /// Enable metrics collection.
  final bool collectMetrics;

  /// Enable validation of configuration on creation.
  final bool validateOnCreation;

  const ReplicoreConfig({
    this.batchSize = 500,
    this.maxConcurrentSyncs = 1,
    this.operationTimeout = const Duration(seconds: 30),
    this.maxRetries = 3,
    this.initialRetryDelay = const Duration(milliseconds: 300),
    this.maxRetryDelay = const Duration(seconds: 30),
    this.isSyncedColumn = 'is_synced',
    this.operationIdColumn = 'op_id',
    this.autoSyncOnStartup = false,
    this.periodicSyncInterval,
    this.enableDetailedLogging = false,
    this.collectMetrics = true,
    this.validateOnCreation = true,
  });

  /// Create a production-grade configuration.
  factory ReplicoreConfig.production() {
    return ReplicoreConfig(
      batchSize: 1000,
      maxRetries: 5,
      initialRetryDelay: const Duration(seconds: 1),
      maxRetryDelay: const Duration(minutes: 5),
      enableDetailedLogging: false,
      collectMetrics: true,
      periodicSyncInterval: const Duration(minutes: 5),
    );
  }

  /// Create a development configuration with verbose logging.
  factory ReplicoreConfig.development() {
    return ReplicoreConfig(
      batchSize: 100,
      maxRetries: 2,
      enableDetailedLogging: true,
      collectMetrics: true,
      operationTimeout: const Duration(seconds: 60),
    );
  }

  /// Create a configuration for testing.
  factory ReplicoreConfig.testing() {
    return ReplicoreConfig(
      batchSize: 50,
      maxRetries: 1,
      enableDetailedLogging: false,
      collectMetrics: false,
      operationTimeout: const Duration(seconds: 10),
      validateOnCreation: false,
    );
  }

  /// Validate configuration parameters.
  void validate() {
    if (batchSize <= 0) {
      throw ArgumentError('batchSize must be > 0, got $batchSize');
    }
    if (maxConcurrentSyncs <= 0) {
      throw ArgumentError(
        'maxConcurrentSyncs must be > 0, got $maxConcurrentSyncs',
      );
    }
    if (maxRetries < 0) {
      throw ArgumentError('maxRetries must be >= 0, got $maxRetries');
    }
    if (operationTimeout.inMilliseconds <= 0) {
      throw ArgumentError('operationTimeout must be positive');
    }
    if (initialRetryDelay.inMilliseconds <= 0) {
      throw ArgumentError('initialRetryDelay must be positive');
    }
    if (maxRetryDelay < initialRetryDelay) {
      throw ArgumentError('maxRetryDelay must be >= initialRetryDelay');
    }
    if (isSyncedColumn.isEmpty) {
      throw ArgumentError('isSyncedColumn cannot be empty');
    }
    if (operationIdColumn.isEmpty) {
      throw ArgumentError('operationIdColumn cannot be empty');
    }
    if (periodicSyncInterval != null &&
        periodicSyncInterval!.inMilliseconds <= 0) {
      throw ArgumentError('periodicSyncInterval must be positive or null');
    }
  }

  /// Create a copy with some fields overridden.
  ReplicoreConfig copyWith({
    int? batchSize,
    int? maxConcurrentSyncs,
    Duration? operationTimeout,
    int? maxRetries,
    Duration? initialRetryDelay,
    Duration? maxRetryDelay,
    String? isSyncedColumn,
    String? operationIdColumn,
    bool? autoSyncOnStartup,
    Duration? periodicSyncInterval,
    bool? enableDetailedLogging,
    bool? collectMetrics,
    bool? validateOnCreation,
  }) {
    return ReplicoreConfig(
      batchSize: batchSize ?? this.batchSize,
      maxConcurrentSyncs: maxConcurrentSyncs ?? this.maxConcurrentSyncs,
      operationTimeout: operationTimeout ?? this.operationTimeout,
      maxRetries: maxRetries ?? this.maxRetries,
      initialRetryDelay: initialRetryDelay ?? this.initialRetryDelay,
      maxRetryDelay: maxRetryDelay ?? this.maxRetryDelay,
      isSyncedColumn: isSyncedColumn ?? this.isSyncedColumn,
      operationIdColumn: operationIdColumn ?? this.operationIdColumn,
      autoSyncOnStartup: autoSyncOnStartup ?? this.autoSyncOnStartup,
      periodicSyncInterval: periodicSyncInterval ?? this.periodicSyncInterval,
      enableDetailedLogging:
          enableDetailedLogging ?? this.enableDetailedLogging,
      collectMetrics: collectMetrics ?? this.collectMetrics,
      validateOnCreation: validateOnCreation ?? this.validateOnCreation,
    );
  }

  Map<String, dynamic> toJson() => {
    'batch_size': batchSize,
    'max_concurrent_syncs': maxConcurrentSyncs,
    'operation_timeout_ms': operationTimeout.inMilliseconds,
    'max_retries': maxRetries,
    'initial_retry_delay_ms': initialRetryDelay.inMilliseconds,
    'max_retry_delay_ms': maxRetryDelay.inMilliseconds,
    'is_synced_column': isSyncedColumn,
    'operation_id_column': operationIdColumn,
    'auto_sync_on_startup': autoSyncOnStartup,
    'periodic_sync_interval_ms': periodicSyncInterval?.inMilliseconds,
    'enable_detailed_logging': enableDetailedLogging,
    'collect_metrics': collectMetrics,
  };
}
