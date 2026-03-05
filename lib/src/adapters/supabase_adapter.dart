import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/exceptions.dart';
import '../core/models.dart';
import '../core/realtime_subscription.dart';
import '../storage/local_store.dart';
import 'remote_adapter.dart';
import 'supabase_realtime.dart';

/// [RemoteAdapter] implementation backed by Supabase.
///
/// **Cursor storage**: Cursors are read from and written to [localStore]
/// (a dedicated `_replicore_meta` SQLite table) instead of SharedPreferences.
/// This ensures cursors survive "Clear Cache" actions and OS-level preference
/// eviction, because the cursor lives in the same file as the data it tracks.
class SupabaseAdapter implements RemoteAdapter {
  final SupabaseClient client;
  final String updatedAtColumn;

  /// The local store is used exclusively for cursor persistence.
  /// No application data is read or written here by the adapter.
  final LocalStore localStore;

  SupabaseAdapter({
    required this.client,
    required this.localStore,
    this.updatedAtColumn = 'updated_at',
  });

  // ── Pull ───────────────────────────────────────────────────────────────────

  @override
  Future<PullResult> pull(PullRequest request) async {
    // Prefer an in-memory cursor passed by the engine (mid-pagination) over
    // the persisted one (start of a new sync session).
    final effectiveCursor =
        request.cursor ?? await localStore.readCursor(request.table);

    var queryBuilder = client
        .from(request.table)
        .select(request.columns.join(','));

    if (effectiveCursor != null) {
      final cursorTs = effectiveCursor.updatedAt.toUtc().toIso8601String();

      if (effectiveCursor.primaryKey != null) {
        // Keyset pagination: records strictly after (updatedAt, primaryKey).
        final pkFilterValue = _toFilterLiteral(effectiveCursor.primaryKey);
        queryBuilder = queryBuilder.or(
          '${request.updatedAtColumn}.gt.$cursorTs,'
          'and(${request.updatedAtColumn}.eq.$cursorTs,'
          '${request.primaryKey}.gt.$pkFilterValue)',
        );
      } else {
        // Cursor exists but has no PK (first-ever sync marker) — use simple gt.
        queryBuilder = queryBuilder.gt(request.updatedAtColumn, cursorTs);
      }
    }

    final List<Map<String, dynamic>> records;

    try {
      final batchData = await queryBuilder
          .order(request.updatedAtColumn, ascending: true)
          .order(request.primaryKey, ascending: true)
          .limit(request.limit);

      records = List<Map<String, dynamic>>.from(batchData);
    } on AuthException catch (e) {
      throw SyncAuthException(table: request.table, cause: e);
    } catch (e) {
      throw SyncNetworkException(
        table: request.table,
        message: 'Failed to pull data for table "${request.table}".',
        cause: e,
      );
    }

    SyncCursor? nextCursor;

    if (records.isNotEmpty) {
      final latestRecord = records.last;
      nextCursor = SyncCursor(
        updatedAt: DateTime.parse(
          latestRecord[request.updatedAtColumn].toString(),
        ),
        primaryKey: latestRecord[request.primaryKey],
      );

      // Persist after every batch so an interrupted sync can resume here
      // rather than restarting from the beginning.
      await localStore.writeCursor(request.table, nextCursor);
    } else if (request.cursor == null &&
        await localStore.readCursor(request.table) == null) {
      // First ever sync returned zero records — write a "caught up to now"
      // marker so future syncs use incremental deltas.
      await localStore.writeCursor(
        request.table,
        SyncCursor(updatedAt: DateTime.now().toUtc(), primaryKey: null),
      );
    }

    return PullResult(
      records: records,
      nextCursor: records.length == request.limit ? nextCursor : null,
    );
  }

  // ── Write operations ───────────────────────────────────────────────────────

  @override
  Future<void> upsert({
    required String table,
    required Map<String, dynamic> data,
    String? idempotencyKey,
  }) async {
    try {
      await client.from(table).upsert(data);
    } on AuthException catch (e) {
      throw SyncAuthException(table: table, cause: e);
    } catch (e) {
      throw SyncNetworkException(
        table: table,
        message: 'Upsert failed for table "$table".',
        cause: e,
      );
    }
  }

  @override
  Future<void> softDelete({
    required String table,
    required String primaryKeyColumn,
    required dynamic id,
    required Map<String, dynamic> payload,
    String? idempotencyKey,
  }) async {
    try {
      await client.from(table).update(payload).eq(primaryKeyColumn, id);
    } on AuthException catch (e) {
      throw SyncAuthException(table: table, cause: e);
    } catch (e) {
      throw SyncNetworkException(
        table: table,
        message: 'Soft-delete failed for table "$table" (id: $id).',
        cause: e,
      );
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _toFilterLiteral(dynamic value) {
    if (value is num) return value.toString();
    if (value == null) return 'null';
    final escaped = value.toString().replaceAll('"', '\\"');
    return '"$escaped"';
  }

  @override
  RealtimeSubscriptionProvider? getRealtimeProvider() {
    return SupabaseRealtimeProvider(client: client);
  }
}
