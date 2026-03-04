import '../core/models.dart';

abstract class RemoteAdapter {
  Future<PullResult> pull(PullRequest request);

  Future<void> upsert({
    required String table,
    required Map<String, dynamic> data,
    String? idempotencyKey,
  });

  Future<void> softDelete({
    required String table,
    required String primaryKeyColumn,
    required dynamic id,
    required Map<String, dynamic> payload,
    String? idempotencyKey,
  });
}
