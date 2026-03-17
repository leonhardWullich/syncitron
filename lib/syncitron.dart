/// Enterprise-grade local-first synchronization framework for Flutter.
///
/// syncitron provides a robust, battle-tested foundation for building
/// offline-capable Flutter applications with automatic data synchronization,
/// conflict resolution, and comprehensive monitoring.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:syncitron/syncitron.dart';
///
/// // 1. Create a config (production defaults recommended)
/// final config = syncitronConfig.production();
///
/// // 2. Create engine with your database and remote adapter
/// final engine = SyncEngine(
///   localStore: SqfliteStore(database, conflictAlgorithm: ConflictAlgorithm.replace),
///   remoteAdapter: SupabaseAdapter(
///     client: supabaseClient,
///     localStore: sqfliteStore,
///     postgresChangeEventAll: PostgresChangeEvent.all,
///   ),
///   config: config,
///   logger: ConsoleLogger(),
/// );
///
/// // 3. Register tables with conflict resolution strategies
/// engine
///   .registerTable(TableConfig(
///     name: 'todos',
///     columns: ['id', 'title', 'completed', 'updated_at', 'deleted_at'],
///     strategy: SyncStrategy.lastWriteWins,
///   ))
///   .registerTable(TableConfig(
///     name: 'projects',
///     columns: ['id', 'name', 'updated_at', 'deleted_at'],
///     strategy: SyncStrategy.serverWins,
///   ));
///
/// // 4. Perform synchronization
/// await engine.init();
/// final metrics = await engine.syncAll();
/// print(metrics);
/// ```
///
/// ## Features
///
/// - **Offline-First**: Works seamlessly offline, syncs when connected
/// - **Flexible Sync Strategies**: ServerWins, LocalWins, LastWriteWins, Custom
/// - **Automatic Retry**: Exponential backoff with configurable limits
/// - **Comprehensive Logging**: Structured logging for debugging and analytics
/// - **Metrics & Monitoring**: Track sync performance and data flow
/// - **Health Checks**: Built-in diagnostics for system state
/// - **Dependency Injection**: Fully composable with your architecture
/// - **Enterprise-Ready**: Configuration management, error handling, and recovery
/// - **Multi-Engine Management**: Coordinate multiple sync contexts
///
/// See the documentation for more details on advanced features:
/// https://github.com/leonhardWullich/syncitron

export 'src/core/config.dart';
export 'src/core/diagnostics.dart';
export 'src/core/exceptions.dart';
export 'src/core/logger.dart';
export 'src/core/metrics.dart';
export 'src/core/models.dart';
export 'src/core/sync_engine.dart';
export 'src/core/sync_strategy.dart';
export 'src/core/sync_orchestration_strategy.dart';
export 'src/core/table_config.dart';
export 'src/core/realtime_subscription.dart';
export 'src/core/sync_manager.dart';

export 'src/adapters/remote_adapter.dart';
export 'src/adapters/supabase_adapter.dart';
export 'src/adapters/supabase_realtime.dart';
export 'src/adapters/firebase_firestore_adapter.dart';
export 'src/adapters/firebase_firestore_realtime.dart';
export 'src/adapters/appwrite_adapter.dart';
export 'src/adapters/appwrite_realtime.dart';
export 'src/adapters/graphql_adapter.dart';
export 'src/adapters/graphql_realtime.dart';

export 'src/storage/local_store.dart';
export 'src/storage/sqflite_store.dart';
export 'src/storage/drift_store.dart';
export 'src/storage/hive_store.dart';
export 'src/storage/isar_store.dart';

export 'src/ui/sync_widgets.dart';

export 'src/utils/retry.dart';
