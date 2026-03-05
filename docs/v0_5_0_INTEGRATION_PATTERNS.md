# v0.5.0 Integration Patterns - Complete Setup Guides

This guide provides complete, production-ready setup examples for every combination of LocalStore and RemoteAdapter in Replicore v0.5.0.

---

## 📦 All Combinations (4 × 4 Matrix)

```
LocalStores  × RemoteAdapters
Sqflite      × Supabase ✅ (existing)
Drift        × Supabase, Firebase, Appwrite, GraphQL
Hive         × Supabase, Firebase, Appwrite, GraphQL
Isar         × Supabase, Firebase, Appwrite, GraphQL
```

---

## 1️⃣ Sqflite LocalStore

### 1.1 Sqflite + Supabase (Recommended for most apps)

```dart
// pubspec.yaml
dependencies:
  flutter:
    sdk: flutter
  replicore: ^0.5.0
  supabase_flutter: ^2.12.0
  sqflite: ^2.4.2

// main.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:replicore/replicore.dart';
import 'package:sqflite/sqflite.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://your-project.supabase.co',
    anonKey: 'your-anon-key',
  );

  final database = await openDatabase(
    'app_db.sqlite',
    version: 1,
  );

  final store = SqfliteStore(database);
  final adapter = SupabaseAdapter(
    client: Supabase.instance.client,
    localStore: store,
  );

  final engine = SyncEngine(
    localStore: store,
    remoteAdapter: adapter,
    config: ReplicoreConfig.production(),
    logger: ConsoleLogger(),
  );

  await engine.init();

  // Register tables
  engine
    .registerTable(TableConfig(
      name: 'todos',
      columns: ['id', 'title', 'completed', 'updated_at', 'deleted_at'],
      strategy: SyncStrategy.lastWriteWins,
    ))
    .registerTable(TableConfig(
      name: 'projects',
      columns: ['id', 'name', 'owner_id', 'updated_at', 'deleted_at'],
      strategy: SyncStrategy.serverWins,
    ));

  runApp(MyApp(engine: engine));
}

class MyApp extends StatelessWidget {
  final SyncEngine engine;

  const MyApp({required this.engine});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: TodosScreen(engine: engine),
    );
  }
}
```

### 1.2 Sqflite + Firebase Firestore

```dart
// pubspec.yaml
dependencies:
  replicore: ^0.5.0
  sqflite: ^2.4.2
  cloud_firestore: ^4.13.0
  firebase_core: ^2.24.0

// main.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:replicore/replicore.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final database = await openDatabase('app_db.sqlite');

  final store = SqfliteStore(database);
  final adapter = FirebaseFirestoreAdapter(
    firestore: FirebaseFirestore.instance,
    localStore: store,
    enableOfflinePersistence: true,
  );

  final engine = SyncEngine(
    localStore: store,
    remoteAdapter: adapter,
    config: ReplicoreConfig.production(),
  );

  await engine.init();
  engine.registerTable(TableConfig(
    name: 'todos',
    columns: ['id', 'title', 'uid', 'completed', 'updated_at'],
    strategy: SyncStrategy.lastWriteWins,
  ));

  runApp(MyApp(engine: engine));
}
```

### 1.3 Sqflite + Appwrite

```dart
// pubspec.yaml
dependencies:
  replicore: ^0.5.0
  sqflite: ^2.4.2
  appwrite: ^11.0.0

// main.dart
import 'package:appwrite/appwrite.dart';
import 'package:replicore/replicore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final client = Client()
    .setEndpoint('https://appwrite.example.com/v1')
    .setProject('project-id')
    .setSelfSigned(status: true); // For self-signed certificates

  final database = Databases(client);

  final sqliteDb = await openDatabase('app_db.sqlite');
  final store = SqfliteStore(sqliteDb);

  final adapter = AppwriteAdapter(
    client: client,
    database: database,
    localStore: store,
    databaseId: 'default',
  );

  final engine = SyncEngine(
    localStore: store,
    remoteAdapter: adapter,
    config: ReplicoreConfig.production(),
  );

  await engine.init();
  engine.registerTable(TableConfig(
    name: 'todos',
    columns: ['id', 'title', 'completed', 'updated_at', 'deleted_at'],
    strategy: SyncStrategy.lastWriteWins,
  ));

  runApp(MyApp(engine: engine));
}
```

### 1.4 Sqflite + GraphQL

```dart
// pubspec.yaml
dependencies:
  replicore: ^0.5.0
  sqflite: ^2.4.2
  graphql: ^5.1.0

// main.dart
import 'package:graphql/client.dart';
import 'package:replicore/replicore.dart';

const graphqlEndpoint = 'https://api.example.com/graphql';

String buildPullQuery(PullRequest request) {
  return '''
    query GetRecords(\$limit: Int!, \$cursor: DateTime) {
      ${request.table}(
        limit: \$limit
        where: { updated_at: { _gte: \$cursor } }
        order_by: { updated_at: asc }
      ) {
        ${request.columns.join(', ')}
      }
    }
  ''';
}

String buildUpsertMutation(String table, Map<String, dynamic> data) {
  return '''
    mutation Upsert(\$data: ${table}Input!) {
      upsert_${table}(input: \$data) {
        id
      }
    }
  ''';
}

String buildSoftDeleteMutation(String table, String id) {
  return '''
    mutation SoftDelete(\$id: ID!) {
      soft_delete_${table}(id: \$id) {
        id
      }
    }
  ''';
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final graphqlClient = GraphQLClient(
    link: HttpLink(graphqlEndpoint),
    cache: GraphQLCache(),
  );

  final sqliteDb = await openDatabase('app_db.sqlite');
  final store = SqfliteStore(sqliteDb);

  final adapter = GraphQLAdapter(
    graphqlClient: graphqlClient,
    localStore: store,
    queryBuilder: buildPullQuery,
    mutationBuilder: buildUpsertMutation,
    softDeleteMutationBuilder: buildSoftDeleteMutation,
  );

  final engine = SyncEngine(
    localStore: store,
    remoteAdapter: adapter,
    config: ReplicoreConfig.production(),
  );

  await engine.init();
  runApp(MyApp(engine: engine));
}
```

---

## 2️⃣ Drift LocalStore

### 2.1 Drift + Supabase

```dart
// pubspec.yaml
dependencies:
  replicore: ^0.5.0
  drift: ^2.14.0
  sqlite3_flutter_libs: ^0.5.0
  supabase_flutter: ^2.12.0

dev_dependencies:
  drift_dev: ^2.14.0
  build_runner: ^2.4.0

// database.dart (Drift schema)
import 'package:drift/drift.dart';

part 'database.g.dart';

@DataClassName('ReplicoreMeta')
class ReplicoreMetas extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

@DataClassName('Todo')
class Todos extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(true))();
  TextColumn get opId => text().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [ReplicoreMetas, Todos])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  Future<ReplicoreMeta?> readMeta(String key) {
    return (select(replicoreMetas)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
  }

  Future<void> writeMeta(String key, String value) {
    return into(replicoreMetas).insert(
      ReplicoreMeta(key: key, value: value),
      onConflict: DoUpdate((_) => const {}),
    );
  }

  Future<void> deleteMeta(String key) {
    return (delete(replicoreMetas)..where((t) => t.key.equals(key))).go();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final file = File(p.join(
      await getDatabasesPath(),
      'app_database.db',
    ));

    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }

    return NativeDatabase(file);
  });
}

// main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://your-project.supabase.co',
    anonKey: 'your-anon-key',
  );

  final database = AppDatabase();

  final store = DriftStore(
    tables: {
      'todos': database.todos,
    },
    readMetadataQuery: (key) async {
      final meta = await database.readMeta(key);
      return meta?.value;
    },
    writeMetadataQuery: (key, value) => database.writeMeta(key, value),
    deleteMetadataQuery: (key) => database.deleteMeta(key),
  );

  final adapter = SupabaseAdapter(
    client: Supabase.instance.client,
    localStore: store,
  );

  final engine = SyncEngine(
    localStore: store,
    remoteAdapter: adapter,
    config: ReplicoreConfig.production(),
  );

  await engine.init();
  engine.registerTable(TableConfig(
    name: 'todos',
    columns: ['id', 'title', 'completed', 'updated_at', 'deleted_at'],
    strategy: SyncStrategy.lastWriteWins,
  ));

  runApp(MyApp(engine: engine));
}
```

### 2.2 Drift + Firebase Firestore

```dart
// (Reuse database.dart from above)

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final database = AppDatabase();

  final store = DriftStore(
    tables: {'todos': database.todos},
    readMetadataQuery: (key) async {
      final meta = await database.readMeta(key);
      return meta?.value;
    },
    writeMetadataQuery: database.writeMeta,
    deleteMetadataQuery: database.deleteMeta,
  );

  final adapter = FirebaseFirestoreAdapter(
    firestore: FirebaseFirestore.instance,
    localStore: store,
    enableOfflinePersistence: true,
  );

  final engine = SyncEngine(
    localStore: store,
    remoteAdapter: adapter,
    config: ReplicoreConfig.production(),
  );

  await engine.init();
  runApp(MyApp(engine: engine));
}
```

---

## 3️⃣ Hive LocalStore

### 3.1 Hive + Supabase (Lightweight)

```dart
// pubspec.yaml
dependencies:
  replicore: ^0.5.0
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  supabase_flutter: ^2.12.0

// main.dart
import 'package:hive_flutter/hive_flutter.dart';
import 'package:replicore/replicore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();
  Hive.registerAdapter(TodoAdapter());

  await Supabase.initialize(
    url: 'https://your-project.supabase.co',
    anonKey: 'your-anon-key',
  );

  // Open boxes
  final metaBox = await Hive.openBox('replicore_meta');
  final todosBox = await Hive.openBox<Map<String, dynamic>>('todos');

  final store = HiveStore(
    metadataBox: metaBox,
    dataBoxFactory: (table) async {
      if (table == 'todos') return todosBox;
      if (table == 'projects') {
        return await Hive.openBox<Map<String, dynamic>>(table);
      }
      throw Exception('Unknown table: $table');
    },
  );

  final adapter = SupabaseAdapter(
    client: Supabase.instance.client,
    localStore: store,
  );

  final engine = SyncEngine(
    localStore: store,
    remoteAdapter: adapter,
    config: ReplicoreConfig.production(),
  );

  await engine.init();
  engine.registerTable(TableConfig(
    name: 'todos',
    columns: ['id', 'title', 'completed', 'updated_at', 'deleted_at'],
    strategy: SyncStrategy.lastWriteWins,
  ));

  runApp(MyApp(engine: engine));
}

// Hive Adapter for type safety
class TodoAdapter extends TypeAdapter<Todo> {
  @override
  final int typeId = 0;

  @override
  Todo read(BinaryReader reader) {
    return Todo.fromJson(reader.read());
  }

  @override
  void write(BinaryWriter writer, Todo obj) {
    writer.write(obj.toJson());
  }
}

class Todo {
  final String id;
  final String title;
  final bool completed;
  final DateTime updatedAt;

  Todo({
    required this.id,
    required this.title,
    required this.completed,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'completed': completed,
    'updated_at': updatedAt.toIso8601String(),
  };

  factory Todo.fromJson(Map<String, dynamic> json) => Todo(
    id: json['id'],
    title: json['title'],
    completed: json['completed'] ?? false,
    updatedAt: DateTime.parse(json['updated_at']),
  );
}
```

### 3.2 Hive + Firebase Firestore

```dart
// pubspec.yaml
dependencies:
  replicore: ^0.5.0
  hive_flutter: ^1.1.0
  firebase_core: ^2.24.0
  cloud_firestore: ^4.13.0

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final metaBox = await Hive.openBox('replicore_meta');

  final store = HiveStore(
    metadataBox: metaBox,
    dataBoxFactory: (table) => Hive.openBox<Map<String, dynamic>>(table),
  );

  final adapter = FirebaseFirestoreAdapter(
    firestore: FirebaseFirestore.instance,
    localStore: store,
    enableOfflinePersistence: true,
  );

  final engine = SyncEngine(
    localStore: store,
    remoteAdapter: adapter,
    config: ReplicoreConfig.production(),
  );

  await engine.init();
  runApp(MyApp(engine: engine));
}
```

### 3.3 Hive + Appwrite

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();

  final metaBox = await Hive.openBox('replicore_meta');

  final client = Client()
    .setEndpoint('https://appwrite.example.com/v1')
    .setProject('project-id');

  final store = HiveStore(
    metadataBox: metaBox,
    dataBoxFactory: (table) => Hive.openBox<Map<String, dynamic>>(table),
  );

  final adapter = AppwriteAdapter(
    client: client,
    database: Databases(client),
    localStore: store,
    databaseId: 'default',
  );

  final engine = SyncEngine(
    localStore: store,
    remoteAdapter: adapter,
    config: ReplicoreConfig.production(),
  );

  await engine.init();
  runApp(MyApp(engine: engine));
}
```

### 3.4 Hive + GraphQL

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();

  final metaBox = await Hive.openBox('replicore_meta');
  
  final graphqlClient = GraphQLClient(
    link: HttpLink('https://api.example.com/graphql'),
    cache: GraphQLCache(),
  );

  final store = HiveStore(
    metadataBox: metaBox,
    dataBoxFactory: (table) => Hive.openBox<Map<String, dynamic>>(table),
  );

  final adapter = GraphQLAdapter(
    graphqlClient: graphqlClient,
    localStore: store,
    queryBuilder: (req) => 'query { ${req.table} }',
    mutationBuilder: (table, data) => 'mutation { upsert_$table }',
    softDeleteMutationBuilder: (table, id) => 'mutation { delete_$table }',
  );

  final engine = SyncEngine(
    localStore: store,
    remoteAdapter: adapter,
    config: ReplicoreConfig.production(),
  );

  await engine.init();
  runApp(MyApp(engine: engine));
}
```

---

## 4️⃣ Isar LocalStore (High-Performance)

### 4.1 Isar + Firebase Firestore (High-Performance)

```dart
// pubspec.yaml
dependencies:
  replicore: ^0.5.0
  isar: ^3.1.0
  isar_flutter_libs: ^3.1.0
  firebase_core: ^2.24.0
  cloud_firestore: ^4.13.0

// models.dart (Isar schemas)
import 'package:isar/isar.dart';

part 'models.g.dart';

@collection
class ReplicoreMeta {
  Id? id;
  @Index(unique: true)
  late String key;
  late String value;
}

@collection
class Todo {
  Id? id;
  @Index()
  late String remoteId;
  late String title;
  late bool completed;
  late DateTime updatedAt;
  DateTime? deletedAt;
  late bool isSynced;
  String? operationId;
}

// main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open(
    [ReplicoreMetaSchema, TodoSchema],
    directory: dir.path,
  );

  final store = IsarStore(
    isar: isar,
    collectionFactory: (table) {
      if (table == '_replicore_meta') {
        return isar.replicoreMetas;
      } else if (table == 'todos') {
        return isar.todos;
      }
      throw Exception('Unknown table: $table');
    },
  );

  final adapter = FirebaseFirestoreAdapter(
    firestore: FirebaseFirestore.instance,
    localStore: store,
    enableOfflinePersistence: true,
  );

  final engine = SyncEngine(
    localStore: store,
    remoteAdapter: adapter,
    config: ReplicoreConfig.production(),
  );

  await engine.init();
  engine.registerTable(TableConfig(
    name: 'todos',
    columns: ['id', 'title', 'completed', 'updated_at', 'deleted_at'],
    strategy: SyncStrategy.lastWriteWins,
  ));

  runApp(MyApp(engine: engine));
}
```

### 4.2 Isar + Appwrite (Distributed Systems)

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open(
    [ReplicoreMetaSchema, TodoSchema],
    directory: dir.path,
  );

  final client = Client()
    .setEndpoint('https://appwrite.example.com/v1')
    .setProject('project-id');

  final store = IsarStore(
    isar: isar,
    collectionFactory: (table) => isar.collection<Todo>(),
  );

  final adapter = AppwriteAdapter(
    client: client,
    database: Databases(client),
    localStore: store,
    databaseId: 'production',
  );

  final engine = SyncEngine(
    localStore: store,
    remoteAdapter: adapter,
    config: ReplicoreConfig.production(),
  );

  await engine.init();
  runApp(MyApp(engine: engine));
}
```

### 4.3 Isar + GraphQL (Type-Safe Full-Stack)

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open(
    [ReplicoreMetaSchema, TodoSchema],
    directory: dir.path,
  );

  final graphqlClient = GraphQLClient(
    link: HttpLink('https://api.example.com/graphql'),
    cache: GraphQLCache(),
  );

  final store = IsarStore(
    isar: isar,
    collectionFactory: (table) {
      if (table == '_replicore_meta') return isar.replicoreMetas;
      if (table == 'todos') return isar.todos;
      throw Exception('Unknown table');
    },
  );

  final adapter = GraphQLAdapter(
    graphqlClient: graphqlClient,
    localStore: store,
    queryBuilder: (req) => _buildPullQuery(req),
    mutationBuilder: (table, data) => _buildUpsertMutation(table, data),
    softDeleteMutationBuilder: (table, id) => _buildDeleteMutation(table, id),
  );

  final engine = SyncEngine(
    localStore: store,
    remoteAdapter: adapter,
    config: ReplicoreConfig.production(),
  );

  await engine.init();
  runApp(MyApp(engine: engine));
}

String _buildPullQuery(PullRequest request) => '''
  query GetTodos(\$limit: Int!) {
    todos(limit: \$limit, order_by: {updated_at: asc}) {
      ${request.columns.join(', ')}
    }
  }
''';

String _buildUpsertMutation(String table, Map<String, dynamic> data) => '''
  mutation Upsert(\$data: ${table}Input!) {
    upsert_$table(input: \$data) { id }
  }
''';

String _buildDeleteMutation(String table, String id) => '''
  mutation SoftDelete(\$id: ID!) {
    soft_delete_$table(id: \$id) { id }
  }
''';
```

---

## Testing Your Setup

```dart
// test/sync_engine_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:replicore/replicore.dart';

void main() {
  group('SyncEngine Configuration', () {
    late SyncEngine engine;
    late LocalStore store;
    late RemoteAdapter adapter;

    setUp(() async {
      // Initialize your chosen LocalStore/RemoteAdapter
      store = HiveStore(
        metadataBox: metadataBox,
        dataBoxFactory: dataBoxFactory,
      );
      adapter = SupabaseAdapter(
        client: supabaseClient,
        localStore: store,
      );
      engine = SyncEngine(
        localStore: store,
        remoteAdapter: adapter,
        config: ReplicoreConfig.testing(),
      );
    });

    test('LocalStore cursor persistence', () async {
      final cursor = SyncCursor(
        updatedAt: DateTime.now(),
        primaryKey: 'test-123',
      );

      await store.writeCursor('todos', cursor);
      final read = await store.readCursor('todos');

      expect(read?.primaryKey, equals('test-123'));
    });

    test('RemoteAdapter pull operation', () async {
      final result = await adapter.pull(PullRequest(
        table: 'todos',
        columns: ['id', 'title'],
        primaryKey: 'id',
        updatedAtColumn: 'updated_at',
        limit: 10,
      ));

      expect(result.records, isA<List>());
    });
  });
}
```

---

## Production Deployment Checklist

- [ ] Choose LocalStore based on data scale and query complexity
- [ ] Choose RemoteAdapter based on backend infrastructure
- [ ] Set up appropriate error handling and logging
- [ ] Configure ReplicoreConfig.production() settings
- [ ] Test sync with network interruptions
- [ ] Test conflict resolution with your strategies
- [ ] Set up monitoring/analytics integration
- [ ] Configure appropriate timeouts
- [ ] Test data migration paths
- [ ] Load test with expected data volumes
- [ ] Document your specific adapter implementations
- [ ] Train team on chosen patterns

Happy syncing! 🎉
