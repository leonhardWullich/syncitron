import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:syncitron/syncitron.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync/sync_service.dart';
import 'ui/login_screen.dart';
import 'ui/todo_list_screen.dart';

// ── Global app state (accessed by screens via appDb, appEngine, etc.) ────────
late Database appDb;
late SyncEngine appEngine;
late Logger appLogger;
late MetricsCollector appMetricsCollector;
RealtimeSubscriptionManager? appRealtimeManager;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── 1. Initialize Supabase ─────────────────────────────────────────────────
  // IMPORTANT: Run the setup in example/supabase_setup.md to create the tables
  // or provide the required credentials below.

  await Supabase.initialize(
    url: 'YOUR_SUPABASE_URL',
    anonKey: 'YOUR_SUPABASE_ANON_KEY',
  );

  // ── 2. Open Local SQLite Database ──────────────────────────────────────────
  appDb = await openDatabase(
    join(await getDatabasesPath(), 'syncitron_example.db'),
    version: 1,
    onCreate: (db, _) async {
      // Minimal schema — syncitron adds sync columns automatically via
      // ensureSyncColumns() during engine.init().
      await db.execute('''
        CREATE TABLE todos (
          id       TEXT PRIMARY KEY NOT NULL,
          user_id  TEXT NOT NULL,
          title    TEXT NOT NULL,
          is_done  INTEGER NOT NULL DEFAULT 0
        )
      ''');
    },
  );

  // ── 3. Initialize syncitron ────────────────────────────────────────────────

  // Create local store (handles both data and sync cursors)
  final localStore =
      SqfliteStore(appDb, conflictAlgorithm: ConflictAlgorithm.replace);

  // Create remote adapter for Supabase
  final remoteAdapter = SupabaseAdapter(
    client: Supabase.instance.client,
    localStore: localStore,
    postgresChangeEventAll: PostgresChangeEvent.all,
    isAuthException: (e) => e is AuthException,
  );

  // Create logger (console output for development)
  appLogger = ConsoleLogger(minLevel: LogLevel.info);

  // Create metrics collector (in-memory for this example)
  appMetricsCollector = InMemoryMetricsCollector();

  // Create SyncEngine with production configuration
  appEngine = SyncEngine(
    localStore: localStore,
    remoteAdapter: remoteAdapter,
    config: syncitronConfig.production(),
    logger: appLogger,
    metricsCollector: appMetricsCollector,
  )..registerTable(
      const TableConfig(
        name: 'todos',
        primaryKey: 'id',
        columns: [
          'id',
          'user_id',
          'title',
          'is_done',
          'updated_at',
          'deleted_at',
        ],
        // Last write (most recent timestamp) wins on conflict
        strategy: SyncStrategy.lastWriteWins,
      ),
    );

  // Initialize engine (idempotent — safe to call on every app start)
  try {
    await appEngine.init();
  } catch (e) {
    appLogger.error('Failed to initialize syncitron engine', error: e);
    // Continue anyway — the app can still function offline
  }

  // ── 4. Setup Real-Time Subscriptions ───────────────────────────────────────

  // Get the realtime provider from the adapter
  final realtimeProvider = remoteAdapter.getRealtimeProvider();

  if (realtimeProvider != null) {
    appRealtimeManager = RealtimeSubscriptionManager(
      config: RealtimeSubscriptionConfig.production(),
      provider: realtimeProvider,
      engine: appEngine,
      logger: appLogger,
    );

    try {
      // Subscribe to real-time changes on the 'todos' table
      await appRealtimeManager!.initialize(['todos']);
      appLogger.info('Real-time subscriptions active for todos table.');
    } catch (e) {
      appLogger.error('Failed to initialize real-time subscriptions', error: e);
      // Continue without real-time — periodic sync will still work
    }
  } else {
    appLogger
        .info('No real-time provider available — using periodic sync only.');
  }

  // ── 5. Setup Background Sync ───────────────────────────────────────────────
  SyncService.instance.start(engine: appEngine);

  runApp(TodoApp(
    db: appDb,
    engine: appEngine,
    logger: appLogger,
    metricsCollector: appMetricsCollector,
  ));
}

// ── Root Widget ────────────────────────────────────────────────────────────────

class TodoApp extends StatelessWidget {
  final Database db;
  final SyncEngine engine;
  final Logger logger;
  final MetricsCollector metricsCollector;

  const TodoApp({
    super.key,
    required this.db,
    required this.engine,
    required this.logger,
    required this.metricsCollector,
  });

  @override
  Widget build(BuildContext context) {
    final currentUser = Supabase.instance.client.auth.currentUser;

    return MaterialApp(
      title: 'syncitron Todo Example',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: currentUser != null
          ? TodoListScreen(
              db: db,
              engine: engine,
              logger: logger,
              metricsCollector: metricsCollector,
            )
          : const LoginScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
