/// Base class for all exceptions thrown by the Replicore framework.
///
/// Catching [ReplicoreException] is sufficient to handle any framework error.
/// Catch the subclasses for more targeted error handling in the UI.
///
/// ```dart
/// try {
///   await engine.syncAll();
/// } on SyncNetworkException catch (e) {
///   showBanner('You appear to be offline.');
/// } on SchemaMigrationException catch (e) {
///   showBanner('Database schema error: ${e.table}');
/// } on ReplicoreException catch (e) {
///   showBanner('Sync error: ${e.message}');
/// }
/// ```
sealed class ReplicoreException implements Exception {
  final String message;

  /// The underlying error that caused this exception, if any.
  final Object? cause;

  const ReplicoreException(this.message, {this.cause});

  @override
  String toString() {
    final causeStr = cause != null ? ' (caused by: $cause)' : '';
    return '${runtimeType}: $message$causeStr';
  }
}

// ── Network & Remote ──────────────────────────────────────────────────────────

/// Thrown when a network request to the remote adapter fails.
///
/// This is the error to catch for "user is offline" scenarios.
///
/// ```dart
/// on SyncNetworkException catch (e) {
///   if (e.isOffline) showOfflineBanner();
/// }
/// ```
class SyncNetworkException extends ReplicoreException {
  /// The table that was being synced when the error occurred.
  final String table;

  /// HTTP status code, if available.
  final int? statusCode;

  const SyncNetworkException({
    required this.table,
    required String message,
    this.statusCode,
    Object? cause,
  }) : super(message, cause: cause);

  /// Returns true when the error looks like a connectivity issue
  /// (no status code = no response received at all).
  bool get isOffline => statusCode == null;
}

/// Thrown when the remote adapter signals that the request is unauthorized.
///
/// Usually means the user's session has expired.
class SyncAuthException extends ReplicoreException {
  /// The table that was being synced when the error occurred.
  final String table;

  const SyncAuthException({
    required this.table,
    String message = 'Unauthorized. Session may have expired.',
    Object? cause,
  }) : super(message, cause: cause);
}

// ── Conflict Resolution ───────────────────────────────────────────────────────

/// Thrown when a [SyncStrategy.custom] resolver throws an unhandled error.
///
/// The original resolver exception is available via [cause].
class ConflictResolutionException extends ReplicoreException {
  /// The table in which the conflict occurred.
  final String table;

  /// The primary key value of the record that could not be resolved.
  final dynamic primaryKey;

  const ConflictResolutionException({
    required this.table,
    required this.primaryKey,
    String message = 'Custom conflict resolver threw an exception.',
    Object? cause,
  }) : super(message, cause: cause);
}

// ── Local Storage & Schema ────────────────────────────────────────────────────

/// Thrown when an auto-migration (ALTER TABLE) fails.
///
/// This typically means the database is locked, or the schema is in an
/// unexpected state. Check [table] and [column] for details.
class SchemaMigrationException extends ReplicoreException {
  /// The table on which migration was attempted.
  final String table;

  /// The column that could not be added.
  final String column;

  const SchemaMigrationException({
    required this.table,
    required this.column,
    required String message,
    Object? cause,
  }) : super(message, cause: cause);
}

/// Thrown when a batch upsert to the local SQLite store fails.
class LocalStoreException extends ReplicoreException {
  /// The table on which the write failed.
  final String table;

  const LocalStoreException({
    required this.table,
    required String message,
    Object? cause,
  }) : super(message, cause: cause);
}

// ── Engine Configuration ──────────────────────────────────────────────────────

/// Thrown when [SyncEngine.syncTable] is called with a table name that was
/// not registered via [SyncEngine.registerTable].
class UnregisteredTableException extends ReplicoreException {
  final String table;

  const UnregisteredTableException(this.table)
    : super("Table '$table' was not registered with SyncEngine.");
}

/// Thrown when [SyncEngine] is used before [SyncEngine.init] has completed,
/// or when configuration is invalid (e.g. [SyncStrategy.custom] without a
/// [ConflictResolver]).
class EngineConfigurationException extends ReplicoreException {
  const EngineConfigurationException(String message) : super(message);
}
