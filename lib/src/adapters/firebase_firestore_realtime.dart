import 'dart:async';

import '../core/realtime_subscription.dart';

/// Firebase Firestore implementation of [RealtimeSubscriptionProvider].
class FirebaseFirestoreRealtimeProvider
    implements RealtimeSubscriptionProvider {
  final dynamic firestore;
  final Duration connectionTimeout;

  final Map<String, StreamSubscription> _subscriptions = {};
  bool _isConnected = false;
  late StreamController<bool> _connectionStatusController;

  FirebaseFirestoreRealtimeProvider({
    required this.firestore,
    this.connectionTimeout = const Duration(seconds: 30),
  }) {
    _connectionStatusController = StreamController<bool>.broadcast();
    _isConnected = true;
  }

  @override
  Stream<RealtimeChangeEvent> subscribe(String table) {
    return _createSnapshotStream(table);
  }

  /// Create a stream of real-time changes for a collection.
  Stream<RealtimeChangeEvent> _createSnapshotStream(String table) async* {
    try {
      final collection = firestore.collection(table);
      final snapshots = collection.snapshots().asBroadcastStream();

      final previousDocs = <String, dynamic>{};

      yield* snapshots
          .map<RealtimeChangeEvent>((snapshot) {
            for (final doc in snapshot.docs) {
              final docId = doc.id;
              final data = doc.data() as Map<String, dynamic>;

              if (!previousDocs.containsKey(docId)) {
                // Insert
                previousDocs[docId] = data;
                return RealtimeChangeEvent(
                  table: table,
                  operation: RealtimeOperation.insert,
                  record: data,
                  metadata: {'id': docId},
                  timestamp: DateTime.now(),
                );
              } else {
                // Update
                if (previousDocs[docId] != data) {
                  previousDocs[docId] = data;
                  return RealtimeChangeEvent(
                    table: table,
                    operation: RealtimeOperation.update,
                    record: data,
                    metadata: {'id': docId},
                    timestamp: DateTime.now(),
                  );
                }
              }
            }

            // Check for deletes
            final currentIds = snapshot.docs.map((d) => d.id).toSet();
            for (final docId in previousDocs.keys.toList()) {
              if (!currentIds.contains(docId)) {
                previousDocs.remove(docId);
                return RealtimeChangeEvent(
                  table: table,
                  operation: RealtimeOperation.delete,
                  metadata: {'id': docId},
                  timestamp: DateTime.now(),
                );
              }
            }

            // No changes
            return RealtimeChangeEvent(
              table: table,
              operation: RealtimeOperation.update,
              metadata: {'status': 'no-change'},
              timestamp: DateTime.now(),
            );
          })
          .where(
            (event) =>
                event.operation != RealtimeOperation.update ||
                event.metadata['status'] != 'no-change',
          );
    } catch (e) {
      yield* Stream.error(e);
    }
  }

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;

  @override
  Future<void> close() async {
    for (final sub in _subscriptions.values) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await _connectionStatusController.close();
  }
}
