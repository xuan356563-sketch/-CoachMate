import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/local/database_local_storage_service.dart';
import 'package:trainflow_ai/data/local/trainmate_structured_database_gateway.dart';
import 'package:trainflow_ai/data/local/trainflow_database_gateway.dart';
import 'package:trainflow_ai/data/models/training_metrics.dart';
import 'package:trainflow_ai/data/models/generated_training_plan.dart';
import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/data/models/weekly_report.dart';
import 'package:trainflow_ai/data/repositories/generated_training_plan_repository.dart';
import 'package:trainflow_ai/data/repositories/growth_evidence_repository.dart';
import 'package:trainflow_ai/data/repositories/sqlite_training_metrics_repository.dart';
import 'package:trainflow_ai/data/repositories/training_log_repository.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/data/repositories/weekly_report_repository.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/feature_access.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/plugins/settings/plugin_settings.dart';
import 'package:trainflow_ai/plugins/settings/plugin_settings_repository.dart';
import 'package:trainflow_ai/plugins/sports/built_in_sport_plugins.dart';
import 'package:trainflow_ai/plugins/sports/sport_strategy_plugin.dart';
import 'package:trainflow_ai/services/four_week_plan_generator.dart';

void main() {
  test('正式到同版本注入发行再到正式发行的完整本地数据回滚演练', () async {
    final ProcessResult lookup = await Process.run('which', <String>[
      'sqlite3',
    ]);
    expect(lookup.exitCode, 0, reason: '本次回滚演练需要系统 sqlite3');
    final Directory directory = await Directory.systemTemp.createTemp(
      'trainmate-p7-rollback-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final String databasePath = '${directory.path}/trainflow.db';
    final _SqliteDocumentGateway gateway = await _SqliteDocumentGateway.open(
      databasePath,
    );
    final DatabaseLocalStorageService storage =
        await DatabaseLocalStorageService.create(gateway);
    addTearDown(storage.close);

    final generation = FourWeekPlanGenerator().generate(
      profile: InMemoryUserProfileRepository.defaultProfile,
      startsOn: DateTime(2026, 7, 13),
    );
    final GeneratedTrainingPlanRepository plans =
        GeneratedTrainingPlanRepository(storage);
    plans.savePlan(generation.plan);
    storage.saveJson(GeneratedTrainingPlanRepository.versionsStorageKey, {
      'schemaVersion': 1,
      'activeVersionId': 'legacy-plan-version',
      'versions': [
        {
          'id': 'legacy-plan-version',
          'plan': generation.plan.toJson(),
          'weekPhases': generation.weeks.map((w) => w.phase.jsonValue).toList(),
          'source': GeneratedPlanSource.legacy.jsonValue,
          'createdAt': '2026-07-13T00:00:00.000',
          'activatedAt': '2026-07-13T00:00:00.000',
          'inputDigest': 'legacy-context',
          'compilerVersion': 'legacy',
          'auditSummary': <String, dynamic>{},
        },
      ],
      'activationEvents': <Map<String, dynamic>>[],
    });
    PersistedTrainingLogRepository(storage).saveLog(
      TrainingLog(
        id: 'rollback-log',
        workoutDayId: generation.plan.workoutDays.first.id,
        date: DateTime(2026, 9, 4),
        completed: true,
        rpe: 6,
        fatigueLevel: 4,
        sleepQuality: 8,
        painNote: null,
        userNote: '合成回滚演练日志',
        createdAt: DateTime(2026, 9, 4),
      ),
    );
    PersistedWeeklyReportRepository(storage).saveReport(
      WeeklyReport(
        id: 'compat-report',
        weekLabel: '2026 第 36 周',
        generatedAt: DateTime(2026, 9, 4),
        completedWorkouts: 3,
        plannedWorkouts: 4,
        completionRate: 0.75,
        loadTrendLabel: '稳定',
        decisionReview: '保持节奏',
        recoverySummary: '恢复正常',
        highlights: const <String>[],
        nextWeekFocus: const <String>[],
      ),
    );
    storage.saveJson(PersistedGrowthEvidenceRepository.storageKey, {
      'schemaVersion': 2,
      'events': <Object>[],
      'levelStates': <String, Object>{},
      'weeklyReports': [
        {
          'id': 'growth-report',
          'athleteProfileId': 'account-a',
          'weekKey': '2026-08-31',
          'weekStartsOn': '2026-08-31T00:00:00.000',
          'weekEndsOn': '2026-09-06T00:00:00.000',
          'generatedAt': '2026-09-04T00:00:00.000',
          'lockedAt': null,
          'regeneratedAt': null,
          'consecutiveTrainingDays': 3,
          'runningDistanceKm': 12.0,
          'strengthSessionCount': 2,
          'completionRate': 0.75,
          'trainingLoad': 240.0,
          'growthIndex': 82.0,
          'availableIndexDimensions': 3,
          'recoverySummary': '成长恢复正常',
          'evidenceEventIds': <String>[],
          'modelVersion': 1,
        },
      ],
    });
    storage.saveJson(pluginSettingsStorageKey, {
      'version': 1,
      'enabledOverrides': {
        'goal.fat_loss': false,
        'feature.motion_check': false,
      },
    });
    storage.saveJson('trainflow.account_binding.v1', {'userId': 'account-a'});
    await storage.flush();
    await gateway.insertStructuredFixtures(generation.plan.toJson());

    final String before = await gateway.logicalSnapshot();
    Set<String>? expectedEnabled;
    Map<String, PluginRef>? expectedRefs;
    for (final bool rollback in <bool>[false, true, false]) {
      final PluginRegistry registry = PluginRegistry(
        plugins: builtInDistribution(
          sportPluginFactory:
              rollback ? _sameVersionInjectedSportPlugins : null,
        ),
      );
      final PluginRuntime runtime = PluginRuntime(registry);
      final PluginSettings settings = PluginSettingsRepository(
        storage,
      ).read().settings;
      final Set<String> enabled = settings.enabledIds(registry.descriptors);
      expect((await runtime.initialize(enabledIds: enabled)).isSuccess, isTrue);
      try {
        expectedEnabled ??= registry.enabledIds;
        expect(registry.enabledIds, expectedEnabled);
        expect(runtime.isEnabled('goal.fat_loss'), isFalse);
        expect(runtime.isEnabled('feature.motion_check'), isFalse);
        final Map<String, PluginRef> refs = {
          for (final descriptor in registry.descriptors.values)
            descriptor.id: descriptor.ref,
        };
        expectedRefs ??= refs;
        expect(refs, expectedRefs, reason: '回滚实现必须保持同 ID 同版本');
        expect(runtime.service('support.rehab'), isNotNull);
        expect(
          runtime.contributions.whereType<RouteContribution>().any(
                (contribution) => contribution.path == '/rehab',
              ),
          isTrue,
        );
        expect(plans.getPlan()!.toJson(), generation.plan.toJson());
        expect(plans.getHistory().activeVersion!.pluginRefs, isNull);
        expect(
          PersistedTrainingLogRepository(storage).listLogs().single.id,
          'rollback-log',
        );
        expect(
          PersistedWeeklyReportRepository(storage).listReports().single.id,
          'compat-report',
        );
        expect(
          await PersistedGrowthEvidenceRepository(
            storage,
          ).listWeeklyReports(athleteProfileId: 'account-a'),
          hasLength(1),
        );
        expect(
          await SqliteGrowthEvidenceRepository(
            gateway,
          ).listWeeklyReports(athleteProfileId: 'account-a'),
          hasLength(1),
        );
        expect(
          await SQLiteTrainingMetricsRepository(gateway).listReportRevisions(
            athleteProfileId: 'account-a',
            period: MetricPeriod.week,
            periodStart: DateTime(2026, 8, 31),
          ),
          hasLength(1),
        );
        expect(await gateway.structuredRowCount('training_plan_versions'), 1);
        expect(await gateway.structuredRowCount('training_logs'), 1);
        expect(await gateway.logicalSnapshot(), before);
      } finally {
        final PluginOperationResult stopped = await runtime.shutdown();
        expect(stopped.cleanupErrors, isEmpty);
        runtime.dispose();
        registry.dispose();
      }
      expect(await gateway.logicalSnapshot(), before);
    }

    // 持久化失败必须恢复原设置；数据库的逻辑内容保持逐字节一致。
    gateway.failNextUpsert = true;
    final PluginSettingsReadResult prior = PluginSettingsRepository(
      storage,
    ).read();
    await expectLater(
      PluginSettingsRepository(storage).commit(
        const PluginSettings(enabledOverrides: {'goal.fat_loss': true}),
        previousDocument: prior.rawDocument,
      ),
      throwsA(isA<PluginSettingsPersistenceException>()),
    );
    expect(await gateway.logicalSnapshot(), before);

    // 初始化失败不写本地数据，随后正式发行仍可启动。
    final TrainMatePlugin strength = builtInDistribution().singleWhere(
      (plugin) => plugin.descriptor.id == 'sport.strength',
    );
    final PluginRuntime failedInitialization = PluginRuntime(
      PluginRegistry(
        plugins: builtInDistribution(
          replacements: {
            'sport.strength': _InitializationFailure(strength.descriptor),
          },
        ),
      ),
    );
    expect(
      (await failedInitialization.initialize()).failures,
      contains('sport.strength'),
    );
    await failedInitialization.shutdown();
    failedInitialization.dispose();
    expect(await gateway.logicalSnapshot(), before);

    // 清理失败可在同一运行时重试；不借助整库或 Git 恢复。
    final PluginRuntime cleanupRuntime = PluginRuntime(
      PluginRegistry(plugins: builtInDistribution()),
    );
    expect((await cleanupRuntime.initialize()).isSuccess, isTrue);
    int cleanupAttempts = 0;
    cleanupRuntime.registerCleanup('feature.ai_center', () {
      cleanupAttempts += 1;
      if (cleanupAttempts == 1) throw StateError('合成清理失败');
    });
    expect((await cleanupRuntime.shutdown()).cleanupErrors, hasLength(1));
    expect((await cleanupRuntime.shutdown()).cleanupErrors, isEmpty);
    expect(cleanupAttempts, 2);
    cleanupRuntime.dispose();
    expect(await gateway.logicalSnapshot(), before);

    // 账号 epoch 会拒绝旧异步结果；失败恢复态只可显式重试。
    final PluginRuntime accountRuntime = PluginRuntime(
      PluginRegistry(plugins: builtInDistribution()),
    );
    expect((await accountRuntime.initialize()).isSuccess, isTrue);
    final FeatureOperation oldOperation = accountRuntime.beginOperation(
      'feature.ai_center',
    );
    await expectLater(
      accountRuntime.changeAccountScope(
        replaceScope: () => throw StateError('合成换域失败'),
      ),
      throwsStateError,
    );
    expect(oldOperation.checkActive, throwsStateError);
    expect(accountRuntime.isAccountChanging, isTrue);
    await accountRuntime.changeAccountScope(replaceScope: () async {});
    expect(accountRuntime.isAccountChanging, isFalse);
    expect(oldOperation.checkActive, throwsStateError);
    expect(await gateway.logicalSnapshot(), before);
    await accountRuntime.shutdown();
    accountRuntime.dispose();
  });
}

/// 只模拟同 ID、同版本的发行替换，不保留迁移期旧算法。
List<TrainMatePlugin> _sameVersionInjectedSportPlugins() => [
      for (final plugin in builtInSportPlugins())
        _SameVersionInjectedSportPlugin(plugin.descriptor, plugin.strategy),
    ];

class _SameVersionInjectedSportPlugin extends SportStrategyPlugin {
  _SameVersionInjectedSportPlugin(this.descriptor, super.strategy);

  @override
  final PluginDescriptor descriptor;
}

class _InitializationFailure extends TrainMatePlugin {
  _InitializationFailure(this.descriptor);

  @override
  final PluginDescriptor descriptor;

  @override
  Future<void> initialize(PluginContext context) async {
    throw StateError('合成初始化失败');
  }
}

class _SqliteDocumentGateway
    implements
        TrainFlowDatabaseGateway,
        GrowthDatabaseGateway,
        TrainMateStructuredDatabaseGateway {
  _SqliteDocumentGateway._(this.path);

  final String path;
  bool failNextUpsert = false;

  static Future<_SqliteDocumentGateway> open(String path) async {
    final gateway = _SqliteDocumentGateway._(path);
    await gateway._sql('''
CREATE TABLE legacy_documents(
  storage_key TEXT PRIMARY KEY,
  payload_json TEXT NOT NULL,
  migrated_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE report_revisions(
  id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  report_type TEXT NOT NULL,
  period_key TEXT NOT NULL,
  revision_number INTEGER NOT NULL,
  input_fingerprint TEXT NOT NULL,
  algorithm_version TEXT NOT NULL,
  content_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  supersedes_revision_id TEXT
);
CREATE TABLE training_plan_versions(
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
  activated_at TEXT
);
CREATE TABLE training_logs(
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
  updated_at TEXT NOT NULL
);
CREATE TABLE weekly_reports(
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
  model_version INTEGER NOT NULL DEFAULT 1
);
''');
    return gateway;
  }

  String _quote(String value) => "'${value.replaceAll("'", "''")}'";

  Future<String> _sql(String sql, {bool json = false}) async {
    final ProcessResult result = await Process.run('sqlite3', <String>[
      if (json) '-json',
      path,
      sql,
    ]);
    if (result.exitCode != 0) {
      throw StateError((result.stderr as String).trim());
    }
    return result.stdout as String;
  }

  @override
  Future<Map<String, Map<String, dynamic>>> readAllLegacyDocuments() async {
    final String output = await _sql(
      'SELECT storage_key,payload_json FROM legacy_documents ORDER BY storage_key',
      json: true,
    );
    if (output.trim().isEmpty) return <String, Map<String, dynamic>>{};
    final List<dynamic> rows = jsonDecode(output) as List<dynamic>;
    return <String, Map<String, dynamic>>{
      for (final Map<String, dynamic> row in rows.cast<Map<String, dynamic>>())
        row['storage_key'] as String:
            jsonDecode(row['payload_json'] as String) as Map<String, dynamic>,
    };
  }

  @override
  Future<void> upsertLegacyDocument(
    String key,
    Map<String, dynamic> value,
  ) async {
    if (failNextUpsert) {
      failNextUpsert = false;
      throw StateError('合成 SQLite 写入失败');
    }
    final String now = DateTime.utc(2026, 9, 4).toIso8601String();
    await _sql('''
INSERT INTO legacy_documents(storage_key,payload_json,migrated_at,updated_at)
VALUES(${_quote(key)},${_quote(jsonEncode(value))},${_quote(now)},${_quote(now)})
ON CONFLICT(storage_key) DO UPDATE SET
payload_json=excluded.payload_json,updated_at=excluded.updated_at;
''');
  }

  @override
  Future<void> deleteLegacyDocument(String key) async {
    await _sql('DELETE FROM legacy_documents WHERE storage_key=${_quote(key)}');
  }

  @override
  Future<void> clearLegacyDocuments({
    Set<String> preservedKeys = const {},
  }) async {
    final String predicate = preservedKeys.isEmpty
        ? ''
        : ' WHERE storage_key NOT IN (${preservedKeys.map(_quote).join(',')})';
    await _sql('DELETE FROM legacy_documents$predicate');
  }

  @override
  Future<void> replaceBusinessDataAtomically({
    Set<String> preservedKeys = const {},
    Map<String, Map<String, dynamic>> replacementDocuments = const {},
  }) async {
    final String predicate = preservedKeys.isEmpty
        ? ''
        : ' AND storage_key NOT IN (${preservedKeys.map(_quote).join(',')})';
    final StringBuffer sql = StringBuffer('BEGIN;')
      ..write(
        "DELETE FROM legacy_documents WHERE storage_key LIKE 'trainflow.%'$predicate;",
      );
    for (final entry in replacementDocuments.entries) {
      final String now = DateTime.utc(2026, 9, 4).toIso8601String();
      sql.write(
        'INSERT OR REPLACE INTO legacy_documents(storage_key,payload_json,migrated_at,updated_at) VALUES(${_quote(entry.key)},${_quote(jsonEncode(entry.value))},${_quote(now)},${_quote(now)});',
      );
    }
    sql.write('COMMIT;');
    await _sql(sql.toString());
  }

  Future<void> insertStructuredFixtures(Map<String, dynamic> plan) => _sql('''
INSERT INTO training_plan_versions VALUES(
  'structured-plan','account-a',NULL,NULL,NULL,1,'2026-07-13','2026-08-09',
  'active','rollback-drill',${_quote(jsonEncode(plan))},
  '2026-07-13T00:00:00.000','2026-07-13T00:00:00.000'
);
INSERT INTO training_logs VALUES(
  'structured-log','account-a',NULL,'strength','2026-09-04T00:00:00.000',
  '2026-09-04T00:45:00.000',45,100,6,NULL,'合成结构化日志',
  '{"source":"rollback-drill"}','2026-09-04T00:00:00.000',
  '2026-09-04T00:45:00.000'
);
INSERT INTO weekly_reports VALUES(
  'growth-report','account-a','2026-08-31','2026-08-31','2026-09-06',
  0.75,240,'成长恢复正常',
  '{"consecutiveTrainingDays":3,"runningDistanceKm":12.0,"strengthSessionCount":2,"completionRate":0.75,"trainingLoad":240.0,"growthIndex":82.0,"availableIndexDimensions":3,"recoverySummary":"成长恢复正常","evidenceEventIds":[],"generatedAt":"2026-09-04T00:00:00.000"}',
  '2026-09-04T00:00:00.000','2026-09-04T00:00:00.000',NULL,NULL,1
);
INSERT INTO report_revisions VALUES(
  'structured-report','account-a','week','2026-08-31T00:00:00.000',1,'fingerprint','v1',
  '{"metricIds":[],"narrative":"结构化周报"}',
  '2026-09-04T00:00:00.000',NULL
);
''');

  Future<int> structuredRowCount(String table) async =>
      int.parse((await _sql('SELECT COUNT(*) FROM $table')).trim());

  Future<List<Map<String, Object?>>> _rows(
    String table, {
    String? where,
    String orderBy = 'id',
  }) async {
    final String output = await _sql(
      'SELECT * FROM $table${where == null ? '' : ' WHERE $where'} ORDER BY $orderBy',
      json: true,
    );
    if (output.trim().isEmpty) return <Map<String, Object?>>[];
    return (jsonDecode(output) as List<dynamic>)
        .map((item) => Map<String, Object?>.from(item as Map))
        .toList(growable: false);
  }

  @override
  Future<List<Map<String, Object?>>> listWeeklyGrowthReportRows({
    required String athleteProfileId,
    required int limit,
    required int offset,
  }) async =>
      (await _rows(
        'weekly_reports',
        where: 'athlete_profile_id=${_quote(athleteProfileId)}',
        orderBy: 'week_starts_on DESC',
      ))
          .skip(offset)
          .take(limit)
          .toList(growable: false);

  @override
  Future<List<Map<String, Object?>>> listReportRevisionRows({
    required String athleteProfileId,
    required String reportType,
    required String periodKey,
  }) =>
      _rows(
        'report_revisions',
        where: 'athlete_profile_id=${_quote(athleteProfileId)} AND '
            'report_type=${_quote(reportType)} AND '
            'period_key=${_quote(periodKey)}',
        orderBy: 'revision_number DESC',
      );

  Future<String> logicalSnapshot() async {
    final StringBuffer snapshot = StringBuffer();
    for (final String table in <String>[
      'legacy_documents',
      'training_plan_versions',
      'training_logs',
      'weekly_reports',
      'report_revisions',
    ]) {
      snapshot
        ..writeln(table)
        ..writeln(
          jsonEncode(
            await _rows(
              table,
              orderBy: table == 'legacy_documents' ? 'storage_key' : 'id',
            ),
          ),
        );
    }
    return snapshot.toString();
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(TrainFlowDatabaseTransaction transaction) action,
  ) {
    throw UnsupportedError('演练不调用迁移事务');
  }

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
