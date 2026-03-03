import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/models.dart';
import 'remote_adapter.dart';

class SupabaseAdapter implements RemoteAdapter {
  final SupabaseClient client;
  final String updatedAtColumn;
  final SharedPreferences prefs;

  SupabaseAdapter({
    required this.client,
    required this.prefs,
    this.updatedAtColumn = 'updated_at',
  });

  Future<PullResult> pull(PullRequest request) async {
    final lastSyncKey = 'replicore_last_${request.table}';
    final lastSyncStr = prefs.getString(lastSyncKey);
    final lastSync = lastSyncStr != null ? DateTime.parse(lastSyncStr) : null;

    int offset = 0;
    bool hasMore = true;
    final List<Map<String, dynamic>> allRecords = [];

    while (hasMore) {
      var queryBuilder = client
          .from(request.table)
          .select(request.columns.join(','));

      // incremental pull only
      if (lastSync != null) {
        queryBuilder = queryBuilder.gt(
          updatedAtColumn,
          lastSync.toIso8601String(),
        );
      }

      // stable order for pagination
      final orderedBuilder = queryBuilder
          .order(updatedAtColumn, ascending: true)
          .limit(request.limit);

      // fetch batch
      final batchData = await orderedBuilder.range(
        offset,
        offset + request.limit - 1,
      );

      if (batchData.isEmpty) {
        hasMore = false;
        break;
      }

      // append to allRecords
      allRecords.addAll(List<Map<String, dynamic>>.from(batchData));

      if (batchData.length < request.limit) {
        hasMore = false;
      } else {
        offset += request.limit;
      }
    }

    // update last sync timestamp after successful pull
    if (allRecords.isNotEmpty) {
      final latest = allRecords.last;
      final lastUpdated = latest[updatedAtColumn] as String;
      await prefs.setString(lastSyncKey, lastUpdated);
    }

    return PullResult(
      records: allRecords,
      nextCursor: allRecords.isNotEmpty
          ? SyncCursor(
              updatedAt: DateTime.parse(allRecords.last[updatedAtColumn]),
              primaryKey: allRecords.last['id'],
            )
          : null,
    );
  }

  @override
  Future<void> upsert({
    required String table,
    required Map<String, dynamic> data,
  }) async {
    await client.from(table).upsert(data);
  }

  @override
  Future<void> softDelete({
    required String table,
    required dynamic id,
    required Map<String, dynamic> payload,
  }) async {
    await client.from(table).update(payload).eq('id', id);
  }
}
