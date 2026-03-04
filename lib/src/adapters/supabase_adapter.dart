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

    var queryBuilder = client
        .from(request.table)
        .select(request.columns.join(','));

    // Cursor-Paginierung: Lade nur Datensätze, die NEUER sind als der Cursor.
    // Wenn kein Cursor da ist (erster Durchlauf), nimm den lastSync der ganzen Tabelle.
    if (request.cursor != null) {
      queryBuilder = queryBuilder.gt(
        updatedAtColumn,
        request.cursor!.updatedAt.toIso8601String(),
      );
    } else if (lastSync != null) {
      queryBuilder = queryBuilder.gt(
        updatedAtColumn,
        lastSync.toIso8601String(),
      );
    }

    // Lade genau EINEN Batch, geordnet nach Zeitstempel
    final batchData = await queryBuilder
        .order(updatedAtColumn, ascending: true)
        // Wir limitieren strikt auf die angefragte Batch-Size
        .limit(request.limit);

    final records = List<Map<String, dynamic>>.from(batchData);

    SyncCursor? nextCursor;

    if (records.isNotEmpty) {
      // Der Cursor für die nächste Anfrage ist der Zeitstempel des LETZTEN Datensatzes
      final latestRecord = records.last;
      nextCursor = SyncCursor(
        updatedAt: DateTime.parse(latestRecord[updatedAtColumn]),
        primaryKey:
            latestRecord['id'], // Info: Bei dynamischem PK müsste man hier request.primaryKey übergeben!
      );

      // Wenn dies der letzte Batch war (wir haben weniger bekommen als angefragt),
      // merken wir uns den finalen Zeitstempel für den nächsten App-Start.
      if (records.length < request.limit) {
        await prefs.setString(lastSyncKey, latestRecord[updatedAtColumn]);
      }
    } else if (request.cursor == null) {
      // Fallback: Es gab gar keine neuen Daten. Timestamp aktualisieren, damit
      // wir wissen, dass ein erfolgreicher Sync-Check stattgefunden hat.
      await prefs.setString(
        lastSyncKey,
        DateTime.now().toUtc().toIso8601String(),
      );
    }

    return PullResult(
      records: records,
      nextCursor: records.length == request.limit
          ? nextCursor
          : null, // Nur einen nextCursor liefern, wenn es noch mehr geben könnte
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
