import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/app/trainflow_app.dart';
import 'package:trainflow_ai/core/theme/tdesign_theme.dart';
import 'package:trainflow_ai/data/models/achievement.dart';
import 'package:trainflow_ai/data/models/body_metric.dart';
import 'package:trainflow_ai/data/models/body_metric_export.dart';
import 'package:trainflow_ai/data/models/daily_adjustment.dart';
import 'package:trainflow_ai/data/models/exercise.dart';
import 'package:trainflow_ai/data/models/formal_ai_plan.dart';
import 'package:trainflow_ai/data/models/imported_workout.dart';
import 'package:trainflow_ai/data/models/knowledge_entry.dart';
import 'package:trainflow_ai/data/models/meal_guide.dart';
import 'package:trainflow_ai/data/models/motion_check.dart';
import 'package:trainflow_ai/data/models/motion_pose.dart';
import 'package:trainflow_ai/data/models/pain_log.dart';
import 'package:trainflow_ai/data/models/plan_adjustment.dart';
import 'package:trainflow_ai/data/models/race.dart';
import 'package:trainflow_ai/data/models/self_use_acceptance.dart';
import 'package:trainflow_ai/data/models/starter_program.dart';
import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/data/models/training_plan.dart';
import 'package:trainflow_ai/data/models/training_rule_audit.dart';
import 'package:trainflow_ai/data/models/user_insight.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/models/weekly_report.dart';
import 'package:trainflow_ai/data/models/weekly_report_export.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/data/models/workout_player_step.dart';
import 'package:trainflow_ai/data/repositories/achievement_repository.dart';
import 'package:trainflow_ai/data/repositories/body_metric_export_repository.dart';
import 'package:trainflow_ai/data/repositories/body_metric_repository.dart';
import 'package:trainflow_ai/data/repositories/formal_ai_plan_repository.dart';
import 'package:trainflow_ai/data/repositories/imported_workout_repository.dart';
import 'package:trainflow_ai/data/repositories/knowledge_repository.dart';
import 'package:trainflow_ai/data/repositories/meal_preference_repository.dart';
import 'package:trainflow_ai/data/repositories/motion_analysis_repository.dart';
import 'package:trainflow_ai/data/repositories/pain_log_repository.dart';
import 'package:trainflow_ai/data/repositories/plan_adjustment_repository.dart';
import 'package:trainflow_ai/data/repositories/race_repository.dart';
import 'package:trainflow_ai/data/repositories/self_use_acceptance_repository.dart';
import 'package:trainflow_ai/data/repositories/starter_program_repository.dart';
import 'package:trainflow_ai/data/repositories/training_log_repository.dart';
import 'package:trainflow_ai/data/repositories/user_insight_repository.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/data/repositories/weekly_report_export_repository.dart';
import 'package:trainflow_ai/data/repositories/weekly_report_repository.dart';
import 'package:trainflow_ai/data/seed/seed_body_metrics.dart';
import 'package:trainflow_ai/data/seed/seed_exercises.dart';
import 'package:trainflow_ai/data/seed/seed_motion_checks.dart';
import 'package:trainflow_ai/data/seed/seed_races.dart';
import 'package:trainflow_ai/data/seed/seed_training_plans.dart';
import 'package:trainflow_ai/services/knowledge_import_service.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/services/daily_adjustment_service.dart';
import 'package:trainflow_ai/services/motion_analysis_service.dart';
import 'package:trainflow_ai/services/motion_pose_analysis_service.dart';
import 'package:trainflow_ai/services/motion_pose_import_service.dart';
import 'package:trainflow_ai/services/exercise_substitution_service.dart';
import 'package:trainflow_ai/services/race_auto_schedule_service.dart';
import 'package:trainflow_ai/services/race_import_service.dart';
import 'package:trainflow_ai/services/training_rule_audit_service.dart';
import 'package:trainflow_ai/services/weekly_report_service.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/exercise_library/exercise_detail_page.dart';
import 'package:trainflow_ai/features/motion_check/motion_check_page.dart';
import 'package:trainflow_ai/features/workout_player/workout_player_page.dart';
import 'package:trainflow_ai/features/self_use_acceptance/self_use_acceptance_page.dart';

void main() {
  test('无器械条件会把结构化训练动作替换为可执行动作', () {
    final WorkoutDay workout = seedTrainingPlans.first.workoutDays.singleWhere(
      (WorkoutDay day) => day.workoutExercises.any(
        (WorkoutExerciseLink link) =>
            link.exerciseId == 'exercise-goblet-squat',
      ),
    );
    final WorkoutSubstitutionResult result =
        ExerciseSubstitutionService().applyNoEquipment(
      workout: workout,
      exercises: seedExercises,
    );

    expect(result.changed, isTrue);
    expect(result.unresolvedExerciseNames, isEmpty);
    expect(
      result.substitutions.any(
        (ExerciseSubstitution item) =>
            item.originalExerciseId == 'exercise-goblet-squat' &&
            item.replacementExerciseId == 'exercise-bodyweight-squat',
      ),
      isTrue,
    );
    expect(
      result.workout.workoutExercises.any(
        (WorkoutExerciseLink link) =>
            link.exerciseId == 'exercise-goblet-squat',
      ),
      isFalse,
    );
    expect(result.workout.coachNotes, contains('无器械替代已生效'));
  });

  test('14 天自用验收仓库会持久化每日记录和阻断问题', () {
    final InMemoryLocalStorageService storageService =
        InMemoryLocalStorageService();
    final PersistedSelfUseAcceptanceRepository repository =
        PersistedSelfUseAcceptanceRepository(storageService);

    final SelfUseAcceptanceRecord started =
        repository.start(DateTime(2026, 7, 10));
    expect(started.days, hasLength(14));
    expect(started.days.first.dayNumber, 1);
    expect(started.days.last.dayNumber, 14);

    SelfUseAcceptanceDay day = started.days.first;
    day = day.copyWith(
      bodyDataLogged: true,
      planReviewed: true,
      workoutExecuted: true,
      feedbackLogged: true,
      starterProgramChecked: true,
      blockingIssue: true,
      notes: '测试阻断问题',
    );
    repository.updateDay(day);

    final PersistedSelfUseAcceptanceRepository restoredRepository =
        PersistedSelfUseAcceptanceRepository(storageService);
    final SelfUseAcceptanceRecord restored = restoredRepository.getRecord();

    expect(restored.completedDayCount, 1);
    expect(restored.blockingDayCount, 1);
    expect(restored.findDay(1)?.notes, '测试阻断问题');
    expect(restored.checklistReady, isFalse);
  });

  test('14 天自用验收不能提前写入未来日期', () {
    final InMemoryLocalStorageService storageService =
        InMemoryLocalStorageService();
    final PersistedSelfUseAcceptanceRepository repository =
        PersistedSelfUseAcceptanceRepository(storageService);
    final SelfUseAcceptanceRecord started = repository.start(DateTime.now());

    repository.updateDay(
      started.days[1].copyWith(
        bodyDataLogged: true,
        planReviewed: true,
        workoutExecuted: true,
        feedbackLogged: true,
        starterProgramChecked: true,
      ),
    );

    expect(repository.getRecord().findDay(2)?.checklistComplete, isFalse);
  });

  testWidgets('14 天自用验收页面可以开始并勾选每日记录', (WidgetTester tester) async {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: TDesignTheme.lightTheme,
          home: const SelfUseAcceptancePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('开始 14 天验收'), findsOneWidget);
    await tester.tap(find.text('开始 14 天验收'));
    await tester.pumpAndSettle();

    expect(find.text('第 1 天'), findsWidgets);
    final ChoiceChip futureDayChip = tester.widget(
      find.widgetWithText(ChoiceChip, '第 14 天'),
    );
    expect(futureDayChip.onSelected, isNull);
    expect(find.text('今日验收记录已保存。'), findsNothing);
    await tester.tap(find.text('早上录入身体数据'));
    await tester.pumpAndSettle();

    final PersistedSelfUseAcceptanceRepository repository =
        PersistedSelfUseAcceptanceRepository(
      container.read(localStorageServiceProvider),
    );
    expect(repository.getRecord().findDay(1)?.bodyDataLogged, isTrue);
  });

  test('30 天引导仓库会持久化 starter_progress', () {
    final InMemoryLocalStorageService storageService =
        InMemoryLocalStorageService();
    final PersistedStarterProgramRepository repository =
        PersistedStarterProgramRepository(storageService: storageService);

    repository.saveProgress(
      const StarterProgramProgress(
        goal: StarterProgramGoal.runningIntro,
        dayIndex: 12,
        streak: 8,
        rescueMode: true,
        statusMessage: '测试 5 分钟补救版',
      ),
    );

    final PersistedStarterProgramRepository restoredRepository =
        PersistedStarterProgramRepository(storageService: storageService);

    expect(
        restoredRepository.getProgress().goal, StarterProgramGoal.runningIntro);
    expect(restoredRepository.getProgress().dayIndex, 12);
    expect(restoredRepository.getProgress().streak, 8);
    expect(restoredRepository.getProgress().rescueMode, isTrue);
    expect(restoredRepository.getProgress().statusMessage, '测试 5 分钟补救版');
    expect(restoredRepository.findDay(StarterProgramGoal.runningIntro, 12).id,
        isNotEmpty);

    restoredRepository.saveProgress(
      const StarterProgramProgress(
        goal: StarterProgramGoal.fatLoss,
        dayIndex: 99,
        streak: 99,
        rescueMode: false,
        statusMessage: '测试范围归一化',
      ),
    );

    final PersistedStarterProgramRepository normalizedRepository =
        PersistedStarterProgramRepository(storageService: storageService);

    expect(normalizedRepository.getProgress().dayIndex, 30);
    expect(normalizedRepository.getProgress().streak, 30);

    normalizedRepository.clearProgress();

    final PersistedStarterProgramRepository clearedRepository =
        PersistedStarterProgramRepository(storageService: storageService);

    expect(clearedRepository.getProgress().goal, StarterProgramGoal.habit);
    expect(clearedRepository.getProgress().dayIndex, 1);
    expect(clearedRepository.getProgress().streak, 0);
  });

  test('正式 AI 计划仓库会持久化 formal_ai_plan', () {
    final InMemoryLocalStorageService storageService =
        InMemoryLocalStorageService();
    final PersistedFormalAiPlanRepository repository =
        PersistedFormalAiPlanRepository(storageService);
    final FormalAiPlan plan = FormalAiPlan(
      id: 'formal-plan-test',
      generatedAt: DateTime(2026, 7, 9, 21),
      title: '测试正式周期',
      goalLabel: '测试目标',
      durationLabel: '4 周正式周期',
      weeklyStructure: '每周 4 天，每次 45 分钟。',
      progressionRule: '每周只增加一个变量。',
      safetyRule: '疼痛 >= 7 停止相关训练。',
      weeklyFocus: const ['第 1 周：测试重点'],
      decisionRules: const ['准备度低于 60 自动降级。'],
    );

    expect(repository.isUnlocked(), isFalse);
    expect(repository.getPlan(), isNull);

    repository.savePlan(plan);

    final PersistedFormalAiPlanRepository restoredRepository =
        PersistedFormalAiPlanRepository(storageService);

    expect(restoredRepository.isUnlocked(), isTrue);
    expect(restoredRepository.getPlan()?.title, '测试正式周期');
    expect(restoredRepository.getPlan()?.generatedDateLabel, '2026-07-09');
    expect(restoredRepository.getPlan()?.weeklyFocus, const ['第 1 周：测试重点']);
    expect(
        restoredRepository.getPlan()?.decisionRules, const ['准备度低于 60 自动降级。']);

    restoredRepository.clearPlan();

    final PersistedFormalAiPlanRepository clearedRepository =
        PersistedFormalAiPlanRepository(storageService);

    expect(clearedRepository.isUnlocked(), isFalse);
    expect(clearedRepository.getPlan(), isNull);
  });

  test('动作分析仓库会持久化 motion_analysis_results 并按时间排序', () {
    final InMemoryLocalStorageService storageService =
        InMemoryLocalStorageService();
    final PersistedMotionAnalysisRepository repository =
        PersistedMotionAnalysisRepository(storageService);
    final MotionAnalysisResult firstResult = MotionAnalysisResult(
      id: 'motion-analysis-test',
      sourceRuleId: 'motion-rule-test',
      type: MotionCheckType.squat,
      title: '测试深蹲分析',
      score: 76,
      riskLevel: MotionRiskLevel.medium,
      capturedAt: DateTime(2026, 7, 8, 20),
      detectedErrors: const ['膝内扣'],
      involvedAreas: const ['膝', '髋'],
      bodyEngineSummary: '测试 Body Engine 解释',
      decisionImpact: '测试决策影响',
      suggestedImpact: TrainingDecisionImpact.deload,
      replacementActions: const ['箱式深蹲'],
      evidenceSources: const [],
    );
    final MotionAnalysisResult updatedResult = MotionAnalysisResult(
      id: firstResult.id,
      sourceRuleId: firstResult.sourceRuleId,
      type: MotionCheckType.squat,
      title: '测试深蹲分析更新',
      score: 82,
      riskLevel: MotionRiskLevel.low,
      capturedAt: DateTime(2026, 7, 9, 20),
      detectedErrors: const ['躯干前倾'],
      involvedAreas: const ['核心'],
      bodyEngineSummary: '更新 Body Engine 解释',
      decisionImpact: '更新决策影响',
      suggestedImpact: TrainingDecisionImpact.keep,
      replacementActions: const ['节奏深蹲'],
      evidenceSources: const [],
    );

    repository.saveResult(firstResult);
    repository.saveResult(updatedResult);

    final PersistedMotionAnalysisRepository restoredRepository =
        PersistedMotionAnalysisRepository(storageService);

    expect(restoredRepository.listResults(), hasLength(1));
    expect(restoredRepository.listResults().first.score, 82);
    expect(restoredRepository.listResults().first.suggestedImpact,
        TrainingDecisionImpact.keep);
    expect(
        restoredRepository.listResults().first.capturedDateLabel, '2026-07-09');

    restoredRepository.clearResults();

    final PersistedMotionAnalysisRepository clearedRepository =
        PersistedMotionAnalysisRepository(storageService);

    expect(clearedRepository.listResults(), isEmpty);
  });

  test('照吃场景仓库会持久化 meal_preference', () {
    final InMemoryLocalStorageService storageService =
        InMemoryLocalStorageService();
    final PersistedMealPreferenceRepository repository =
        PersistedMealPreferenceRepository(storageService);

    expect(repository.getPreference().scenario, MealScenario.takeaway);

    repository.savePreference(
      const MealPreference(scenario: MealScenario.homeCooking),
    );

    final PersistedMealPreferenceRepository restoredRepository =
        PersistedMealPreferenceRepository(storageService);

    expect(
        restoredRepository.getPreference().scenario, MealScenario.homeCooking);

    restoredRepository.clearPreference();

    final PersistedMealPreferenceRepository clearedRepository =
        PersistedMealPreferenceRepository(storageService);

    expect(clearedRepository.getPreference().scenario, MealScenario.takeaway);
  });

  test('身体数据仓库会持久化指标和修订留痕', () {
    final InMemoryLocalStorageService storageService =
        InMemoryLocalStorageService();
    final PersistedBodyMetricRepository repository =
        PersistedBodyMetricRepository(storageService);
    final BodyMetric originalMetric = repository.listMetrics().first;
    final BodyMetric revisedMetric = BodyMetric(
      id: 'body-metric-test-revised',
      measuredAt: originalMetric.measuredAt,
      weightKg: originalMetric.weightKg + 1.2,
      bodyFatPercentage: originalMetric.bodyFatPercentage,
      restingHeartRate: originalMetric.restingHeartRate + 3,
      hrvMs: originalMetric.hrvMs,
      sleepHours: originalMetric.sleepHours,
      fatigueLevel: originalMetric.fatigueLevel,
      sorenessLevel: originalMetric.sorenessLevel,
      moodLabel: '测试修订',
      source: BodyMetricSource.manual,
      note: '测试持久化覆盖',
    );

    repository.saveMetric(revisedMetric, reason: '测试同日覆盖');

    final PersistedBodyMetricRepository restoredRepository =
        PersistedBodyMetricRepository(storageService);

    expect(restoredRepository.listMetrics().first.weightKg,
        revisedMetric.weightKg);
    expect(restoredRepository.listRevisions(), hasLength(1));
    expect(restoredRepository.listRevisions().first.reason, '测试同日覆盖');

    restoredRepository.clearMetrics();

    final PersistedBodyMetricRepository clearedRepository =
        PersistedBodyMetricRepository(storageService);

    expect(clearedRepository.listMetrics(), isEmpty);
    expect(clearedRepository.listRevisions(), isEmpty);
  });

  test('身体数据导出仓库会持久化 JSON CSV 和导出包摘要记录', () {
    final InMemoryLocalStorageService storageService =
        InMemoryLocalStorageService();
    final PersistedBodyMetricExportRepository repository =
        PersistedBodyMetricExportRepository(storageService);
    final BodyMetricExportRecord jsonRecord = BodyMetricExportRecord(
      id: 'body-export-json-test',
      format: BodyMetricExportFormat.json,
      metricCount: 3,
      byteCount: 1024,
      fileName: 'trainflow_body_metrics_json_20260709.json',
      exportedAt: DateTime(2026, 7, 9, 8),
    );
    final BodyMetricExportRecord packageRecord = BodyMetricExportRecord(
      id: 'body-export-package-test',
      format: BodyMetricExportFormat.packageSummary,
      metricCount: 3,
      byteCount: 2048,
      fileName: 'trainflow_body_metrics_package_summary_20260709.txt',
      exportedAt: DateTime(2026, 7, 9, 9),
    );

    repository.saveRecord(jsonRecord);
    repository.saveRecord(packageRecord);

    final PersistedBodyMetricExportRepository restoredRepository =
        PersistedBodyMetricExportRepository(storageService);

    expect(restoredRepository.listRecords(), hasLength(2));
    expect(restoredRepository.listRecords().first.format,
        BodyMetricExportFormat.packageSummary);
    expect(restoredRepository.listRecords().first.sizeLabel, '2.0 KB');
    expect(restoredRepository.listRecords().last.fileName,
        'trainflow_body_metrics_json_20260709.json');

    restoredRepository.clearRecords();

    final PersistedBodyMetricExportRepository clearedRepository =
        PersistedBodyMetricExportRepository(storageService);

    expect(clearedRepository.listRecords(), isEmpty);
  });

  test('计划调整仓库会保留训练日修改与恢复历史', () {
    final InMemoryLocalStorageService storageService =
        InMemoryLocalStorageService();
    final PersistedPlanAdjustmentRepository repository =
        PersistedPlanAdjustmentRepository(storageService);
    final PlanAdjustment adjusted = PlanAdjustment(
      id: 'plan-adjustment-test',
      planId: 'plan-test',
      workoutDayId: 'workout-test',
      workoutTitle: '测试训练日',
      originalEstimatedMinutes: 50,
      adjustedEstimatedMinutes: 35,
      originalIntensity: 'RPE 6',
      adjustedIntensity: 'RPE 4-5',
      reason: '测试午休时间限制',
      kind: PlanAdjustmentKind.adjusted,
      adjustedAt: DateTime(2026, 7, 10, 8),
    );
    final PlanAdjustment restored = PlanAdjustment(
      id: 'plan-restored-test',
      planId: 'plan-test',
      workoutDayId: 'workout-test',
      workoutTitle: '测试训练日',
      originalEstimatedMinutes: 50,
      adjustedEstimatedMinutes: 50,
      originalIntensity: 'RPE 6',
      adjustedIntensity: 'RPE 6',
      reason: '测试恢复原计划',
      kind: PlanAdjustmentKind.restored,
      adjustedAt: DateTime(2026, 7, 10, 9),
    );

    repository.saveAdjustment(adjusted);
    repository.saveAdjustment(restored);

    final PersistedPlanAdjustmentRepository restoredRepository =
        PersistedPlanAdjustmentRepository(storageService);
    final List<PlanAdjustment> records = restoredRepository.listAdjustments();

    expect(records, hasLength(2));
    expect(records.first.kind, PlanAdjustmentKind.restored);
    expect(records.first.isActive, isFalse);
    expect(records.last.adjustedEstimatedMinutes, 35);
  });

  test('周报仓库会持久化最近归档并按周去重', () {
    final InMemoryLocalStorageService storageService =
        InMemoryLocalStorageService();
    final PersistedWeeklyReportRepository repository =
        PersistedWeeklyReportRepository(storageService);
    final WeeklyReport report = WeeklyReport(
      id: 'weekly-report-test',
      weekLabel: '7/6 - 7/12',
      generatedAt: DateTime(2026, 7, 9, 8),
      completedWorkouts: 2,
      plannedWorkouts: 4,
      completionRate: 0.5,
      loadTrendLabel: '维持稳定',
      decisionReview: '测试决策回顾',
      recoverySummary: '测试恢复建议',
      highlights: const ['测试亮点'],
      nextWeekFocus: const ['测试重点'],
    );

    repository.saveReport(report);
    repository.saveReport(
      WeeklyReport(
        id: 'weekly-report-test-updated',
        weekLabel: report.weekLabel,
        generatedAt: DateTime(2026, 7, 9, 9),
        completedWorkouts: 3,
        plannedWorkouts: 4,
        completionRate: 0.75,
        loadTrendLabel: '稳步上升',
        decisionReview: '更新决策回顾',
        recoverySummary: '更新恢复建议',
        highlights: const ['更新亮点'],
        nextWeekFocus: const ['更新重点'],
      ),
    );

    final PersistedWeeklyReportRepository restoredRepository =
        PersistedWeeklyReportRepository(storageService);

    expect(restoredRepository.listReports(), hasLength(1));
    expect(restoredRepository.listReports().first.completionRateLabel, '75%');
    expect(restoredRepository.listReports().first.markdown,
        contains('## TrainFlow AI 周报'));
  });

  test('周报导出仓库会持久化 Markdown 和 PNG 导出记录', () {
    final InMemoryLocalStorageService storageService =
        InMemoryLocalStorageService();
    final PersistedWeeklyReportExportRepository repository =
        PersistedWeeklyReportExportRepository(storageService);
    final WeeklyReportExportRecord markdownRecord = WeeklyReportExportRecord(
      id: 'weekly-export-markdown-test',
      reportId: 'weekly-report-test',
      weekLabel: '7/6 - 7/12',
      format: WeeklyReportExportFormat.markdown,
      byteCount: 1200,
      fileName: 'trainflow_weekly_7_6_7_12.md',
      exportedAt: DateTime(2026, 7, 9, 8),
    );
    final WeeklyReportExportRecord pngRecord = WeeklyReportExportRecord(
      id: 'weekly-export-png-test',
      reportId: 'weekly-report-test',
      weekLabel: markdownRecord.weekLabel,
      format: WeeklyReportExportFormat.png,
      byteCount: 4096,
      fileName: 'trainflow_weekly_7_6_7_12.png',
      exportedAt: DateTime(2026, 7, 9, 9),
    );

    repository.saveRecord(markdownRecord);
    repository.saveRecord(pngRecord);

    final PersistedWeeklyReportExportRepository restoredRepository =
        PersistedWeeklyReportExportRepository(storageService);

    expect(restoredRepository.listRecords(), hasLength(2));
    expect(restoredRepository.listRecords().first.format,
        WeeklyReportExportFormat.png);
    expect(restoredRepository.listRecords().first.sizeLabel, '4.0 KB');
    expect(restoredRepository.listRecords().last.fileName,
        'trainflow_weekly_7_6_7_12.md');

    restoredRepository.clearRecords();

    final PersistedWeeklyReportExportRepository clearedRepository =
        PersistedWeeklyReportExportRepository(storageService);

    expect(clearedRepository.listRecords(), isEmpty);
  });

  test('成就记录仓库会持久化已解锁进度并按定义去重', () {
    final InMemoryLocalStorageService storageService =
        InMemoryLocalStorageService();
    final PersistedAchievementRecordRepository repository =
        PersistedAchievementRecordRepository(storageService);
    const AchievementDefinition definition = AchievementDefinition(
      id: 'achievement-test',
      title: '测试成就',
      description: '用于验证成就记录持久化。',
      category: AchievementCategory.execution,
      targetValue: 1,
    );

    repository.syncUnlockedProgresses(
      const [
        AchievementProgress(
          definition: definition,
          currentValue: 1,
        ),
      ],
    );
    repository.syncUnlockedProgresses(
      const [
        AchievementProgress(
          definition: definition,
          currentValue: 1,
        ),
      ],
    );

    final PersistedAchievementRecordRepository restoredRepository =
        PersistedAchievementRecordRepository(storageService);

    expect(restoredRepository.listRecords(), hasLength(1));
    expect(restoredRepository.listRecords().first.definitionId,
        'achievement-test');
    expect(restoredRepository.listRecords().first.title, '测试成就');

    restoredRepository.clearRecords();

    final PersistedAchievementRecordRepository clearedRepository =
        PersistedAchievementRecordRepository(storageService);

    expect(clearedRepository.listRecords(), isEmpty);
  });

  test('用户画像仓库会持久化三表快照和周度任务', () {
    final InMemoryLocalStorageService storageService =
        InMemoryLocalStorageService();
    final PersistedUserInsightRepository repository =
        PersistedUserInsightRepository(storageService);
    final DateTime capturedAt = DateTime(2026, 7, 9, 8);
    final UserProfile profile = UserProfile(
      id: 'profile-test',
      name: '测试用户',
      gender: Gender.unknown,
      age: 30,
      heightCm: 170,
      weightKg: 65,
      trainingGoal: '测试画像',
      mainSports: const [MainSport.generalFitness],
      weeklyTrainingDays: 3,
      dailyAvailableMinutes: 30,
      injuryHistory: const [],
      workScheduleType: WorkScheduleType.regularOffice,
      createdAt: capturedAt,
      updatedAt: capturedAt,
    );

    repository.saveWeeklySnapshot(
      profile: profile,
      profileEvents: [
        ProfileEvent(
          id: 'profile-event-test',
          type: ProfileEventType.onboarding,
          title: '测试学习信号',
          detail: '测试细节',
          occurredAt: capturedAt,
        ),
      ],
      userProfiles: const [
        UserProfileInsight(
          id: 'insight-test',
          dimension: UserInsightDimension.basic,
          title: '测试画像结论',
          conclusion: '测试结论',
          confidence: 0.7,
          evidenceLabels: ['测试证据'],
          conservativeAction: '测试保守策略',
        ),
      ],
      predictionLogs: [
        PredictionLog(
          id: 'prediction-test',
          predictionType: '测试预测',
          predictedValue: '预计稳定',
          actualValue: null,
          status: PredictionStatus.pending,
          predictedAt: capturedAt,
          dueAt: capturedAt.add(const Duration(days: 1)),
        ),
      ],
    );

    final PersistedUserInsightRepository restoredRepository =
        PersistedUserInsightRepository(storageService);
    final UserInsightTableState restoredState =
        restoredRepository.getTableState();

    expect(restoredState.profileEvents, hasLength(1));
    expect(restoredState.userProfiles, hasLength(1));
    expect(restoredState.predictionLogs, hasLength(1));
    expect(restoredState.weeklyTasks, hasLength(1));
    expect(restoredState.profileSnapshot?.name, '测试用户');
    expect(restoredState.latestWeeklyTask?.profileEventCount, 1);

    restoredRepository.clearSnapshots();

    final PersistedUserInsightRepository clearedRepository =
        PersistedUserInsightRepository(storageService);

    expect(clearedRepository.getTableState().totalTableRows, 0);
    expect(clearedRepository.getTableState().weeklyTasks, isEmpty);
  });

  test('知识库仓库会持久化本地导入书籍和引文', () {
    final InMemoryLocalStorageService storageService =
        InMemoryLocalStorageService();
    final PersistedKnowledgeRepository repository =
        PersistedKnowledgeRepository(storageService);
    final KnowledgeImportResult result = KnowledgeImportService().parse('''
书名：测试训练书
作者：测试作者
领域：跑步,恢复
章节：测试章节
页码：p. 1-3
引文：测试引文内容
适用：用于测试搜索和导入。
''');

    repository.saveImportedEntry(result);

    final PersistedKnowledgeRepository restoredRepository =
        PersistedKnowledgeRepository(storageService);

    expect(
      restoredRepository
          .listBooks()
          .where((TrainingBook book) => book.title == '测试训练书'),
      hasLength(1),
    );
    expect(
      restoredRepository
          .listQuotes()
          .where((BookQuote quote) => quote.quote == '测试引文内容'),
      hasLength(1),
    );

    restoredRepository.clearImportedEntries();

    final PersistedKnowledgeRepository clearedRepository =
        PersistedKnowledgeRepository(storageService);

    expect(
      clearedRepository
          .listBooks()
          .where((TrainingBook book) => book.title == '测试训练书'),
      isEmpty,
    );
  });

  test('训练日志仓库会持久化 workout_logs 并按创建时间排序', () {
    final InMemoryLocalStorageService storageService =
        InMemoryLocalStorageService();
    final PersistedTrainingLogRepository repository =
        PersistedTrainingLogRepository(storageService);
    final TrainingLog firstLog = TrainingLog(
      id: 'training-log-test',
      workoutDayId: 'workout-test',
      date: DateTime(2026, 7, 8, 18),
      completed: true,
      rpe: 6,
      fatigueLevel: 6,
      sleepQuality: 7,
      painNote: null,
      userNote: '测试训练日志',
      createdAt: DateTime(2026, 7, 8, 18),
    );
    final TrainingLog updatedLog = TrainingLog(
      id: firstLog.id,
      workoutDayId: firstLog.workoutDayId,
      date: DateTime(2026, 7, 9, 19),
      completed: false,
      rpe: 5,
      fatigueLevel: 5,
      sleepQuality: 7,
      painNote: '测试疼痛备注',
      userNote: '测试训练日志更新',
      createdAt: DateTime(2026, 7, 9, 19),
    );

    final TrainingLog reviewedLog = TrainingLog.fromJson({
      ...updatedLog.toJson(),
      'logKind': 'sessionReview',
      'actualDurationMinutes': 42,
      'completionPercentage': 75,
      'averageHeartRate': 146,
      'averagePaceSecondsPerKm': 333,
      'plannedSetCount': 12,
      'completedSetCount': 9,
      'interruptionReason': '临时加班，提前结束。',
      'exerciseRecords': [
        {
          'exerciseId': 'exercise-goblet-squat',
          'exerciseName': '高脚杯深蹲',
          'plannedSetCount': 4,
          'completedSetCount': 4,
          'repetitionsPerSet': 8,
          'weightKg': 24.0,
        },
      ],
    });

    repository.saveLog(firstLog);
    repository.saveLog(reviewedLog);

    final PersistedTrainingLogRepository restoredRepository =
        PersistedTrainingLogRepository(storageService);

    expect(restoredRepository.listLogs(), hasLength(1));
    expect(restoredRepository.listLogs().first.completed, isFalse);
    expect(restoredRepository.listLogs().first.userNote, '测试训练日志更新');
    expect(
      restoredRepository.listLogs().first.toJson()['logKind'],
      'sessionReview',
    );
    expect(
      restoredRepository.listLogs().first.toJson()['actualDurationMinutes'],
      42,
    );
    expect(
      restoredRepository.listLogs().first.toJson()['completionPercentage'],
      75,
    );
    expect(
      restoredRepository.listLogs().first.toJson()['averageHeartRate'],
      146,
    );
    expect(
      restoredRepository.listLogs().first.toJson()['averagePaceSecondsPerKm'],
      333,
    );
    expect(
      restoredRepository.listLogs().first.toJson()['plannedSetCount'],
      12,
    );
    expect(
      restoredRepository.listLogs().first.toJson()['completedSetCount'],
      9,
    );
    expect(
      restoredRepository.listLogs().first.toJson()['interruptionReason'],
      '临时加班，提前结束。',
    );
    final Object? rawExerciseRecords =
        restoredRepository.listLogs().first.toJson()['exerciseRecords'];
    expect(rawExerciseRecords, isA<List<dynamic>>());
    final List<dynamic> exerciseRecords = rawExerciseRecords! as List<dynamic>;
    expect(exerciseRecords, hasLength(1));
    expect(exerciseRecords.first['exerciseId'], 'exercise-goblet-squat');
    expect(exerciseRecords.first['exerciseName'], '高脚杯深蹲');
    expect(exerciseRecords.first['plannedSetCount'], 4);
    expect(exerciseRecords.first['completedSetCount'], 4);
    expect(exerciseRecords.first['repetitionsPerSet'], 8);
    expect(exerciseRecords.first['weightKg'], 24.0);

    restoredRepository.clearLogs();

    final PersistedTrainingLogRepository clearedRepository =
        PersistedTrainingLogRepository(storageService);

    expect(clearedRepository.listLogs(), isEmpty);
  });

  test('周报只按训练会话的实际完成度计算完成率', () {
    final DateTime now = DateTime.now();
    final UserProfile profile = PersistedUserProfileRepository(
      InMemoryLocalStorageService(),
    ).getProfile().copyWith(weeklyTrainingDays: 4);
    final WorkoutDay workout = seedTrainingPlans.first.workoutDays.first;
    final WeeklyReport report = WeeklyReportService().buildWeeklyReport(
      profile: profile,
      todayWorkout: workout,
      logs: [
        TrainingLog(
          id: 'player-step-test',
          workoutDayId: workout.id,
          date: now,
          completed: true,
          rpe: 9,
          fatigueLevel: 9,
          sleepQuality: 7,
          painNote: null,
          userNote: '[跟练执行] 完成：动态拉伸',
          createdAt: now,
          kind: TrainingLogKind.playerStep,
        ),
        TrainingLog(
          id: 'session-review-test',
          workoutDayId: workout.id,
          date: now,
          completed: false,
          rpe: 7,
          fatigueLevel: 7,
          sleepQuality: 7,
          painNote: null,
          userNote: '测试训练后复盘',
          createdAt: now,
          kind: TrainingLogKind.sessionReview,
          actualDurationMinutes: 42,
          completionPercentage: 75,
        ),
      ],
      bodyMetrics: const [],
      readinessScore: 80,
      trainingStatusLabel: '维持',
      trainingStatusReason: '测试状态稳定。',
      recoveryCountdownLabel: '预计 12 小时',
      recoveryAdvice: '保持规律作息。',
      achievementSummaryLabel: '测试成就状态。',
    );

    expect(report.completedWorkouts, 1);
    expect(report.completionRate, closeTo(0.1875, 0.0001));
    expect(report.loadTrendLabel, '维持稳定');
  });

  test('力量训练日会序列化有序的 workout_exercises 动作关联', () {
    final WorkoutDay strengthWorkout = seedTrainingPlans.first.workoutDays[1];
    final Object? rawWorkoutExercises =
        strengthWorkout.toJson()['workoutExercises'];

    expect(rawWorkoutExercises, isA<List<dynamic>>());
    final List<dynamic> workoutExercises =
        rawWorkoutExercises! as List<dynamic>;
    expect(workoutExercises, hasLength(10));
    final Map<String, dynamic> gobletSquat = workoutExercises.singleWhere(
      (dynamic item) => item['exerciseId'] == 'exercise-goblet-squat',
    ) as Map<String, dynamic>;
    final Map<String, dynamic> rdl = workoutExercises.singleWhere(
      (dynamic item) => item['exerciseId'] == 'exercise-rdl',
    ) as Map<String, dynamic>;
    expect(workoutExercises.first['module'], 'foam_rolling');
    expect(gobletSquat['sequence'], 5);
    expect(gobletSquat['plannedSetCount'], 4);
    expect(gobletSquat['repetitionsPerSet'], 8);
    expect(rdl['sequence'], 6);
    expect(
      workoutExercises.map((dynamic item) => item['exerciseId']),
      contains('exercise-dead-bug'),
    );
  });

  test('非休息训练日的主训练和辅助训练都有媒体动作关联', () {
    final List<WorkoutDay> activeWorkouts = seedTrainingPlans.first.workoutDays
        .where(
          (WorkoutDay day) => day.trainingType != TrainingType.rest,
        )
        .toList();

    for (final WorkoutDay workout in activeWorkouts) {
      final List<WorkoutExerciseLink> mainLinks = workout.workoutExercises
          .where(
            (WorkoutExerciseLink link) =>
                link.module == WorkoutExerciseModule.mainTraining,
          )
          .toList();
      final List<WorkoutExerciseLink> accessoryLinks = workout.workoutExercises
          .where(
            (WorkoutExerciseLink link) =>
                link.module == WorkoutExerciseModule.accessory,
          )
          .toList();

      expect(mainLinks, hasLength(workout.mainSets.length));
      expect(
        accessoryLinks.length,
        greaterThanOrEqualTo(workout.accessoryWork.length),
      );
      for (final WorkoutExerciseLink link in [
        ...mainLinks,
        ...accessoryLinks
      ]) {
        final matches = seedExercises
            .where((exercise) => exercise.id == link.exerciseId)
            .toList();
        expect(matches, hasLength(1));
        expect(matches.single.mediaUrl, startsWith('placeholder://'));
        expect(matches.single.evidenceSources, isNotEmpty);
      }
    }
  });

  test('非休息训练日的五步流程都有媒体动作关联', () {
    const List<String> requiredModules = [
      'foam_rolling',
      'dynamic_stretch',
      'activation',
      'warmup',
      'cooldown',
    ];
    final List<WorkoutDay> activeWorkouts = seedTrainingPlans.first.workoutDays
        .where(
          (WorkoutDay day) => day.trainingType != TrainingType.rest,
        )
        .toList();

    for (final WorkoutDay workout in activeWorkouts) {
      final List<WorkoutExerciseLink> phaseLinks = workout.workoutExercises
          .where(
            (WorkoutExerciseLink link) => requiredModules.contains(
              link.toJson()['module'],
            ),
          )
          .toList();
      final List<String> modules = phaseLinks
          .map((WorkoutExerciseLink link) => link.toJson()['module'] as String)
          .toList();

      for (final String module in requiredModules) {
        expect(modules, contains(module));
      }
      for (final WorkoutExerciseLink link in phaseLinks) {
        final matches = seedExercises
            .where((exercise) => exercise.id == link.exerciseId)
            .toList();
        expect(matches, hasLength(1));
        expect(matches.single.mediaUrl, startsWith('placeholder://'));
        expect(matches.single.evidenceSources, isNotEmpty);
      }
    }
  });

  test('动作库会序列化替代、退阶和进阶关联', () {
    final dynamic calfRaiseJson = seedExercises
        .singleWhere(
          (exercise) => exercise.id == 'exercise-standing-calf-raise',
        )
        .toJson();
    final List<dynamic> relations = calfRaiseJson['relations'] as List<dynamic>;

    expect(relations, hasLength(2));
    expect(
      relations.map((dynamic item) => item['type']),
      contains('replacement'),
    );
    expect(
      relations.map((dynamic item) => item['type']),
      contains('progression'),
    );
    expect(
      relations.map((dynamic item) => item['targetExerciseId']),
      contains('exercise-seated-calf-isometric'),
    );
    expect(
      relations.map((dynamic item) => item['targetExerciseId']),
      contains('exercise-single-leg-calf-raise'),
    );
  });

  test('动作库首批内容达到 80 个且每个条目有媒体和依据', () {
    expect(seedExercises, hasLength(80));
    expect(
      seedExercises.map((Exercise exercise) => exercise.id).toSet(),
      hasLength(80),
    );

    for (final Exercise exercise in seedExercises) {
      expect(exercise.mediaUrl, startsWith('placeholder://'));
      expect(exercise.evidenceSources, isNotEmpty);
      expect(exercise.breathingCue, isNotEmpty);
      expect(exercise.contraindications, isNotEmpty);
      expect(exercise.suitableFor, isNotEmpty);
    }

    final Exercise coreExercise = seedExercises.singleWhere(
      (Exercise exercise) => exercise.id == 'exercise-goblet-squat',
    );
    expect(coreExercise.mediaUrls, hasLength(2));
    expect(coreExercise.mediaUrls.first, startsWith('assets/'));
    expect(coreExercise.mediaStatus, ExerciseMediaStatus.precise);

    final Exercise referenceExercise = seedExercises.singleWhere(
      (Exercise exercise) => exercise.id == 'exercise-a-skip',
    );
    expect(referenceExercise.mediaStatus, ExerciseMediaStatus.reference);

    final Exercise highKneeExercise = seedExercises.singleWhere(
      (Exercise exercise) => exercise.id == 'exercise-high-knee',
    );
    expect(highKneeExercise.mediaStatus, ExerciseMediaStatus.precise);
    expect(highKneeExercise.mediaUrls.single, endsWith('high_knees.gif'));

    final Exercise sideRunExercise = seedExercises.singleWhere(
      (Exercise exercise) => exercise.id == 'exercise-running-side-form',
    );
    expect(sideRunExercise.mediaStatus, ExerciseMediaStatus.reference);
    expect(sideRunExercise.mediaUrls.single, endsWith('runner_side_view.jpg'));

    final Exercise restored = Exercise.fromJson(
      seedExercises.last.toJson(),
    );
    expect(restored.id, seedExercises.last.id);
    expect(restored.breathingCue, seedExercises.last.breathingCue);
    expect(restored.contraindications, seedExercises.last.contraindications);
    expect(restored.suitableFor, seedExercises.last.suitableFor);

    final Exercise restoredCore = Exercise.fromJson(coreExercise.toJson());
    expect(restoredCore.mediaUrls, coreExercise.mediaUrls);
    expect(restoredCore.mediaStatus, coreExercise.mediaStatus);
  });

  test('Body Engine 为 8 个动作纠错动作提供结构化身体知识', () {
    const List<String> coreExerciseIds = [
      'exercise-goblet-squat',
      'exercise-reverse-lunge',
      'exercise-rdl',
      'exercise-incline-push-up',
      'exercise-plank',
      'exercise-standing-calf-raise',
      'exercise-high-knee',
      'exercise-running-side-form',
    ];

    for (final String exerciseId in coreExerciseIds) {
      final Exercise exercise = seedExercises.singleWhere(
        (Exercise item) => item.id == exerciseId,
      );
      expect(exercise.bodyEngineProfile.isStructured, isTrue);
      expect(exercise.bodyEngineProfile.involvedJoints, isNotEmpty);
      expect(exercise.bodyEngineProfile.riskAreas, isNotEmpty);

      final Exercise restored = Exercise.fromJson(exercise.toJson());
      expect(restored.bodyEngineProfile.isStructured, isTrue);
      expect(
        restored.bodyEngineProfile.movementPattern,
        exercise.bodyEngineProfile.movementPattern,
      );
    }

    final MotionCheckRule squatRule = seedMotionChecks.singleWhere(
      (MotionCheckRule rule) => rule.type == MotionCheckType.squat,
    );
    final Exercise squat = seedExercises.singleWhere(
      (Exercise exercise) => exercise.id == squatRule.exerciseId,
    );
    final MotionAnalysisResult result = MotionAnalysisService().buildMockResult(
      rule: squatRule,
      capturedAt: DateTime(2026, 7, 10),
      bodyProfile: squat.bodyEngineProfile,
    );
    expect(result.involvedAreas, contains('膝'));
    expect(result.bodyEngineSummary, contains('动作模式'));
    expect(result.bodyEngineSummary, contains('常见代偿'));
  });

  test('结构化关键点会计算动作角度、风险和置信度', () {
    final MotionPoseAnalysisService service = MotionPoseAnalysisService();
    final MotionPoseFrame frame = MotionPoseAnalysisService.sampleFrameFor(
      MotionCheckType.squat,
    );
    final MotionPoseAnalysis analysis = service.analyze(
      type: MotionCheckType.squat,
      frame: frame,
    );

    expect(analysis.measurements, isNotEmpty);
    expect(analysis.score, inInclusiveRange(0, 100));
    expect(analysis.confidence, greaterThan(0));
    expect(analysis.detectedErrors, isNotEmpty);

    final MotionCheckRule squatRule = seedMotionChecks.singleWhere(
      (MotionCheckRule rule) => rule.type == MotionCheckType.squat,
    );
    final MotionAnalysisResult result = MotionAnalysisService().buildPoseResult(
      rule: squatRule,
      frame: frame,
      capturedAt: DateTime(2026, 7, 10),
    );
    final MotionAnalysisResult restored = MotionAnalysisResult.fromJson(
      result.toJson(),
    );
    expect(result.analysisSource, contains('关键点几何分析'));
    expect(result.angleMetrics, isNotEmpty);
    expect(restored.analysisConfidence, result.analysisConfidence);
    expect(restored.poseFrame?.sourceLabel, frame.sourceLabel);
    expect(restored.poseFrame?.landmarks, hasLength(frame.landmarks.length));
  });

  test('关键点 JSON 导入会校验坐标并兼容嵌套 poseFrame', () {
    final MotionPoseFrame frame = MotionPoseAnalysisService.sampleFrameFor(
      MotionCheckType.squat,
    );
    final MotionPoseImportService service = MotionPoseImportService();

    final MotionPoseImportResult valid = service.parse(
      jsonEncode({'poseFrame': frame.toJson()}),
    );
    final MotionPoseImportResult invalid = service.parse(
      '{"landmarks":[{"type":"left_hip","x":2,"y":0.5}]}',
    );

    expect(valid.isValid, isTrue);
    expect(valid.frame?.landmarks, hasLength(frame.landmarks.length));
    expect(invalid.isValid, isFalse);
    expect(invalid.errorMessage, contains('坐标'));
  });

  test('8 个动作纠错规则均关联动作库与安全提示', () {
    expect(seedMotionChecks, hasLength(8));

    for (final MotionCheckRule rule in seedMotionChecks) {
      expect(rule.exerciseId, isNotNull);
      final Exercise exercise = seedExercises.singleWhere(
        (Exercise item) => item.id == rule.exerciseId,
      );

      expect(exercise.breathingCue, isNotEmpty);
      expect(exercise.suitableFor, isNotEmpty);
      expect(exercise.contraindications, isNotEmpty);
      expect(exercise.mediaUrls, isNotEmpty);
      expect(exercise.mediaStatus, isNot(ExerciseMediaStatus.placeholder));
      expect(rule.toJson()['exerciseId'], exercise.id);
    }
  });

  testWidgets('动作详情会展示替代和进阶动作', (WidgetTester tester) async {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: TDesignTheme.lightTheme,
          home: const ExerciseDetailPage(
            exerciseId: 'exercise-standing-calf-raise',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('动作调整'),
      420,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('动作调整'), findsOneWidget);
    expect(find.text('替代'), findsOneWidget);
    expect(find.text('进阶'), findsOneWidget);
    expect(find.text('坐姿小腿等长收缩'), findsOneWidget);
    expect(find.text('单腿提踵'), findsOneWidget);
    expect(find.textContaining('小腿或跟腱不适时'), findsOneWidget);
  });

  testWidgets('动作纠错页会展示动作库安全提示入口', (WidgetTester tester) async {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: TDesignTheme.lightTheme,
          home: const MotionCheckPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('查看动作安全提示').first,
      360,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('动作库'), findsWidgets);
    expect(find.text('查看动作安全提示'), findsWidgets);
  });

  test('规则审计会阻断缺少结构化动作媒体关联的训练日', () {
    final TrainingPlan incompletePlan = seedTrainingPlans.first.copyWith(
      workoutDays: [
        for (final WorkoutDay day in seedTrainingPlans.first.workoutDays)
          day.id == 'workout-week1-day5'
              ? day.copyWith(workoutExercises: const [])
              : day,
      ],
    );
    final TrainingRuleAuditReport report =
        TrainingRuleAuditService().buildReport(
      incompletePlan,
      exercises: seedExercises,
    );
    final TrainingRuleAuditItem mediaItem = report.items.singleWhere(
      (TrainingRuleAuditItem item) => item.title == '动作媒体关联',
    );

    expect(mediaItem.severity, TrainingRuleAuditSeverity.fail);
    expect(mediaItem.description, contains('HYROX 综合循环'));

    final TrainingPlan missingWarmupPlan = seedTrainingPlans.first.copyWith(
      workoutDays: [
        for (final WorkoutDay day in seedTrainingPlans.first.workoutDays)
          day.id == 'workout-week1-day1'
              ? day.copyWith(
                  workoutExercises: day.workoutExercises
                      .where(
                        (WorkoutExerciseLink link) =>
                            link.module != WorkoutExerciseModule.warmup,
                      )
                      .toList(),
                )
              : day,
      ],
    );
    final TrainingRuleAuditItem warmupItem = TrainingRuleAuditService()
        .buildReport(
          missingWarmupPlan,
          exercises: seedExercises,
        )
        .items
        .singleWhere(
          (TrainingRuleAuditItem item) => item.title == '动作媒体关联',
        );
    expect(warmupItem.severity, TrainingRuleAuditSeverity.fail);
    expect(warmupItem.description, contains('低强度有氧跑缺少热身'));

    final TrainingRuleAuditItem validMediaItem = TrainingRuleAuditService()
        .buildReport(
          seedTrainingPlans.first,
          exercises: seedExercises,
        )
        .items
        .singleWhere(
          (TrainingRuleAuditItem item) => item.title == '动作媒体关联',
        );
    expect(validMediaItem.severity, TrainingRuleAuditSeverity.pass);
  });

  test('规则审计会阻断超过用户可用时长的训练日', () {
    final TrainingRuleAuditReport report =
        TrainingRuleAuditService().buildReport(
      seedTrainingPlans.first,
      exercises: seedExercises,
      availableMinutes: 40,
    );
    final TrainingRuleAuditItem timeBudgetItem = report.items.singleWhere(
      (TrainingRuleAuditItem item) => item.title == '时间预算',
    );

    expect(timeBudgetItem.severity, TrainingRuleAuditSeverity.fail);
    expect(timeBudgetItem.description, contains('超过当前可训练时间 40 分钟'));
    expect(timeBudgetItem.description, contains('五步流程总时长已计入预算'));
  });

  test('跑步硬性模块会使用结构化动作标签', () {
    final WorkoutDay runningWorkout = seedTrainingPlans.first.workoutDays
        .singleWhere((WorkoutDay day) => day.id == 'workout-week1-day4');
    final List<Map<String, dynamic>> runningLinks = runningWorkout
        .workoutExercises
        .map((WorkoutExerciseLink item) => item.toJson())
        .toList();

    expect(
      runningLinks.map((Map<String, dynamic> item) => item['module']),
      contains('hip_drive'),
    );
    expect(
      runningLinks.map((Map<String, dynamic> item) => item['module']),
      contains('calf'),
    );
    expect(
      runningLinks.map((Map<String, dynamic> item) => item['exerciseId']),
      contains('exercise-a-skip'),
    );
    expect(
      runningLinks.map((Map<String, dynamic> item) => item['exerciseId']),
      contains('exercise-standing-calf-raise'),
    );
    expect(
      seedExercises.any(
        (exercise) =>
            exercise.id == 'exercise-standing-calf-raise' &&
            exercise.mediaUrl ==
                'placeholder://standing-calf-raise-motion-loop' &&
            exercise.evidenceSources.isNotEmpty,
      ),
      isTrue,
    );

    final RegExp runningKeywords = RegExp(r'提膝|高抬腿|A Skip|提踵|小腿|踝弹跳');
    List<String> withoutRunningKeywords(List<String> items) {
      return items
          .where((String item) => !runningKeywords.hasMatch(item))
          .toList();
    }

    final List<WorkoutDay> textFreeWorkouts = [
      for (final WorkoutDay day in seedTrainingPlans.first.workoutDays)
        day.copyWith(
          title: runningKeywords.hasMatch(day.title) ? '训练日' : day.title,
          coachNotes: runningKeywords.hasMatch(day.coachNotes)
              ? '按当日计划完成。'
              : day.coachNotes,
          foamRollingSteps: withoutRunningKeywords(day.foamRollingSteps),
          dynamicStretchSteps: withoutRunningKeywords(day.dynamicStretchSteps),
          activationSteps: withoutRunningKeywords(day.activationSteps),
          warmupSteps: withoutRunningKeywords(day.warmupSteps),
          mainSets: withoutRunningKeywords(day.mainSets),
          accessoryWork: withoutRunningKeywords(day.accessoryWork),
          cooldownSteps: withoutRunningKeywords(day.cooldownSteps),
        ),
    ];
    final TrainingRuleAuditReport report =
        TrainingRuleAuditService().buildReport(
      seedTrainingPlans.first.copyWith(workoutDays: textFreeWorkouts),
      exercises: seedExercises,
    );
    final TrainingRuleAuditItem runningModuleItem = report.items.singleWhere(
      (TrainingRuleAuditItem item) => item.title == '跑步硬性模块',
    );

    expect(runningModuleItem.severity, TrainingRuleAuditSeverity.pass);
    expect(runningModuleItem.description, contains('结构化关联'));
    expect(report.runningModuleCount, 2);
  });

  testWidgets('跟练播放器会显示关联动作的本地媒体', (WidgetTester tester) async {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    final TrainingMvpController controller =
        container.read(trainingMvpProvider.notifier);
    controller.startWorkoutPlayer(workoutDayId: 'workout-week1-day2');
    for (int index = 0; index < 3; index += 1) {
      controller.completeWorkoutPlayerStep();
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: TDesignTheme.lightTheme,
          home: const WorkoutPlayerPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('高脚杯深蹲'), findsOneWidget);
    expect(find.text('精确示范'), findsWidgets);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('结构化复盘只记录正式和辅助动作', (WidgetTester tester) async {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    final TrainingMvpController controller =
        container.read(trainingMvpProvider.notifier);
    controller.startWorkoutPlayer(workoutDayId: 'workout-week1-day1');
    for (int index = 0; index < 5; index += 1) {
      controller.completeWorkoutPlayerStep();
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: TDesignTheme.lightTheme,
          home: const WorkoutPlayerPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('记录训练反馈'),
      500,
      maxScrolls: 20,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('记录训练反馈'));
    await tester.pumpAndSettle();

    expect(find.text('轻松跑'), findsOneWidget);
    expect(find.text('臀桥'), findsOneWidget);
    expect(find.text('死虫'), findsOneWidget);
    expect(find.text('跑步动态拉伸流程'), findsNothing);
    expect(find.text('跑后放松流程'), findsNothing);
  });

  test('结构化动作会映射到对应跟练阶段', () {
    final WorkoutDay strengthWorkout = seedTrainingPlans.first.workoutDays
        .singleWhere((WorkoutDay day) => day.id == 'workout-week1-day2');
    final WorkoutDay runningWorkout = seedTrainingPlans.first.workoutDays
        .singleWhere((WorkoutDay day) => day.id == 'workout-week1-day4');
    final List<WorkoutPlayerStep> strengthSteps = buildWorkoutPlayerSteps(
      strengthWorkout,
      deloaded: false,
    );
    final List<WorkoutPlayerStep> runningSteps = buildWorkoutPlayerSteps(
      runningWorkout,
      deloaded: false,
    );

    expect(
      strengthSteps
          .singleWhere(
            (WorkoutPlayerStep step) => step.phase == WorkoutPlayerPhase.main,
          )
          .exerciseIds,
      orderedEquals([
        'exercise-goblet-squat',
        'exercise-rdl',
        'exercise-dead-bug',
        'exercise-plank',
        'exercise-lateral-band-walk',
      ]),
    );
    expect(
      runningSteps
          .singleWhere(
            (WorkoutPlayerStep step) =>
                step.phase == WorkoutPlayerPhase.dynamicStretch,
          )
          .exerciseIds,
      orderedEquals([
        'exercise-running-dynamic-flow',
        'exercise-a-skip',
        'exercise-running-stride-warmup',
      ]),
    );
    expect(
      runningSteps
          .singleWhere(
            (WorkoutPlayerStep step) =>
                step.phase == WorkoutPlayerPhase.activation,
          )
          .exerciseIds,
      orderedEquals([
        'exercise-running-activation-flow',
        'exercise-standing-calf-raise',
      ]),
    );
  });

  testWidgets('结构化力量日复盘会保存动作库 ID', (WidgetTester tester) async {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    final TrainingMvpController controller =
        container.read(trainingMvpProvider.notifier);
    controller.startWorkoutPlayer(workoutDayId: 'workout-week1-day2');
    for (int index = 0; index < 6; index += 1) {
      controller.completeWorkoutPlayerStep();
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: TDesignTheme.lightTheme,
          home: const WorkoutPlayerPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('记录训练反馈'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('记录训练反馈'));
    await tester.pumpAndSettle();

    expect(find.text('高脚杯深蹲'), findsOneWidget);
    expect(find.text('计划 4 组 x 8 次'), findsOneWidget);
    await tester.enterText(
      find.byKey(
        const ValueKey<String>(
          'workout-review-exercise-0-completed-sets-field',
        ),
      ),
      '4',
    );
    await tester.enterText(
      find.byKey(
        const ValueKey<String>('workout-review-exercise-0-weight-field'),
      ),
      '24',
    );
    await tester.ensureVisible(find.text('保存训练反馈'));
    await tester.tap(find.text('保存训练反馈'));
    await tester.pumpAndSettle();

    final ExerciseExecutionRecord? firstRecord = container
        .read(trainingMvpProvider)
        .latestWorkoutSessionReview
        ?.exerciseRecords
        .firstOrNull;
    expect(firstRecord?.exerciseId, 'exercise-goblet-squat');
    expect(firstRecord?.completedSetCount, 4);
    expect(firstRecord?.weightKg, 24);
  });

  test('训练导入仓库会持久化 imported_workouts 并保留最近导入顺序', () {
    final InMemoryLocalStorageService storageService =
        InMemoryLocalStorageService();
    final PersistedImportedWorkoutRepository repository =
        PersistedImportedWorkoutRepository(storageService);
    final ImportedWorkout firstWorkout = ImportedWorkout(
      id: 'imported-workout-test',
      source: ImportedWorkoutSource.gpx,
      title: '测试 GPX 导入',
      startedAt: DateTime(2026, 7, 8, 18),
      distanceKm: 5.2,
      durationMinutes: 32,
      elevationGainMeters: 80,
      averageHeartRate: 142,
      trainingEffect: TrainingEffectLabel.aerobic,
    );
    final ImportedWorkout updatedWorkout = ImportedWorkout(
      id: firstWorkout.id,
      source: ImportedWorkoutSource.fitSummary,
      title: '测试 FIT 摘要更新',
      startedAt: DateTime(2026, 7, 9, 19),
      distanceKm: 6.1,
      durationMinutes: 36,
      elevationGainMeters: 120,
      averageHeartRate: 150,
      trainingEffect: TrainingEffectLabel.aerobic,
    );
    final ImportedWorkout latestWorkout = ImportedWorkout(
      id: 'imported-workout-latest',
      source: ImportedWorkoutSource.gpx,
      title: '测试最近导入',
      startedAt: DateTime(2026, 7, 10, 7),
      distanceKm: 4.2,
      durationMinutes: 25,
      elevationGainMeters: 40,
      averageHeartRate: 132,
      trainingEffect: TrainingEffectLabel.recovery,
    );

    repository.saveWorkout(firstWorkout);
    repository.saveWorkout(updatedWorkout);
    repository.saveWorkout(latestWorkout);

    final PersistedImportedWorkoutRepository restoredRepository =
        PersistedImportedWorkoutRepository(storageService);

    expect(restoredRepository.listWorkouts(), hasLength(2));
    expect(restoredRepository.listWorkouts().first.id, latestWorkout.id);
    expect(restoredRepository.listWorkouts().last.title, '测试 FIT 摘要更新');
    expect(restoredRepository.listWorkouts().last.distanceKm, 6.1);

    restoredRepository.clearWorkouts();

    final PersistedImportedWorkoutRepository clearedRepository =
        PersistedImportedWorkoutRepository(storageService);

    expect(clearedRepository.listWorkouts(), isEmpty);
  });

  test('疼痛记录仓库会持久化 rehab_logs 并按创建时间排序', () {
    final InMemoryLocalStorageService storageService =
        InMemoryLocalStorageService();
    final PersistedPainLogRepository repository =
        PersistedPainLogRepository(storageService);
    final PainLog firstLog = PainLog(
      id: 'pain-log-test',
      bodyPart: '膝盖',
      painLevel: 4,
      timing: PainTiming.afterTraining,
      note: '测试康复记录',
      date: DateTime(2026, 7, 8, 20),
      createdAt: DateTime(2026, 7, 8, 20),
    );
    final PainLog updatedLog = PainLog(
      id: firstLog.id,
      bodyPart: firstLog.bodyPart,
      painLevel: 7,
      timing: PainTiming.duringTraining,
      note: '测试疼痛红线',
      date: DateTime(2026, 7, 9, 20),
      createdAt: DateTime(2026, 7, 9, 20),
    );

    repository.savePainLog(firstLog);
    repository.savePainLog(updatedLog);

    final PersistedPainLogRepository restoredRepository =
        PersistedPainLogRepository(storageService);

    expect(restoredRepository.listPainLogs(), hasLength(1));
    expect(restoredRepository.listPainLogs().first.painLevel, 7);
    expect(restoredRepository.listPainLogs().first.requiresMedicalAttention,
        isTrue);
    expect(restoredRepository.listPainLogs().first.note, '测试疼痛红线');

    restoredRepository.clearPainLogs();

    final PersistedPainLogRepository clearedRepository =
        PersistedPainLogRepository(storageService);

    expect(clearedRepository.listPainLogs(), isEmpty);
  });

  test('疼痛持续超过两周会触发就医红线', () {
    final DateTime now = DateTime.now();
    final PainLog persistentPain = PainLog(
      id: 'persistent-pain-test',
      bodyPart: '跟腱/小腿',
      painLevel: 3,
      timing: PainTiming.ongoing,
      note: '测试持续疼痛红线',
      date: now.subtract(const Duration(days: 15)),
      createdAt: now,
    );

    expect(persistentPain.ongoingDays, greaterThan(14));
    expect(persistentPain.persistsOverTwoWeeks, isTrue);
    expect(persistentPain.requiresMedicalAttention, isTrue);
    expect(persistentPain.shouldDeloadTraining, isTrue);
    expect(persistentPain.medicalAttentionReason, contains('持续超过 2 周'));

    final DailyAdjustmentDecision decision =
        DailyAdjustmentService().buildDecision(
      baseWorkout: seedTrainingPlans.first.workoutDays.first,
      availableMinutes: 30,
      workStress: WorkStressLevel.normal,
      environment: TrainingEnvironment.home,
      weather: WeatherCondition.good,
      latestBodyMetric: null,
      latestPainLog: persistentPain,
      latestMotionAnalysisResult: null,
      readinessScore: 80,
    );
    expect(decision.decisionType, TrainingDecisionType.rest);
    expect(decision.reason, contains('持续超过 2 周'));
  });

  test('比赛导入会生成 RacePlan 并持久化 races', () {
    final RaceImportService importService = RaceImportService();
    final RacePlan importedRace = importService.parse('''
赛事：测试半程马拉松
类型：路跑
日期：2026-11-08
目标：2 小时内完赛
赛道：城市路跑，后半程微上坡。
''');
    final InMemoryLocalStorageService storageService =
        InMemoryLocalStorageService();
    final PersistedRaceRepository repository =
        PersistedRaceRepository(storageService);

    repository.saveRace(importedRace);

    final PersistedRaceRepository restoredRepository =
        PersistedRaceRepository(storageService);

    expect(importedRace.name, '测试半程马拉松');
    expect(importedRace.type, RaceType.roadRunning);
    expect(importedRace.raceDateLabel, '2026-11-08');
    expect(importedRace.phases, hasLength(4));
    expect(restoredRepository.listRaces().first.name, '测试半程马拉松');
    expect(restoredRepository.listRaces().first.courseInfo, contains('微上坡'));

    restoredRepository.clearImportedRaces();

    final PersistedRaceRepository clearedRepository =
        PersistedRaceRepository(storageService);

    expect(clearedRepository.listRaces().first.id, seedRaces.first.id);
  });

  test('比赛自动排期会按比赛日期生成阶段任务和安全门槛', () {
    final RaceAutoSchedule schedule = RaceAutoScheduleService().buildSchedule(
      race: seedRaces.first,
      now: DateTime(2026, 7, 9, 9),
      readinessScore: 72,
      hasPainRedline: false,
    );

    expect(schedule.raceName, '上海马拉松备赛');
    expect(schedule.items, hasLength(4));
    expect(schedule.statusLabel, contains('自动排期'));
    expect(schedule.currentItem?.phaseType, RacePhaseType.base);
    expect(schedule.currentItem?.keyWorkouts, isNotEmpty);
    expect(schedule.currentItem?.safetyGate, contains('疼痛'));
  });

  testWidgets('TrainFlow AI 默认进入今日训练页', (WidgetTester tester) async {
    final InMemoryLocalStorageService storageService =
        InMemoryLocalStorageService();
    final DateTime yesterday =
        DateTime.now().subtract(const Duration(days: 1));
    final BodyMetric yesterdayMetric = BodyMetric(
      id: 'body-metric-test-yesterday',
      measuredAt: DateTime(
        yesterday.year,
        yesterday.month,
        yesterday.day,
        7,
        20,
      ),
      weightKg: 73.8,
      bodyFatPercentage: 18.6,
      restingHeartRate: 58,
      hrvMs: 52,
      sleepHours: 7.1,
      fatigueLevel: 4,
      sorenessLevel: 3,
      moodLabel: '稳定',
      source: BodyMetricSource.manual,
      note: '测试日期基线',
    );
    storageService.saveJson('trainflow.body_metrics.v1', {
      'schemaVersion': 1,
      'metrics': [
        ...seedBodyMetrics,
        yesterdayMetric,
      ].map((BodyMetric metric) => metric.toJson()).toList(),
      'revisions': <Map<String, dynamic>>[],
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storageService),
        ],
        child: const TrainFlowApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('今日训练'), findsWidgets);
    expect(find.text('首次进入请填写基础资料'), findsOneWidget);
    expect(find.text('训练计划'), findsOneWidget);
    expect(find.text('动作库'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);

    await tester.tap(find.text('训练计划'));
    await tester.pumpAndSettle();

    expect(find.text('跑步 + HYROX 基础 4 周计划'), findsOneWidget);

    await tester.tap(find.text('跑步 + HYROX 基础 4 周计划'));
    await tester.pumpAndSettle();

    expect(find.text('规则引擎校验'), findsOneWidget);
    expect(find.text('引用绑定 · 通过'), findsOneWidget);
    expect(find.text('训练日依据 · 通过'), findsOneWidget);
    expect(find.text('跑步硬性模块 · 通过'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('下肢力量基础'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('下肢力量基础'));
    await tester.pumpAndSettle();

    expect(find.text('下肢力量基础'), findsWidgets);
    expect(find.widgetWithText(FilledButton, '开始跟练'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('训练-动作关联'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('训练-动作关联'), findsOneWidget);
    expect(find.textContaining('高脚杯深蹲 · 4 组 x 8 次'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('手动调整本次计划'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('手动调整本次计划'));
    await tester.pumpAndSettle();

    expect(find.text('手动调整训练日'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey<String>('plan-adjustment-minutes-field')),
      '35',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('plan-adjustment-reason-field')),
      '今天只有午休时间。',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存调整'));
    await tester.pumpAndSettle();

    expect(find.textContaining('当前调整：35 分钟'), findsOneWidget);
    expect(find.textContaining('已记录为本地学习信号'), findsOneWidget);

    await tester.tap(find.text('手动调整本次计划'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('恢复原计划'));
    await tester.pumpAndSettle();

    expect(find.text('50 分钟'), findsOneWidget);
    expect(find.textContaining('已恢复原计划并记录为本地学习信号'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '开始跟练'));
    await tester.pumpAndSettle();

    expect(find.text('跟练执行'), findsWidgets);
    expect(find.text('下肢力量基础'), findsOneWidget);
    expect(find.text('真实倒计时'), findsOneWidget);
    expect(find.textContaining('05:00'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('TTS 提示队列'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('TTS 提示队列'), findsOneWidget);
    expect(find.text('屏幕常亮意图'), findsOneWidget);
    expect(find.text('关闭语音'), findsOneWidget);
    expect(find.textContaining('浏览器屏幕常亮'), findsOneWidget);

    await tester.tap(find.text('关闭语音'));
    await tester.pumpAndSettle();
    expect(find.textContaining('当前只显示文字动作提示'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('开始计时'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, '开始计时'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.drag(find.byType(Scrollable).first, const Offset(0, 800));
    await tester.pump();

    expect(find.textContaining('04:59'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('暂停计时'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, '暂停计时'));
    await tester.pump();

    await tester.tap(find.text('今日训练').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('晨间报告'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('晨间报告'), findsOneWidget);
    expect(find.text('昨晚睡眠'), findsOneWidget);
    expect(find.text('今日安排'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('主动提醒'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('主动提醒'), findsOneWidget);
    expect(find.text('打开提醒'), findsOneWidget);

    await tester.tap(find.text('打开提醒'));
    await tester.pumpAndSettle();

    expect(find.text('提醒编排'), findsWidgets);
    expect(find.text('主动服务设置'), findsOneWidget);
    expect(find.text('今日训练提醒'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('30 天引导提醒'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('30 天引导提醒'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('周报提醒'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('周报提醒'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('暂停提醒'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('暂停提醒'));
    await tester.pumpAndSettle();

    expect(find.textContaining('提醒已暂停'), findsWidgets);

    await tester.tap(find.text('今日训练').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('今日签到'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('今日签到'), findsOneWidget);
    expect(find.text('打开签到'), findsOneWidget);

    await tester.tap(find.text('打开签到'));
    await tester.pumpAndSettle();

    expect(find.text('精简签到'), findsWidgets);
    expect(find.text('输入递减'), findsOneWidget);
    expect(find.textContaining('动态排序'), findsWidgets);
    expect(find.textContaining('P2 疼痛'), findsWidgets);
    expect(find.textContaining('P2 疲劳'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('一键确认'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('和昨天一样'), findsOneWidget);

    await tester.ensureVisible(find.text('和昨天一样'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('和昨天一样'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已按画像预填完成今日签到'), findsOneWidget);

    await tester.tap(find.text('今日训练').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('恢复倒计时'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('恢复倒计时'), findsOneWidget);
    expect(find.text('距下次高强度课'), findsOneWidget);
    expect(find.textContaining('预计'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('每日调整'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('每日调整'), findsOneWidget);
    expect(find.text('打开调整'), findsOneWidget);

    await tester.tap(find.text('打开调整'));
    await tester.pumpAndSettle();

    expect(find.text('每日调整'), findsWidgets);
    expect(find.text('现实约束'), findsOneWidget);
    expect(find.text('五类决策'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('20 分钟'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('20 分钟'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('爆表'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('无器械'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('无器械'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('应用今日调整'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('应用今日调整'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已应用今日调整'), findsOneWidget);

    await tester.tap(find.text('今日训练').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('训练状态趋势'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('训练状态趋势'), findsOneWidget);
    expect(find.text('ATL 急性负荷'), findsOneWidget);
    expect(find.text('CTL 慢性体能'), findsOneWidget);
    expect(find.text('CTL / ATL / TSB 训练负荷曲线'), findsOneWidget);
    expect(find.textContaining('当前 TSB'), findsOneWidget);
    expect(find.text('CTL'), findsOneWidget);
    expect(find.text('ATL'), findsOneWidget);
    expect(find.text('TSB'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('今日照吃卡'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('今日照吃卡'), findsOneWidget);
    expect(find.textContaining('点餐公式'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('30 天渐进引导'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('30 天渐进引导'), findsOneWidget);
    expect(find.textContaining('第 1/30 天'), findsOneWidget);

    await tester.tap(find.text('打开引导'));
    await tester.pumpAndSettle();

    expect(find.text('30 天渐进引导'), findsWidgets);
    expect(find.text('今天做什么'), findsOneWidget);
    expect(find.text('今天照吃'), findsOneWidget);
    expect(find.text('太累了'), findsOneWidget);
    expect(find.text('刚好'), findsOneWidget);
    expect(find.text('太轻松'), findsOneWidget);
    expect(find.text('5 分钟补救版'), findsOneWidget);
    expect(find.text('漏练顺延'), findsOneWidget);

    await tester.ensureVisible(find.text('5 分钟补救版'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('5 分钟补救版'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.textContaining('出门快走 3 分钟'));
    await tester.pumpAndSettle();

    expect(find.textContaining('出门快走 3 分钟'), findsOneWidget);

    await tester.ensureVisible(find.text('漏练顺延'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('漏练顺延'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.textContaining('计划已顺延'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('计划已顺延'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('刚好'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('刚好'));
    await tester.pumpAndSettle();

    expect(find.textContaining('第 2/30 天'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('1 天'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('1 天'), findsOneWidget);

    for (int i = 0; i < 29; i += 1) {
      await tester.ensureVisible(find.text('刚好'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('刚好'));
      await tester.pumpAndSettle();
    }

    await tester.scrollUntilVisible(
      find.text('查看毕业报告'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('查看毕业报告'));
    await tester.pumpAndSettle();

    expect(find.text('30 天毕业报告'), findsWidgets);
    expect(find.text('能力评估'), findsOneWidget);
    expect(find.text('心率变化'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('主观感受趋势'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('主观感受趋势'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('正式 AI 计划衔接'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('正式 AI 计划衔接'), findsOneWidget);

    await tester.tap(find.text('切换正式 AI 计划'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已生成正式 AI 个性化周期'), findsOneWidget);
    expect(find.text('已生成正式周期'), findsOneWidget);
    expect(find.text('周期长度'), findsOneWidget);
    expect(find.text('4 周重点'), findsOneWidget);
    expect(find.textContaining('每周'), findsWidgets);

    await tester.tap(find.text('今日训练').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('今日训练内容'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('今日训练五步'), findsOneWidget);
    expect(find.text('开始跟练'), findsOneWidget);

    await tester.ensureVisible(find.text('开始跟练'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始跟练'));
    await tester.pumpAndSettle();

    expect(find.text('跟练执行'), findsWidgets);
    expect(find.text('当前步骤'), findsOneWidget);
    expect(find.text('倒计时'), findsOneWidget);
    expect(find.text('真实倒计时'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('TTS 提示队列'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('TTS 提示队列'), findsOneWidget);
    expect(find.text('屏幕常亮意图'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('练中反馈'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('练中反馈'), findsOneWidget);

    await tester.tap(find.text('太累了'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.textContaining('已一键降级'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('已一键降级'), findsOneWidget);
    expect(find.text('降级训练'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('完成'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('训练后放松与反馈'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('训练后放松与反馈'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('完成'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(find.textContaining('本次跟练已完成'), findsWidgets);
    expect(find.textContaining('执行记录已写入 workout_logs'), findsWidgets);
    expect(find.text('记录训练反馈'), findsOneWidget);

    await tester.tap(find.text('记录训练反馈'));
    await tester.pumpAndSettle();

    expect(find.text('训练后复盘'), findsOneWidget);
    expect(find.text('实际动作记录'), findsOneWidget);
    expect(find.text('轻松跑'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>(
          'workout-review-exercise-0-completed-sets-field',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('workout-review-exercise-0-weight-field'),
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('workout-review-duration-field')),
      '42',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('workout-review-rpe-selector')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('RPE 7').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('75% 完成'));
    await tester.enterText(
      find.byKey(const ValueKey<String>('workout-review-heart-rate-field')),
      '146',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('workout-review-pace-field')),
      '333',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('workout-review-planned-sets-field')),
      '12',
    );
    await tester.enterText(
      find.byKey(
        const ValueKey<String>('workout-review-completed-sets-field'),
      ),
      '9',
    );
    await tester.enterText(
      find.byKey(
        const ValueKey<String>(
          'workout-review-exercise-0-completed-sets-field',
        ),
      ),
      '1',
    );
    await tester.enterText(
      find.byKey(
        const ValueKey<String>('workout-review-exercise-0-weight-field'),
      ),
      '5',
    );
    await tester.enterText(
      find.byKey(
        const ValueKey<String>('workout-review-interruption-reason-field'),
      ),
      '临时加班，提前结束。',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('workout-review-note-field')),
      '深蹲动作稳定，后半段疲劳上升。',
    );
    await tester.ensureVisible(find.text('保存训练反馈'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存训练反馈'));
    await tester.pumpAndSettle();

    expect(find.textContaining('实际 42 分钟'), findsOneWidget);
    expect(find.textContaining('75% 完成 · RPE 7'), findsOneWidget);
    expect(find.textContaining('已保存训练反馈'), findsOneWidget);
    expect(
      find.textContaining(
        '轻松跑 · 1/1 组 · 5.0 kg',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('回到今日训练'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('恢复倒计时'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('还需约'), findsWidgets);

    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('用户画像'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('用户画像'), findsOneWidget);
    expect(find.text('透明用户画像'), findsOneWidget);

    await tester.tap(find.text('查看画像'));
    await tester.pumpAndSettle();

    expect(find.text('用户画像'), findsWidgets);
    expect(find.text('透明画像'), findsOneWidget);
    expect(find.textContaining('条已回填'), findsWidgets);
    expect(find.text('本地画像三表'), findsOneWidget);
    expect(find.text('生成周度画像任务'), findsOneWidget);

    await tester.ensureVisible(find.text('生成周度画像任务'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('生成周度画像任务'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已生成'), findsWidgets);
    expect(find.textContaining('profile_events'), findsWidgets);
    expect(find.textContaining('prediction_logs'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('信任回顾'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('信任回顾'), findsOneWidget);
    expect(find.text('预测准确率'), findsOneWidget);
    expect(find.textContaining('已对账'), findsOneWidget);
    expect(find.text('兑现回顾'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('画像结论'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('画像结论'), findsOneWidget);
    expect(find.textContaining('置信度'), findsWidgets);

    await tester.ensureVisible(find.text('标记不准').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('标记不准').first);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.textContaining('已记录修正'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('已记录修正'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('学习信号 profile_events'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('学习信号 profile_events'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('预测对账 prediction_logs'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('预测对账 prediction_logs'), findsOneWidget);
    expect(find.text('恢复时间'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('体重趋势'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('体重趋势'), findsOneWidget);
    expect(find.textContaining('已自动回填'), findsWidgets);

    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('自动周报'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('自动周报'), findsOneWidget);
    expect(find.text('自动周报 Agent Mock'), findsOneWidget);

    await tester.tap(find.text('打开周报'));
    await tester.pumpAndSettle();

    expect(find.text('自动周报'), findsWidgets);
    expect(find.text('完成率'), findsOneWidget);
    expect(find.text('负荷趋势'), findsOneWidget);
    expect(find.text('决策命中回顾'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('下周重点'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('下周重点'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('导出 Markdown'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('导出 Markdown'));
    await tester.pumpAndSettle();

    expect(find.textContaining('## TrainFlow AI 周报'), findsOneWidget);
    expect(find.textContaining('### 下周重点'), findsOneWidget);
    expect(find.text('TrainFlow AI 周报卡片'), findsOneWidget);
    expect(find.text('本地导出记录'), findsOneWidget);
    expect(find.textContaining('已登记 Markdown 导出'), findsOneWidget);

    await tester.ensureVisible(find.text('保存到本地归档'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '保存到本地归档'));
    await tester.pumpAndSettle();

    expect(find.text('本地周报归档'), findsOneWidget);
    expect(find.textContaining('已保存'), findsWidgets);

    await tester.ensureVisible(find.text('生成图片卡片'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '生成图片卡片'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();

    expect(find.textContaining('图片卡片已生成'), findsOneWidget);
    expect(find.textContaining('KB，可接系统分享'), findsOneWidget);
    expect(find.textContaining('已登记 PNG 图片 导出'), findsOneWidget);

    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('成就徽章'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('成就徽章'), findsOneWidget);
    expect(find.text('成就体系'), findsOneWidget);
    expect(find.text('本地成就记录表'), findsOneWidget);
    expect(find.text('同步成就记录'), findsOneWidget);
    expect(find.text('首次跟练'), findsOneWidget);
    expect(find.text('听身体的'), findsOneWidget);
    expect(find.text('新手第一天'), findsOneWidget);
    expect(find.text('身体数据起步'), findsOneWidget);
    expect(find.textContaining('已解锁'), findsWidgets);

    await tester.ensureVisible(find.text('同步成就记录'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '同步成就记录'));
    await tester.pumpAndSettle();

    expect(find.textContaining('本地 achievements 表'), findsOneWidget);
    expect(find.textContaining('已入库'), findsWidgets);

    await tester.tap(find.text('今日训练').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('身体数据'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('身体数据'), findsOneWidget);
    expect(find.textContaining('7 日均值'), findsOneWidget);

    await tester.tap(find.text('查看身体数据'));
    await tester.pumpAndSettle();

    expect(find.text('身体数据'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('数据质量'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('数据质量'), findsOneWidget);
    expect(find.text('质量分'), findsOneWidget);
    expect(find.text('覆盖率'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('指标目标'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('指标目标'), findsOneWidget);
    expect(find.text('体重下降 5%'), findsOneWidget);
    expect(find.text('连续数据地基'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('10 秒快录'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('10 秒快录'), findsOneWidget);
    expect(find.textContaining('HRV'), findsWidgets);
    expect(find.text('补录日期'), findsOneWidget);

    await tester.tap(find.text('昨天补录'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('保存身体数据'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存身体数据'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已保存'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('最近修订'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('最近修订'), findsOneWidget);
    expect(find.textContaining('10 秒快录覆盖同日记录'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('前天补录'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('前天补录'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byType(Slider).first);
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Slider).first, const Offset(500, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存身体数据'));
    await tester.pumpAndSettle();

    expect(find.textContaining('异常值确认'), findsOneWidget);
    expect(find.text('确认保存异常值'), findsOneWidget);

    await tester.tap(find.text('确认保存异常值'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已确认并保存异常值'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('截图识别 Mock'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('截图识别 Mock'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('识别截图文字'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('识别截图文字'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已识别'), findsOneWidget);
    expect(find.text('确认写入截图识别数据'), findsOneWidget);

    await tester.tap(find.text('确认写入截图识别数据'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已确认截图识别数据'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('身体 CSV 导入'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('身体 CSV 导入'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('导入身体数据 CSV'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('导入身体数据 CSV'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已解析 3 条身体数据'), findsOneWidget);
    expect(find.textContaining('body_metrics'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('趋势窗口'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('趋势窗口'), findsOneWidget);
    expect(find.text('7 日'), findsWidgets);
    expect(find.text('30 日'), findsOneWidget);

    await tester.tap(find.text('30 日'));
    await tester.pumpAndSettle();

    expect(find.text('30 日'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('30 日趋势图表'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('30 日趋势图表'), findsOneWidget);
    expect(find.text('体重线'), findsOneWidget);
    expect(find.text('HRV线'), findsOneWidget);
    expect(find.text('疲劳线'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('趋势洞察'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('趋势洞察'), findsOneWidget);
    expect(find.textContaining('30 日窗口'), findsWidgets);
    expect(find.text('叠加视图'), findsOneWidget);
    expect(find.text('减脂保护'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('数据出口'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('导出 JSON'));
    await tester.pumpAndSettle();

    expect(find.textContaining('"weightKg"'), findsWidgets);
    expect(find.text('本地导出记录'), findsWidgets);
    expect(find.textContaining('已登记 JSON 导出'), findsOneWidget);

    await tester.tap(find.text('导出 CSV'));
    await tester.pumpAndSettle();

    expect(find.textContaining('measured_at,weight_kg'), findsWidgets);
    expect(find.textContaining('已登记 CSV 导出'), findsOneWidget);

    await tester.tap(find.text('生成导出包'));
    await tester.pumpAndSettle();

    expect(find.textContaining('导出包已生成'), findsOneWidget);
    expect(find.textContaining('body_metrics.json'), findsOneWidget);
    expect(find.textContaining('body_metrics.csv'), findsOneWidget);
    expect(find.textContaining('已登记导出包摘要'), findsOneWidget);

    await tester.tap(find.text('清除导出记录'));
    await tester.pumpAndSettle();

    expect(find.text('清除本地导出记录？'), findsOneWidget);
    expect(
      find.textContaining('不会删除身体数据或当前导出预览'),
      findsOneWidget,
    );

    await tester.tap(find.text('确认清除'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已清除本地身体数据导出记录'), findsOneWidget);

    await tester.tap(find.text('清除身体数据'));
    await tester.pumpAndSettle();

    expect(find.textContaining('当前记录 0 条'), findsOneWidget);
    expect(find.textContaining('导出包需重新生成'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('GPX / FIT 导入'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('打开导入'));
    await tester.pumpAndSettle();

    expect(find.text('训练文件导入'), findsWidgets);
    expect(find.text('导入训练文件'), findsOneWidget);
    expect(find.textContaining('GPX / FIT 导入 Mock'), findsOneWidget);

    await tester.ensureVisible(find.text('导入训练文件'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('导入训练文件'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.textContaining('已导入 GPX'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('已导入 GPX'), findsOneWidget);
    expect(find.textContaining('workout_logs'), findsWidgets);
    expect(find.text('有氧刺激'), findsWidgets);
    expect(find.text('最近导入'), findsOneWidget);

    await tester.tap(find.text('今日训练').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('今日照吃卡'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('查看照吃指令'));
    await tester.pumpAndSettle();

    expect(find.text('照吃指令卡'), findsWidgets);
    expect(find.text('外卖照吃卡'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('食堂'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('食堂'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('自炊'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('自炊'), findsWidgets);

    await tester.tap(find.text('今日训练').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('动作纠错'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('动作纠错'), findsOneWidget);
    expect(find.textContaining('8 个核心动作规则已接入'), findsOneWidget);

    await tester.tap(find.text('查看纠错'));
    await tester.pumpAndSettle();

    expect(find.text('Motion Vision 管线'), findsOneWidget);
    expect(find.textContaining('本地规则 Mock'), findsOneWidget);
    expect(find.text('导入关键点数据'), findsWidgets);
    expect(find.text('深蹲纠错'), findsOneWidget);
    expect(find.text('纠正建议'), findsWidgets);

    await tester.ensureVisible(find.text('模拟上传分析').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('模拟上传分析').first);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('计算关键点样例').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('计算关键点样例').first);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.textContaining('已完成本地关键点几何分析'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('已完成本地关键点几何分析'), findsOneWidget);
    expect(find.text('Body Engine'), findsOneWidget);
    expect(find.text('分析来源'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('跑步侧面姿态纠错'),
      600,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('跑步侧面姿态纠错'), findsOneWidget);

    await tester.tap(find.text('今日训练').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('动作纠错'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('动作质量风险已进入每日调整'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('比赛备战'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('比赛备战'), findsOneWidget);
    expect(find.textContaining('周期反推'), findsOneWidget);

    await tester.tap(find.text('查看比赛备战'));
    await tester.pumpAndSettle();

    expect(find.text('比赛备战'), findsWidgets);
    expect(find.text('base→build→specific→taper'), findsOneWidget);
    expect(find.text('赛事导入'), findsOneWidget);
    expect(find.text('导入比赛'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(FilledButton, '导入比赛'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '导入比赛'));
    await tester.pumpAndSettle();

    expect(find.text('杭州半程马拉松备赛'), findsOneWidget);
    expect(find.textContaining('已导入 杭州半程马拉松备赛'), findsOneWidget);
    expect(find.textContaining('本地 races'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('上海马拉松备赛'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('上海马拉松备赛'), findsOneWidget);
    expect(find.text('自动排期'), findsWidgets);
    expect(find.text('本周阶段'), findsWidgets);
    expect(find.textContaining('安全门槛'), findsWidgets);
    expect(find.text('成绩预测'), findsWidgets);
    expect(find.text('赛前减量'), findsWidgets);
    expect(find.text('装备建议'), findsWidgets);
    expect(find.text('比赛策略'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('HYROX Open 备赛'),
      600,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('HYROX Open 备赛'), findsOneWidget);

    await tester.tap(find.text('今日训练').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('今日训练内容'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('今日训练内容'), findsOneWidget);
    expect(find.text('今日训练五步'), findsOneWidget);
    expect(find.text('决策 正常'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('AI 教练建议 Mock'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('AI 教练建议 Mock'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('训练依据'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('训练依据'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.textContaining('p. 84-91'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('p. 84-91'), findsOneWidget);
    expect(find.textContaining('原文片段'), findsWidgets);

    await tester.tap(find.text('查看书库'));
    await tester.pumpAndSettle();

    expect(find.text('书库 / 知识库'), findsWidgets);
    expect(find.text('引用闭环'), findsOneWidget);
    expect(find.text('4 本'), findsOneWidget);
    expect(find.text('5 条'), findsWidgets);
    expect(find.text('书库搜索与导入'), findsOneWidget);
    expect(find.text('导入知识片段'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.textContaining('p. 84-91'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('p. 84-91'), findsOneWidget);
    expect(find.textContaining('今日训练：轻松跑 + 技术动作'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('knowledge-search-field')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('knowledge-search-field')),
      'Daniels',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('1 本匹配'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Daniels\' Running Formula'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Daniels\' Running Formula'), findsOneWidget);
    expect(find.text('引用关联'), findsWidgets);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('knowledge-search-field')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('knowledge-search-field')),
      '',
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('导入知识片段'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('导入知识片段'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已导入《Atomic Habits 训练习惯摘录》'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Atomic Habits 训练习惯摘录'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Atomic Habits 训练习惯摘录'), findsOneWidget);

    await tester.tap(find.text('今日训练').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.textContaining('免责声明'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('免责声明'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('记录疼痛'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('记录疼痛').first);
    await tester.pumpAndSettle();

    expect(find.text('康复记录'), findsWidgets);
    expect(find.text('疼痛记录表单'), findsOneWidget);
    expect(find.textContaining('疼痛 ≥7'), findsOneWidget);

    await tester.tap(find.text('记录疼痛 7 分'));
    await tester.pumpAndSettle();

    expect(find.text('疼痛红线已触发'), findsOneWidget);
    expect(find.textContaining('停止相关训练并就医'), findsWidgets);

    await tester.tap(find.text('今日训练').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('疼痛红线：停止相关训练'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('疼痛红线：停止相关训练'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('决策 休息'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('决策 休息'), findsOneWidget);

    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('打开验收记录'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开验收记录'));
    await tester.pumpAndSettle();

    expect(find.text('14 天自用验收'), findsWidgets);
    expect(find.text('开始 14 天验收'), findsOneWidget);
  });
}
