abstract class LocalStore {
  Future<List<Map<String, dynamic>>> queryDirty(String table);

  Future<void> upsertBatch(String table, List<Map<String, dynamic>> records);

  Future<void> markAsSynced(String table, String pkColumn, dynamic primaryKey);

  Future<Map<String, dynamic>?> findById(
    String table,
    String pkColumn,
    dynamic id,
  );

  Future<List<Map<String, dynamic>>> findManyByIds(
    String table,
    String pkColumn,
    List<dynamic> ids,
  );
}
