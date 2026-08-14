import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/training_reminder.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/services/training_reminder_service.dart';

void main() {
  group('训练提醒心理安全策略', () {
    test('保护态只保留恢复与复盘提醒，不继续推动训练', () {
      final List<TrainingReminder> reminders = _buildReminders(
        readinessScore: 42,
        trainingStatusLabel: '过度风险',
        remainingRecoveryHours: 18,
      );

      expect(
        reminders.map((TrainingReminder item) => item.type),
        containsAll(<TrainingReminderType>[
          TrainingReminderType.proactiveDeload,
          TrainingReminderType.recoveryCheck,
          TrainingReminderType.weeklyReport,
        ]),
      );
      expect(
        reminders.map((TrainingReminder item) => item.type),
        isNot(contains(TrainingReminderType.dailyPlan)),
      );
      expect(
        reminders.map((TrainingReminder item) => item.type),
        isNot(contains(TrainingReminderType.starterProgram)),
      );
      expect(
        reminders.map((TrainingReminder item) => item.type),
        isNot(contains(TrainingReminderType.formalPlan)),
      );
    });

    test('一般疲劳仍提供轻松版确认和当天训练入口', () {
      final List<TrainingReminder> reminders = _buildReminders(
        readinessScore: 55,
        trainingStatusLabel: '需要调整',
      );

      expect(
        reminders.map((TrainingReminder item) => item.type),
        containsAll(<TrainingReminderType>[
          TrainingReminderType.proactiveDeload,
          TrainingReminderType.dailyPlan,
          TrainingReminderType.starterProgram,
          TrainingReminderType.weeklyReport,
        ]),
      );
    });

    test('缺少身体指标时不因默认低分误判为保护态', () {
      final List<TrainingReminder> reminders = _buildReminders(
        readinessScore: 48,
        trainingStatusLabel: '数据积累中',
      );

      expect(
        reminders.map((TrainingReminder item) => item.type),
        contains(TrainingReminderType.starterProgram),
      );
    });
  });
}

List<TrainingReminder> _buildReminders({
  required int readinessScore,
  required String trainingStatusLabel,
  int remainingRecoveryHours = 0,
}) {
  final DateTime now = DateTime(2026, 7, 26, 8);
  return TrainingReminderService().buildReminders(
    enabled: true,
    preferredTimeLabel: '20:30',
    profile: UserProfile(
      id: 'athlete-1',
      name: '测试用户',
      gender: Gender.unknown,
      age: 30,
      heightCm: 170,
      weightKg: 65,
      trainingGoal: '稳定训练',
      mainSports: const <MainSport>[MainSport.generalFitness],
      weeklyTrainingDays: 3,
      dailyAvailableMinutes: 30,
      injuryHistory: const <String>[],
      workScheduleType: WorkScheduleType.regularOffice,
      createdAt: now,
      updatedAt: now,
    ),
    todayWorkout: const WorkoutDay(
      id: 'workout-1',
      planId: 'plan-1',
      weekIndex: 1,
      dayIndex: 1,
      title: '轻松跑',
      trainingType: TrainingType.easyRun,
      decisionType: TrainingDecisionType.normal,
      estimatedMinutes: 30,
      intensity: 'RPE 5',
      foamRollingSteps: <String>[],
      dynamicStretchSteps: <String>[],
      activationSteps: <String>[],
      warmupSteps: <String>[],
      mainSets: <String>[],
      accessoryWork: <String>[],
      cooldownSteps: <String>[],
      coachNotes: '',
      evidenceSources: <Never>[],
    ),
    starterProgramStreak: 5,
    starterProgramDayIndex: 6,
    formalPlanUnlocked: false,
    latestBodyMetric: null,
    remainingRecoveryHours: remainingRecoveryHours,
    recoveryAdvice: '优先恢复',
    readinessScore: readinessScore,
    trainingStatusLabel: trainingStatusLabel,
    morningReportAdvice: '降低训练压力',
  );
}
