import 'dart:async';

import '../core/exceptions.dart';
import '../core/models.dart';
import '../core/realtime_subscription.dart';
import 'remote_adapter.dart';
import 'appwrite_realtime.dart';

/// Appwrite implementation of [RemoteAdapter].
///
/// Appwrite is an self-hosted or managed backend-as-a-service (BaaS)
/// compatible with Replicore for robust sync scenarios.
///
/// Example setup:
/// ```dart
/// import 'package:appwrite/appwrite.dart';
///
/// final client = Client()
///   .setEndpoint('https://your-appwrite-instance.io/v1')
///   .setProject('your-project-id');
///
/// final adapter = AppwriteAdapter(
///   client: client,
///   localStore: sqfliteStore,
///   databaseId: 'your-database-id',
/// );
/// ```
class AppwriteAdapter implements RemoteAdapter {
  /// Appwrite Client instance.
  final dynamic client;

  /// Appwrite Database instance.
  final dynamic database;

  /// Local store for storing metadata and sync state.
  final dynamic localStore;

  /// Appwrite database ID.
  final String databaseId;

  /// Timeout for Appwrite operations (default 30 seconds).
  final Duration timeout;

  AppwriteAdapter({
    required this.client,
    required this.database,
    required this.localStore,
    required this.databaseId,
    this.timeout = const Duration(seconds: 30),
  });

  // ── Pull Operations ────────────────────────────────────────────────────────

  @override
  Future<PullResult> pull(PullRequest request) async {
    try {
      // Build Appwrite query
      final queries = <String>[];

      // Order by updatedAt ascending
      queries.add('orderAsc("${request.updatedAtColumn}")');

      // If we have a cursor, filter for records after it
      if (request.cursor != null) {
        queries.add(
          'greaterThan("${request.updatedAtColumn}", '
          '"${request.cursor!.updatedAt.toIso8601String()}")',
        );
      }

      // Limit results
      queries.add('limit(${request.limit})');

      // Execute query
      final response = await database
          .listDocuments(
            databaseId: databaseId,
            collectionId: request.table,
            queries: queries,
          )
          .timeout(timeout);

      final records = <Map<String, dynamic>>[];
      SyncCursor? nextCursor;

      for (final doc in response.documents ?? []) {
        final data = doc.data ?? <String, dynamic>{};

        // Ensure document ID is included
        if (!data.containsKey(request.primaryKey)) {
          data[request.primaryKey] = doc.$id;
        }

        // Filter to requested columns
        final filtered = <String, dynamic>{};
        for (final col in request.columns) {
          if (data.containsKey(col)) {
            filtered[col] = data[col];
          }
        }

        records.add(filtered);

        // Update cursor for next batch
        final updatedAt = data[request.updatedAtColumn];
        if (updatedAt != null) {
          nextCursor = SyncCursor(
            updatedAt: DateTime.parse(updatedAt.toString()),
            primaryKey: data[request.primaryKey],
          );
        }
      }

      return PullResult(
        records: records,
        nextCursor: records.isEmpty ? null : nextCursor,
      );
    } on TimeoutException catch (e) {
      throw SyncNetworkException(
        table: request.table,
        message: 'Appwrite pull operation timed out.',
        cause: e,
      );
    } catch (e) {
      throw SyncNetworkException(
        table: request.table,
        message: 'Failed to pull from Appwrite table "${request.table}".',
        cause: e,
      );
    }
  }

  // ── Push Operations ────────────────────────────────────────────────────────

  @override
  Future<void> upsert({
    required String table,
    required Map<String, dynamic> data,
    String? idempotencyKey,
  }) async {
    try {
      final id = data['id'] ?? data.keys.first;

      // Check if document exists
      final doc = await database
          .getDocument(
            databaseId: databaseId,
            collectionId: table,
            documentId: id.toString(),
          )
          .timeout(timeout)
          .catchError((_) => null); // Return null if not found

      if (doc != null) {
        // Update existing document
        await database
            .updateDocument(
              databaseId: databaseId,
              collectionId: table,
              documentId: id.toString(),
              data: data,
            )
            .timeout(timeout);
      } else {
        // Create new document
        await database
            .createDocument(
              databaseId: databaseId,
              collectionId: table,
              documentId: id.toString(),
              data: data,
            )
            .timeout(timeout);
      }
    } on TimeoutException catch (e) {
      throw SyncNetworkException(
        table: table,
        message: 'Appwrite upsert operation timed out.',
        cause: e,
      );
    } catch (e) {
      throw SyncNetworkException(
        table: table,
        message: 'Failed to upsert into Appwrite table "$table".',
        cause: e,
      );
    }
  }

  // ── Soft Delete Operations ─────────────────────────────────────────────────

  @override
  Future<void> softDelete({
    required String table,
    required String primaryKeyColumn,
    required dynamic id,
    required Map<String, dynamic> payload,
    String? idempotencyKey,
  }) async {
    try {
      final updateData = <String, dynamic>{
        ...payload,
        'deleted_at': DateTime.now().toIso8601String(),
      };

      await database
          .updateDocument(
            databaseId: databaseId,
            collectionId: table,
            documentId: id.toString(),
            data: updateData,
          )
          .timeout(timeout);
    } on TimeoutException catch (e) {
      throw SyncNetworkException(
        table: table,
        message: 'Appwrite soft delete operation timed out.',
        cause: e,
      );
    } catch (e) {
      throw SyncNetworkException(
        table: table,
        message: 'Failed to soft delete from Appwrite table "$table".',
        cause: e,
      );
    }
  }

  // ── Appwrite-specific features ─────────────────────────────────────────────

  /// Execute a custom Appwrite Function.
  /// Useful for complex server-side logic.
  Future<Map<String, dynamic>> executeFunction({
    required String functionId,
    required Map<String, dynamic> data,
  }) async {
    try {
      final response = await client.functions
          .createExecution(functionId: functionId, data: data)
          .timeout(timeout);

      return {
        'statusCode': response.statusCode,
        'response': response.responseBody,
      };
    } catch (e) {
      throw SyncNetworkException(
        table: '',
        message: 'Appwrite function execution failed.',
        cause: e,
      );
    }
  }

  /// Perform batch operations with Appwrite.
  Future<Map<String, dynamic>> batchWrite({
    required String table,
    required List<Map<String, dynamic>> creates,
    required List<Map<String, dynamic>> updates,
    required List<String> deletes,
  }) async {
    try {
      final results = <String, dynamic>{};

      // Create documents
      for (final doc in creates) {
        final id = doc['id'] ?? UniqueId().getUniqueID();
        final created = await database.createDocument(
          databaseId: databaseId,
          collectionId: table,
          documentId: id.toString(),
          data: doc,
        );
        results['created_$id'] = created.$id;
      }

      // Update documents
      for (final doc in updates) {
        final id = doc['id'] ?? doc.keys.first;
        await database.updateDocument(
          databaseId: databaseId,
          collectionId: table,
          documentId: id.toString(),
          data: doc,
        );
      }

      // Delete documents
      for (final id in deletes) {
        await database.deleteDocument(
          databaseId: databaseId,
          collectionId: table,
          documentId: id,
        );
      }

      return results;
    } catch (e) {
      throw SyncNetworkException(
        table: table,
        message: 'Appwrite batch operation failed.',
        cause: e,
      );
    }
  }

  /// Watch a collection for real-time changes (via WebSocket).
  /// Returns a Stream of document updates.
  Stream<Map<String, dynamic>> watchCollection(String table) async* {
    try {
      final channel = 'databases.$databaseId.collections.$table.documents';

      // This would use Appwrite's RealtimeService
      // Implementation depends on your Appwrite SDK version
      yield {'message': 'Watching $table', 'channel': channel};
    } catch (e) {
      throw SyncNetworkException(
        table: table,
        message: 'Failed to watch Appwrite collection "$table".',
        cause: e,
      );
    }
  }

  @override
  RealtimeSubscriptionProvider? getRealtimeProvider() {
    return AppwriteRealtimeProvider(client: client);
  }
}

/// Helper for generating unique IDs compatible with Appwrite.
class UniqueId {
  String getUniqueID() {
    // Appwrite-compatible ID generation
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
}
