import 'sync_strategy.dart';

typedef ConflictResolver =
    Future<Map<String, dynamic>?> Function(
      Map<String, dynamic> local,
      Map<String, dynamic> remote,
    );

class TableConfig {
  final String name;
  final String primaryKey;
  final String updatedAtColumn;
  final String deletedAtColumn;
  final List<String> columns;
  final SyncStrategy strategy;
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
