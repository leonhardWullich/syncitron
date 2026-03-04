class SyncCursor {
  final DateTime updatedAt;

  /// The primary key value of the last seen record.
  /// Must not be null — a null cursor means "start from the beginning".
  final dynamic primaryKey;

  const SyncCursor({required this.updatedAt, required this.primaryKey});

  Map<String, dynamic> toJson() => {
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'primary_key': primaryKey,
  };

  factory SyncCursor.fromJson(Map<String, dynamic> json) {
    return SyncCursor(
      updatedAt: DateTime.parse(json['updated_at'] as String),
      primaryKey: json['primary_key'],
    );
  }
}

class PullRequest {
  final String table;
  final List<String> columns;
  final String primaryKey;
  final String updatedAtColumn;
  final SyncCursor? cursor;
  final int limit;

  const PullRequest({
    required this.table,
    required this.columns,
    required this.primaryKey,
    required this.updatedAtColumn,
    this.cursor,
    required this.limit,
  });
}

class PullResult {
  final List<Map<String, dynamic>> records;
  final SyncCursor? nextCursor;

  const PullResult({required this.records, this.nextCursor});
}
