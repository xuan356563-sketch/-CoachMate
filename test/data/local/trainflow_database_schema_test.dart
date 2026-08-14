import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/local/trainflow_database_schema.dart';

void main() {
  test('数据库第八版包含 Coach 治理表、陪伴表、宠物表与既有训练事实表', () {
    expect(TrainFlowDatabaseSchema.version, 8);
    expect(
      TrainFlowDatabaseSchema.requiredTables,
      <String>{
        'athlete_profiles',
        'training_goals',
        'training_availability',
        'races',
        'training_plan_versions',
        'scheduled_workouts',
        'training_logs',
        'exercise_execution_records',
        'health_snapshots',
        'pain_logs',
        'recovery_scores',
        'plan_adjustments',
        'weekly_reports',
        'growth_evidence_events',
        'growth_level_state',
        'legacy_documents',
        'migration_state',
        'workouts',
        'health_observations',
        'health_sync_runs',
        'health_sync_anchors',
        'scheduled_workout_results',
        'strength_sets',
        'athlete_primary_exercises',
        'workout_analysis_runs',
        'metric_aggregates',
        'metric_lineage',
        'report_revisions',
        'adjustment_proposals',
        'storage_cutover_state',
        'rhythm_snapshots',
        'meal_records',
        'sync_outbox',
        'sync_cursor',
        'sync_entity_state',
        'sync_conflicts',
        'daily_activity_summaries',
        'pet_collection',
        'pet_profile',
        'pet_daily_energy',
        'companion_messages',
        'companion_events',
        'companion_relationship',
        'coach_state_snapshots',
        'coach_memories',
        'coach_memory_sources',
        'coach_turn_traces',
      },
    );

    for (final String table in TrainFlowDatabaseSchema.requiredTables) {
      expect(
        TrainFlowDatabaseSchema.creationStatements,
        contains(contains('CREATE TABLE IF NOT EXISTS $table')),
        reason: '缺少 $table 的建表语句',
      );
    }
  });

  test('数据库启用外键并为关键查询建立索引', () {
    expect(
      TrainFlowDatabaseSchema.configureStatements,
      contains('PRAGMA foreign_keys = ON'),
    );
    expect(
      TrainFlowDatabaseSchema.creationStatements,
      contains(contains('scheduled_workouts(scheduled_date, status)')),
    );
    expect(
      TrainFlowDatabaseSchema.creationStatements,
      contains(contains(
          'growth_evidence_events(athlete_profile_id, revoked_at, occurred_at DESC, id DESC)')),
    );
    expect(
      TrainFlowDatabaseSchema.creationStatements,
      contains(
        contains(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_weekly_reports_profile_week_key',
        ),
      ),
    );
  });

  test('第二版迁移保留旧列并增加成长事件查询字段', () {
    expect(
      TrainFlowDatabaseSchema.version2UpgradeStatements,
      contains(contains('ADD COLUMN occurred_on')),
    );
    expect(
      TrainFlowDatabaseSchema.version2UpgradeStatements,
      contains(contains('ADD COLUMN revoked_at')),
    );
    expect(
      TrainFlowDatabaseSchema.version2UpgradeStatements,
      contains(contains('ADD COLUMN week_key')),
    );
    expect(
      TrainFlowDatabaseSchema.version2UpgradeStatements,
      contains(contains('CREATE TABLE IF NOT EXISTS growth_level_state')),
    );
  });

  test('第三版迁移只追加新表和关键索引', () {
    expect(
      TrainFlowDatabaseSchema.version3UpgradeStatements,
      contains(contains('CREATE TABLE IF NOT EXISTS workouts')),
    );
    expect(
      TrainFlowDatabaseSchema.version3UpgradeStatements,
      contains(contains('CREATE TABLE IF NOT EXISTS metric_aggregates')),
    );
    expect(
      TrainFlowDatabaseSchema.version3UpgradeStatements,
      contains(contains('CREATE TABLE IF NOT EXISTS storage_cutover_state')),
    );
    expect(
      TrainFlowDatabaseSchema.requiredIndexes,
      containsAll(<String>{
        'idx_workouts_external_uuid',
        'idx_workouts_route_external_uuid',
        'idx_metric_aggregates_period',
        'idx_metric_lineage_source',
      }),
    );
    expect(
      TrainFlowDatabaseSchema.version2UpgradeStatements,
      isNot(contains(contains('workouts'))),
    );
    expect(
      TrainFlowDatabaseSchema.version3UpgradeStatements,
      contains(contains('route_external_uuid TEXT')),
    );
    expect(
      TrainFlowDatabaseSchema.version3UpgradeStatements,
      contains(contains('heart_rate_sample_count INTEGER')),
    );
    expect(
      TrainFlowDatabaseSchema.version3UpgradeStatements,
      contains(contains('metadata_json TEXT NOT NULL')),
    );
    expect(
      TrainFlowDatabaseSchema.version3UpgradeStatements,
      contains(contains('relationship TEXT NOT NULL')),
    );
    expect(
      TrainFlowDatabaseSchema.version3UpgradeStatements,
      contains(contains('invalidated_at TEXT')),
    );
    expect(
      TrainFlowDatabaseSchema.version3UpgradeStatements,
      contains(contains('trigger_metric_code TEXT NOT NULL')),
    );
  });

  test('第四版迁移增加生日、不可变周快照和可撤销饮食记录', () {
    expect(
      TrainFlowDatabaseSchema.version4UpgradeStatements,
      contains(contains('ADD COLUMN birth_date')),
    );
    expect(
      TrainFlowDatabaseSchema.version4UpgradeStatements,
      contains(contains('CREATE TABLE IF NOT EXISTS rhythm_snapshots')),
    );
    expect(
      TrainFlowDatabaseSchema.version4UpgradeStatements,
      contains(contains('UNIQUE (athlete_profile_id, week_start)')),
    );
    expect(
      TrainFlowDatabaseSchema.version4UpgradeStatements,
      contains(contains('CREATE TABLE IF NOT EXISTS meal_records')),
    );
    expect(
      TrainFlowDatabaseSchema.requiredIndexes,
      containsAll(<String>{
        'idx_rhythm_snapshots_profile_week',
        'idx_meal_records_profile_date',
      }),
    );
  });

  test('第六版迁移只追加四张宠物表和三项关键索引', () {
    expect(
      TrainFlowDatabaseSchema.version6UpgradeStatements,
      contains(contains('CREATE TABLE IF NOT EXISTS daily_activity_summaries')),
    );
    expect(
      TrainFlowDatabaseSchema.version6UpgradeStatements,
      contains(contains('CREATE TABLE IF NOT EXISTS pet_collection')),
    );
    expect(
      TrainFlowDatabaseSchema.version6UpgradeStatements,
      contains(contains('CREATE TABLE IF NOT EXISTS pet_profile')),
    );
    expect(
      TrainFlowDatabaseSchema.version6UpgradeStatements,
      contains(contains('CREATE TABLE IF NOT EXISTS pet_daily_energy')),
    );
    expect(
      TrainFlowDatabaseSchema.requiredIndexes,
      containsAll(<String>{
        'idx_daily_activity_summaries_profile_date',
        'idx_pet_collection_profile_unlocked',
        'idx_pet_daily_energy_recipient_date',
      }),
    );
  });

  test('第七版迁移只追加本地陪伴三张表与四项查询索引', () {
    expect(
      TrainFlowDatabaseSchema.version7UpgradeStatements,
      contains(contains('CREATE TABLE IF NOT EXISTS companion_messages')),
    );
    expect(
      TrainFlowDatabaseSchema.version7UpgradeStatements,
      contains(contains('CREATE TABLE IF NOT EXISTS companion_events')),
    );
    expect(
      TrainFlowDatabaseSchema.version7UpgradeStatements,
      contains(contains('CREATE TABLE IF NOT EXISTS companion_relationship')),
    );
    expect(
      TrainFlowDatabaseSchema.version7UpgradeStatements.join('\n'),
      isNot(contains('sync_outbox')),
      reason: '陪伴表不得写入云同步队列',
    );
    expect(
      TrainFlowDatabaseSchema.version7UpgradeStatements,
      contains(contains('notifications_enabled INTEGER NOT NULL DEFAULT 0')),
      reason: '搭子系统通知必须由用户单独开启',
    );
    expect(
      TrainFlowDatabaseSchema.requiredIndexes,
      containsAll(<String>{
        'idx_companion_messages_profile_date',
        'idx_companion_messages_profile_variant',
        'idx_companion_messages_profile_intent',
        'idx_companion_events_profile_kind',
      }),
    );
  });

  test('第八版迁移只追加 Coach 治理结构且不接入同步队列', () {
    expect(
      TrainFlowDatabaseSchema.version8CreationStatements,
      contains(contains('CREATE TABLE IF NOT EXISTS coach_state_snapshots')),
    );
    expect(
      TrainFlowDatabaseSchema.version8CreationStatements,
      contains(contains('CREATE TABLE IF NOT EXISTS coach_memories')),
    );
    expect(
      TrainFlowDatabaseSchema.version8CreationStatements,
      contains(contains('CREATE TABLE IF NOT EXISTS coach_memory_sources')),
    );
    expect(
      TrainFlowDatabaseSchema.version8CreationStatements,
      contains(contains('CREATE TABLE IF NOT EXISTS coach_turn_traces')),
    );
    expect(
      TrainFlowDatabaseSchema.version8UpgradeStatements.join('\n'),
      isNot(contains('sync_outbox')),
    );
    expect(
      TrainFlowDatabaseSchema.version8AddedColumnStatements,
      contains(contains("message_role TEXT NOT NULL DEFAULT 'companion'")),
    );
    expect(
      TrainFlowDatabaseSchema.requiredIndexes,
      containsAll(<String>{
        'idx_coach_snapshots_profile_validity',
        'idx_coach_memories_profile_status_validity',
        'idx_coach_memory_sources_memory',
        'idx_coach_traces_profile_created',
      }),
    );
  });

  test('第八版加列迁移按实际列补缺并兼容旧版回写版本号', () {
    final List<String> freshUpgrade =
        TrainFlowDatabaseSchema.pendingVersion8AddedColumnStatements(
            const <String>{});
    expect(
      freshUpgrade,
      TrainFlowDatabaseSchema.version8AddedColumnStatements,
    );

    final List<String> reopenedUpgrade =
        TrainFlowDatabaseSchema.pendingVersion8AddedColumnStatements(
      TrainFlowDatabaseSchema.version8AddedColumnNames.toSet(),
    );
    expect(reopenedUpgrade, isEmpty);

    final List<String> partialUpgrade = TrainFlowDatabaseSchema
        .pendingVersion8AddedColumnStatements(const <String>{
      'message_role',
      'thread_id',
      'turn_id',
    });
    expect(partialUpgrade, hasLength(4));
    expect(partialUpgrade.join('\n'), isNot(contains('ADD COLUMN turn_id')));
    expect(
      partialUpgrade.join('\n'),
      contains('ADD COLUMN verification_state'),
    );
  });
}
