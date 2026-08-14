class TrainFlowDatabaseSchema {
  const TrainFlowDatabaseSchema._();

  static const String databaseName = 'trainflow.db';
  static const int version = 8;

  static const Set<String> requiredTables = <String>{
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
  };

  static const Set<String> requiredIndexes = <String>{
    'idx_workouts_external_uuid',
    'idx_workouts_route_external_uuid',
    'idx_workouts_profile_started_at',
    'idx_health_observations_external_uuid',
    'idx_health_observations_profile_kind_time',
    'idx_health_sync_runs_profile_started_at',
    'idx_scheduled_workout_results_plan_item',
    'idx_strength_sets_workout',
    'idx_workout_analysis_runs_workout',
    'idx_metric_aggregates_period',
    'idx_metric_lineage_source',
    'idx_report_revisions_period',
    'idx_adjustment_proposals_profile_status',
    'idx_rhythm_snapshots_profile_week',
    'idx_meal_records_profile_date',
    'idx_sync_outbox_account_state_retry',
    'idx_sync_entity_state_account_type',
    'idx_sync_conflicts_account_status',
    'idx_daily_activity_summaries_profile_date',
    'idx_pet_collection_profile_unlocked',
    'idx_pet_daily_energy_recipient_date',
    'idx_companion_messages_profile_date',
    'idx_companion_messages_profile_variant',
    'idx_companion_messages_profile_intent',
    'idx_companion_events_profile_kind',
    'idx_coach_snapshots_profile_validity',
    'idx_coach_memories_profile_status_validity',
    'idx_coach_memory_sources_memory',
    'idx_coach_traces_profile_created',
  };

  static const List<String> configureStatements = <String>[
    'PRAGMA foreign_keys = ON',
  ];

  /// v2 到 v3 只追加训练事实、同步、指标血缘与审计结构。
  static const List<String> version3UpgradeStatements = <String>[
    '''
CREATE TABLE IF NOT EXISTS workouts (
  id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  external_uuid TEXT,
  source_bundle_id TEXT NOT NULL DEFAULT '',
  source_product_type TEXT,
  source_kind TEXT NOT NULL,
  discipline TEXT NOT NULL,
  run_context TEXT,
  started_at_utc TEXT NOT NULL,
  ended_at_utc TEXT NOT NULL,
  local_date TEXT NOT NULL,
  time_zone_name TEXT NOT NULL,
  utc_offset_minutes INTEGER NOT NULL,
  active_duration_seconds INTEGER,
  elapsed_duration_seconds INTEGER NOT NULL,
  distance_meters REAL,
  energy_kcal REAL,
  elevation_gain_meters REAL,
  average_heart_rate REAL,
  maximum_heart_rate REAL,
  heart_rate_sample_count INTEGER NOT NULL DEFAULT 0,
  heart_rate_coverage REAL NOT NULL DEFAULT 0,
  route_status TEXT NOT NULL DEFAULT 'unavailable',
  route_external_uuid TEXT,
  payload_json TEXT NOT NULL,
  source_deleted_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS health_observations (
  id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  external_uuid TEXT,
  source_bundle_id TEXT NOT NULL DEFAULT '',
  observation_kind TEXT NOT NULL,
  observed_at_utc TEXT NOT NULL,
  local_date TEXT NOT NULL,
  time_zone_name TEXT NOT NULL,
  value REAL NOT NULL,
  unit TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  source_deleted_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS health_sync_runs (
  id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  object_type TEXT NOT NULL,
  query_version INTEGER NOT NULL,
  sync_mode TEXT NOT NULL,
  started_at TEXT NOT NULL,
  completed_at TEXT,
  upsert_count INTEGER NOT NULL DEFAULT 0,
  deleted_count INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL,
  error_message TEXT,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS health_sync_anchors (
  athlete_profile_id TEXT NOT NULL,
  object_type TEXT NOT NULL,
  query_version INTEGER NOT NULL,
  anchor_payload TEXT NOT NULL,
  committed_at TEXT NOT NULL,
  PRIMARY KEY (athlete_profile_id, object_type, query_version),
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS scheduled_workout_results (
  id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  scheduled_workout_id TEXT,
  workout_id TEXT,
  system_status TEXT NOT NULL,
  system_completion_ratio REAL,
  manual_override_status TEXT,
  override_reason TEXT,
  matching_basis TEXT NOT NULL,
  decided_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE,
  FOREIGN KEY (scheduled_workout_id) REFERENCES scheduled_workouts(id)
    ON DELETE SET NULL,
  FOREIGN KEY (workout_id) REFERENCES workouts(id)
    ON DELETE SET NULL
)
''',
    '''
CREATE TABLE IF NOT EXISTS strength_sets (
  id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  workout_id TEXT NOT NULL,
  exercise_key TEXT NOT NULL,
  exercise_name TEXT NOT NULL,
  set_index INTEGER NOT NULL,
  repetitions REAL,
  weight_kg REAL,
  rpe REAL,
  duration_seconds INTEGER,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE,
  FOREIGN KEY (workout_id) REFERENCES workouts(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS athlete_primary_exercises (
  athlete_profile_id TEXT NOT NULL,
  exercise_key TEXT NOT NULL,
  display_name TEXT NOT NULL,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (athlete_profile_id, exercise_key),
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS workout_analysis_runs (
  id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  workout_id TEXT NOT NULL,
  algorithm_version TEXT NOT NULL,
  input_fingerprint TEXT NOT NULL,
  status TEXT NOT NULL,
  quality_json TEXT NOT NULL,
  result_json TEXT NOT NULL,
  started_at TEXT NOT NULL,
  completed_at TEXT,
  invalidated_at TEXT,
  UNIQUE (workout_id, algorithm_version, input_fingerprint),
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE,
  FOREIGN KEY (workout_id) REFERENCES workouts(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS metric_aggregates (
  id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  metric_code TEXT NOT NULL,
  load_method TEXT NOT NULL DEFAULT '',
  period_type TEXT NOT NULL,
  period_start_local TEXT NOT NULL,
  period_end_local TEXT NOT NULL,
  time_zone_name TEXT NOT NULL,
  value REAL,
  unit TEXT NOT NULL,
  sample_count INTEGER NOT NULL DEFAULT 0,
  sample_duration_seconds INTEGER NOT NULL DEFAULT 0,
  coverage REAL NOT NULL DEFAULT 0,
  status TEXT NOT NULL,
  baseline_value REAL,
  algorithm_version TEXT NOT NULL,
  input_fingerprint TEXT NOT NULL,
  computed_at TEXT NOT NULL,
  invalidated_at TEXT,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  UNIQUE (
    athlete_profile_id, metric_code, load_method, period_type,
    period_start_local, algorithm_version
  ),
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS metric_lineage (
  metric_aggregate_id TEXT NOT NULL,
  source_table TEXT NOT NULL,
  source_id TEXT NOT NULL,
  source_fingerprint TEXT NOT NULL DEFAULT '',
  relationship TEXT NOT NULL,
  created_at TEXT NOT NULL,
  invalidated_at TEXT,
  PRIMARY KEY (metric_aggregate_id, source_table, source_id, relationship),
  FOREIGN KEY (metric_aggregate_id) REFERENCES metric_aggregates(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS report_revisions (
  id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  report_type TEXT NOT NULL,
  period_key TEXT NOT NULL,
  revision_number INTEGER NOT NULL,
  input_fingerprint TEXT NOT NULL,
  algorithm_version TEXT NOT NULL,
  content_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  supersedes_revision_id TEXT,
  UNIQUE (athlete_profile_id, report_type, period_key, revision_number),
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE,
  FOREIGN KEY (supersedes_revision_id) REFERENCES report_revisions(id)
    ON DELETE SET NULL
)
''',
    '''
CREATE TABLE IF NOT EXISTS adjustment_proposals (
  id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  trigger_metric_id TEXT,
  trigger_metric_code TEXT NOT NULL,
  plan_id TEXT NOT NULL,
  workout_day_id TEXT,
  workout_title TEXT NOT NULL,
  algorithm_version TEXT NOT NULL,
  status TEXT NOT NULL,
  reason TEXT NOT NULL,
  before_json TEXT NOT NULL,
  proposed_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  confirmed_at TEXT,
  rejected_at TEXT,
  undone_at TEXT,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE,
  FOREIGN KEY (trigger_metric_id) REFERENCES metric_aggregates(id)
    ON DELETE SET NULL
)
''',
    '''
CREATE TABLE IF NOT EXISTS storage_cutover_state (
  id TEXT PRIMARY KEY,
  schema_version INTEGER NOT NULL,
  status TEXT NOT NULL,
  completed_at TEXT NOT NULL,
  CHECK (id = 'local_primary')
)
''',
    '''
CREATE UNIQUE INDEX IF NOT EXISTS idx_workouts_external_uuid
ON workouts(athlete_profile_id, source_bundle_id, external_uuid)
WHERE external_uuid IS NOT NULL
''',
    '''
CREATE INDEX IF NOT EXISTS idx_workouts_profile_started_at
ON workouts(athlete_profile_id, started_at_utc DESC)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_workouts_route_external_uuid
ON workouts(athlete_profile_id, route_external_uuid)
WHERE route_external_uuid IS NOT NULL
''',
    '''
CREATE UNIQUE INDEX IF NOT EXISTS idx_health_observations_external_uuid
ON health_observations(athlete_profile_id, source_bundle_id, external_uuid)
WHERE external_uuid IS NOT NULL
''',
    '''
CREATE INDEX IF NOT EXISTS idx_health_observations_profile_kind_time
ON health_observations(athlete_profile_id, observation_kind, observed_at_utc DESC)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_health_sync_runs_profile_started_at
ON health_sync_runs(athlete_profile_id, started_at DESC)
''',
    '''
CREATE UNIQUE INDEX IF NOT EXISTS idx_scheduled_workout_results_plan_item
ON scheduled_workout_results(athlete_profile_id, scheduled_workout_id)
WHERE scheduled_workout_id IS NOT NULL
''',
    '''
CREATE INDEX IF NOT EXISTS idx_strength_sets_workout
ON strength_sets(workout_id, exercise_key, set_index)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_workout_analysis_runs_workout
ON workout_analysis_runs(workout_id, invalidated_at, completed_at DESC)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_metric_aggregates_period
ON metric_aggregates(
  athlete_profile_id, metric_code, period_type, period_start_local DESC
)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_metric_lineage_source
ON metric_lineage(source_table, source_id)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_report_revisions_period
ON report_revisions(athlete_profile_id, report_type, period_key, revision_number DESC)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_adjustment_proposals_profile_status
ON adjustment_proposals(athlete_profile_id, status, created_at DESC)
''',
  ];

  /// v3 到 v4 增加状态年龄所需生日、每周节奏快照和真实饮食记录。
  static const List<String> version4CreationStatements = <String>[
    '''
CREATE TABLE IF NOT EXISTS rhythm_snapshots (
  id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  week_start TEXT NOT NULL,
  time_zone_name TEXT NOT NULL,
  utc_offset_minutes INTEGER NOT NULL,
  rhythm_speed REAL NOT NULL,
  actual_age REAL,
  state_age REAL,
  factor_json TEXT NOT NULL,
  config_version TEXT NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE (athlete_profile_id, week_start),
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS meal_records (
  id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  local_date TEXT NOT NULL,
  meal_type TEXT NOT NULL,
  summary TEXT NOT NULL,
  created_at TEXT NOT NULL,
  revoked_at TEXT,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE UNIQUE INDEX IF NOT EXISTS idx_rhythm_snapshots_profile_week
ON rhythm_snapshots(athlete_profile_id, week_start)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_meal_records_profile_date
ON meal_records(athlete_profile_id, local_date DESC, revoked_at)
''',
  ];

  static const List<String> version4UpgradeStatements = <String>[
    'ALTER TABLE athlete_profiles ADD COLUMN birth_date TEXT',
    ...version4CreationStatements,
  ];

  /// v4 到 v5 只追加本地优先云同步的 outbox、游标、实体状态和冲突表。
  ///
  /// 迁移不会扫描或上传既有业务数据；用户明确启用后才会创建账号游标状态。
  static const List<String> version5UpgradeStatements = <String>[
    '''
CREATE TABLE IF NOT EXISTS sync_outbox (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL,
  mutation_id TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL,
  base_version INTEGER,
  payload_json TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'pending',
  attempt_count INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TEXT,
  last_error_code TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE (account_id, mutation_id)
)
''',
    '''
CREATE TABLE IF NOT EXISTS sync_cursor (
  account_id TEXT PRIMARY KEY,
  enabled INTEGER NOT NULL DEFAULT 0,
  cursor INTEGER NOT NULL DEFAULT 0,
  snapshot_required INTEGER NOT NULL DEFAULT 1,
  has_existing_local_data INTEGER NOT NULL DEFAULT 0,
  snapshot_applied_at TEXT,
  updated_at TEXT NOT NULL
)
''',
    '''
CREATE TABLE IF NOT EXISTS sync_entity_state (
  account_id TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  cloud_version INTEGER NOT NULL DEFAULT 0,
  local_version INTEGER NOT NULL DEFAULT 0,
  cloud_payload_json TEXT NOT NULL DEFAULT '{}',
  local_payload_json TEXT NOT NULL DEFAULT '{}',
  last_mutation_id TEXT,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (account_id, entity_type, entity_id)
)
''',
    '''
CREATE TABLE IF NOT EXISTS sync_conflicts (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  local_payload_json TEXT NOT NULL,
  cloud_payload_json TEXT NOT NULL,
  cloud_version INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TEXT NOT NULL,
  resolved_at TEXT
)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_sync_outbox_account_state_retry
ON sync_outbox(account_id, state, next_attempt_at, created_at)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_sync_entity_state_account_type
ON sync_entity_state(account_id, entity_type, updated_at)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_sync_conflicts_account_status
ON sync_conflicts(account_id, status, created_at)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_sync_outbox_entity
ON sync_outbox(account_id, entity_type, entity_id, created_at)
''',
  ];

  /// v5 到 v6 只追加每日活动摘要、宠物档案和能量账本。
  static const List<String> version6UpgradeStatements = <String>[
    '''
CREATE TABLE IF NOT EXISTS daily_activity_summaries (
  athlete_profile_id TEXT NOT NULL,
  local_date TEXT NOT NULL,
  time_zone_name TEXT NOT NULL,
  time_zone_offset_minutes INTEGER NOT NULL,
  steps INTEGER,
  step_goal INTEGER,
  active_energy_kcal REAL,
  active_energy_goal_kcal REAL,
  exercise_minutes INTEGER,
  exercise_goal_minutes INTEGER,
  stand_hours INTEGER,
  stand_goal_hours INTEGER,
  field_sources_json TEXT NOT NULL,
  synced_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (athlete_profile_id, local_date),
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS pet_collection (
  pet_id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  species_id TEXT NOT NULL,
  nickname TEXT NOT NULL,
  unlocked_at TEXT NOT NULL,
  born_at TEXT NOT NULL,
  selected_accessory_id TEXT,
  selected_badge_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE (athlete_profile_id, species_id),
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS pet_profile (
  athlete_profile_id TEXT PRIMARY KEY,
  active_pet_id TEXT,
  first_egg_species_id TEXT,
  selected_shell_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE,
  FOREIGN KEY (active_pet_id) REFERENCES pet_collection(pet_id)
    ON DELETE SET NULL
)
''',
    '''
CREATE TABLE IF NOT EXISTS pet_daily_energy (
  athlete_profile_id TEXT NOT NULL,
  local_date TEXT NOT NULL,
  recipient_pet_id TEXT NOT NULL,
  steps_energy INTEGER NOT NULL CHECK (steps_energy >= 0),
  stand_energy INTEGER NOT NULL CHECK (stand_energy >= 0),
  exercise_energy INTEGER NOT NULL CHECK (exercise_energy >= 0),
  active_energy INTEGER NOT NULL CHECK (active_energy >= 0),
  training_energy INTEGER NOT NULL CHECK (training_energy >= 0),
  recovery_energy INTEGER NOT NULL CHECK (recovery_energy >= 0),
  calculated_total INTEGER NOT NULL CHECK (calculated_total BETWEEN 0 AND 160),
  awarded_total INTEGER NOT NULL CHECK (awarded_total BETWEEN 0 AND 160),
  source_snapshot_json TEXT NOT NULL,
  model_version INTEGER NOT NULL,
  settled_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (athlete_profile_id, local_date),
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE,
  FOREIGN KEY (recipient_pet_id) REFERENCES pet_collection(pet_id)
    ON DELETE RESTRICT
)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_daily_activity_summaries_profile_date
ON daily_activity_summaries(athlete_profile_id, local_date DESC)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_pet_collection_profile_unlocked
ON pet_collection(athlete_profile_id, unlocked_at ASC)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_pet_daily_energy_recipient_date
ON pet_daily_energy(recipient_pet_id, local_date DESC)
''',
  ];

  /// v6 到 v7 只追加运动搭子的本地消息、事件与关系设置。
  /// 这些表不接入 sync_outbox，既有训练、健康、计划和宠物表保持只读。
  static const List<String> version7UpgradeStatements = <String>[
    '''
CREATE TABLE IF NOT EXISTS companion_messages (
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
  message_role TEXT NOT NULL DEFAULT 'companion',
  thread_id TEXT NOT NULL DEFAULT 'default',
  turn_id TEXT,
  source_snapshot_id TEXT,
  trace_id TEXT,
  retention_class TEXT NOT NULL DEFAULT 'companion_history',
  verification_state TEXT NOT NULL DEFAULT 'local_only',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS companion_events (
  event_id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  occurred_on TEXT NOT NULL,
  payload_json TEXT NOT NULL DEFAULT '{}',
  is_mentionable INTEGER NOT NULL DEFAULT 1,
  last_mentioned_at TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS companion_relationship (
  athlete_profile_id TEXT PRIMARY KEY,
  companion_name TEXT,
  species_id TEXT NOT NULL DEFAULT 'balance_raccoon',
  started_on TEXT NOT NULL,
  last_resolved_state TEXT NOT NULL DEFAULT 'onboarding',
  state_entered_on TEXT,
  disturb_tier TEXT NOT NULL DEFAULT 'normal',
  quiet_hours_start_minute INTEGER NOT NULL DEFAULT 1320,
  quiet_hours_end_minute INTEGER NOT NULL DEFAULT 420,
  notifications_enabled INTEGER NOT NULL DEFAULT 0,
  notification_detail_enabled INTEGER NOT NULL DEFAULT 0,
  boundaries_json TEXT NOT NULL DEFAULT '[]',
  consecutive_unopened INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_companion_messages_profile_date
ON companion_messages(athlete_profile_id, local_date DESC, created_at DESC)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_companion_messages_profile_variant
ON companion_messages(athlete_profile_id, copy_variant_id, created_at DESC)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_companion_messages_profile_intent
ON companion_messages(athlete_profile_id, intent_id, created_at DESC)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_companion_events_profile_kind
ON companion_events(athlete_profile_id, kind, occurred_on DESC)
''',
  ];

  /// v8 为 Coach 增加可审计训练快照、精选记忆、来源和非内容决策追踪。
  ///
  /// v7 旧库需要先补 companion_messages 列；全新数据库已经由更新后的
  /// v7 建表语句带上这些列，因此只执行下面的幂等建表与索引语句。
  static const List<String> version8AddedColumnStatements = <String>[
    "ALTER TABLE companion_messages ADD COLUMN message_role TEXT NOT NULL DEFAULT 'companion'",
    "ALTER TABLE companion_messages ADD COLUMN thread_id TEXT NOT NULL DEFAULT 'default'",
    'ALTER TABLE companion_messages ADD COLUMN turn_id TEXT',
    'ALTER TABLE companion_messages ADD COLUMN source_snapshot_id TEXT',
    'ALTER TABLE companion_messages ADD COLUMN trace_id TEXT',
    "ALTER TABLE companion_messages ADD COLUMN retention_class TEXT NOT NULL DEFAULT 'companion_history'",
    "ALTER TABLE companion_messages ADD COLUMN verification_state TEXT NOT NULL DEFAULT 'local_only'",
  ];

  static const List<String> version8AddedColumnNames = <String>[
    'message_role',
    'thread_id',
    'turn_id',
    'source_snapshot_id',
    'trace_id',
    'retention_class',
    'verification_state',
  ];

  /// 旧版应用打开 v8 数据库后可能只回写较低的 user_version。
  /// 再次升级时按实际列集合补缺，禁止重复 ALTER 或删除已有数据。
  static List<String> pendingVersion8AddedColumnStatements(
    Set<String> existingColumns,
  ) {
    return <String>[
      for (int index = 0;
          index < version8AddedColumnStatements.length;
          index += 1)
        if (!existingColumns.contains(version8AddedColumnNames[index]))
          version8AddedColumnStatements[index],
    ];
  }

  static const List<String> version8CreationStatements = <String>[
    '''
CREATE TABLE IF NOT EXISTS coach_state_snapshots (
  snapshot_id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  contract_version INTEGER NOT NULL,
  contract_hash TEXT NOT NULL,
  rule_set_version TEXT NOT NULL,
  source_digest TEXT NOT NULL,
  local_date TEXT NOT NULL,
  time_zone_name TEXT NOT NULL,
  generated_at TEXT NOT NULL,
  valid_until TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  missing_fields_json TEXT NOT NULL DEFAULT '[]',
  quality_codes_json TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS coach_memories (
  memory_id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  category TEXT NOT NULL,
  subject TEXT NOT NULL,
  value_json TEXT NOT NULL,
  display_text TEXT NOT NULL,
  confidence_bps INTEGER NOT NULL CHECK(confidence_bps BETWEEN 0 AND 10000),
  importance_bps INTEGER NOT NULL CHECK(importance_bps BETWEEN 0 AND 10000),
  sensitivity TEXT NOT NULL,
  status TEXT NOT NULL,
  version INTEGER NOT NULL CHECK(version >= 1),
  validity_policy TEXT NOT NULL,
  valid_from TEXT NOT NULL,
  valid_until TEXT,
  may_mention INTEGER NOT NULL DEFAULT 0,
  user_confirmed INTEGER NOT NULL DEFAULT 0,
  sync_allowed INTEGER NOT NULL DEFAULT 0,
  confirmation_basis TEXT NOT NULL DEFAULT 'none',
  surfaced_count_30d INTEGER NOT NULL DEFAULT 0,
  superseded_by TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE,
  FOREIGN KEY (superseded_by) REFERENCES coach_memories(memory_id)
    ON DELETE SET NULL
)
''',
    '''
CREATE TABLE IF NOT EXISTS coach_memory_sources (
  source_id TEXT PRIMARY KEY,
  memory_id TEXT NOT NULL,
  source_kind TEXT NOT NULL,
  source_local_id TEXT NOT NULL,
  source_digest TEXT NOT NULL,
  source_summary TEXT,
  observed_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (memory_id) REFERENCES coach_memories(memory_id)
    ON DELETE CASCADE,
  UNIQUE (memory_id, source_kind, source_local_id)
)
''',
    '''
CREATE TABLE IF NOT EXISTS coach_turn_traces (
  trace_id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  turn_id TEXT NOT NULL,
  intent TEXT NOT NULL,
  emotion TEXT NOT NULL,
  snapshot_id TEXT,
  input_digest TEXT NOT NULL,
  local_decision_digest TEXT NOT NULL,
  remote_decision_digest TEXT,
  final_decision_digest TEXT NOT NULL,
  verification_state TEXT NOT NULL,
  reason_codes_json TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE,
  FOREIGN KEY (snapshot_id) REFERENCES coach_state_snapshots(snapshot_id)
    ON DELETE SET NULL,
  UNIQUE (athlete_profile_id, turn_id)
)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_coach_snapshots_profile_validity
ON coach_state_snapshots(athlete_profile_id, valid_until DESC, generated_at DESC)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_coach_memories_profile_status_validity
ON coach_memories(athlete_profile_id, status, valid_until, updated_at DESC)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_coach_memory_sources_memory
ON coach_memory_sources(memory_id, observed_at DESC)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_coach_traces_profile_created
ON coach_turn_traces(athlete_profile_id, created_at DESC)
''',
  ];

  static const List<String> version8UpgradeStatements = <String>[
    ...version8AddedColumnStatements,
    ...version8CreationStatements,
  ];

  static const List<String> creationStatements = <String>[
    '''
CREATE TABLE IF NOT EXISTS athlete_profiles (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  age INTEGER,
  birth_date TEXT,
  biological_sex TEXT,
  height_cm REAL,
  weight_kg REAL,
  experience_level TEXT,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''',
    '''
CREATE TABLE IF NOT EXISTS training_goals (
  id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  discipline TEXT NOT NULL,
  priority TEXT NOT NULL,
  target_summary TEXT NOT NULL,
  target_date TEXT,
  is_active INTEGER NOT NULL DEFAULT 1,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS training_availability (
  id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  weekday INTEGER NOT NULL,
  available_minutes INTEGER NOT NULL,
  preferred_period TEXT,
  is_available INTEGER NOT NULL DEFAULT 1,
  payload_json TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE,
  UNIQUE (athlete_profile_id, weekday)
)
''',
    '''
CREATE TABLE IF NOT EXISTS races (
  id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  name TEXT NOT NULL,
  discipline TEXT NOT NULL,
  race_date TEXT NOT NULL,
  location TEXT,
  priority TEXT,
  current_phase TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS training_plan_versions (
  id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  primary_goal_id TEXT,
  secondary_goal_id TEXT,
  race_id TEXT,
  version_number INTEGER NOT NULL,
  starts_on TEXT NOT NULL,
  ends_on TEXT NOT NULL,
  status TEXT NOT NULL,
  generation_reason TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  activated_at TEXT,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE,
  FOREIGN KEY (primary_goal_id) REFERENCES training_goals(id)
    ON DELETE SET NULL,
  FOREIGN KEY (secondary_goal_id) REFERENCES training_goals(id)
    ON DELETE SET NULL,
  FOREIGN KEY (race_id) REFERENCES races(id)
    ON DELETE SET NULL
)
''',
    '''
CREATE TABLE IF NOT EXISTS scheduled_workouts (
  id TEXT PRIMARY KEY,
  plan_version_id TEXT NOT NULL,
  source_workout_id TEXT,
  title TEXT NOT NULL,
  discipline TEXT NOT NULL,
  scheduled_date TEXT NOT NULL,
  week_index INTEGER NOT NULL,
  phase TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'planned',
  estimated_minutes INTEGER NOT NULL,
  intensity TEXT NOT NULL,
  content_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  started_at TEXT,
  completed_at TEXT,
  FOREIGN KEY (plan_version_id) REFERENCES training_plan_versions(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS training_logs (
  id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  scheduled_workout_id TEXT,
  discipline TEXT NOT NULL,
  started_at TEXT NOT NULL,
  ended_at TEXT,
  duration_minutes INTEGER NOT NULL,
  completion_percent INTEGER NOT NULL,
  session_rpe REAL,
  pain_score INTEGER,
  notes TEXT,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE,
  FOREIGN KEY (scheduled_workout_id) REFERENCES scheduled_workouts(id)
    ON DELETE SET NULL
)
''',
    '''
CREATE TABLE IF NOT EXISTS exercise_execution_records (
  id TEXT PRIMARY KEY,
  training_log_id TEXT NOT NULL,
  exercise_id TEXT NOT NULL,
  exercise_name TEXT NOT NULL,
  sequence_index INTEGER NOT NULL,
  planned_json TEXT NOT NULL,
  actual_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (training_log_id) REFERENCES training_logs(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS health_snapshots (
  id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  captured_at TEXT NOT NULL,
  source TEXT NOT NULL,
  sleep_minutes INTEGER,
  hrv_ms REAL,
  resting_heart_rate REAL,
  fatigue_score INTEGER,
  soreness_score INTEGER,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS pain_logs (
  id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  training_log_id TEXT,
  recorded_at TEXT NOT NULL,
  body_area TEXT NOT NULL,
  score INTEGER NOT NULL,
  notes TEXT,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE,
  FOREIGN KEY (training_log_id) REFERENCES training_logs(id)
    ON DELETE SET NULL
)
''',
    '''
CREATE TABLE IF NOT EXISTS recovery_scores (
  id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  scored_at TEXT NOT NULL,
  score INTEGER NOT NULL,
  level TEXT NOT NULL,
  confidence TEXT NOT NULL,
  factor_json TEXT NOT NULL,
  recommendation TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS plan_adjustments (
  id TEXT PRIMARY KEY,
  plan_version_id TEXT NOT NULL,
  scheduled_workout_id TEXT NOT NULL,
  recovery_score_id TEXT,
  adjustment_type TEXT NOT NULL,
  reason TEXT NOT NULL,
  before_json TEXT NOT NULL,
  after_json TEXT NOT NULL,
  applied_at TEXT NOT NULL,
  undone_at TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (plan_version_id) REFERENCES training_plan_versions(id)
    ON DELETE CASCADE,
  FOREIGN KEY (scheduled_workout_id) REFERENCES scheduled_workouts(id)
    ON DELETE CASCADE,
  FOREIGN KEY (recovery_score_id) REFERENCES recovery_scores(id)
    ON DELETE SET NULL
)
''',
    '''
CREATE TABLE IF NOT EXISTS weekly_reports (
  id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  week_key TEXT NOT NULL,
  week_starts_on TEXT NOT NULL,
  week_ends_on TEXT NOT NULL,
  completion_rate REAL NOT NULL,
  training_load REAL NOT NULL,
  summary TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  locked_at TEXT,
  regenerated_at TEXT,
  model_version INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE,
  UNIQUE (athlete_profile_id, week_starts_on)
)
''',
    '''
CREATE TABLE IF NOT EXISTS growth_evidence_events (
  id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  occurred_at TEXT NOT NULL,
  occurred_on TEXT NOT NULL,
  time_zone_offset_minutes INTEGER NOT NULL DEFAULT 0,
  time_zone_name TEXT NOT NULL DEFAULT '',
  source_table TEXT NOT NULL,
  source_id TEXT NOT NULL,
  evidence_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revoked_at TEXT,
  model_version INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS growth_level_state (
  athlete_profile_id TEXT PRIMARY KEY,
  peak_xp INTEGER NOT NULL DEFAULT 0,
  peak_level INTEGER NOT NULL DEFAULT 1,
  model_version INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS legacy_documents (
  storage_key TEXT PRIMARY KEY,
  payload_json TEXT NOT NULL,
  migrated_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''',
    '''
CREATE TABLE IF NOT EXISTS migration_state (
  migration_id TEXT PRIMARY KEY,
  version INTEGER NOT NULL,
  status TEXT NOT NULL,
  source_document_count INTEGER NOT NULL,
  migrated_document_count INTEGER NOT NULL,
  completed_at TEXT NOT NULL
)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_training_goals_profile_active
ON training_goals(athlete_profile_id, is_active)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_races_date
ON races(race_date)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_scheduled_workouts_date_status
ON scheduled_workouts(scheduled_date, status)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_training_logs_started_at
ON training_logs(started_at DESC)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_health_snapshots_captured_at
ON health_snapshots(captured_at DESC)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_recovery_scores_scored_at
ON recovery_scores(scored_at DESC)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_growth_evidence_occurred_at
ON growth_evidence_events(athlete_profile_id, revoked_at, occurred_at DESC, id DESC)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_growth_evidence_source
ON growth_evidence_events(source_table, source_id)
''',
    '''
CREATE UNIQUE INDEX IF NOT EXISTS idx_weekly_reports_profile_week_key
ON weekly_reports(athlete_profile_id, week_key)
''',
    ...version3UpgradeStatements,
    ...version4CreationStatements,
    ...version5UpgradeStatements,
    ...version6UpgradeStatements,
    ...version7UpgradeStatements,
    ...version8CreationStatements,
  ];

  /// v1 到 v2 只追加列和表；调用方必须在单一 SQLite 事务中执行。
  static const List<String> version2UpgradeStatements = <String>[
    "ALTER TABLE growth_evidence_events ADD COLUMN occurred_on TEXT NOT NULL DEFAULT ''",
    'ALTER TABLE growth_evidence_events ADD COLUMN time_zone_offset_minutes INTEGER NOT NULL DEFAULT 0',
    "ALTER TABLE growth_evidence_events ADD COLUMN time_zone_name TEXT NOT NULL DEFAULT ''",
    'ALTER TABLE growth_evidence_events ADD COLUMN updated_at TEXT',
    'ALTER TABLE growth_evidence_events ADD COLUMN revoked_at TEXT',
    'ALTER TABLE growth_evidence_events ADD COLUMN model_version INTEGER NOT NULL DEFAULT 1',
    "UPDATE growth_evidence_events SET occurred_on = substr(occurred_at, 1, 10) WHERE occurred_on = ''",
    'UPDATE growth_evidence_events SET updated_at = created_at WHERE updated_at IS NULL',
    "ALTER TABLE weekly_reports ADD COLUMN week_key TEXT NOT NULL DEFAULT ''",
    'ALTER TABLE weekly_reports ADD COLUMN locked_at TEXT',
    'ALTER TABLE weekly_reports ADD COLUMN regenerated_at TEXT',
    'ALTER TABLE weekly_reports ADD COLUMN model_version INTEGER NOT NULL DEFAULT 1',
    "UPDATE weekly_reports SET week_key = week_starts_on WHERE week_key = ''",
    '''
CREATE TABLE IF NOT EXISTS growth_level_state (
  athlete_profile_id TEXT PRIMARY KEY,
  peak_xp INTEGER NOT NULL DEFAULT 0,
  peak_level INTEGER NOT NULL DEFAULT 1,
  model_version INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id)
    ON DELETE CASCADE
)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_growth_evidence_occurred_at
ON growth_evidence_events(athlete_profile_id, revoked_at, occurred_at DESC, id DESC)
''',
    '''
CREATE INDEX IF NOT EXISTS idx_growth_evidence_source
ON growth_evidence_events(source_table, source_id)
''',
    '''
CREATE UNIQUE INDEX IF NOT EXISTS idx_weekly_reports_profile_week_key
ON weekly_reports(athlete_profile_id, week_key)
''',
  ];
}
