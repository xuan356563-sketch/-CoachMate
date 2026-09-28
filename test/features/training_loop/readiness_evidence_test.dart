import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/body_metric.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/models/weekly_report.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/data/repositories/daily_context_repository.dart';
import 'package:trainflow_ai/data/seed/seed_training_plans.dart';
import 'package:trainflow_ai/features/daily_adjustment/application/daily_adjustment_controller.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/services/readiness_evidence_service.dart';
import 'package:trainflow_ai/services/weekly_report_service.dart';
import 'package:trainflow_ai/services/user_insight_service.dart';
import 'package:trainflow_ai/services/body_metric_snapshot_service.dart';
import 'package:trainflow_ai/data/local/cloud_sync_projection_builder.dart';
import 'package:trainflow_ai/data/models/user_insight.dart';
import '../resource_library/local_plan_test.dart' show LocalFixture;
import '../resource_library/assessment_test.dart' show FailStorage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('倒计时不能自证预测命中，本地证据和调整文档不产生云变更', () {
    final prediction = UserInsightService().buildPredictionLogs(
      recommendedRecoveryHours: 24, remainingRecoveryHours: 0,
      hasLatestLog: false, latestLog: null, bodyMetrics: []).single;
    expect(prediction.status, PredictionStatus.pending);
    expect(prediction.predictedValue, contains('无法评估'));
    for (final key in ['trainflow.daily_context.v1', 'trainflow.plan_adjustments.v1',
      'trainflow.weekly_reports.v1', 'trainflow.body_metrics.v1']) {
      expect(CloudSyncProjectionBuilder.build(changedKey: key,
          previousDocuments: {}, currentDocuments: {key: {'schemaVersion': 1, 'test': '仅本机证据'}}), isEmpty);
    }
  });
  final now = DateTime(2026, 9, 13, 12);
  final profile = InMemoryUserProfileRepository.defaultProfile.copyWith(
      weeklyTrainingDays: 2,
      dailyAvailableMinutes: 30,
      injuryHistory: [],
      workScheduleType: WorkScheduleType.regularOffice);
  BodyMetric metric({Map<String, dynamic> changes = const {}}) =>
      BodyMetric.fromJson({
        'id': 'synthetic',
        'measuredAt': now.toIso8601String(),
        'source': 'manual',
        'sleepHours': 8.0,
        'fatigueLevel': 2,
        ...changes,
      });
  ReadinessEvidence assess(BodyMetric m, {DateTime? confirmedAt}) =>
      const ReadinessEvidenceService().evaluate(
          profile: profile,
          metrics: [m],
          pain: null,
          now: now,
          confirmedAt: confirmedAt);

  test('缺少心率和 HRV 不按零扣分，使用原公式且展示输入', () {
    final result = assess(metric(), confirmedAt: now);
    expect(result.score, 69);
    expect(result.missing, ['HRV', '静息心率']);
    expect(result.explanation, contains('工程估算'));
    expect(assess(metric(changes: {'hrvMs': 40}), confirmedAt: now).score, 63);
    expect(
        assess(metric(changes: {'sleepHours': 5.0, 'fatigueLevel': 8}),
                confirmedAt: now)
            .score,
        53);
  });
  test('未确认、旧日、未来、未知来源和缺失主观输入均无法评估', () {
    expect(assess(metric()).score, isNull);
    expect(
        assess(metric(), confirmedAt: now.subtract(const Duration(days: 1)))
            .score,
        isNull);
    for (final changes in [
      {'source': 'other'},
      {'sourceVerified': false},
      {'sleepHours': 0},
      {
        'recordedFields': ['sleepHours']
      },
      {'measuredAt': now.add(const Duration(minutes: 1)).toIso8601String()},
      {'measuredAt': now.subtract(const Duration(days: 1)).toIso8601String()},
    ]) {
      expect(assess(metric(changes: changes), confirmedAt: now).score, isNull);
    }
  });
  test('缺失字段重启后仍缺失，未知旧来源保留可读但不可用', () {
    final partial = metric();
    final restored = BodyMetric.fromJson(partial.toJson());
    expect(restored.hasValue('hrvMs'), isFalse);
    expect(restored.hasValue('sorenessLevel'), isFalse);
    expect(restored.hasValue('fatigueLevel'), isTrue);
    final unknown = metric(changes: {'source': null});
    expect(unknown.sleepHours, 8);
    expect(
        BodyMetric.fromJson(unknown.toJson()).hasValue('sleepHours'), isFalse);
  });
  test('截图继承的旧字段不作为本次观测', () {
    final result = BodyMetricSnapshotRecognitionService()
        .recognize('体重 70', fallback: metric());
    expect(result.metric.hasValue('sleepHours'), isFalse);
    expect(result.metric.hasValue('fatigueLevel'), isFalse);
  });
  test('空周报及洞察不输出恢复正常和默认置信度', () {
    final report = WeeklyReportService().buildWeeklyReport(
        profile: profile,
        todayWorkout: seedTrainingPlans.first.workoutDays.first,
        logs: [],
        bodyMetrics: [],
        readinessScore: null,
        trainingStatusLabel: '无法评估',
        trainingStatusReason: '缺少记录',
        recoveryCountdownLabel: '',
        recoveryAdvice: '',
        achievementSummaryLabel: '',
        evaluatedAt: now);
    expect(report.recoverySummary, contains('无法评估'));
    expect(report.loadTrendLabel, contains('无法评估'));
    expect(WeeklyReport.fromJson(report.toJson()).psychRiskLabel, '无法评估');
    expect(report.realityObservation, contains('0'));
    final insights = UserInsightService().buildInsights(
        profile: profile,
        logs: [],
        bodyMetrics: [],
        painLogs: [],
        importedWorkouts: [],
        starterProgramStreak: 0,
        readinessScore: null,
        trainingStatusLabel: '无法评估');
    final recovery = insights.firstWhere((i) => i.id == 'physiology-recovery');
    expect(recovery.confidence, 0);
    expect(recovery.conclusion, contains('无法评估'));
  });
  test('今日确认持久化失败不更新，重启可读且不修改计划', () async {
    final storage = FailStorage();
    final f = await LocalFixture.create(storage: storage);
    addTearDown(f.close);
    final controller =
        f.container.read(dailyAdjustmentControllerProvider.notifier);
    final before = f.container.read(trainingMvpProvider).activePlan.toJson();
    storage.fail = true;
    await expectLater(controller.confirmTodayStatus(), throwsStateError);
    expect(
        f.container
            .read(dailyAdjustmentControllerProvider)
            .context
            .statusConfirmedAt,
        isNull);
    await controller.confirmTodayStatus();
    expect(
        PersistedDailyContextRepository(storage).getContext().statusConfirmedAt,
        isNotNull);
    expect(f.container.read(trainingMvpProvider).activePlan.toJson(), before);
  });
}
