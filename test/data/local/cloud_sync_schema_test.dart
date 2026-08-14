import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/local/trainflow_database_schema.dart';

void main() {
  test('数据库保留第五版云同步状态表且不改写既有业务表', () {
    expect(TrainFlowDatabaseSchema.version, greaterThanOrEqualTo(5));
    expect(
      TrainFlowDatabaseSchema.requiredTables,
      containsAll(<String>{
        'sync_outbox',
        'sync_cursor',
        'sync_entity_state',
        'sync_conflicts',
      }),
    );
    expect(
      TrainFlowDatabaseSchema.version5UpgradeStatements,
      hasLength(greaterThanOrEqualTo(8)),
    );
    for (final String table in <String>[
      'sync_outbox',
      'sync_cursor',
      'sync_entity_state',
      'sync_conflicts',
    ]) {
      expect(
        TrainFlowDatabaseSchema.version5UpgradeStatements,
        contains(contains('CREATE TABLE IF NOT EXISTS $table')),
        reason: '第五版迁移缺少 $table',
      );
    }
  });

  test('云同步本地表按账号隔离并保留快照与冲突状态', () {
    final String schema =
        TrainFlowDatabaseSchema.version5UpgradeStatements.join('\n');
    expect(schema, contains('account_id TEXT NOT NULL'));
    expect(schema, contains('snapshot_required INTEGER NOT NULL DEFAULT 1'));
    expect(
        schema, contains('has_existing_local_data INTEGER NOT NULL DEFAULT 0'));
    expect(schema, contains('cloud_payload_json TEXT NOT NULL'));
    expect(schema, contains('local_payload_json TEXT NOT NULL'));
    expect(schema, contains('UNIQUE (account_id, mutation_id)'));
    expect(
      TrainFlowDatabaseSchema.requiredIndexes,
      containsAll(<String>{
        'idx_sync_outbox_account_state_retry',
        'idx_sync_entity_state_account_type',
        'idx_sync_conflicts_account_status',
      }),
    );
  });
}
