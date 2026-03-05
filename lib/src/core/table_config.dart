import 'sync_strategy.dart';

/// A resolver callback for [SyncStrategy.custom].
///
/// Return one of:
/// - [UseLocal]   → discard the remote record, keep local dirty version
/// - [UseRemote]  → overwrite local with the remote record
/// - [UseMerged]  → save a manually merged map
typedef ConflictResolver =
    Future<ConflictResolution> Function(
      Map<String, dynamic> local,
      Map<String, dynamic> remote,
    );

/// Configuration for a single table in the sync topology.
///
/// Defines how a local SQLite table should be synchronized with
/// a remote backend, including conflict resolution strategy and
/// change tracking column names.
class TableConfig {
  /// Name of the table in both local and remote databases.
  final String name;

  /// Name of the primary key column (default: 'id').
  final String primaryKey;

  /// Name of the column tracking last modification time (default: 'updated_at').
  final String updatedAtColumn;

  /// Name of the column tracking soft deletes (default: 'deleted_at').
  final String deletedAtColumn;

  /// Name of the local column tracking sync status.
  /// Added automatically if missing (default: 'is_synced').
  final String isSyncedColumn;

  /// Name of the local column tracking operation IDs for idempotency.
  /// Added automatically if missing (default: 'op_id').
  final String operationIdColumn;

  /// Columns to SELECT from the remote source.
  /// Do NOT include sync-internal columns like `is_synced` or `op_id` here —
  /// those are managed locally and will be stripped/set automatically.
  final List<String> columns;

  /// Strategy for resolving conflicts between local and remote changes.
  final SyncStrategy strategy;

  /// Required when [strategy] is [SyncStrategy.custom].
  final ConflictResolver? customResolver;

  const TableConfig({
    required this.name,
    this.primaryKey = 'id',
    this.updatedAtColumn = 'updated_at',
    this.deletedAtColumn = 'deleted_at',
    this.isSyncedColumn = 'is_synced',
    this.operationIdColumn = 'op_id',
    required this.columns,
    this.strategy = SyncStrategy.serverWins,
    this.customResolver,
  });

  /// Validate the configuration.
  void validate() {
    if (name.isEmpty) {
      throw ArgumentError('Table name cannot be empty');
    }
    if (primaryKey.isEmpty) {
      throw ArgumentError('Primary key column name cannot be empty');
    }
    if (updatedAtColumn.isEmpty) {
      throw ArgumentError('Updated at column name cannot be empty');
    }
    if (columns.isEmpty) {
      throw ArgumentError('Must specify at least one column to sync');
    }
    if (strategy == SyncStrategy.custom && customResolver == null) {
      throw ArgumentError(
        'Table "$name" uses SyncStrategy.custom but no customResolver provided',
      );
    }
  }
}
