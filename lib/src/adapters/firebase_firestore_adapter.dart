import 'dart:async';

import '../core/exceptions.dart';
import '../core/models.dart';
import '../core/realtime_subscription.dart';
import 'remote_adapter.dart';
import 'firebase_firestore_realtime.dart';

/// Firebase Firestore implementation of [RemoteAdapter].
///
/// Integrates directly with Firebase Firestore for real-time sync capabilities
/// and cloud infrastructure benefits.
///
/// Example setup:
/// ```dart
/// import 'package:cloud_firestore/cloud_firestore.dart';
///
/// final adapter = FirebaseFirestoreAdapter(
///   firestore: FirebaseFirestore.instance,
///   localStore: sqfliteStore,
/// );
/// ```
class FirebaseFirestoreAdapter implements RemoteAdapter {
  /// Firebase Firestore instance.
  final dynamic firestore;

  /// Local store for storing metadata and sync state.
  final dynamic localStore;

  /// Timeout for Firestore operations (default 30 seconds).
  final Duration timeout;

  /// Whether to enable offline persistence (Firestore feature).
  final bool enableOfflinePersistence;

  FirebaseFirestoreAdapter({
    required this.firestore,
    required this.localStore,
    this.timeout = const Duration(seconds: 30),
    this.enableOfflinePersistence = true,
  });

  // ── Pull Operations ────────────────────────────────────────────────────────

  @override
  Future<PullResult> pull(PullRequest request) async {
    try {
      final collection = firestore.collection(request.table);

      // Build query with cursor filtering
      dynamic query = collection;

      if (request.cursor != null) {
        // Filter by updatedAt > cursor.updatedAt
        query = query
            .where(
              request.updatedAtColumn,
              isGreaterThan: request.cursor!.updatedAt.toIso8601String(),
            )
            .orderBy(request.updatedAtColumn);
      } else {
        query = query.orderBy(request.updatedAtColumn);
      }

      // Limit results to batch size
      query = query.limit(request.limit);

      // Execute query with timeout
      final snapshot = await query.get().timeout(timeout);

      final records = <Map<String, dynamic>>[];
      SyncCursor? nextCursor;

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;

        // Include the Firestore document ID if not already present
        if (!data.containsKey(request.primaryKey)) {
          data[request.primaryKey] = doc.id;
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
        message: 'Firestore pull operation timed out.',
        cause: e,
      );
    } catch (e) {
      throw SyncNetworkException(
        table: request.table,
        message: 'Failed to pull from Firestore table "${request.table}".',
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
      final doc = firestore.collection(table).doc(id);

      // Merge ensures updates don't overwrite entire document
      await doc.set(data, <String, dynamic>{'merge': true}).timeout(timeout);
    } on TimeoutException catch (e) {
      throw SyncNetworkException(
        table: table,
        message: 'Firestore upsert operation timed out.',
        cause: e,
      );
    } catch (e) {
      throw SyncNetworkException(
        table: table,
        message: 'Failed to upsert into Firestore table "$table".',
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
      final doc = firestore.collection(table).doc(id.toString());

      // Mark as deleted by setting deleted_at timestamp
      await doc
          .update({...payload, 'deleted_at': DateTime.now().toIso8601String()})
          .timeout(timeout);
    } on TimeoutException catch (e) {
      throw SyncNetworkException(
        table: table,
        message: 'Firestore soft delete operation timed out.',
        cause: e,
      );
    } catch (e) {
      throw SyncNetworkException(
        table: table,
        message: 'Failed to soft delete from Firestore table "$table".',
        cause: e,
      );
    }
  }

  // ── Firestore-specific features ────────────────────────────────────────────

  /// Enable real-time listener for a collection.
  /// Returns a Stream that emits document changes.
  Stream<List<Map<String, dynamic>>> watchCollection(String table) {
    return firestore.collection(table).snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();
    });
  }

  /// Perform a batch write operation (multi-document transaction).
  Future<void> batchWrite(
    List<({String table, String operation, Map<String, dynamic> data})>
    operations,
  ) async {
    try {
      final batch = firestore.batch();

      for (final op in operations) {
        final doc = firestore.collection(op.table).doc(op.data['id']);

        switch (op.operation) {
          case 'set':
            batch.set(doc, op.data);
          case 'update':
            batch.update(doc, op.data);
          case 'delete':
            batch.delete(doc);
        }
      }

      await batch.commit().timeout(timeout);
    } catch (e) {
      throw RemoteAdapterException(
        message: 'Firestore batch write failed.',
        cause: e,
      );
    }
  }

  /// Execute a transaction for atomic multi-document updates.
  Future<T> runTransaction<T>(
    Future<T> Function(dynamic txn) updateCallback,
  ) async {
    try {
      return await firestore.runTransaction(updateCallback).timeout(timeout);
    } catch (e) {
      throw SyncNetworkException(
        table: '',
        message: 'Firestore transaction failed.',
        cause: e,
      );
    }
  }

  @override
  RealtimeSubscriptionProvider? getRealtimeProvider() {
    return FirebaseFirestoreRealtimeProvider(
      firestore: firestore,
      connectionTimeout: timeout,
    );
  }
}

class RemoteAdapterException extends SyncNetworkException {
  RemoteAdapterException({required String message, required Object cause})
    : super(table: '', message: message, cause: cause);
}
