import 'dart:async';

import '../core/exceptions.dart';
import '../core/models.dart';
import '../core/realtime_subscription.dart';
import 'remote_adapter.dart';
import 'graphql_realtime.dart';

/// Generic GraphQL implementation of [RemoteAdapter].
///
/// Works with any GraphQL backend (Apollo, Hasura, Supabase GraphQL, etc.).
/// Requires you to define GraphQL queries/mutations in a companion service.
///
/// Example setup:
/// ```dart
/// import 'package:graphql/client.dart';
///
/// final graphqlClient = GraphQLClient(
///   link: HttpLink('https://your-graphql-api.io/graphql'),
///   cache: GraphQLCache(),
/// );
///
/// final adapter = GraphQLAdapter(
///   graphqlClient: graphqlClient,
///   localStore: sqfliteStore,
///   queryBuilder: pullQueryBuilder,     // Your custom query composer
///   mutationBuilder: upsertMutationBuilder, // Your custom mutation composer
/// );
/// ```
class GraphQLAdapter implements RemoteAdapter {
  /// GraphQL client instance (typically from `graphql` package).
  final dynamic graphqlClient;

  /// Local store for storing metadata and sync state.
  final dynamic localStore;

  /// Custom function to build pull queries.
  /// Signature: String Function(PullRequest) -> returns GraphQL query string
  final String Function(PullRequest) queryBuilder;

  /// Custom function to build upsert mutations.
  /// Signature: String Function(String table, Map<String, dynamic>) -> returns GraphQL mutation
  final String Function(String, Map<String, dynamic>) mutationBuilder;

  /// Custom function to build soft delete mutations.
  /// Signature: String Function(String table, String id) -> returns GraphQL mutation
  final String Function(String, String) softDeleteMutationBuilder;

  /// Timeout for GraphQL operations (default 30 seconds).
  final Duration timeout;

  GraphQLAdapter({
    required this.graphqlClient,
    required this.localStore,
    required this.queryBuilder,
    required this.mutationBuilder,
    required this.softDeleteMutationBuilder,
    this.timeout = const Duration(seconds: 30),
  });

  // ── Pull Operations ────────────────────────────────────────────────────────

  @override
  Future<PullResult> pull(PullRequest request) async {
    try {
      // Build the GraphQL query
      final query = queryBuilder(request);

      // Execute query via GraphQL client
      final result = await graphqlClient
          .query(
            QueryOptions(
              document: query,
              variables: {
                'table': request.table,
                'limit': request.limit,
                'cursor': request.cursor?.toJson(),
              },
              fetchPolicy: FetchPolicy.noCache,
            ),
          )
          .timeout(timeout);

      if (result.hasException) {
        throw result.exception!;
      }

      final data = result.data?[request.table] ?? [];
      final records = List<Map<String, dynamic>>.from(data as List);

      // Extract next cursor from response
      SyncCursor? nextCursor;
      if (records.isNotEmpty) {
        final lastRecord = records.last;
        final updatedAt = lastRecord[request.updatedAtColumn];
        if (updatedAt != null) {
          nextCursor = SyncCursor(
            updatedAt: DateTime.parse(updatedAt.toString()),
            primaryKey: lastRecord[request.primaryKey],
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
        message: 'GraphQL pull operation timed out.',
        cause: e,
      );
    } catch (e) {
      throw SyncNetworkException(
        table: request.table,
        message:
            'Failed to pull from GraphQL backend for table "${request.table}".',
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
      // Build mutation query
      final mutation = mutationBuilder(table, data);

      // Execute mutation
      final result = await graphqlClient
          .mutate(
            MutationOptions(
              document: mutation,
              variables: {
                'table': table,
                'data': data,
                if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
              },
            ),
          )
          .timeout(timeout);

      if (result.hasException) {
        throw result.exception!;
      }
    } on TimeoutException catch (e) {
      throw SyncNetworkException(
        table: table,
        message: 'GraphQL upsert operation timed out.',
        cause: e,
      );
    } catch (e) {
      throw SyncNetworkException(
        table: table,
        message: 'Failed to upsert into GraphQL backend table "$table".',
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
      // Build soft delete mutation
      final mutation = softDeleteMutationBuilder(table, id.toString());

      final result = await graphqlClient
          .mutate(
            MutationOptions(
              document: mutation,
              variables: {
                'table': table,
                'id': id,
                'payload': payload,
                if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
              },
            ),
          )
          .timeout(timeout);

      if (result.hasException) {
        throw result.exception!;
      }
    } on TimeoutException catch (e) {
      throw SyncNetworkException(
        table: table,
        message: 'GraphQL soft delete operation timed out.',
        cause: e,
      );
    } catch (e) {
      throw SyncNetworkException(
        table: table,
        message: 'Failed to soft delete from GraphQL backend table "$table".',
        cause: e,
      );
    }
  }

  // ── GraphQL-specific features ──────────────────────────────────────────────

  /// Execute a custom GraphQL query (for advanced use cases).
  Future<Map<String, dynamic>> executeQuery({
    required String query,
    Map<String, dynamic>? variables,
  }) async {
    try {
      final result = await graphqlClient
          .query(
            QueryOptions(
              document: query,
              variables: variables ?? {},
              fetchPolicy: FetchPolicy.noCache,
            ),
          )
          .timeout(timeout);

      if (result.hasException) {
        throw result.exception!;
      }

      return result.data ?? {};
    } catch (e) {
      throw SyncNetworkException(
        table: '',
        message: 'Custom GraphQL query execution failed.',
        cause: e,
      );
    }
  }

  /// Execute a custom GraphQL mutation.
  Future<Map<String, dynamic>> executeMutation({
    required String mutation,
    Map<String, dynamic>? variables,
  }) async {
    try {
      final result = await graphqlClient
          .mutate(
            MutationOptions(document: mutation, variables: variables ?? {}),
          )
          .timeout(timeout);

      if (result.hasException) {
        throw result.exception!;
      }

      return result.data ?? {};
    } catch (e) {
      throw SyncNetworkException(
        table: '',
        message: 'Custom GraphQL mutation execution failed.',
        cause: e,
      );
    }
  }

  /// Subscribe to GraphQL subscription for real-time updates.
  /// Returns a Stream of subscription events.
  Stream<Map<String, dynamic>> subscribe({
    required String subscription,
    Map<String, dynamic>? variables,
  }) async* {
    try {
      // This would use graphqlClient.subscribe() for real-time
      // Implementation depends on your GraphQL client configuration
      yield {};
    } catch (e) {
      throw SyncNetworkException(
        table: '',
        message: 'GraphQL subscription setup failed.',
        cause: e,
      );
    }
  }

  @override
  RealtimeSubscriptionProvider? getRealtimeProvider() {
    return GraphQLRealtimeProvider(graphqlClient: graphqlClient);
  }
}

/// Helper placeholder for GraphQL document parsing.
/// In real use, you'd import from 'graphql/language/ast.dart'
class gql {
  static dynamic call(String query) {
    // In actual use, this would parse the GraphQL query string
    return query;
  }
}

/// GraphQL Client query options placeholder.
class QueryOptions {
  final dynamic document;
  final Map<String, dynamic> variables;
  final dynamic fetchPolicy;

  QueryOptions({
    required this.document,
    this.variables = const {},
    this.fetchPolicy,
  });
}

/// GraphQL Client mutation options placeholder.
class MutationOptions {
  final dynamic document;
  final Map<String, dynamic> variables;

  MutationOptions({required this.document, this.variables = const {}});
}

/// GraphQL Fetch Policy enum.
class FetchPolicy {
  static const String noCache = 'no-cache';
  static const String cacheFirst = 'cache-first';
  static const String cacheAndNetwork = 'cache-and-network';
  static const String networkOnly = 'network-only';
}
