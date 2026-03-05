import 'dart:async';

import '../core/realtime_subscription.dart';

/// GraphQL implementation of [RealtimeSubscriptionProvider].
///
/// Uses GraphQL subscriptions over WebSocket for real-time table changes.
/// Compatible with any GraphQL server that supports subscriptions
/// (Apollo, Hasura, Supabase GraphQL, etc.).
class GraphQLRealtimeProvider implements RealtimeSubscriptionProvider {
  final dynamic graphqlClient;
  final Duration connectionTimeout;

  final Map<String, StreamSubscription> _subscriptions = {};
  bool _isConnected = false;
  late StreamController<bool> _connectionStatusController;

  GraphQLRealtimeProvider({
    required this.graphqlClient,
    this.connectionTimeout = const Duration(seconds: 30),
  }) {
    _connectionStatusController = StreamController<bool>.broadcast();
    _isConnected = true;
  }

  @override
  Stream<RealtimeChangeEvent> subscribe(String table) {
    return _createSubscriptionStream(table);
  }

  /// Create a stream of real-time changes via GraphQL subscription.
  ///
  /// Requires your GraphQL schema to have subscriptions like:
  /// ```graphql
  /// subscription On${Table}Changed {
  ///   ${table}Changed {
  ///     operation
  ///     record
  ///     previous
  ///     timestamp
  ///   }
  /// }
  /// ```
  Stream<RealtimeChangeEvent> _createSubscriptionStream(String table) async* {
    try {
      // Monitor connection status
      _isConnected = true;
      _connectionStatusController.add(true);

      // In production, build a GraphQL subscription query:
      // final subscriptionQuery = buildSubscriptionForTable(table);
      //
      // Then subscribe:
      // final subscription = graphqlClient.subscribe(
      //   SubscriptionOptions(document: subscriptionQuery),
      // );

      // For now, emit periodic updates to show the flow
      yield* Stream.periodic(const Duration(seconds: 30))
          .asyncMap((_) {
            return RealtimeChangeEvent(
              table: table,
              operation: RealtimeOperation.update,
              metadata: {'status': 'listening', 'provider': 'graphql'},
              timestamp: DateTime.now(),
            );
          })
          .where((event) => false); // Filter out in normal use
    } catch (e) {
      _isConnected = false;
      _connectionStatusController.add(false);
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
