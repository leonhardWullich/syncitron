import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:replicore/replicore.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // SQLite Setup
  final dbPath = await getDatabasesPath();
  final path = join(dbPath, 'replicore_demo.db');
  final db = await openDatabase(
    path,
    version: 1,
    onCreate: (db, version) async {
      await db.execute('''
      CREATE TABLE todos(
        id TEXT PRIMARY KEY,
        title TEXT,
        updated_at TEXT,
        is_synced INTEGER
      )
    ''');
    },
  );

  // Supabase Setup
  await Supabase.initialize(
    url: 'YOUR_SUPABASE_URL',
    anonKey: 'YOUR_SUPABASE_ANON_KEY',
  );

  final engine = SyncEngine(
    localStore: SqfliteStore(db),
    remoteAdapter: SupabaseAdapter(
        client: Supabase.instance.client,
        prefs: await SharedPreferences.getInstance(),
        updatedAtColumn: 'updated_at'),
  );

  engine.registerTable(
    TableConfig(
      name: 'todos',
      columns: ['id', 'title', 'updated_at', 'is_synced'],
    ),
  );

  // Run sync
  await engine.syncAll();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: Center(child: Text('Replicore v0.1 Demo'))),
    );
  }
}
