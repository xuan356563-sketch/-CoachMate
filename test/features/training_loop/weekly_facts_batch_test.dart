import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/exercise_training_profile.dart';
import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/data/models/weekly_report.dart';
import 'package:trainflow_ai/data/models/weekly_psych_check_in.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/data/repositories/weekly_report_repository.dart';
import 'package:trainflow_ai/data/seed/seed_training_plans.dart';
import 'package:trainflow_ai/features/weekly_report/weekly_report_page.dart';
import 'package:trainflow_ai/services/weekly_report_service.dart';
import '../../support/test_harness.dart';

void main() {
  final now = DateTime(2026, 9, 15, 12);
  final workout = seedTrainingPlans.first.workoutDays.first.copyWith(
      id: 'synthetic-day', dimensionFocus: const DimensionFocus(
          primary: [TrainingDimension.strength, TrainingDimension.breathing]));
  TrainingLog log({int completion = 0, DateTime? date, DateTime? created,
      TrainingLogKind kind = TrainingLogKind.sessionReview,
      List<ExerciseExecutionRecord> exercises = const []}) => TrainingLog(
        id: 'synthetic-log', workoutDayId: workout.id, date: date ?? now,
        completed: completion == 100, rpe: 5, fatigueLevel: 3, sleepQuality: 7,
        painNote: null, userNote: '合成事实测试', createdAt: created ?? now,
        completionPercentage: completion, kind: kind, exerciseRecords: exercises);
  WeeklyReport report(List<TrainingLog> logs, {WeeklyPsychCheckIn? checkIn}) =>
      WeeklyReportService().buildWeeklyReport(
        profile: InMemoryUserProfileRepository.defaultProfile.copyWith(weeklyTrainingDays: 3),
        todayWorkout: workout, plannedWorkoutsForWeek: [workout],
        logs: logs, bodyMetrics: [], readinessScore: null,
        trainingStatusLabel: '无法评估', trainingStatusReason: '合成测试',
        recoveryCountdownLabel: '', recoveryAdvice: '', achievementSummaryLabel: '',
        psychCheckIn: checkIn, evaluatedAt: now);

  test('零完成及逐步记录不制造训练维度，部分完成不推断整课维度', () {
    for (final entry in [log(), log(completion: 50),
      log(completion: 100, kind: TrainingLogKind.playerStep)]) {
      expect(report([entry]).dimensionExposure.every((e) => e.completedSessions == 0), isTrue);
    }
    expect(report([log(completion: 100)]).dimensionExposure
        .singleWhere((e) => e.dimension == TrainingDimension.strength).completedSessions, 1);
  });

  test('有动作明细时，只依据实际完成组数归属维度', () {
    final zeroExercise = ExerciseExecutionRecord(exerciseId: 'exercise-goblet-squat',
        exerciseName: '高脚杯深蹲', plannedSetCount: 3, completedSetCount: 0,
        repetitionsPerSet: 10, weightKg: 8);
    final result = report([log(completion: 100, exercises: [zeroExercise])]);
    expect(result.dimensionExposure.every((e) => e.completedSessions == 0), isTrue);
    final partial = report([log(completion: 50, exercises: [
      const ExerciseExecutionRecord(exerciseId: 'exercise-goblet-squat',
          exerciseName: '高脚杯深蹲', plannedSetCount: 3, completedSetCount: 1,
          repetitionsPerSet: 10, weightKg: 8),
    ])]);
    expect(partial.dimensionExposure.singleWhere((e) => e.dimension == TrainingDimension.strength).completedSessions, 1);
    expect(partial.dimensionExposure.singleWhere((e) => e.dimension == TrainingDimension.breathing).completedSessions, 0);
  });

  test('半次完成保留小数，不把折算值写成一次实际完成', () {
    final result = report([log(completion: 50)]);
    expect(result.completionRate, closeTo(0.5 / 3, 0.0001));
    expect(result.realityObservation, contains('0.50/3'));
    expect(result.markdown, isNot(contains('完成率：1/3')));
    expect(WeeklyReport.fromJson(result.toJson()).realityObservation, result.realityObservation);
  });

  test('补录按训练日期归属，未来及窗口外记录不进入本期', () {
    for (final entry in [
      log(completion: 100, date: now.subtract(const Duration(days: 8))),
      log(completion: 100, date: now.add(const Duration(days: 1))),
      log(completion: 100, created: now.add(const Duration(minutes: 1))),
    ]) {
      expect(report([entry]).completionRate, 0);
    }
    final recent = report([log(completion: 50, date: now.subtract(const Duration(days: 1)))]);
    expect(recent.completionRate, closeTo(0.5 / 3, 0.0001));
    expect(recent.realityObservation, contains('训练日期'));
  });

  test('跳过全部状态评分或仅填备注不产生常规恢复结论', () {
    for (final checkIn in [const WeeklyPsychCheckIn(),
      const WeeklyPsychCheckIn(weekNote: '仅记录备注')]) {
      final result = report([], checkIn: checkIn);
      expect(result.psychRiskLabel, '无法评估');
      expect(WeeklyReport.fromJson(result.toJson()).psychRiskLabel, '无法评估');
    }
    expect(report([], checkIn: const WeeklyPsychCheckIn(perceivedStress: 5))
        .psychRiskLabel, '观察');
  });

  testWidgets('页面保存空白复盘仍无法评估，保存与回读保留事实说明', (tester) async {
    tester.view.physicalSize = const Size(393, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = TestHarness();
    await tester.pumpWidget(harness.buildApp(const MaterialApp(home: WeeklyReportPage())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('weekly-psych-save')));
    await tester.pumpAndSettle();
    final saved = PersistedWeeklyReportRepository(harness.storageService).listReports().single;
    expect(saved.psychRiskLabel, '无法评估');
    expect(find.text(saved.realityObservation), findsOneWidget);
    expect(find.textContaining('实际记录 0 次，计划'), findsWidgets);
    expect(saved.dimensionExposure.every((e) => e.completedSessions == 0), isTrue);
  });
}
