import 'package:flutter_test/flutter_test.dart';
import 'package:replicore/replicore.dart';

class InMemoryLocalStore implements LocalStore {
  final Map<String, List<Map<String, dynamic>>> tables = {};
  final List<String> ensuredTables = [];

  List<Map<String, dynamic>> table(String name) => tables.putIfAbsent(name, () => []);

  @override
  Future<void> ensureSyncColumns(String table, String updatedAtColumn, String deletedAtColumn) async {
    ensuredTables.add('$table:$updatedAtColumn:$deletedAtColumn');
  }

  @override
  Future<Map<String, dynamic>?> findById(String table, String pkColumn, id) async {
    for (final row in this.table(table)) {
      if (row[pkColumn] == id) return Map<String, dynamic>.from(row);
    }
    return null;
  }

  @override
  Future<List<Map<String, dynamic>>> findManyByIds(String table, String pkColumn, List ids) async {
    final idSet = ids.toSet();
    return this
        .table(table)
        .where((r) => idSet.contains(r[pkColumn]))
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  @override
  Future<void> markAsSynced(String table, String pkColumn, primaryKey) async {
    for (final row in this.table(table)) {
      if (row[pkColumn] == primaryKey) {
        row['is_synced'] = 1;
        row['op_id'] = null;
      }
    }
  }

  @override
  Future<List<Map<String, dynamic>>> queryDirty(String table) async {
    return this
        .table(table)
        .where((r) => r['is_synced'] == 0)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  @override
  Future<void> setOperationId(String table, String pkColumn, primaryKey, String operationId) async {
    for (final row in this.table(table)) {
      if (row[pkColumn] == primaryKey) {
        row['op_id'] = operationId;
      }
    }
  }

  @override
  Future<void> upsertBatch(String table, List<Map<String, dynamic>> records) async {
    for (final incoming in records) {
      final pk = incoming['id'] ?? incoming['uuid'];
      final index = this.table(table).indexWhere((r) => (r['id'] ?? r['uuid']) == pk);
      if (index == -1) {
        this.table(table).add(Map<String, dynamic>.from(incoming));
      } else {
        this.table(table)[index] = Map<String, dynamic>.from(incoming);
      }
    }
  }
}

class FakeRemoteAdapter implements RemoteAdapter {
  final Map<String, List<Map<String, dynamic>>> remoteTables = {};
  final List<PullRequest> pullRequests = [];
  final List<Map<String, dynamic>> upserts = [];
  final List<Map<String, dynamic>> deletes = [];
  final Set<String> failOnceOpIds = {};
  final Set<String> failedOpIds = {};

  @override
  Future<PullResult> pull(PullRequest request) async {
    pullRequests.add(request);
    final source = List<Map<String, dynamic>>.from(remoteTables[request.table] ?? []);
    source.sort((a, b) {
      final aTs = DateTime.parse(a[request.updatedAtColumn] as String);
      final bTs = DateTime.parse(b[request.updatedAtColumn] as String);
      final byTs = aTs.compareTo(bTs);
      if (byTs != 0) return byTs;
      return a[request.primaryKey].toString().compareTo(b[request.primaryKey].toString());
    });

    final filtered = source.where((row) {
      if (request.cursor == null) return true;
      final rowTs = DateTime.parse(row[request.updatedAtColumn] as String);
      final cTs = request.cursor!.updatedAt;
      if (rowTs.isAfter(cTs)) return true;
      if (!rowTs.isAtSameMomentAs(cTs)) return false;
      return row[request.primaryKey].toString().compareTo(request.cursor!.primaryKey.toString()) > 0;
    }).toList();

    final page = filtered.take(request.limit).toList();
    SyncCursor? next;
    if (page.length == request.limit) {
      final last = page.last;
      next = SyncCursor(
        updatedAt: DateTime.parse(last[request.updatedAtColumn] as String),
        primaryKey: last[request.primaryKey],
      );
    }

    return PullResult(records: page, nextCursor: next);
  }

  @override
  Future<void> softDelete({required String table, required String primaryKeyColumn, required id, required Map<String, dynamic> payload, String? idempotencyKey}) async {
    if (idempotencyKey != null && failOnceOpIds.contains(idempotencyKey) && !failedOpIds.contains(idempotencyKey)) {
      failedOpIds.add(idempotencyKey);
      throw Exception('planned failure');
    }
    deletes.add({'table': table, 'pk': primaryKeyColumn, 'id': id, 'payload': payload, 'op_id': idempotencyKey});
  }

  @override
  Future<void> upsert({required String table, required Map<String, dynamic> data, String? idempotencyKey}) async {
    if (idempotencyKey != null && failOnceOpIds.contains(idempotencyKey) && !failedOpIds.contains(idempotencyKey)) {
      failedOpIds.add(idempotencyKey);
      throw Exception('planned failure');
    }
    upserts.add({'table': table, 'data': data, 'op_id': idempotencyKey});
  }
}

TableConfig notesTable({SyncStrategy strategy = SyncStrategy.serverWins, ConflictResolver? resolver}) {
  return TableConfig(
    name: 'notes',
    primaryKey: 'uuid',
    updatedAtColumn: 'updated_at',
    deletedAtColumn: 'deleted_at',
    columns: const ['uuid', 'title', 'updated_at', 'deleted_at', 'is_synced'],
    strategy: strategy,
    customResolver: resolver,
  );
}

void main() {
  group('phase 1 correctness', () {
    test('init ensures columns for registered tables', () async {
      final local = InMemoryLocalStore();
      final remote = FakeRemoteAdapter();
      final engine = SyncEngine(localStore: local, remoteAdapter: remote)..registerTable(notesTable());
      await engine.init();
      expect(local.ensuredTables.single, contains('notes:updated_at:deleted_at'));
    });

    test('pull request contains primary key and updatedAt column', () async {
      final local = InMemoryLocalStore();
      final remote = FakeRemoteAdapter();
      remote.remoteTables['notes'] = [];
      final engine = SyncEngine(localStore: local, remoteAdapter: remote, batchSize: 2)..registerTable(notesTable());
      await engine.syncTable(notesTable());
      expect(remote.pullRequests.single.primaryKey, 'uuid');
      expect(remote.pullRequests.single.updatedAtColumn, 'updated_at');
    });

    test('composite cursor paginates same timestamp records without skipping', () async {
      final local = InMemoryLocalStore();
      final remote = FakeRemoteAdapter();
      remote.remoteTables['notes'] = [
        {'uuid': 'a', 'title': 'A', 'updated_at': '2024-01-01T00:00:00Z'},
        {'uuid': 'b', 'title': 'B', 'updated_at': '2024-01-01T00:00:00Z'},
        {'uuid': 'c', 'title': 'C', 'updated_at': '2024-01-02T00:00:00Z'},
      ];
      final engine = SyncEngine(localStore: local, remoteAdapter: remote, batchSize: 2)..registerTable(notesTable());
      await engine.syncTable(notesTable());
      final uuids = local.table('notes').map((e) => e['uuid']).toList();
      expect(uuids, containsAll(['a', 'b', 'c']));
      expect(remote.pullRequests.length, 2);
      expect(remote.pullRequests[1].cursor!.primaryKey, 'b');
    });

    test('serverWins overwrites dirty local', () async {
      final local = InMemoryLocalStore();
      local.table('notes').add({'uuid': '1', 'title': 'local', 'is_synced': 0, 'updated_at': '2024-01-01T00:00:00Z'});
      final remote = FakeRemoteAdapter()
        ..remoteTables['notes'] = [
          {'uuid': '1', 'title': 'remote', 'updated_at': '2024-01-02T00:00:00Z'},
        ];
      final engine = SyncEngine(localStore: local, remoteAdapter: remote)..registerTable(notesTable(strategy: SyncStrategy.serverWins));
      await engine.syncTable(notesTable(strategy: SyncStrategy.serverWins));
      expect(local.table('notes').single['title'], 'remote');
    });

    test('localWins keeps dirty local', () async {
      final local = InMemoryLocalStore();
      local.table('notes').add({'uuid': '1', 'title': 'local', 'is_synced': 0, 'updated_at': '2024-01-03T00:00:00Z'});
      final remote = FakeRemoteAdapter()
        ..remoteTables['notes'] = [
          {'uuid': '1', 'title': 'remote', 'updated_at': '2024-01-04T00:00:00Z'},
        ];
      final engine = SyncEngine(localStore: local, remoteAdapter: remote)..registerTable(notesTable(strategy: SyncStrategy.localWins));
      await engine.syncTable(notesTable(strategy: SyncStrategy.localWins));
      expect(local.table('notes').single['title'], 'local');
    });

    test('lastWriteWins chooses remote when remote newer', () async {
      final local = InMemoryLocalStore();
      local.table('notes').add({'uuid': '1', 'title': 'local', 'is_synced': 0, 'updated_at': '2024-01-01T00:00:00Z'});
      final remote = FakeRemoteAdapter()
        ..remoteTables['notes'] = [
          {'uuid': '1', 'title': 'remote', 'updated_at': '2024-01-02T00:00:00Z'},
        ];
      final engine = SyncEngine(localStore: local, remoteAdapter: remote)..registerTable(notesTable(strategy: SyncStrategy.lastWriteWins));
      await engine.syncTable(notesTable(strategy: SyncStrategy.lastWriteWins));
      expect(local.table('notes').single['title'], 'remote');
    });

    test('lastWriteWins keeps local when local newer', () async {
      final local = InMemoryLocalStore();
      local.table('notes').add({'uuid': '1', 'title': 'local', 'is_synced': 0, 'updated_at': '2024-01-05T00:00:00Z'});
      final remote = FakeRemoteAdapter()
        ..remoteTables['notes'] = [
          {'uuid': '1', 'title': 'remote', 'updated_at': '2024-01-04T00:00:00Z'},
        ];
      final engine = SyncEngine(localStore: local, remoteAdapter: remote)..registerTable(notesTable(strategy: SyncStrategy.lastWriteWins));
      await engine.syncTable(notesTable(strategy: SyncStrategy.lastWriteWins));
      expect(local.table('notes').single['title'], 'local');
    });

    test('custom resolver is used for dirty conflicts', () async {
      final local = InMemoryLocalStore();
      local.table('notes').add({'uuid': '1', 'title': 'local', 'is_synced': 0, 'updated_at': '2024-01-01T00:00:00Z'});
      final remote = FakeRemoteAdapter()
        ..remoteTables['notes'] = [
          {'uuid': '1', 'title': 'remote', 'updated_at': '2024-01-03T00:00:00Z'},
        ];
      final engine = SyncEngine(localStore: local, remoteAdapter: remote)
        ..registerTable(notesTable(strategy: SyncStrategy.custom, resolver: (l, r) async => {'uuid': l['uuid'], 'title': '${l['title']}+${r['title']}', 'updated_at': r['updated_at']}));
      await engine.syncTable(notesTable(strategy: SyncStrategy.custom, resolver: (l, r) async => {'uuid': l['uuid'], 'title': '${l['title']}+${r['title']}', 'updated_at': r['updated_at']}));
      expect(local.table('notes').single['title'], 'local+remote');
    });

    test('clean local row is updated even with localWins strategy', () async {
      final local = InMemoryLocalStore();
      local.table('notes').add({'uuid': '1', 'title': 'old', 'is_synced': 1, 'updated_at': '2024-01-01T00:00:00Z'});
      final remote = FakeRemoteAdapter()
        ..remoteTables['notes'] = [
          {'uuid': '1', 'title': 'new', 'updated_at': '2024-01-02T00:00:00Z'},
        ];
      final engine = SyncEngine(localStore: local, remoteAdapter: remote)..registerTable(notesTable(strategy: SyncStrategy.localWins));
      await engine.syncTable(notesTable(strategy: SyncStrategy.localWins));
      expect(local.table('notes').single['title'], 'new');
    });

    test('push uses configured primary key in soft delete', () async {
      final local = InMemoryLocalStore();
      local.table('notes').add({
        'uuid': 'pk-1',
        'title': 'x',
        'is_synced': 0,
        'deleted_at': '2024-02-01T00:00:00Z',
        'updated_at': '2024-02-01T00:00:00Z',
      });
      final remote = FakeRemoteAdapter();
      final engine = SyncEngine(localStore: local, remoteAdapter: remote)..registerTable(notesTable());
      await engine.syncTable(notesTable());
      expect(remote.deletes.single['pk'], 'uuid');
      expect(remote.deletes.single['id'], 'pk-1');
    });

    test('push generates operation id when missing', () async {
      final local = InMemoryLocalStore();
      local.table('notes').add({'uuid': '1', 'title': 'x', 'is_synced': 0, 'updated_at': '2024-01-01T00:00:00Z'});
      final remote = FakeRemoteAdapter();
      final engine = SyncEngine(localStore: local, remoteAdapter: remote)..registerTable(notesTable());
      await engine.syncTable(notesTable());
      expect(remote.upserts.single['op_id'], isNotNull);
    });

    test('push reuses pre-existing operation id', () async {
      final local = InMemoryLocalStore();
      local.table('notes').add({'uuid': '1', 'title': 'x', 'is_synced': 0, 'op_id': 'fixed-op', 'updated_at': '2024-01-01T00:00:00Z'});
      final remote = FakeRemoteAdapter();
      final engine = SyncEngine(localStore: local, remoteAdapter: remote)..registerTable(notesTable());
      await engine.syncTable(notesTable());
      expect(remote.upserts.single['op_id'], 'fixed-op');
    });

    test('operation id persists across retry in same sync cycle', () async {
      final local = InMemoryLocalStore();
      local.table('notes').add({'uuid': '1', 'title': 'x', 'is_synced': 0, 'updated_at': '2024-01-01T00:00:00Z'});
      final remote = FakeRemoteAdapter();
      final expectedOpPrefix = 'notes:1:2024-01-01T00:00:00Z:';
      remote.failOnceOpIds.add(expectedOpPrefix);
      final engine = SyncEngine(localStore: local, remoteAdapter: remote)..registerTable(notesTable());
      await engine.syncTable(notesTable());
      expect(remote.upserts.single['op_id'], expectedOpPrefix);
      expect(local.table('notes').single['is_synced'], 1);
    });

    test('markAsSynced clears op_id', () async {
      final local = InMemoryLocalStore();
      local.table('notes').add({'uuid': '1', 'title': 'x', 'is_synced': 0, 'op_id': 'op-1', 'updated_at': '2024-01-01T00:00:00Z'});
      final remote = FakeRemoteAdapter();
      final engine = SyncEngine(localStore: local, remoteAdapter: remote)..registerTable(notesTable());
      await engine.syncTable(notesTable());
      expect(local.table('notes').single['op_id'], isNull);
    });

    test('push sends upload without local sync metadata', () async {
      final local = InMemoryLocalStore();
      local.table('notes').add({'uuid': '1', 'title': 'x', 'is_synced': 0, 'op_id': 'op-1', 'updated_at': '2024-01-01T00:00:00Z'});
      final remote = FakeRemoteAdapter();
      final engine = SyncEngine(localStore: local, remoteAdapter: remote)..registerTable(notesTable());
      await engine.syncTable(notesTable());
      final data = remote.upserts.single['data'] as Map<String, dynamic>;
      expect(data.containsKey('is_synced'), isFalse);
      expect(data.containsKey('op_id'), isFalse);
    });

    test('pull inserts new records', () async {
      final local = InMemoryLocalStore();
      final remote = FakeRemoteAdapter()
        ..remoteTables['notes'] = [
          {'uuid': '1', 'title': 'A', 'updated_at': '2024-01-01T00:00:00Z'},
        ];
      final engine = SyncEngine(localStore: local, remoteAdapter: remote)..registerTable(notesTable());
      await engine.syncTable(notesTable());
      expect(local.table('notes').length, 1);
    });

    test('pull ignores records without primary key', () async {
      final local = InMemoryLocalStore();
      final remote = FakeRemoteAdapter()
        ..remoteTables['notes'] = [
          {'title': 'A', 'updated_at': '2024-01-01T00:00:00Z'},
        ];
      final engine = SyncEngine(localStore: local, remoteAdapter: remote)..registerTable(notesTable());
      await engine.syncTable(notesTable());
      expect(local.table('notes'), isEmpty);
    });

    test('syncAll processes registered tables', () async {
      final local = InMemoryLocalStore();
      final remote = FakeRemoteAdapter();
      final table1 = notesTable();
      final table2 = TableConfig(
        name: 'tags',
        primaryKey: 'id',
        columns: const ['id', 'updated_at', 'deleted_at', 'is_synced'],
      );
      remote.remoteTables['tags'] = [
        {'id': 1, 'updated_at': '2024-01-01T00:00:00Z'},
      ];
      final engine = SyncEngine(localStore: local, remoteAdapter: remote)
        ..registerTable(table1)
        ..registerTable(table2);
      await engine.syncAll();
      expect(local.table('tags').single['id'], 1);
    });

    test('status stream emits progress updates', () async {
      final local = InMemoryLocalStore();
      final remote = FakeRemoteAdapter();
      final engine = SyncEngine(localStore: local, remoteAdapter: remote)..registerTable(notesTable());
      final messages = <String>[];
      final sub = engine.statusStream.listen(messages.add);
      await engine.syncTable(notesTable());
      await sub.cancel();
      expect(messages.any((m) => m.contains('Syncing notes')), isTrue);
    });

    test('retry allows transient pull failure', () async {
      final local = InMemoryLocalStore();
      var called = 0;
      final remote = _FailingPullAdapter(() {
        called++;
        if (called == 1) throw Exception('boom');
        return PullResult(records: const []);
      });
      final engine = SyncEngine(localStore: local, remoteAdapter: remote)..registerTable(notesTable());
      await engine.syncTable(notesTable());
      expect(called, 2);
    });

    test('push handles null primary key rows gracefully', () async {
      final local = InMemoryLocalStore();
      local.table('notes').add({'title': 'x', 'is_synced': 0, 'updated_at': '2024-01-01T00:00:00Z'});
      final remote = FakeRemoteAdapter();
      final engine = SyncEngine(localStore: local, remoteAdapter: remote)..registerTable(notesTable());
      await engine.syncTable(notesTable());
      expect(remote.upserts, isEmpty);
    });

    test('soft delete includes timestamp fallback', () async {
      final local = InMemoryLocalStore();
      local.table('notes').add({'uuid': '1', 'title': 'x', 'is_synced': 0, 'deleted_at': '2024-01-01T00:00:00Z'});
      final remote = FakeRemoteAdapter();
      final engine = SyncEngine(localStore: local, remoteAdapter: remote)..registerTable(notesTable());
      await engine.syncTable(notesTable());
      final payload = remote.deletes.single['payload'] as Map<String, dynamic>;
      expect(payload['updated_at'], isNotNull);
    });

    test('operation id composition is deterministic', () async {
      final local = InMemoryLocalStore();
      local.table('notes').add({'uuid': '42', 'title': 'x', 'is_synced': 0, 'updated_at': '2024-01-01T00:00:00Z', 'deleted_at': null});
      final remote = FakeRemoteAdapter();
      final engine = SyncEngine(localStore: local, remoteAdapter: remote)..registerTable(notesTable());
      await engine.syncTable(notesTable());
      expect(remote.upserts.single['op_id'], 'notes:42:2024-01-01T00:00:00Z:');
    });

    test('custom resolver fallback to remote when not provided', () async {
      final local = InMemoryLocalStore();
      local.table('notes').add({'uuid': '1', 'title': 'local', 'is_synced': 0, 'updated_at': '2024-01-01T00:00:00Z'});
      final remote = FakeRemoteAdapter()
        ..remoteTables['notes'] = [
          {'uuid': '1', 'title': 'remote', 'updated_at': '2024-01-02T00:00:00Z'},
        ];
      final engine = SyncEngine(localStore: local, remoteAdapter: remote)..registerTable(notesTable(strategy: SyncStrategy.custom));
      await engine.syncTable(notesTable(strategy: SyncStrategy.custom));
      expect(local.table('notes').single['title'], 'remote');
    });
  });
}

class _FailingPullAdapter implements RemoteAdapter {
  final PullResult Function() onPull;
  _FailingPullAdapter(this.onPull);

  @override
  Future<PullResult> pull(PullRequest request) async => onPull();

  @override
  Future<void> softDelete({required String table, required String primaryKeyColumn, required id, required Map<String, dynamic> payload, String? idempotencyKey}) async {}

  @override
  Future<void> upsert({required String table, required Map<String, dynamic> data, String? idempotencyKey}) async {}
}
