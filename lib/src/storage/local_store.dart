abstract class LocalStore {
  Future<List<Map<String, dynamic>>> queryDirty(String table);

  Future<void> upsertBatch(String table, List<Map<String, dynamic>> records);

  Future<void> markAsSynced(String table, dynamic primaryKey);

  Future<Map<String, dynamic>?> findById(String table, dynamic id);
}
