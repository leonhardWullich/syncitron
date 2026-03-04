import 'dart:convert';

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

  @override
  Future<PullResult> pull(PullRequest request) async {
    final lastSyncKey = 'replicore_cursor_${request.table}';
    final persistedCursor = _readCursor(lastSyncKey);

    final effectiveCursor = request.cursor ?? persistedCursor;

    var queryBuilder = client.from(request.table).select(request.columns.join(','));

    if (effectiveCursor != null) {
      final cursorTs = effectiveCursor.updatedAt.toUtc().toIso8601String();
      final pkFilterValue = _toFilterLiteral(effectiveCursor.primaryKey);
      queryBuilder = queryBuilder.or(
        '${request.updatedAtColumn}.gt.$cursorTs,and(${request.updatedAtColumn}.eq.$cursorTs,${request.primaryKey}.gt.$pkFilterValue)',
      );
    }

    final batchData = await queryBuilder
        .order(request.updatedAtColumn, ascending: true)
        .order(request.primaryKey, ascending: true)
        .limit(request.limit);

    final records = List<Map<String, dynamic>>.from(batchData);

    SyncCursor? nextCursor;
    if (records.isNotEmpty) {
      final latestRecord = records.last;
      nextCursor = SyncCursor(
        updatedAt: DateTime.parse(latestRecord[request.updatedAtColumn].toString()),
        primaryKey: latestRecord[request.primaryKey],
      );

      if (records.length < request.limit) {
        await prefs.setString(lastSyncKey, jsonEncode(nextCursor.toJson()));
      }
    } else if (request.cursor == null && persistedCursor == null) {
      await prefs.setString(
        lastSyncKey,
        jsonEncode(
          SyncCursor(
            updatedAt: DateTime.now().toUtc(),
            primaryKey: null,
          ).toJson(),
        ),
      );
    }

    return PullResult(
      records: records,
      nextCursor: records.length == request.limit ? nextCursor : null,
    );
  }

  SyncCursor? _readCursor(String key) {
    final value = prefs.getString(key);
    if (value == null || value.isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        return SyncCursor.fromJson(decoded);
      }
      if (decoded is Map) {
        return SyncCursor.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String _toFilterLiteral(dynamic value) {
    if (value is num) return value.toString();
    if (value == null) return 'null';
    final escaped = value.toString().replaceAll('"', '\\"');
    return '"$escaped"';
  }

  @override
  Future<void> upsert({
    required String table,
    required Map<String, dynamic> data,
    String? idempotencyKey,
  }) async {
    await client.from(table).upsert(data);
  }

  @override
  Future<void> softDelete({
    required String table,
    required String primaryKeyColumn,
    required dynamic id,
    required Map<String, dynamic> payload,
    String? idempotencyKey,
  }) async {
    await client.from(table).update(payload).eq(primaryKeyColumn, id);
  }
}
