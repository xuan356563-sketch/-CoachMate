import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/data/models/exercise_training_profile.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/data/models/weekly_report.dart';
import 'package:trainflow_ai/data/models/weekly_psych_check_in.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/data/seed/seed_training_plans.dart';
import 'package:trainflow_ai/services/coach_feedback_policy.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/services/weekly_report_service.dart';

void main() {
  test('周报使用 GROW 四段并只给用户可选择的过程方向', () {
    final DateTime now = DateTime.now();
    final report = WeeklyReportService().buildWeeklyReport(
      profile: PersistedUserProfileRepository(
        InMemoryLocalStorageService(),
      ).getProfile(),
      todayWorkout: seedTrainingPlans.first.workoutDays.first,
      logs: <TrainingLog>[
        _log(now: now, rpe: 6, completionPercentage: 75),
      ],
      bodyMetrics: const [],
      readinessScore: 80,
      trainingStatusLabel: '维持',
      trainingStatusReason: '训练状态维持稳定。',
      recoveryCountdownLabel: '预计 12 小时',
      recoveryAdvice: '按计划恢复。',
      achievementSummaryLabel: '本周记录 1 次过程证据。',
      psychCheckIn: const WeeklyPsychCheckIn(
        motivation: 4,
        perceivedStress: 2,
        recoveryFeel: 4,
        weekNote: '周末训练更从容',
      ),
    );

    expect(report.goalSummary, contains('过程目标'));
    expect(report.realityObservation, contains('完成'));
    expect(report.options, isNotEmpty);
    expect(report.options.length, lessThanOrEqualTo(3));
    expect(report.reflectionQuestion, endsWith('？'));
    expect(report.psychRiskLevel, PsychRiskLevel.normal);
    expect(
      CoachFeedbackPolicy.containsForbiddenCopy(report.markdown),
      isFalse,
    );
  });

  test('两个独立风险信号进入建议级并减少推动', () {
    final DateTime now = DateTime.now();
    final report = WeeklyReportService().buildWeeklyReport(
      profile: PersistedUserProfileRepository(
        InMemoryLocalStorageService(),
      ).getProfile(),
      todayWorkout: seedTrainingPlans.first.workoutDays.first,
      logs: <TrainingLog>[
        _log(now: now, rpe: 9, completionPercentage: 100),
      ],
      bodyMetrics: const [],
      readinessScore: 72,
      trainingStatusLabel: '维持',
      trainingStatusReason: '训练负荷需要复核。',
      recoveryCountdownLabel: '预计 24 小时',
      recoveryAdvice: '先完成恢复。',
      achievementSummaryLabel: '本周记录 1 次过程证据。',
      psychCheckIn: const WeeklyPsychCheckIn(
        motivation: 2,
        perceivedStress: 5,
        recoveryFeel: 2,
      ),
    );

    expect(report.psychRiskLevel, PsychRiskLevel.advise);
    expect(report.options.first.label, contains('恢复'));
    expect(report.realityObservation, isNot(contains('不够')));
  });

  test('旧周报缺少心理字段时保持为空和正常级', () {
    final WeeklyReport restored = WeeklyReport.fromJson(
      <String, dynamic>{
        'id': 'legacy',
        'weekLabel': '7/20 - 7/26',
        'generatedAt': '2026-07-27T08:00:00.000',
      },
    );

    expect(restored.psychCheckIn, isNull);
    expect(restored.psychRiskLevel, PsychRiskLevel.normal);
    expect(restored.options, isEmpty);
    expect(restored.dimensionExposure, isEmpty);
  });

  test('周报按结构课程统计五维计划和实际完成次数', () {
    final DateTime now = DateTime.now();
    final WorkoutDay workout =
        seedTrainingPlans.first.workoutDays.first.copyWith(
      id: 'day-1',
      dimensionFocus: const DimensionFocus(
        primary: <TrainingDimension>[
          TrainingDimension.strength,
          TrainingDimension.eccentric,
        ],
        touch: <TrainingDimension>[TrainingDimension.breathing],
      ),
    );

    final WeeklyReport report = WeeklyReportService().buildWeeklyReport(
      profile: PersistedUserProfileRepository(
        InMemoryLocalStorageService(),
      ).getProfile(),
      todayWorkout: workout,
      plannedWorkoutsForWeek: <WorkoutDay>[workout],
      logs: <TrainingLog>[
        _log(now: now, rpe: 6, completionPercentage: 100),
      ],
      bodyMetrics: const [],
      readinessScore: 80,
      trainingStatusLabel: '维持',
      trainingStatusReason: '训练状态稳定。',
      recoveryCountdownLabel: '预计 12 小时',
      recoveryAdvice: '按计划恢复。',
      achievementSummaryLabel: '本周记录 1 次过程证据。',
    );

    final TrainingDimensionExposure strength = report.dimensionExposure
        .singleWhere((TrainingDimensionExposure item) =>
            item.dimension == TrainingDimension.strength);
    expect(strength.plannedSessions, 1);
    expect(strength.completedSessions, 1);
  });
}

TrainingLog _log({
  required DateTime now,
  required int rpe,
  required int completionPercentage,
}) {
  return TrainingLog(
    id: 'log-$rpe',
    workoutDayId: 'day-1',
    date: now,
    completed: completionPercentage == 100,
    rpe: rpe,
    fatigueLevel: rpe,
    sleepQuality: 7,
    painNote: null,
    userNote: null,
    createdAt: now,
    kind: TrainingLogKind.sessionReview,
    completionPercentage: completionPercentage,
  );
}
