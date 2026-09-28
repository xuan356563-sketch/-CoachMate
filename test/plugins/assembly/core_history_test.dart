import 'package:trainflow_ai/data/models/user_profile.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/plugins/history/core_history.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/data/models/training_metrics.dart';
import 'package:trainflow_ai/data/repositories/training_metrics_repository.dart';
import 'package:trainflow_ai/data/repositories/generated_training_plan_repository.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/data/repositories/growth_evidence_repository.dart';
import 'package:trainflow_ai/services/four_week_plan_generator.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('关闭计划后读取两个旧版本与训练日不产生任何历史补写', () async {
    final storage = _CountingStorage();
    final plan = FourWeekPlanGenerator()
        .generate(
            profile: InMemoryUserProfileRepository.defaultProfile,
            startsOn: DateTime(2026, 7, 13))
        .plan;
    storage.saveJson(GeneratedTrainingPlanRepository.versionsStorageKey, {
      'activeVersionId': 'version-2',
      'versions': [
        for (final id in ['version-1', 'version-2'])
          {
            'id': id,
            'plan': plan.toJson(),
            'weekPhases': <String>[],
            'source': 'local_template',
            'createdAt': '2026-07-13T00:00:00',
            'activatedAt': '2026-07-13T00:00:00',
            'inputDigest': 'historical',
            'compilerVersion': '1.0.0',
            'pluginRefs': [
              {'id': 'support.rehab', 'version': '1.0.0'}
            ],
            'auditSummary': {
              'passCount': 1,
              'warningCount': 0,
              'blockingReasons': <String>[]
            },
          }
      ],
      'activationEvents': <Object>[],
    });
    final before = jsonEncode(
        storage.readJson(GeneratedTrainingPlanRepository.versionsStorageKey));
    final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
    addTearDown(container.dispose);
    final runtime = container.read(pluginRuntimeProvider);
    await runtime.initialize();
    expect(runtime.checkDisable('sport.hyrox').join(), contains('主运动或次运动'));
    PersistedUserProfileRepository(storage).saveProfile(
        InMemoryUserProfileRepository.defaultProfile
            .copyWith(mainSports: [MainSport.strength]));
    expect(runtime.checkDisable('sport.hyrox').join(), contains('有效计划'));
    expect(runtime.checkDisable('support.rehab').join(), contains('有效计划'));
    expect(runtime.checkDisable('feature.training_plan'), isEmpty);
    await runtime.disable('feature.training_plan');
    final writes = storage.writes;
    final history = container.read(coreHistoryProvider);
    expect(history.getPlanHistory().versions, hasLength(2));
    expect(history.getPlanVersion('version-1')!.plan.workoutDays, isNotEmpty);
    expect(history.listLogs(), isEmpty);
    expect(history.listWeeklyReports(), isEmpty);
    expect(history.listSchedule(), isEmpty);
    expect(await history.listGrowthReports(athleteProfileId: 'test'), isEmpty);
    expect(storage.writes, writes);
    expect(
        jsonEncode(storage
            .readJson(GeneratedTrainingPlanRepository.versionsStorageKey)),
        before);
    final old = history;
    await runtime.changeAccountScope();
    expect(old.listLogs, throwsStateError);
    expect(container.read(coreHistoryProvider).listLogs(), isEmpty);
    await runtime.registry.shutdown();
  });
  test('异步历史查询账号变化后不交付旧账号结果', () async {
    final storage = InMemoryLocalStorageService();
    final metrics = _DelayedMetrics();
    var active = true;
    final history = CoreHistory(
        storage: storage,
        metrics: metrics,
        growth: PersistedGrowthEvidenceRepository(storage),
        checkScope: () {
          if (!active) throw StateError('账户已切换');
        });
    final pending = history.listReportRevisions(
        athleteProfileId: 'test',
        period: MetricPeriod.week,
        periodStart: DateTime(2024, 1, 1));
    active = false;
    final assertion = expectLater(pending, throwsStateError);
    metrics.result.complete([]);
    await assertion;
  });
}

class _CountingStorage extends InMemoryLocalStorageService {
  int writes = 0;
  @override
  void saveJson(String key, Map<String, dynamic> value) {
    writes++;
    super.saveJson(key, value);
  }

  @override
  void remove(String key) {
    writes++;
    super.remove(key);
  }
}

class _DelayedMetrics extends InMemoryTrainingMetricsRepository {
  final result = Completer<List<ReportRevision>>();
  @override
  Future<List<ReportRevision>> listReportRevisions(
          {required String athleteProfileId,
          required MetricPeriod period,
          required DateTime periodStart}) =>
      result.future;
}
