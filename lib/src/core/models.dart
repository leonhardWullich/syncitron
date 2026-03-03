class SyncCursor {
  final DateTime updatedAt;
  final dynamic primaryKey;

  const SyncCursor({required this.updatedAt, required this.primaryKey});
}

class PullRequest {
  final String table;
  final List<String> columns;
  final SyncCursor? cursor;
  final int limit;

  const PullRequest({
    required this.table,
    required this.columns,
    this.cursor,
    required this.limit,
  });
}

class PullResult {
  final List<Map<String, dynamic>> records;
  final SyncCursor? nextCursor;

  const PullResult({required this.records, this.nextCursor});
}
