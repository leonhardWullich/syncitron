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

class TableConfig {
  final String name;
  final String primaryKey;
  final String updatedAtColumn;
  final String deletedAtColumn;

  /// Columns to SELECT from the remote source.
  /// Do NOT include sync-internal columns like `is_synced` or `op_id` here —
  /// those are managed locally and will be stripped/set automatically.
  final List<String> columns;

  final SyncStrategy strategy;

  /// Required when [strategy] is [SyncStrategy.custom].
  final ConflictResolver? customResolver;

  const TableConfig({
    required this.name,
    this.primaryKey = 'id',
    this.updatedAtColumn = 'updated_at',
    this.deletedAtColumn = 'deleted_at',
    required this.columns,
    this.strategy = SyncStrategy.serverWins,
    this.customResolver,
  });
}
