import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:trainflow_ai/data/local/trainflow_database_schema.dart';

void main() {
  test('第八版完整建表语句可重复执行并通过 SQLite 完整性检查', () async {
    final ProcessResult lookup =
        await Process.run('which', <String>['sqlite3']);
    if (lookup.exitCode != 0) {
      // 项目未新增 FFI 测试依赖；没有系统 SQLite 的环境由结构测试继续兜底。
      return;
    }
    final String executable = (lookup.stdout as String).trim();
    final Directory directory =
        await Directory.systemTemp.createTemp('trainmate-schema-sqlite-');
    addTearDown(() => directory.delete(recursive: true));
    final String databasePath = p.join(directory.path, 'trainflow.db');
    final Process process = await Process.start(
      executable,
      <String>[databasePath],
    );
    process.stdin.writeln('PRAGMA foreign_keys = ON;');
    for (int pass = 0; pass < 2; pass += 1) {
      for (final String statement
          in TrainFlowDatabaseSchema.creationStatements) {
        process.stdin.writeln('$statement;');
      }
    }
    process.stdin.writeln('PRAGMA foreign_key_check;');
    process.stdin.writeln('PRAGMA quick_check;');
    await process.stdin.close();
    final String stdout =
        await process.stdout.transform(const SystemEncoding().decoder).join();
    final String stderr =
        await process.stderr.transform(const SystemEncoding().decoder).join();
    final int exitCode = await process.exitCode;

    expect(exitCode, 0, reason: stderr);
    expect(stderr, isEmpty);
    expect(stdout.trim().split('\n').last, 'ok');
  });

  test('脱敏第二版旧库升级到第八版时保留原档案并留下可恢复备份', () async {
    final ProcessResult lookup =
        await Process.run('which', <String>['sqlite3']);
    if (lookup.exitCode != 0) return;
    final String executable = (lookup.stdout as String).trim();
    final Directory directory =
        await Directory.systemTemp.createTemp('trainmate-v2-upgrade-');
    addTearDown(() => directory.delete(recursive: true));
    final String databasePath = p.join(directory.path, 'trainflow.db');

    final Process createProcess = await Process.start(
      executable,
      <String>[databasePath],
    );
    createProcess.stdin.writeln('.bail on');
    createProcess.stdin.writeln('PRAGMA foreign_keys = ON;');
    final int version2StatementCount =
        TrainFlowDatabaseSchema.creationStatements.length -
            TrainFlowDatabaseSchema.version3UpgradeStatements.length -
            TrainFlowDatabaseSchema.version4CreationStatements.length -
            TrainFlowDatabaseSchema.version5UpgradeStatements.length -
            TrainFlowDatabaseSchema.version6UpgradeStatements.length -
            TrainFlowDatabaseSchema.version7UpgradeStatements.length -
            TrainFlowDatabaseSchema.version8CreationStatements.length;
    for (final String statement in TrainFlowDatabaseSchema.creationStatements
        .take(version2StatementCount)) {
      createProcess.stdin.writeln(
        '${statement.replaceFirst('  birth_date TEXT,\n', '')};',
      );
    }
    createProcess.stdin.writeln('PRAGMA user_version = 2;');
    createProcess.stdin.writeln('''
INSERT INTO athlete_profiles(
  id, name, payload_json, created_at, updated_at
) VALUES (
  'fixture-athlete', '脱敏旧用户', '{"profileCompleted":true}',
  '2026-07-01T00:00:00.000Z', '2026-07-01T00:00:00.000Z'
);
INSERT INTO legacy_documents(
  storage_key, payload_json, migrated_at, updated_at
) VALUES (
  'trainflow.user_profile.v1', '{"profileCompleted":true}',
  '2026-07-01T00:00:00.000Z', '2026-07-01T00:00:00.000Z'
);
''');
    await createProcess.stdin.close();
    final String createError = await createProcess.stderr
        .transform(const SystemEncoding().decoder)
        .join();
    expect(await createProcess.exitCode, 0, reason: createError);

    final File backup = await File(databasePath).copy('$databasePath.v2.bak');
    expect(await backup.length(), greaterThan(0));

    final Process upgradeProcess = await Process.start(
      executable,
      <String>[databasePath],
    );
    upgradeProcess.stdin.writeln('.bail on');
    upgradeProcess.stdin.writeln('.separator |');
    upgradeProcess.stdin.writeln('PRAGMA foreign_keys = ON;');
    upgradeProcess.stdin.writeln('BEGIN IMMEDIATE;');
    for (final String statement
        in TrainFlowDatabaseSchema.version3UpgradeStatements) {
      upgradeProcess.stdin.writeln('$statement;');
    }
    for (final String statement
        in TrainFlowDatabaseSchema.version4UpgradeStatements) {
      upgradeProcess.stdin.writeln('$statement;');
    }
    for (final String statement
        in TrainFlowDatabaseSchema.version5UpgradeStatements) {
      upgradeProcess.stdin.writeln('$statement;');
    }
    for (final String statement
        in TrainFlowDatabaseSchema.version6UpgradeStatements) {
      upgradeProcess.stdin.writeln('$statement;');
    }
    for (final String statement
        in TrainFlowDatabaseSchema.version7UpgradeStatements) {
      upgradeProcess.stdin.writeln('$statement;');
    }
    for (final String statement
        in TrainFlowDatabaseSchema.version8CreationStatements) {
      upgradeProcess.stdin.writeln('$statement;');
    }
    upgradeProcess.stdin.writeln('PRAGMA user_version = 8;');
    upgradeProcess.stdin.writeln('COMMIT;');
    upgradeProcess.stdin.writeln('''
SELECT id, name FROM athlete_profiles WHERE id = 'fixture-athlete';
SELECT storage_key FROM legacy_documents
WHERE storage_key = 'trainflow.user_profile.v1';
SELECT COUNT(*) FROM sqlite_master
WHERE type = 'table' AND name = 'metric_aggregates';
SELECT COUNT(*) FROM sqlite_master
WHERE type = 'table' AND name = 'rhythm_snapshots';
SELECT COUNT(*) FROM pragma_table_info('athlete_profiles')
WHERE name = 'birth_date';
SELECT COUNT(*) FROM sqlite_master
WHERE type = 'table' AND name = 'pet_profile';
SELECT COUNT(*) FROM sqlite_master
WHERE type = 'table' AND name = 'companion_relationship';
SELECT COUNT(*) FROM sqlite_master
WHERE type = 'table' AND name = 'coach_memories';
PRAGMA foreign_key_check;
PRAGMA quick_check;
''');
    await upgradeProcess.stdin.close();
    final String stdout = await upgradeProcess.stdout
        .transform(const SystemEncoding().decoder)
        .join();
    final String stderr = await upgradeProcess.stderr
        .transform(const SystemEncoding().decoder)
        .join();
    final int exitCode = await upgradeProcess.exitCode;

    expect(exitCode, 0, reason: stderr);
    expect(stderr, isEmpty);
    expect(
      stdout.trim().split('\n'),
      <String>[
        'fixture-athlete|脱敏旧用户',
        'trainflow.user_profile.v1',
        '1',
        '1',
        '1',
        '1',
        '1',
        '1',
        'ok',
      ],
    );

    final ProcessResult backupCheck = await Process.run(
      executable,
      <String>[
        backup.path,
        'SELECT COUNT(*) FROM sqlite_master '
            "WHERE type = 'table' AND name = 'metric_aggregates';",
      ],
    );
    expect(backupCheck.exitCode, 0);
    expect(backupCheck.stdout.toString().trim(), '0');
  });

  test('脱敏第五版旧库升级到第八版时保留训练事实且迁移可重复', () async {
    final ProcessResult lookup =
        await Process.run('which', <String>['sqlite3']);
    if (lookup.exitCode != 0) return;
    final String executable = (lookup.stdout as String).trim();
    final Directory directory =
        await Directory.systemTemp.createTemp('trainmate-v5-upgrade-');
    addTearDown(() => directory.delete(recursive: true));
    final String databasePath = p.join(directory.path, 'trainflow.db');

    final Process createProcess = await Process.start(
      executable,
      <String>[databasePath],
    );
    createProcess.stdin.writeln('.bail on');
    createProcess.stdin.writeln('PRAGMA foreign_keys = ON;');
    final int version5StatementCount =
        TrainFlowDatabaseSchema.creationStatements.length -
            TrainFlowDatabaseSchema.version6UpgradeStatements.length -
            TrainFlowDatabaseSchema.version7UpgradeStatements.length -
            TrainFlowDatabaseSchema.version8CreationStatements.length;
    for (final String statement in TrainFlowDatabaseSchema.creationStatements
        .take(version5StatementCount)) {
      createProcess.stdin.writeln('$statement;');
    }
    createProcess.stdin.writeln('PRAGMA user_version = 5;');
    createProcess.stdin.writeln('''
INSERT INTO athlete_profiles(
  id, name, payload_json, created_at, updated_at
) VALUES (
  'fixture-athlete', '脱敏旧用户', '{}',
  '2026-07-31T00:00:00.000Z', '2026-07-31T00:00:00.000Z'
);
INSERT INTO training_logs(
  id, athlete_profile_id, discipline, started_at, duration_minutes,
  completion_percent, payload_json, created_at, updated_at
) VALUES (
  'fixture-training-log', 'fixture-athlete', 'strength',
  '2026-07-31T01:00:00.000Z', 45, 100, '{}',
  '2026-07-31T01:45:00.000Z', '2026-07-31T01:45:00.000Z'
);
''');
    await createProcess.stdin.close();
    final String createError = await createProcess.stderr
        .transform(const SystemEncoding().decoder)
        .join();
    expect(await createProcess.exitCode, 0, reason: createError);

    final Process upgradeProcess = await Process.start(
      executable,
      <String>[databasePath],
    );
    upgradeProcess.stdin.writeln('.bail on');
    upgradeProcess.stdin.writeln('.separator |');
    upgradeProcess.stdin.writeln('PRAGMA foreign_keys = ON;');
    upgradeProcess.stdin.writeln('BEGIN IMMEDIATE;');
    for (int pass = 0; pass < 2; pass += 1) {
      for (final String statement
          in TrainFlowDatabaseSchema.version6UpgradeStatements) {
        upgradeProcess.stdin.writeln('$statement;');
      }
      for (final String statement
          in TrainFlowDatabaseSchema.version7UpgradeStatements) {
        upgradeProcess.stdin.writeln('$statement;');
      }
      for (final String statement
          in TrainFlowDatabaseSchema.version8CreationStatements) {
        upgradeProcess.stdin.writeln('$statement;');
      }
    }
    upgradeProcess.stdin.writeln('PRAGMA user_version = 8;');
    upgradeProcess.stdin.writeln('COMMIT;');
    upgradeProcess.stdin.writeln('''
SELECT id, discipline FROM training_logs
WHERE id = 'fixture-training-log';
SELECT COUNT(*) FROM sqlite_master
WHERE type = 'table' AND name IN (
  'daily_activity_summaries', 'pet_collection', 'pet_profile',
  'pet_daily_energy'
);
SELECT COUNT(*) FROM sqlite_master
WHERE type = 'index' AND name IN (
  'idx_daily_activity_summaries_profile_date',
  'idx_pet_collection_profile_unlocked',
  'idx_pet_daily_energy_recipient_date'
);
SELECT COUNT(*) FROM sqlite_master
WHERE type = 'table' AND name IN (
  'companion_messages', 'companion_events', 'companion_relationship'
);
SELECT COUNT(*) FROM sqlite_master
WHERE type = 'index' AND name IN (
  'idx_companion_messages_profile_date',
  'idx_companion_messages_profile_variant',
  'idx_companion_messages_profile_intent',
  'idx_companion_events_profile_kind'
);
SELECT COUNT(*) FROM sqlite_master
WHERE type = 'table' AND name IN (
  'coach_state_snapshots', 'coach_memories', 'coach_memory_sources',
  'coach_turn_traces'
);
SELECT COUNT(*) FROM sqlite_master
WHERE type = 'index' AND name IN (
  'idx_coach_snapshots_profile_validity',
  'idx_coach_memories_profile_status_validity',
  'idx_coach_memory_sources_memory',
  'idx_coach_traces_profile_created'
);
PRAGMA foreign_key_check;
PRAGMA quick_check;
''');
    await upgradeProcess.stdin.close();
    final String stdout = await upgradeProcess.stdout
        .transform(const SystemEncoding().decoder)
        .join();
    final String stderr = await upgradeProcess.stderr
        .transform(const SystemEncoding().decoder)
        .join();
    final int exitCode = await upgradeProcess.exitCode;

    expect(exitCode, 0, reason: stderr);
    expect(stderr, isEmpty);
    expect(
      stdout.trim().split('\n'),
      <String>[
        'fixture-training-log|strength',
        '4',
        '3',
        '3',
        '4',
        '4',
        '4',
        'ok',
      ],
    );
  });

  test('真实第七版伙伴消息升级到第八版时保留数据并补齐治理列', () async {
    final ProcessResult lookup =
        await Process.run('which', <String>['sqlite3']);
    if (lookup.exitCode != 0) return;
    final String executable = (lookup.stdout as String).trim();
    final Directory directory =
        await Directory.systemTemp.createTemp('trainmate-v7-upgrade-');
    addTearDown(() => directory.delete(recursive: true));
    final String databasePath = p.join(directory.path, 'trainflow.db');
    final Process process = await Process.start(executable, <String>[
      databasePath,
    ]);
    process.stdin.writeln('.bail on');
    process.stdin.writeln('.separator |');
    process.stdin.writeln('PRAGMA foreign_keys = ON;');
    process.stdin.writeln('''
CREATE TABLE athlete_profiles (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE companion_messages (
  message_id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  local_date TEXT NOT NULL,
  intent_id TEXT NOT NULL,
  copy_variant_id TEXT NOT NULL,
  relationship_state TEXT NOT NULL,
  delivery_kind TEXT NOT NULL,
  privacy_level TEXT NOT NULL,
  notification_title TEXT,
  notification_body TEXT,
  body TEXT NOT NULL,
  facts_json TEXT NOT NULL DEFAULT '[]',
  actions_json TEXT NOT NULL DEFAULT '[]',
  scheduled_at TEXT,
  delivered_at TEXT,
  opened_at TEXT,
  action_taken_id TEXT,
  notification_id INTEGER,
  model_version INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE
);
INSERT INTO athlete_profiles(
  id, name, payload_json, created_at, updated_at
) VALUES (
  'athlete-v7', '脱敏用户', '{}',
  '2026-08-11T00:00:00.000Z', '2026-08-11T00:00:00.000Z'
);
INSERT INTO companion_messages(
  message_id, athlete_profile_id, local_date, intent_id, copy_variant_id,
  relationship_state, delivery_kind, privacy_level, body,
  created_at, updated_at
) VALUES (
  'message-v7', 'athlete-v7', '2026-08-11', 'morning_checkin',
  'variant-v7', 'steady', 'proactive', 'l0', '旧伙伴消息',
  '2026-08-11T01:00:00.000Z', '2026-08-11T01:00:00.000Z'
);
PRAGMA user_version = 7;
BEGIN IMMEDIATE;
''');
    for (final String statement
        in TrainFlowDatabaseSchema.version8UpgradeStatements) {
      process.stdin.writeln('$statement;');
    }
    process.stdin.writeln('''
PRAGMA user_version = 8;
COMMIT;
SELECT message_id, body, message_role, thread_id, retention_class,
       verification_state
FROM companion_messages WHERE message_id = 'message-v7';
SELECT COUNT(*) FROM pragma_table_info('companion_messages')
WHERE name IN (
  'message_role', 'thread_id', 'turn_id', 'source_snapshot_id', 'trace_id',
  'retention_class', 'verification_state'
);
SELECT COUNT(*) FROM sqlite_master
WHERE type = 'table' AND name IN (
  'coach_state_snapshots', 'coach_memories', 'coach_memory_sources',
  'coach_turn_traces'
);
PRAGMA foreign_key_check;
PRAGMA quick_check;
''');
    await process.stdin.close();
    final String stdout =
        await process.stdout.transform(const SystemEncoding().decoder).join();
    final String stderr =
        await process.stderr.transform(const SystemEncoding().decoder).join();
    final int exitCode = await process.exitCode;

    expect(exitCode, 0, reason: stderr);
    expect(stderr, isEmpty);
    expect(stdout.trim().split('\n'), <String>[
      'message-v7|旧伙伴消息|companion|default|companion_history|local_only',
      '7',
      '4',
      'ok',
    ]);
  });

  test('删除运动员账号会级联清除四张宠物业务表且不影响其他账号', () async {
    final ProcessResult lookup =
        await Process.run('which', <String>['sqlite3']);
    if (lookup.exitCode != 0) return;
    final String executable = (lookup.stdout as String).trim();
    final Directory directory =
        await Directory.systemTemp.createTemp('trainmate-pet-cascade-');
    addTearDown(() => directory.delete(recursive: true));
    final String databasePath = p.join(directory.path, 'trainflow.db');
    final Process process = await Process.start(
      executable,
      <String>[databasePath],
    );
    process.stdin.writeln('.bail on');
    process.stdin.writeln('.separator |');
    process.stdin.writeln('PRAGMA foreign_keys = ON;');
    for (final String statement in TrainFlowDatabaseSchema.creationStatements) {
      process.stdin.writeln('$statement;');
    }
    process.stdin.writeln('''
INSERT INTO athlete_profiles(
  id, name, payload_json, created_at, updated_at
) VALUES
  ('athlete-a', '账号甲', '{}', '2026-08-01T00:00:00.000Z',
   '2026-08-01T00:00:00.000Z'),
  ('athlete-b', '账号乙', '{}', '2026-08-01T00:00:00.000Z',
   '2026-08-01T00:00:00.000Z');
INSERT INTO pet_collection(
  pet_id, athlete_profile_id, species_id, nickname, unlocked_at, born_at,
  created_at, updated_at
) VALUES
  ('pet-a', 'athlete-a', 'balance_raccoon', '甲伙伴',
   '2026-08-01T00:00:00.000Z', '2026-08-01T00:00:00.000Z',
   '2026-08-01T00:00:00.000Z', '2026-08-01T00:00:00.000Z'),
  ('pet-b', 'athlete-b', 'balance_raccoon', '乙伙伴',
   '2026-08-01T00:00:00.000Z', '2026-08-01T00:00:00.000Z',
   '2026-08-01T00:00:00.000Z', '2026-08-01T00:00:00.000Z');
INSERT INTO pet_profile(
  athlete_profile_id, active_pet_id, first_egg_species_id,
  created_at, updated_at
) VALUES
  ('athlete-a', 'pet-a', 'balance_raccoon',
   '2026-08-01T00:00:00.000Z', '2026-08-01T00:00:00.000Z'),
  ('athlete-b', 'pet-b', 'balance_raccoon',
   '2026-08-01T00:00:00.000Z', '2026-08-01T00:00:00.000Z');
INSERT INTO daily_activity_summaries(
  athlete_profile_id, local_date, time_zone_name, time_zone_offset_minutes,
  field_sources_json, synced_at, updated_at
) VALUES
  ('athlete-a', '2026-08-01', 'Asia/Shanghai', 480, '{}',
   '2026-08-01T00:00:00.000Z', '2026-08-01T00:00:00.000Z'),
  ('athlete-b', '2026-08-01', 'Asia/Shanghai', 480, '{}',
   '2026-08-01T00:00:00.000Z', '2026-08-01T00:00:00.000Z');
INSERT INTO pet_daily_energy(
  athlete_profile_id, local_date, recipient_pet_id, steps_energy,
  stand_energy, exercise_energy, active_energy, training_energy,
  recovery_energy, calculated_total, awarded_total, source_snapshot_json,
  model_version, settled_at, updated_at
) VALUES
  ('athlete-a', '2026-08-01', 'pet-a', 20, 0, 0, 0, 0, 0, 20, 20, '{}', 1,
   '2026-08-01T00:00:00.000Z', '2026-08-01T00:00:00.000Z'),
  ('athlete-b', '2026-08-01', 'pet-b', 20, 0, 0, 0, 0, 0, 20, 20, '{}', 1,
   '2026-08-01T00:00:00.000Z', '2026-08-01T00:00:00.000Z');
DELETE FROM athlete_profiles WHERE id = 'athlete-a';
SELECT
  (SELECT COUNT(*) FROM daily_activity_summaries
   WHERE athlete_profile_id = 'athlete-a'),
  (SELECT COUNT(*) FROM pet_collection
   WHERE athlete_profile_id = 'athlete-a'),
  (SELECT COUNT(*) FROM pet_profile
   WHERE athlete_profile_id = 'athlete-a'),
  (SELECT COUNT(*) FROM pet_daily_energy
   WHERE athlete_profile_id = 'athlete-a');
SELECT
  (SELECT COUNT(*) FROM daily_activity_summaries
   WHERE athlete_profile_id = 'athlete-b'),
  (SELECT COUNT(*) FROM pet_collection
   WHERE athlete_profile_id = 'athlete-b'),
  (SELECT COUNT(*) FROM pet_profile
   WHERE athlete_profile_id = 'athlete-b'),
  (SELECT COUNT(*) FROM pet_daily_energy
   WHERE athlete_profile_id = 'athlete-b');
PRAGMA foreign_key_check;
PRAGMA quick_check;
''');
    await process.stdin.close();
    final String stdout =
        await process.stdout.transform(const SystemEncoding().decoder).join();
    final String stderr =
        await process.stderr.transform(const SystemEncoding().decoder).join();
    final int exitCode = await process.exitCode;

    expect(exitCode, 0, reason: stderr);
    expect(stderr, isEmpty);
    expect(
      stdout.trim().split('\n'),
      <String>['0|0|0|0', '1|1|1|1', 'ok'],
    );
  });

  test('L1 稳定判定主键、计划项外键和人工覆盖可在真实 SQLite 中保留', () async {
    final ProcessResult lookup =
        await Process.run('which', <String>['sqlite3']);
    if (lookup.exitCode != 0) return;
    final String executable = (lookup.stdout as String).trim();
    final Directory directory =
        await Directory.systemTemp.createTemp('trainmate-l1-sqlite-');
    addTearDown(() => directory.delete(recursive: true));
    final String databasePath = p.join(directory.path, 'trainflow.db');
    final Process process = await Process.start(
      executable,
      <String>[databasePath],
    );
    process.stdin.writeln('.bail on');
    process.stdin.writeln('.separator |');
    process.stdin.writeln('PRAGMA foreign_keys = ON;');
    for (final String statement in TrainFlowDatabaseSchema.creationStatements) {
      process.stdin.writeln('$statement;');
    }
    process.stdin.writeln('''
INSERT INTO athlete_profiles(
  id, name, payload_json, created_at, updated_at
) VALUES (
  'athlete-a', '测试运动员', '{}',
  '2026-07-15T09:00:00.000Z', '2026-07-15T09:00:00.000Z'
);
INSERT INTO training_plan_versions(
  id, athlete_profile_id, version_number, starts_on, ends_on, status,
  generation_reason, payload_json, created_at, activated_at
) VALUES (
  'l1-plan:athlete-a', 'athlete-a', 1, '2026-07-13', '2026-07-19',
  'active', 'L1 投影', '{}', '2026-07-15T09:00:00.000Z',
  '2026-07-15T09:00:00.000Z'
);
INSERT INTO scheduled_workouts(
  id, plan_version_id, source_workout_id, title, discipline,
  scheduled_date, week_index, phase, status, estimated_minutes,
  intensity, content_json, created_at, updated_at
) VALUES (
  'l1-scheduled:athlete-a:plan-1', 'l1-plan:athlete-a', 'plan-1',
  '计划跑', 'roadRun', '2026-07-15', 1, 'l1_execution', 'planned',
  60, 'full', '{}', '2026-07-15T09:00:00.000Z',
  '2026-07-15T09:00:00.000Z'
);
INSERT INTO workouts(
  id, athlete_profile_id, external_uuid, source_bundle_id, source_kind,
  discipline, started_at_utc, ended_at_utc, local_date, time_zone_name,
  utc_offset_minutes, elapsed_duration_seconds, heart_rate_sample_count,
  heart_rate_coverage, route_status, payload_json, created_at, updated_at
) VALUES (
  'local-workout:athlete-a:log-1', 'athlete-a', NULL, 'trainmate.local',
  'local_manual', 'roadRun', '2026-07-15T08:00:00.000Z',
  '2026-07-15T09:00:00.000Z', '2026-07-15', 'Asia/Shanghai', 480,
  3600, 0, 0, 'unavailable', '{}', '2026-07-15T09:00:00.000Z',
  '2026-07-15T09:00:00.000Z'
);
INSERT INTO scheduled_workout_results(
  id, athlete_profile_id, scheduled_workout_id, workout_id, system_status,
  system_completion_ratio, manual_override_status, override_reason,
  matching_basis, decided_at, updated_at
) VALUES (
  'local-result:athlete-a:unplanned:log-1', 'athlete-a', NULL,
  'local-workout:athlete-a:log-1', 'notPlanned', NULL, NULL, NULL,
  'match=unplanned', '2026-07-15T09:00:00.000Z',
  '2026-07-15T09:00:00.000Z'
);
BEGIN IMMEDIATE;
DELETE FROM scheduled_workout_results
WHERE athlete_profile_id = 'athlete-a'
  AND workout_id = 'local-workout:athlete-a:log-1'
  AND scheduled_workout_id IS NULL;
INSERT INTO scheduled_workout_results(
  id, athlete_profile_id, scheduled_workout_id, workout_id, system_status,
  system_completion_ratio, manual_override_status, override_reason,
  matching_basis, decided_at, updated_at
) VALUES (
  'local-result:athlete-a:scheduled:plan-1', 'athlete-a',
  'l1-scheduled:athlete-a:plan-1', 'local-workout:athlete-a:log-1',
  'completed', 1, NULL, NULL, 'match=plan_item_id',
  '2026-07-15T09:00:00.000Z', '2026-07-15T09:00:00.000Z'
);
COMMIT;
UPDATE scheduled_workout_results
SET manual_override_status = 'partial',
    override_reason = '用户确认只完成一半',
    updated_at = '2026-07-15T10:00:00.000Z'
WHERE id = 'local-result:athlete-a:scheduled:plan-1';
UPDATE scheduled_workout_results
SET system_status = 'missed',
    system_completion_ratio = 0.2,
    matching_basis = 'match=plan_item_id;recomputed=true',
    decided_at = '2026-07-15T11:00:00.000Z'
WHERE id = 'local-result:athlete-a:scheduled:plan-1';
SELECT id, scheduled_workout_id, system_status, manual_override_status,
       override_reason, updated_at
FROM scheduled_workout_results;
PRAGMA foreign_key_check;
PRAGMA quick_check;
''');
    await process.stdin.close();
    final String stdout =
        await process.stdout.transform(const SystemEncoding().decoder).join();
    final String stderr =
        await process.stderr.transform(const SystemEncoding().decoder).join();
    final int exitCode = await process.exitCode;

    expect(exitCode, 0, reason: stderr);
    expect(stderr, isEmpty);
    expect(
      stdout.trim().split('\n'),
      <String>[
        'local-result:athlete-a:scheduled:plan-1|'
            'l1-scheduled:athlete-a:plan-1|missed|partial|'
            '用户确认只完成一半|2026-07-15T10:00:00.000Z',
        'ok',
      ],
    );

    final ProcessResult duplicate = await Process.run(
      executable,
      <String>[
        '-cmd',
        '.bail on',
        databasePath,
        '''
PRAGMA foreign_keys = ON;
INSERT INTO scheduled_workout_results(
  id, athlete_profile_id, scheduled_workout_id, workout_id, system_status,
  matching_basis, decided_at, updated_at
) VALUES (
  'duplicate-result', 'athlete-a', 'l1-scheduled:athlete-a:plan-1', NULL,
  'pending', 'duplicate', '2026-07-15T12:00:00.000Z',
  '2026-07-15T12:00:00.000Z'
);
''',
      ],
    );
    expect(duplicate.exitCode, isNot(0));
    expect(duplicate.stderr.toString(), contains('UNIQUE constraint failed'));
  });
}
