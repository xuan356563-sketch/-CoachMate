import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/achievement.dart';
import '../../data/models/ai_artifact.dart';
import '../../data/models/body_data_quality.dart';
import '../../data/models/body_metric_export.dart';
import '../../data/models/body_metric_goal.dart';
import '../../data/models/body_metric.dart';
import '../../data/models/body_metric_import.dart';
import '../../data/models/body_metric_revision.dart';
import '../../data/models/body_trend_insight.dart';
import '../../data/models/coach_feedback.dart';
import '../../data/models/daily_adjustment.dart';
import '../../data/models/daily_check_in.dart';
import '../../data/models/exercise.dart';
import '../../data/models/formal_ai_plan.dart';
import '../../data/models/imported_workout.dart';
import '../../data/models/knowledge_entry.dart';
import '../../data/models/meal_guide.dart';
import '../../data/models/motion_check.dart';
import '../../data/models/motion_pose.dart';
import '../../data/models/pain_log.dart';
import '../../data/models/plan_adjustment.dart';
import '../../data/models/pre_exercise_clearance.dart';
import '../../data/models/race.dart';
import '../../data/models/starter_graduation_report.dart';
import '../../data/models/starter_program.dart';
import '../../data/models/training_load_curve.dart';
import '../../data/models/training_log.dart';
import '../../data/models/training_plan.dart';
import '../../data/models/training_reminder.dart';
import '../../data/models/training_rule_audit.dart';
import '../../data/models/training_schedule.dart';
import '../../data/models/user_insight.dart';
import '../../data/models/user_profile.dart';
import '../../data/models/user_trust_review.dart';
import '../../data/models/weekly_report.dart';
import '../../data/models/weekly_report_export.dart';
import '../../data/models/weekly_psych_check_in.dart';
import '../../data/models/workout_day.dart';
import '../../data/models/workout_player_step.dart';
import '../../data/repositories/exercise_repository.dart';
import '../../data/repositories/formal_ai_plan_repository.dart';
import '../../data/repositories/imported_workout_repository.dart';
import '../../data/repositories/knowledge_repository.dart';
import '../../data/repositories/meal_guide_repository.dart';
import '../../data/repositories/motion_analysis_repository.dart';
import '../../data/repositories/motion_check_repository.dart';
import '../../data/repositories/pain_log_repository.dart';
import '../../data/repositories/race_repository.dart';
import '../../data/repositories/starter_program_repository.dart';
import '../../data/repositories/training_plan_repository.dart';
import '../../data/repositories/user_insight_repository.dart';
import '../../data/repositories/weekly_report_export_repository.dart';
import '../../data/repositories/weekly_report_repository.dart';
import '../../services/activity_import_service.dart';
import '../../services/ai_training_service.dart';
import '../../services/body_data_quality_service.dart';
import '../../services/body_metric_goal_service.dart';
import '../../services/body_trend_insight_service.dart';
import '../../services/coach_feedback_policy.dart';
import '../../services/daily_adjustment_service.dart';
import '../../services/daily_check_in_service.dart';
import '../../services/exercise_substitution_service.dart';
import '../../services/formal_ai_plan_service.dart';
import '../../services/knowledge_import_service.dart';
import '../../services/local_storage_service.dart';
import '../../services/motion_analysis_service.dart';
import '../../services/motion_pose_analysis_service.dart';
import '../../services/motion_pose_import_service.dart';
import '../../services/race_auto_schedule_service.dart';
import '../../services/race_import_service.dart';
import '../../services/starter_graduation_service.dart';
import '../../services/training_reminder_service.dart';
import '../../services/training_rule_audit_service.dart';
import '../../services/user_insight_service.dart';
import '../../services/user_trust_review_service.dart';
import '../../services/weekly_report_service.dart';
import '../daily_adjustment/application/daily_adjustment_controller.dart';
import '../data_center/application/body_metric_controller.dart';
import '../data_center/application/body_metric_export_controller.dart';
import '../growth/application/growth_evidence_controller.dart';
import '../meal_guide/application/meal_preference_controller.dart';
import '../pet/application/pet_controller.dart';
import '../training_log/application/training_record_save_request.dart';
import '../profile/application/achievement_controller.dart';
import '../profile/application/user_profile_controller.dart';
import '../profile/application/training_schedule_controller.dart';
import '../reminders/application/reminder_settings_controller.dart';
import '../training_log/application/training_log_controller.dart';
import '../training_plan/application/four_week_plan_controller.dart';
import '../training_plan/application/plan_adjustment_controller.dart';
import '../training_plan/application/pre_exercise_clearance_controller.dart';
import '../workout_player/application/workout_player_assist_controller.dart';

const Object _unchanged = Object();

ExerciseExecutionRecord _normalizedExerciseRecord(
  ExerciseExecutionRecord item,
) {
  final String exerciseId = item.exerciseId?.trim() ?? '';
  final List<StrengthSetExecutionRecord> sets =
      List<StrengthSetExecutionRecord>.unmodifiable(
    item.sets.indexed.map(
      ((int, StrengthSetExecutionRecord) indexed) {
        final StrengthSetExecutionRecord set = indexed.$2;
        return StrengthSetExecutionRecord(
          setIndex: indexed.$1 + 1,
          repetitions: set.repetitions,
          weightKg: set.weightKg,
          rpe: set.rpe,
          durationSeconds: set.durationSeconds,
        );
      },
    ),
  );
  return ExerciseExecutionRecord(
    exerciseId: exerciseId.isEmpty ? null : exerciseId,
    exerciseName: item.exerciseName.trim(),
    plannedSetCount: item.plannedSetCount,
    completedSetCount: sets.isEmpty ? item.completedSetCount : sets.length,
    repetitionsPerSet: item.repetitionsPerSet,
    weightKg: sets.isEmpty
        ? item.weightKg
        : sets.map((StrengthSetExecutionRecord set) => set.weightKg).reduce(
            (double first, double second) => first > second ? first : second),
    sets: sets,
    landingQuality: item.landingQuality,
  );
}

final trainingMvpProvider =
    NotifierProvider<TrainingMvpController, TrainingMvpState>(
  TrainingMvpController.new,
);

/// 跟练执行时读取的实时钟。使用函数而不是缓存的 DateTime，确保长期前台运行
/// 跨过筛查有效期后，下一次操作会立即重新裁决。
final trainingExecutionClockProvider = Provider<DateTime Function()>(
  (Ref ref) => DateTime.now,
);

final feedbackRpeProvider = NotifierProvider<FeedbackRpeController, int>(
  FeedbackRpeController.new,
);

final feedbackCompletedProvider =
    NotifierProvider<FeedbackCompletedController, bool>(
  FeedbackCompletedController.new,
);

final bodyMetricWeightProvider =
    NotifierProvider<BodyMetricWeightController, double>(
  BodyMetricWeightController.new,
);

final bodyMetricRestingHrProvider =
    NotifierProvider<BodyMetricRestingHrController, int>(
  BodyMetricRestingHrController.new,
);

final bodyMetricHrvProvider = NotifierProvider<BodyMetricHrvController, int>(
  BodyMetricHrvController.new,
);

final bodyMetricSleepProvider =
    NotifierProvider<BodyMetricSleepController, double>(
  BodyMetricSleepController.new,
);

final bodyMetricFatigueProvider =
    NotifierProvider<BodyMetricFatigueController, int>(
  BodyMetricFatigueController.new,
);

final bodyMetricMeasuredAtProvider =
    NotifierProvider<BodyMetricMeasuredAtController, DateTime>(
  BodyMetricMeasuredAtController.new,
);

final bodyMetricExportTextProvider =
    NotifierProvider<BodyMetricExportTextController, String>(
  BodyMetricExportTextController.new,
);

final bodyMetricExportPackageStatusProvider =
    NotifierProvider<BodyMetricExportPackageStatusController, String>(
  BodyMetricExportPackageStatusController.new,
);

final weeklyReportExportTextProvider =
    NotifierProvider<WeeklyReportExportTextController, String>(
  WeeklyReportExportTextController.new,
);

final weeklyReportImageExportStatusProvider =
    NotifierProvider<WeeklyReportImageExportStatusController, String>(
  WeeklyReportImageExportStatusController.new,
);

final activityImportTextProvider =
    NotifierProvider<ActivityImportTextController, String>(
  ActivityImportTextController.new,
);

final raceImportTextProvider =
    NotifierProvider<RaceImportTextController, String>(
  RaceImportTextController.new,
);

final bodyMetricCsvImportTextProvider =
    NotifierProvider<BodyMetricCsvImportTextController, String>(
  BodyMetricCsvImportTextController.new,
);

final bodyMetricSnapshotTextProvider =
    NotifierProvider<BodyMetricSnapshotTextController, String>(
  BodyMetricSnapshotTextController.new,
);

final knowledgeImportTextProvider =
    NotifierProvider<KnowledgeImportTextController, String>(
  KnowledgeImportTextController.new,
);

final bodyMetricTrendWindowProvider =
    NotifierProvider<BodyMetricTrendWindowController, BodyMetricTrendWindow>(
  BodyMetricTrendWindowController.new,
);

enum BodyMetricTrendWindow {
  sevenDays(7, '7 日'),
  thirtyDays(30, '30 日'),
  ninetyDays(90, '90 日');

  final int days;
  final String label;

  const BodyMetricTrendWindow(this.days, this.label);
}

class FeedbackRpeController extends Notifier<int> {
  @override
  int build() {
    return 6;
  }

  void setValue(int value) {
    state = value;
  }
}

class FeedbackCompletedController extends Notifier<bool> {
  @override
  bool build() {
    return true;
  }

  void setValue(bool value) {
    state = value;
  }
}

class BodyMetricWeightController extends Notifier<double> {
  @override
  double build() {
    return ref.watch(
          bodyMetricControllerProvider.select(
            (BodyMetricState value) => value.latestMetric?.weightKg,
          ),
        ) ??
        60;
  }

  void setValue(double value) {
    state = value;
  }
}

class BodyMetricRestingHrController extends Notifier<int> {
  @override
  int build() {
    return ref.watch(
          bodyMetricControllerProvider.select(
            (BodyMetricState value) => value.latestMetric?.restingHeartRate,
          ),
        ) ??
        45;
  }

  void setValue(int value) {
    state = value;
  }
}

class BodyMetricHrvController extends Notifier<int> {
  @override
  int build() {
    return ref.watch(
          bodyMetricControllerProvider.select(
            (BodyMetricState value) => value.latestMetric?.hrvMs,
          ),
        ) ??
        25;
  }

  void setValue(int value) {
    state = value;
  }
}

class BodyMetricSleepController extends Notifier<double> {
  @override
  double build() {
    return ref.watch(
          bodyMetricControllerProvider.select(
            (BodyMetricState value) => value.latestMetric?.sleepHours,
          ),
        ) ??
        4;
  }

  void setValue(double value) {
    state = value;
  }
}

class BodyMetricFatigueController extends Notifier<int> {
  @override
  int build() {
    return ref.watch(
          bodyMetricControllerProvider.select(
            (BodyMetricState value) => value.latestMetric?.fatigueLevel,
          ),
        ) ??
        1;
  }

  void setValue(int value) {
    state = value;
  }
}

class BodyMetricMeasuredAtController extends Notifier<DateTime> {
  @override
  DateTime build() {
    return _dateOnly(DateTime.now());
  }

  void useToday() {
    state = _dateOnly(DateTime.now());
  }

  void useYesterday() {
    state = _dateOnly(DateTime.now().subtract(const Duration(days: 1)));
  }

  void useTwoDaysAgo() {
    state = _dateOnly(DateTime.now().subtract(const Duration(days: 2)));
  }
}

class BodyMetricExportTextController extends Notifier<String> {
  @override
  String build() {
    return '';
  }

  void setValue(String value) {
    state = value;
  }

  void clear() {
    state = '';
  }
}

class BodyMetricExportPackageStatusController extends Notifier<String> {
  @override
  String build() {
    return '导出包尚未生成。';
  }

  void setValue(String value) {
    state = value;
  }
}

class WeeklyReportExportTextController extends Notifier<String> {
  @override
  String build() {
    return '';
  }

  void setValue(String value) {
    state = value;
  }

  void clear() {
    state = '';
  }
}

class WeeklyReportImageExportStatusController extends Notifier<String> {
  @override
  String build() {
    return '图片卡片尚未生成。';
  }

  void setValue(String value) {
    state = value;
  }
}

class ActivityImportTextController extends Notifier<String> {
  @override
  String build() {
    return sampleGpxImportText;
  }

  void setValue(String value) {
    state = value;
  }

  void useFitSummarySample() {
    state = sampleFitSummaryImportText;
  }

  void useGpxSample() {
    state = sampleGpxImportText;
  }
}

class RaceImportTextController extends Notifier<String> {
  @override
  String build() {
    return sampleRaceImportText;
  }

  void setValue(String value) {
    state = value;
  }

  void useSample() {
    state = sampleRaceImportText;
  }
}

class BodyMetricCsvImportTextController extends Notifier<String> {
  @override
  String build() {
    return sampleBodyMetricCsvImportText;
  }

  void setValue(String value) {
    state = value;
  }

  void useSample() {
    state = sampleBodyMetricCsvImportText;
  }
}

class BodyMetricSnapshotTextController extends Notifier<String> {
  @override
  String build() {
    return sampleBodyMetricSnapshotText;
  }

  void setValue(String value) {
    state = value;
  }

  void useSample() {
    state = sampleBodyMetricSnapshotText;
  }
}

class KnowledgeImportTextController extends Notifier<String> {
  @override
  String build() {
    return sampleKnowledgeImportText;
  }

  void setValue(String value) {
    state = value;
  }

  void useSample() {
    state = sampleKnowledgeImportText;
  }
}

class BodyMetricTrendWindowController extends Notifier<BodyMetricTrendWindow> {
  @override
  BodyMetricTrendWindow build() {
    return BodyMetricTrendWindow.sevenDays;
  }

  void setWindow(BodyMetricTrendWindow window) {
    state = window;
  }
}

class TrainingMvpState {
  final bool profileCompleted;
  final UserProfile profile;
  final List<TrainingPlan> plans;
  final List<PlanAdjustment> planAdjustments;
  final String planAdjustmentStatusMessage;
  final List<Exercise> exercises;
  final List<TrainingBook> knowledgeBooks;
  final List<BookQuote> bookQuotes;
  final List<CitationLink> citationLinks;
  final String knowledgeSearchQuery;
  final String knowledgeImportStatusMessage;
  final List<MealGuide> mealGuides;
  final List<MotionCheckRule> motionChecks;
  final List<RacePlan> races;
  final String raceImportStatusMessage;
  final List<BodyMetric> bodyMetrics;
  final List<BodyMetricRevision> bodyMetricRevisions;
  final BodyMetric? pendingBodyMetric;
  final String bodyMetricManualStatusMessage;
  final List<BodyMetricImportResult> bodyMetricImportResults;
  final String bodyMetricImportStatusMessage;
  final String bodyMetricSnapshotStatusMessage;
  final List<BodyMetricExportRecord> bodyMetricExportRecords;
  final String bodyMetricExportStatusMessage;
  final List<AchievementDefinition> achievementDefinitions;
  final List<AchievementRecord> achievementRecords;
  final String achievementRecordStatusMessage;
  final List<ImportedWorkout> importedWorkouts;
  final String activityImportStatusMessage;
  final List<StarterProgramDay> starterProgramDays;
  final StarterProgramGoal starterProgramGoal;
  final int starterProgramDayIndex;
  final int starterProgramStreak;
  final bool starterProgramRescueMode;
  final String starterProgramStatusMessage;
  final bool formalPlanUnlocked;
  final String formalPlanStatusMessage;
  final FormalAiPlan? formalAiPlan;
  final bool remindersEnabled;
  final String reminderTimeLabel;
  final String reminderStatusMessage;
  final String dailyCheckInStatusMessage;
  final int dailyAvailableMinutesOverride;
  final WorkStressLevel dailyWorkStress;
  final TrainingEnvironment dailyTrainingEnvironment;
  final WeatherCondition dailyWeather;
  final String dailyAdjustmentStatusMessage;
  final int workoutPlayerStepIndex;
  final bool workoutPlayerDeloaded;
  final bool workoutPlayerFinished;
  final String? activeWorkoutPlayerDayId;
  final List<String> workoutPlayerEvents;
  final String workoutPlayerStatusMessage;
  final int workoutPlayerRemainingSeconds;
  final bool workoutPlayerTimerRunning;
  final bool workoutPlayerVoiceEnabled;
  final List<String> workoutPlayerVoiceQueue;
  final String workoutPlayerVoiceStatusMessage;
  final bool workoutPlayerScreenAwakeRequested;
  final String workoutPlayerScreenAwakeStatusMessage;
  final MealScenario mealScenario;
  final List<TrainingLog> logs;
  final List<PainLog> painLogs;
  final List<MotionAnalysisResult> motionAnalysisResults;
  final String motionAnalysisStatusMessage;
  final String userInsightStatusMessage;
  final UserInsightTableState userInsightTableState;
  final List<WeeklyReport> savedWeeklyReports;
  final String weeklyReportSaveStatusMessage;
  final List<WeeklyReportExportRecord> weeklyReportExportRecords;
  final String weeklyReportExportStatusMessage;
  final List<String> coachAdvices;
  final ScheduledWorkout? scheduledTodayWorkout;

  const TrainingMvpState({
    required this.profileCompleted,
    required this.profile,
    required this.plans,
    required this.planAdjustments,
    required this.planAdjustmentStatusMessage,
    required this.exercises,
    required this.knowledgeBooks,
    required this.bookQuotes,
    required this.citationLinks,
    required this.knowledgeSearchQuery,
    required this.knowledgeImportStatusMessage,
    required this.mealGuides,
    required this.motionChecks,
    required this.races,
    required this.raceImportStatusMessage,
    required this.bodyMetrics,
    required this.bodyMetricRevisions,
    required this.pendingBodyMetric,
    required this.bodyMetricManualStatusMessage,
    required this.bodyMetricImportResults,
    required this.bodyMetricImportStatusMessage,
    required this.bodyMetricSnapshotStatusMessage,
    required this.bodyMetricExportRecords,
    required this.bodyMetricExportStatusMessage,
    required this.achievementDefinitions,
    required this.achievementRecords,
    required this.achievementRecordStatusMessage,
    required this.importedWorkouts,
    required this.activityImportStatusMessage,
    required this.starterProgramDays,
    required this.starterProgramGoal,
    required this.starterProgramDayIndex,
    required this.starterProgramStreak,
    required this.starterProgramRescueMode,
    required this.starterProgramStatusMessage,
    required this.formalPlanUnlocked,
    required this.formalPlanStatusMessage,
    required this.formalAiPlan,
    required this.remindersEnabled,
    required this.reminderTimeLabel,
    required this.reminderStatusMessage,
    required this.dailyCheckInStatusMessage,
    required this.dailyAvailableMinutesOverride,
    required this.dailyWorkStress,
    required this.dailyTrainingEnvironment,
    required this.dailyWeather,
    required this.dailyAdjustmentStatusMessage,
    required this.workoutPlayerStepIndex,
    required this.workoutPlayerDeloaded,
    required this.workoutPlayerFinished,
    required this.activeWorkoutPlayerDayId,
    required this.workoutPlayerEvents,
    required this.workoutPlayerStatusMessage,
    required this.workoutPlayerRemainingSeconds,
    required this.workoutPlayerTimerRunning,
    required this.workoutPlayerVoiceEnabled,
    required this.workoutPlayerVoiceQueue,
    required this.workoutPlayerVoiceStatusMessage,
    required this.workoutPlayerScreenAwakeRequested,
    required this.workoutPlayerScreenAwakeStatusMessage,
    required this.mealScenario,
    required this.logs,
    required this.painLogs,
    required this.motionAnalysisResults,
    required this.motionAnalysisStatusMessage,
    required this.userInsightStatusMessage,
    required this.userInsightTableState,
    required this.savedWeeklyReports,
    required this.weeklyReportSaveStatusMessage,
    required this.weeklyReportExportRecords,
    required this.weeklyReportExportStatusMessage,
    required this.coachAdvices,
    this.scheduledTodayWorkout,
  });

  TrainingPlan get activePlan {
    return plans.first;
  }

  WorkoutDay get baseTodayWorkout {
    final ScheduledWorkout? scheduled = scheduledTodayWorkout;
    if (scheduled == null) {
      return activePlan.workoutDays.first;
    }
    final WorkoutDay base =
        findWorkoutDay(scheduled.workoutDayId) ?? activePlan.workoutDays.first;
    return applyScheduledWorkout(base, scheduled);
  }

  bool get noEquipmentConstraint {
    return profile.equipmentAccessType == EquipmentAccessType.none ||
        dailyTrainingEnvironment == TrainingEnvironment.noEquipment;
  }

  WorkoutDay withEquipmentConstraint(WorkoutDay workout) {
    if (!noEquipmentConstraint) {
      return workout;
    }
    return ExerciseSubstitutionService()
        .applyNoEquipment(workout: workout, exercises: exercises)
        .workout;
  }

  WorkoutDay get todayWorkout {
    WorkoutDay workout = baseTodayWorkout;
    final PainLog? painLog = latestPainLog;
    if (painLog != null && painLog.shouldDeloadTraining) {
      if (painLog.requiresMedicalAttention) {
        workout = baseTodayWorkout.copyWith(
          title: '疼痛红线：停止相关训练',
          trainingType: TrainingType.rehab,
          decisionType: TrainingDecisionType.rest,
          estimatedMinutes: 0,
          intensity: '停止相关训练',
          foamRollingSteps: [],
          dynamicStretchSteps: [],
          activationSteps: [],
          warmupSteps: [],
          mainSets: [
            '暂停涉及${painLog.bodyPart}的训练',
            '联系医生或物理治疗师评估疼痛原因',
          ],
          accessoryWork: ['如无痛，可进行 5-10 分钟轻松步行或呼吸放松'],
          cooldownSteps: ['记录疼痛位置、等级和出现时机', '持续疼痛不要补课'],
          coachNotes: '${painLog.medicalAttentionReason}，本系统不替代医疗诊断。',
        );
      } else {
        workout = baseTodayWorkout.copyWith(
          title: '疼痛反馈：自动降级恢复训练',
          trainingType: TrainingType.rehab,
          decisionType: TrainingDecisionType.recovery,
          estimatedMinutes: 25,
          intensity: 'RPE 2-3',
          foamRollingSteps: ['避开疼痛点，对${painLog.bodyPart}周边轻柔放松 3 分钟'],
          dynamicStretchSteps: ['选择无痛活动度练习 2 轮', '动作过程中疼痛上升立即停止'],
          activationSteps: ['低强度核心激活 2 组', '无痛范围内臀桥或死虫 2 组'],
          warmupSteps: ['呼吸调整 2 分钟'],
          mainSets: [
            '低强度步行或椭圆机 10-15 分钟',
            '${painLog.bodyPart}无痛活动度练习',
          ],
          accessoryWork: ['跳过原计划高强度内容'],
          cooldownSteps: ['训练后复测疼痛等级', '记录是否比训练前加重'],
          coachNotes:
              '${painLog.bodyPart}疼痛 ${painLog.painLevel}/10，今日计划自动降级；若疼痛持续或加重，请停止训练并就医。',
        );
      }
    }

    return withEquipmentConstraint(workout);
  }

  TrainingLog? get latestLog {
    if (logs.isEmpty) {
      return null;
    }
    return logs.first;
  }

  TrainingLog? get latestWorkoutSessionReview {
    final String workoutDayId = activeWorkoutPlayerWorkout.id;
    for (final TrainingLog log in logs) {
      if (log.workoutDayId == workoutDayId && log.isSessionReview) {
        return log;
      }
    }
    return null;
  }

  MealGuide get activeMealGuide {
    for (final MealGuide guide in mealGuides) {
      if (guide.scenario == mealScenario) {
        return guide;
      }
    }
    return mealGuides.first;
  }

  MotionCheckRule get featuredMotionCheck {
    final MotionAnalysisResult? result = latestMotionAnalysisResult;
    if (result == null) {
      return motionChecks.first;
    }
    return findMotionCheck(result.sourceRuleId) ?? motionChecks.first;
  }

  MotionAnalysisResult? get latestMotionAnalysisResult {
    if (motionAnalysisResults.isEmpty) {
      return null;
    }
    return motionAnalysisResults.first;
  }

  RacePlan get featuredRace {
    return races.first;
  }

  StarterProgramDay get activeStarterProgramDay {
    for (final StarterProgramDay day in starterProgramDays) {
      if (day.goal == starterProgramGoal &&
          day.dayIndex == starterProgramDayIndex) {
        return day;
      }
    }
    return starterProgramDays.first;
  }

  List<WorkoutPlayerStep> get workoutPlayerSteps {
    return buildWorkoutPlayerSteps(
      activeWorkoutPlayerWorkout,
      deloaded: workoutPlayerDeloaded,
    );
  }

  WorkoutDay get activeWorkoutPlayerWorkout {
    final String? workoutDayId = activeWorkoutPlayerDayId;
    if (workoutDayId == null) {
      return todayWorkout;
    }
    return withEquipmentConstraint(
        findWorkoutDay(workoutDayId) ?? todayWorkout);
  }

  WorkoutPlayerStep get activeWorkoutPlayerStep {
    final List<WorkoutPlayerStep> steps = workoutPlayerSteps;
    final int index = workoutPlayerSafeIndex;
    return steps[index];
  }

  int get workoutPlayerSafeIndex {
    final List<WorkoutPlayerStep> steps = workoutPlayerSteps;
    if (steps.isEmpty) {
      return 0;
    }
    return workoutPlayerStepIndex.clamp(0, steps.length - 1).toInt();
  }

  String get workoutPlayerProgressLabel {
    return '${workoutPlayerSafeIndex + 1}/${workoutPlayerSteps.length}';
  }

  String get workoutPlayerRemainingLabel {
    return _formatCountdownSeconds(workoutPlayerRemainingSeconds);
  }

  double get workoutPlayerCountdownProgress {
    final int totalSeconds = activeWorkoutPlayerStep.estimatedSeconds;
    if (totalSeconds <= 0) {
      return 1;
    }
    final int safeRemaining =
        workoutPlayerRemainingSeconds.clamp(0, totalSeconds).toInt();
    return (1 - safeRemaining / totalSeconds).clamp(0, 1).toDouble();
  }

  String get workoutPlayerVoiceSummaryLabel {
    return workoutPlayerVoiceEnabled ? 'TTS 队列开启' : 'TTS 队列关闭';
  }

  String get workoutPlayerScreenAwakeSummaryLabel {
    return workoutPlayerScreenAwakeRequested ? '已请求常亮' : '未请求常亮';
  }

  PainLog? get latestPainLog {
    if (painLogs.isEmpty) {
      return null;
    }
    return painLogs.first;
  }

  BodyMetric? get latestBodyMetric {
    if (bodyMetrics.isEmpty) {
      return null;
    }
    return bodyMetrics.first;
  }

  BodyMetricExportRecord? get latestBodyMetricExportRecord {
    if (bodyMetricExportRecords.isEmpty) {
      return null;
    }
    return bodyMetricExportRecords.first;
  }

  ImportedWorkout? get latestImportedWorkout {
    if (importedWorkouts.isEmpty) {
      return null;
    }
    return importedWorkouts.first;
  }

  WeeklyReportExportRecord? get latestWeeklyReportExportRecord {
    if (weeklyReportExportRecords.isEmpty) {
      return null;
    }
    return weeklyReportExportRecords.first;
  }

  List<BodyMetric> get recentBodyMetrics {
    return bodyMetrics.take(7).toList();
  }

  List<BodyMetric> bodyMetricsForWindow(BodyMetricTrendWindow window) {
    if (bodyMetrics.isEmpty) {
      return const [];
    }
    final DateTime latestDate = _dateOnly(bodyMetrics.first.measuredAt);
    final DateTime earliestDate =
        latestDate.subtract(Duration(days: window.days - 1));
    return bodyMetrics.where((BodyMetric metric) {
      final DateTime measuredDate = _dateOnly(metric.measuredAt);
      return !measuredDate.isBefore(earliestDate) &&
          !measuredDate.isAfter(latestDate);
    }).toList();
  }

  double averageWeightForWindow(BodyMetricTrendWindow window) {
    return _average(
      bodyMetricsForWindow(window).map((BodyMetric metric) => metric.weightKg),
    );
  }

  double averageSleepForWindow(BodyMetricTrendWindow window) {
    return _average(
      bodyMetricsForWindow(window)
          .map((BodyMetric metric) => metric.sleepHours),
    );
  }

  double averageRestingHrForWindow(BodyMetricTrendWindow window) {
    return _average(
      bodyMetricsForWindow(window)
          .map((BodyMetric metric) => metric.restingHeartRate.toDouble()),
    );
  }

  double averageHrvForWindow(BodyMetricTrendWindow window) {
    return _average(
      bodyMetricsForWindow(window)
          .map((BodyMetric metric) => metric.hrvMs.toDouble()),
    );
  }

  double averageFatigueForWindow(BodyMetricTrendWindow window) {
    return _average(
      bodyMetricsForWindow(window)
          .map((BodyMetric metric) => metric.fatigueLevel.toDouble()),
    );
  }

  double get averageWeight7d {
    return _average(
      recentBodyMetrics.map((BodyMetric metric) => metric.weightKg),
    );
  }

  double get averageSleep7d {
    return _average(
      recentBodyMetrics.map((BodyMetric metric) => metric.sleepHours),
    );
  }

  double get averageRestingHr7d {
    return _average(
      recentBodyMetrics
          .map((BodyMetric metric) => metric.restingHeartRate.toDouble()),
    );
  }

  double get averageHrv7d {
    return _average(
      recentBodyMetrics.map((BodyMetric metric) => metric.hrvMs.toDouble()),
    );
  }

  double get averageFatigue7d {
    return _average(
      recentBodyMetrics
          .map((BodyMetric metric) => metric.fatigueLevel.toDouble()),
    );
  }

  String get bodyMetricJsonExport {
    const JsonEncoder encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(
      bodyMetrics.map((BodyMetric metric) => metric.toJson()).toList(),
    );
  }

  String get bodyMetricCsvExport {
    final List<List<String>> rows = [
      [
        'measured_at',
        'weight_kg',
        'body_fat_percentage',
        'resting_heart_rate',
        'hrv_ms',
        'sleep_hours',
        'fatigue_level',
        'soreness_level',
        'mood',
        'source',
        'note',
      ],
      for (final BodyMetric metric in bodyMetrics)
        [
          metric.measuredAt.toIso8601String(),
          metric.weightKg.toStringAsFixed(1),
          metric.bodyFatPercentage.toStringAsFixed(1),
          '${metric.restingHeartRate}',
          '${metric.hrvMs}',
          metric.sleepHours.toStringAsFixed(1),
          '${metric.fatigueLevel}',
          '${metric.sorenessLevel}',
          metric.moodLabel,
          metric.source.jsonValue,
          metric.note,
        ],
    ];
    return rows
        .map((List<String> row) => row.map(_csvCell).join(','))
        .join('\n');
  }

  String get bodyMetricExportPackageSummary {
    final int jsonBytes = utf8.encode(bodyMetricJsonExport).length;
    final int csvBytes = utf8.encode(bodyMetricCsvExport).length;

    return [
      '导出包已生成：${bodyMetrics.length} 条身体数据。',
      'body_metrics.json · ${_formatBytes(jsonBytes)}',
      'body_metrics.csv · ${_formatBytes(csvBytes)}',
      '下一步可接系统保存、分享或本地数据库归档。',
    ].join('\n');
  }

  BodyDataQualityReport get bodyDataQualityReport {
    return BodyDataQualityService().buildReport(bodyMetrics);
  }

  BodyTrendInsightReport get bodyTrendInsightReport {
    return bodyTrendInsightReportForWindow(BodyMetricTrendWindow.sevenDays);
  }

  BodyTrendInsightReport bodyTrendInsightReportForWindow(
    BodyMetricTrendWindow window,
  ) {
    return BodyTrendInsightService().buildReport(
      bodyMetrics: bodyMetrics,
      profile: profile,
      acuteLoadScore: acuteLoadScore,
      windowDays: window.days,
    );
  }

  BodyMetricGoalReport get bodyMetricGoalReport {
    return BodyMetricGoalService().buildReport(
      bodyMetrics: bodyMetrics,
      profile: profile,
    );
  }

  bool get requiresMedicalAttention {
    return latestPainLog?.requiresMedicalAttention ?? false;
  }

  int get recommendedRecoveryHours {
    final int baseHours = switch (todayWorkout.decisionType) {
      TrainingDecisionType.normal => 18,
      TrainingDecisionType.deload => 16,
      TrainingDecisionType.recovery => 10,
      TrainingDecisionType.technique => 12,
      TrainingDecisionType.rest => 6,
    };
    final TrainingLog? log = latestLog;
    final int rpePenalty =
        log == null ? 0 : ((log.rpe - 5).clamp(0, 5) * 3).toInt();
    final BodyMetric? metric = latestBodyMetric;
    final int fatiguePenalty = metric == null
        ? 0
        : ((metric.fatigueLevel - 5).clamp(0, 5) * 2).toInt();
    final int sleepPenalty = metric != null && metric.sleepHours < 6.5 ? 4 : 0;
    final int sorenessPenalty = metric == null
        ? 0
        : ((metric.sorenessLevel - 4).clamp(0, 5) * 2).toInt();
    final int readinessDiscount = readinessScore >= 82 ? 4 : 0;

    return (baseHours +
            rpePenalty +
            fatiguePenalty +
            sleepPenalty +
            sorenessPenalty -
            readinessDiscount)
        .clamp(6, 48)
        .toInt();
  }

  int get remainingRecoveryHours {
    final TrainingLog? log = latestLog;
    if (log == null) {
      return recommendedRecoveryHours;
    }
    final int elapsedHours = DateTime.now().difference(log.createdAt).inHours;
    return (recommendedRecoveryHours - elapsedHours).clamp(0, 72).toInt();
  }

  String get recoveryCountdownLabel {
    if (latestLog == null) {
      return '预计 $recommendedRecoveryHours 小时';
    }
    if (remainingRecoveryHours == 0) {
      return '已恢复到可评估';
    }
    return '还需约 $remainingRecoveryHours 小时';
  }

  String get recoveryAdvice {
    if (requiresMedicalAttention) {
      return '疼痛红线优先于恢复倒计时，今天停止相关训练并就医。';
    }
    if (latestLog == null) {
      return '完成一次跟练或反馈后，首页会按 RPE 和身体数据更新倒计时。';
    }
    if (remainingRecoveryHours == 0) {
      return '可以重新评估下一次高强度课，仍需先看睡眠、HRV 和疼痛。';
    }
    return '倒计时结束前避免高强度课，可做轻松步行、灵活性或低压技术练习。';
  }

  double get acuteLoadScore {
    final List<TrainingLoadCurvePoint> points = trainingLoadCurvePoints;
    if (points.isNotEmpty) {
      return points.last.atlScore;
    }
    return todayWorkout.estimatedMinutes * _intensityFactor(todayWorkout);
  }

  double get chronicLoadScore {
    final List<TrainingLoadCurvePoint> points = trainingLoadCurvePoints;
    if (points.isNotEmpty) {
      return points.last.ctlScore;
    }
    return _initialChronicTrainingLoad();
  }

  List<TrainingLoadCurvePoint> get trainingLoadCurvePoints {
    final DateTime latestDate = _latestTrainingLoadDate();
    final DateTime startDate = latestDate.subtract(const Duration(days: 13));
    final List<TrainingLoadCurvePoint> points = [];
    double ctl = _initialChronicTrainingLoad();
    double atl = ctl * 0.85;

    for (int offset = 0; offset < 14; offset += 1) {
      final DateTime date = startDate.add(Duration(days: offset));
      final double dailyLoad = _dailyTrainingLoad(date);
      ctl = _ewma(previous: ctl, value: dailyLoad, days: 42);
      atl = _ewma(previous: atl, value: dailyLoad, days: 7);
      points.add(
        TrainingLoadCurvePoint(
          label: '${date.month}/${date.day}',
          dailyLoadScore: dailyLoad,
          ctlScore: ctl,
          atlScore: atl,
          tsbScore: ctl - atl,
        ),
      );
    }

    return points;
  }

  DateTime _latestTrainingLoadDate() {
    DateTime latestDate = _dateOnly(DateTime.now());
    for (final BodyMetric metric in bodyMetrics) {
      final DateTime metricDate = _dateOnly(metric.measuredAt);
      if (metricDate.isAfter(latestDate)) {
        latestDate = metricDate;
      }
    }
    for (final TrainingLog log in logs) {
      final DateTime logDate = _dateOnly(log.date);
      if (logDate.isAfter(latestDate)) {
        latestDate = logDate;
      }
    }
    return latestDate;
  }

  double _dailyTrainingLoad(DateTime date) {
    final List<TrainingLog> dayLogs =
        logs.where((TrainingLog log) => _isSameDate(log.date, date)).toList();
    if (dayLogs.isNotEmpty) {
      return dayLogs.fold<double>(
        0,
        (double total, TrainingLog log) => total + _sessionTrainingLoad(log),
      );
    }

    BodyMetric? metricForDate;
    for (final BodyMetric metric in bodyMetrics) {
      if (_isSameDate(metric.measuredAt, date)) {
        metricForDate = metric;
        break;
      }
    }
    if (metricForDate != null) {
      final double fatigueLoad = metricForDate.fatigueLevel * 6;
      final double sorenessLoad = metricForDate.sorenessLevel * 4;
      final double recoveryPenalty = (metricForDate.sleepHours < 6.5 ? 12 : 0) +
          (metricForDate.hrvMs < 48 ? 10 : 0);
      return (fatigueLoad + sorenessLoad + recoveryPenalty)
          .clamp(18, 95)
          .toDouble();
    }

    if (_isSameDate(date, DateTime.now()) &&
        todayWorkout.decisionType != TrainingDecisionType.rest) {
      return todayWorkout.estimatedMinutes * _intensityFactor(todayWorkout) * 4;
    }

    return 0;
  }

  double _sessionTrainingLoad(TrainingLog log) {
    final WorkoutDay? workout = findWorkoutDay(log.workoutDayId);
    final int estimatedMinutes = workout?.estimatedMinutes ?? 45;
    final double completionFactor = log.completed ? 1 : 0.35;
    final double fatigueFactor =
        1 + ((log.fatigueLevel - 5).clamp(0, 5) * 0.04);
    return estimatedMinutes * log.rpe * completionFactor * fatigueFactor;
  }

  double _initialChronicTrainingLoad() {
    final double baseLoad =
        profile.weeklyTrainingDays * profile.dailyAvailableMinutes * 0.75;
    final double recoveryAdjustment = averageHrv7d * 0.8 - averageFatigue7d * 7;
    return (baseLoad + recoveryAdjustment).clamp(35, 260).toDouble();
  }

  double _ewma({
    required double previous,
    required double value,
    required int days,
  }) {
    return previous + (value - previous) / days;
  }

  double get weeklyTrainingCapacityScore {
    return profile.weeklyTrainingDays * profile.dailyAvailableMinutes / 10;
  }

  String get trainingStatusLabel {
    if (requiresMedicalAttention ||
        todayWorkout.decisionType == TrainingDecisionType.rest) {
      return '恢复中';
    }
    if (averageFatigue7d >= 6 ||
        averageHrv7d < 48 ||
        acuteLoadScore > chronicLoadScore * 1.25) {
      return '过度风险';
    }
    if (readinessScore >= 78 &&
        averageFatigue7d <= 4.8 &&
        acuteLoadScore >= chronicLoadScore * 0.45) {
      return '进步中';
    }
    return '维持';
  }

  String get trainingStatusReason {
    switch (trainingStatusLabel) {
      case '恢复中':
        return '今日决策已转为休息或恢复，优先让疼痛和疲劳回落。';
      case '过度风险':
        return '7 日疲劳、HRV 或急性负荷提示压力偏高，下一课不宜硬推。';
      case '进步中':
        return '准备度和 7 日恢复指标稳定，可以保持小幅渐进。';
      default:
        return '当前负荷和恢复大致平衡，先保持节奏，等待更多执行记录。';
    }
  }

  String get morningReportAdvice {
    if (requiresMedicalAttention) {
      return '今天不要硬练，先处理疼痛红线。';
    }
    if (remainingRecoveryHours > 18 && latestLog != null) {
      return '今天把训练换成轻松版，等恢复倒计时下降。';
    }
    if (readinessScore >= 82) {
      return '今天可以按计划推进，但仍保持动作质量优先。';
    }
    if (readinessScore >= 60) {
      return '今天可训练，但强度留余量。';
    }
    return '今天优先恢复，训练只做低压版本。';
  }

  StarterGraduationReport get starterGraduationReport {
    return StarterGraduationService().buildReport(
      goal: starterProgramGoal,
      starterProgramStreak: starterProgramStreak,
      starterProgramDayIndex: starterProgramDayIndex,
      starterProgramStatusMessage: starterProgramStatusMessage,
      bodyMetrics: bodyMetrics,
      logs: logs,
      readinessScore: readinessScore,
      readinessLabel: readinessLabel,
      trainingStatusLabel: trainingStatusLabel,
    );
  }

  List<TrainingReminder> get trainingReminders {
    return TrainingReminderService().buildReminders(
      enabled: remindersEnabled,
      preferredTimeLabel: reminderTimeLabel,
      profile: profile,
      todayWorkout: todayWorkout,
      starterProgramStreak: starterProgramStreak,
      starterProgramDayIndex: starterProgramDayIndex,
      formalPlanUnlocked: formalPlanUnlocked,
      latestBodyMetric: latestBodyMetric,
      remainingRecoveryHours: remainingRecoveryHours,
      recoveryAdvice: recoveryAdvice,
      readinessScore: readinessScore,
      trainingStatusLabel: trainingStatusLabel,
      morningReportAdvice: morningReportAdvice,
    );
  }

  TrainingReminder? get nextTrainingReminder {
    for (final TrainingReminder reminder in trainingReminders) {
      if (reminder.enabled) {
        return reminder;
      }
    }
    return null;
  }

  String get reminderSummaryLabel {
    if (!remindersEnabled) {
      return '提醒已暂停';
    }
    final TrainingReminder? reminder = nextTrainingReminder;
    if (reminder == null) {
      return '暂无提醒';
    }
    return '${reminder.timeLabel} · ${reminder.title}';
  }

  DailyCheckInSummary get dailyCheckInSummary {
    return DailyCheckInService().buildSummary(
      latestBodyMetric: latestBodyMetric,
      latestPainLog: latestPainLog,
      starterProgramStreak: starterProgramStreak,
      highConfidenceInsightCount: highConfidenceInsightCount,
      readinessLabel: readinessLabel,
      readinessScore: readinessScore,
      trainingStatusLabel: trainingStatusLabel,
      reminderTimeLabel: reminderTimeLabel,
    );
  }

  DailyAdjustmentDecision get dailyAdjustmentDecision {
    return DailyAdjustmentService().buildDecision(
      baseWorkout: todayWorkout,
      availableMinutes: dailyAvailableMinutesOverride,
      workStress: dailyWorkStress,
      environment: profile.equipmentAccessType == EquipmentAccessType.none
          ? TrainingEnvironment.noEquipment
          : dailyTrainingEnvironment,
      weather: dailyWeather,
      latestBodyMetric: latestBodyMetric,
      latestPainLog: latestPainLog,
      latestMotionAnalysisResult: latestMotionAnalysisResult,
      readinessScore: readinessScore,
    );
  }

  TrainingRuleAuditReport get activePlanRuleAuditReport {
    return ruleAuditReportForPlan(activePlan);
  }

  TrainingRuleAuditReport ruleAuditReportForPlan(TrainingPlan plan) {
    return TrainingRuleAuditService().buildReport(
      plan,
      exercises: exercises,
      availableMinutes: dailyAvailableMinutesOverride,
    );
  }

  List<ProfileEvent> get profileEvents {
    return UserInsightService().buildEvents(
      profile: profile,
      logs: logs,
      bodyMetrics: bodyMetrics,
      painLogs: painLogs,
      importedWorkouts: importedWorkouts,
      planAdjustments: planAdjustments,
      starterProgramStreak: starterProgramStreak,
    );
  }

  List<UserProfileInsight> get userProfileInsights {
    return UserInsightService().buildInsights(
      profile: profile,
      logs: logs,
      bodyMetrics: bodyMetrics,
      painLogs: painLogs,
      importedWorkouts: importedWorkouts,
      starterProgramStreak: starterProgramStreak,
      readinessScore: readinessScore,
      trainingStatusLabel: trainingStatusLabel,
    );
  }

  List<PredictionLog> get predictionLogs {
    return UserInsightService().buildPredictionLogs(
      recommendedRecoveryHours: recommendedRecoveryHours,
      remainingRecoveryHours: remainingRecoveryHours,
      hasLatestLog: latestLog != null,
      latestLog: latestLog,
      bodyMetrics: bodyMetrics,
    );
  }

  int get settledPredictionCount {
    return predictionLogs
        .where((PredictionLog prediction) => prediction.isSettled)
        .length;
  }

  String get predictionBackfillSummaryLabel {
    return '$settledPredictionCount/${predictionLogs.length} 条已回填';
  }

  int get highConfidenceInsightCount {
    return userProfileInsights
        .where((UserProfileInsight insight) => insight.confidence >= 0.65)
        .length;
  }

  String get userInsightSummaryLabel {
    return '${userProfileInsights.length} 条结论 · $highConfidenceInsightCount 条较高置信';
  }

  String get userInsightTableSummaryLabel {
    return '本地表 ${userInsightTableState.totalTableRows} 行';
  }

  String get userInsightWeeklyTaskLabel {
    final UserInsightWeeklyTask? task = userInsightTableState.latestWeeklyTask;
    if (task == null) {
      return '尚未生成周度任务';
    }
    return '${task.weekLabel} · ${task.generatedAtLabel}';
  }

  UserTrustReviewReport get userTrustReviewReport {
    return UserTrustReviewService().buildReport(
      predictionLogs: predictionLogs,
      insights: userProfileInsights,
      events: profileEvents,
      recoveryAdvice: recoveryAdvice,
      achievementSummaryLabel: achievementSummaryLabel,
    );
  }

  List<AchievementProgress> get achievementProgressList {
    return [
      for (final AchievementDefinition definition in achievementDefinitions)
        AchievementProgress(
          definition: definition,
          currentValue: _achievementCurrentValue(definition.id),
        ),
    ];
  }

  int get unlockedAchievementCount {
    return achievementProgressList
        .where((AchievementProgress progress) => progress.unlocked)
        .length;
  }

  String get achievementSummaryLabel {
    return '已解锁 $unlockedAchievementCount/${achievementDefinitions.length}';
  }

  String get achievementRecordSummaryLabel {
    return '已入库 ${achievementRecords.length} 条';
  }

  AchievementRecord? achievementRecordFor(String definitionId) {
    for (final AchievementRecord record in achievementRecords) {
      if (record.definitionId == definitionId) {
        return record;
      }
    }
    return null;
  }

  int _achievementCurrentValue(String achievementId) {
    switch (achievementId) {
      case 'first_workout_player':
        return logs.any(
          (TrainingLog log) =>
              log.completed && (log.userNote ?? '').contains('[跟练执行]'),
        )
            ? 1
            : 0;
      case 'listen_to_body':
        return workoutPlayerDeloaded ||
                logs.any(
                  (TrainingLog log) => (log.userNote ?? '').contains('太累了'),
                )
            ? 1
            : 0;
      case 'starter_day_one':
        return starterProgramStreak.clamp(0, 1).toInt();
      case 'seven_day_streak':
        return starterProgramStreak.clamp(0, 7).toInt();
      case 'thirty_day_streak':
        return starterProgramStreak.clamp(0, 30).toInt();
      case 'body_data_first':
        return bodyMetrics.isEmpty ? 0 : 1;
      case 'safety_redline':
        return painLogs.any((PainLog log) => log.requiresMedicalAttention)
            ? 1
            : 0;
      default:
        return 0;
    }
  }

  int get readinessScore {
    final int injuryPenalty = profile.injuryHistory.isEmpty ? 0 : 8;
    final int schedulePenalty =
        profile.workScheduleType == WorkScheduleType.overtimeHeavy ? 8 : 0;
    final PainLog? latestPainLogValue = latestPainLog;
    final int painPenalty = latestPainLogValue == null
        ? 0
        : latestPainLogValue.requiresMedicalAttention
            ? 36
            : latestPainLogValue.painLevel >= 4
                ? 18
                : 5;
    final BodyMetric? metric = latestBodyMetric;
    final int sleepPenalty = metric != null && metric.sleepHours < 6.5 ? 8 : 0;
    final int hrvPenalty = metric != null && metric.hrvMs < 45 ? 6 : 0;
    final int fatiguePenalty =
        metric != null && metric.fatigueLevel >= 7 ? 8 : 0;
    final int restingHrPenalty =
        metric != null && metric.restingHeartRate > averageRestingHr7d + 6
            ? 6
            : 0;
    final double score = 48 +
        profile.weeklyTrainingDays * 5 +
        profile.dailyAvailableMinutes * 0.35 -
        injuryPenalty -
        schedulePenalty -
        painPenalty -
        sleepPenalty -
        hrvPenalty -
        fatiguePenalty -
        restingHrPenalty;
    return score.clamp(35, 94).round();
  }

  String get readinessLabel {
    if (requiresMedicalAttention) {
      return '停止训练并就医';
    }
    if ((latestPainLog?.painLevel ?? 0) >= 4) {
      return '自动降级';
    }
    if (readinessScore >= 82) {
      return '状态充足';
    }
    if (readinessScore >= 66) {
      return '可以推进';
    }
    if (readinessScore >= 52) {
      return '控制强度';
    }
    return '优先恢复';
  }

  WorkoutDay? findWorkoutDay(String id) {
    for (final TrainingPlan plan in plans) {
      for (final WorkoutDay day in plan.workoutDays) {
        if (day.id == id) {
          return day;
        }
      }
    }
    return null;
  }

  TrainingPlan? findPlan(String id) {
    for (final TrainingPlan plan in plans) {
      if (plan.id == id) {
        return plan;
      }
    }
    return null;
  }

  PlanAdjustment? latestPlanAdjustmentFor(String workoutDayId) {
    for (final PlanAdjustment adjustment in planAdjustments) {
      if (adjustment.workoutDayId == workoutDayId) {
        return adjustment;
      }
    }
    return null;
  }

  Exercise? findExercise(String id) {
    for (final Exercise exercise in exercises) {
      if (exercise.id == id) {
        return exercise;
      }
    }
    return null;
  }

  MotionCheckRule? findMotionCheck(String id) {
    for (final MotionCheckRule rule in motionChecks) {
      if (rule.id == id) {
        return rule;
      }
    }
    return null;
  }

  RacePlan? findRace(String id) {
    for (final RacePlan race in races) {
      if (race.id == id) {
        return race;
      }
    }
    return null;
  }

  RaceAutoSchedule raceAutoScheduleFor(RacePlan race) {
    return RaceAutoScheduleService().buildSchedule(
      race: race,
      now: DateTime.now(),
      readinessScore: readinessScore,
      hasPainRedline: requiresMedicalAttention,
    );
  }

  List<BookQuote> quotesForBook(String bookId) {
    return bookQuotes
        .where((BookQuote quote) => quote.bookId == bookId)
        .toList();
  }

  List<TrainingBook> get filteredKnowledgeBooks {
    final String query = knowledgeSearchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return knowledgeBooks;
    }
    return knowledgeBooks.where((TrainingBook book) {
      final List<BookQuote> quotes = quotesForBook(book.id);
      final bool bookMatched = [
        book.title,
        book.author,
        book.edition,
        book.summary,
        ...book.areas.map((KnowledgeArea area) => area.label),
      ].any((String value) => value.toLowerCase().contains(query));
      final bool quoteMatched = quotes.any((BookQuote quote) {
        final bool quoteTextMatched = [
          quote.chapter,
          quote.pageRange,
          quote.quote,
          quote.note,
          ...quote.areas.map((KnowledgeArea area) => area.label),
        ].any((String value) => value.toLowerCase().contains(query));
        final bool citationMatched = citationsForQuote(quote.id).any(
          (CitationLink citation) => [
            citation.targetType.label,
            citation.targetTitle,
            citation.reason,
          ].any((String value) => value.toLowerCase().contains(query)),
        );
        return quoteTextMatched || citationMatched;
      });
      return bookMatched || quoteMatched;
    }).toList();
  }

  int get knowledgeSearchMatchCount {
    return filteredKnowledgeBooks.length;
  }

  List<CitationLink> citationsForQuote(String quoteId) {
    return citationLinks
        .where((CitationLink citation) => citation.quoteId == quoteId)
        .toList();
  }

  TrainingMvpState copyWith({
    bool? profileCompleted,
    UserProfile? profile,
    List<TrainingPlan>? plans,
    List<PlanAdjustment>? planAdjustments,
    String? planAdjustmentStatusMessage,
    List<Exercise>? exercises,
    List<TrainingBook>? knowledgeBooks,
    List<BookQuote>? bookQuotes,
    List<CitationLink>? citationLinks,
    String? knowledgeSearchQuery,
    String? knowledgeImportStatusMessage,
    List<MealGuide>? mealGuides,
    List<MotionCheckRule>? motionChecks,
    List<RacePlan>? races,
    String? raceImportStatusMessage,
    List<BodyMetric>? bodyMetrics,
    List<BodyMetricRevision>? bodyMetricRevisions,
    Object? pendingBodyMetric = _unchanged,
    String? bodyMetricManualStatusMessage,
    List<BodyMetricImportResult>? bodyMetricImportResults,
    String? bodyMetricImportStatusMessage,
    String? bodyMetricSnapshotStatusMessage,
    List<BodyMetricExportRecord>? bodyMetricExportRecords,
    String? bodyMetricExportStatusMessage,
    List<AchievementDefinition>? achievementDefinitions,
    List<AchievementRecord>? achievementRecords,
    String? achievementRecordStatusMessage,
    List<ImportedWorkout>? importedWorkouts,
    String? activityImportStatusMessage,
    List<StarterProgramDay>? starterProgramDays,
    StarterProgramGoal? starterProgramGoal,
    int? starterProgramDayIndex,
    int? starterProgramStreak,
    bool? starterProgramRescueMode,
    String? starterProgramStatusMessage,
    bool? formalPlanUnlocked,
    String? formalPlanStatusMessage,
    Object? formalAiPlan = _unchanged,
    bool? remindersEnabled,
    String? reminderTimeLabel,
    String? reminderStatusMessage,
    String? dailyCheckInStatusMessage,
    int? dailyAvailableMinutesOverride,
    WorkStressLevel? dailyWorkStress,
    TrainingEnvironment? dailyTrainingEnvironment,
    WeatherCondition? dailyWeather,
    String? dailyAdjustmentStatusMessage,
    int? workoutPlayerStepIndex,
    bool? workoutPlayerDeloaded,
    bool? workoutPlayerFinished,
    Object? activeWorkoutPlayerDayId = _unchanged,
    List<String>? workoutPlayerEvents,
    String? workoutPlayerStatusMessage,
    int? workoutPlayerRemainingSeconds,
    bool? workoutPlayerTimerRunning,
    bool? workoutPlayerVoiceEnabled,
    List<String>? workoutPlayerVoiceQueue,
    String? workoutPlayerVoiceStatusMessage,
    bool? workoutPlayerScreenAwakeRequested,
    String? workoutPlayerScreenAwakeStatusMessage,
    MealScenario? mealScenario,
    List<TrainingLog>? logs,
    List<PainLog>? painLogs,
    List<MotionAnalysisResult>? motionAnalysisResults,
    String? motionAnalysisStatusMessage,
    String? userInsightStatusMessage,
    UserInsightTableState? userInsightTableState,
    List<WeeklyReport>? savedWeeklyReports,
    String? weeklyReportSaveStatusMessage,
    List<WeeklyReportExportRecord>? weeklyReportExportRecords,
    String? weeklyReportExportStatusMessage,
    List<String>? coachAdvices,
    Object? scheduledTodayWorkout = _unchanged,
  }) {
    return TrainingMvpState(
      profileCompleted: profileCompleted ?? this.profileCompleted,
      profile: profile ?? this.profile,
      plans: plans ?? this.plans,
      planAdjustments: planAdjustments ?? this.planAdjustments,
      planAdjustmentStatusMessage:
          planAdjustmentStatusMessage ?? this.planAdjustmentStatusMessage,
      exercises: exercises ?? this.exercises,
      knowledgeBooks: knowledgeBooks ?? this.knowledgeBooks,
      bookQuotes: bookQuotes ?? this.bookQuotes,
      citationLinks: citationLinks ?? this.citationLinks,
      knowledgeSearchQuery: knowledgeSearchQuery ?? this.knowledgeSearchQuery,
      knowledgeImportStatusMessage:
          knowledgeImportStatusMessage ?? this.knowledgeImportStatusMessage,
      mealGuides: mealGuides ?? this.mealGuides,
      motionChecks: motionChecks ?? this.motionChecks,
      races: races ?? this.races,
      raceImportStatusMessage:
          raceImportStatusMessage ?? this.raceImportStatusMessage,
      bodyMetrics: bodyMetrics ?? this.bodyMetrics,
      bodyMetricRevisions: bodyMetricRevisions ?? this.bodyMetricRevisions,
      pendingBodyMetric: identical(pendingBodyMetric, _unchanged)
          ? this.pendingBodyMetric
          : pendingBodyMetric as BodyMetric?,
      bodyMetricManualStatusMessage:
          bodyMetricManualStatusMessage ?? this.bodyMetricManualStatusMessage,
      bodyMetricImportResults:
          bodyMetricImportResults ?? this.bodyMetricImportResults,
      bodyMetricImportStatusMessage:
          bodyMetricImportStatusMessage ?? this.bodyMetricImportStatusMessage,
      bodyMetricSnapshotStatusMessage: bodyMetricSnapshotStatusMessage ??
          this.bodyMetricSnapshotStatusMessage,
      bodyMetricExportRecords:
          bodyMetricExportRecords ?? this.bodyMetricExportRecords,
      bodyMetricExportStatusMessage:
          bodyMetricExportStatusMessage ?? this.bodyMetricExportStatusMessage,
      achievementDefinitions:
          achievementDefinitions ?? this.achievementDefinitions,
      achievementRecords: achievementRecords ?? this.achievementRecords,
      achievementRecordStatusMessage:
          achievementRecordStatusMessage ?? this.achievementRecordStatusMessage,
      importedWorkouts: importedWorkouts ?? this.importedWorkouts,
      activityImportStatusMessage:
          activityImportStatusMessage ?? this.activityImportStatusMessage,
      starterProgramDays: starterProgramDays ?? this.starterProgramDays,
      starterProgramGoal: starterProgramGoal ?? this.starterProgramGoal,
      starterProgramDayIndex:
          starterProgramDayIndex ?? this.starterProgramDayIndex,
      starterProgramStreak: starterProgramStreak ?? this.starterProgramStreak,
      starterProgramRescueMode:
          starterProgramRescueMode ?? this.starterProgramRescueMode,
      starterProgramStatusMessage:
          starterProgramStatusMessage ?? this.starterProgramStatusMessage,
      formalPlanUnlocked: formalPlanUnlocked ?? this.formalPlanUnlocked,
      formalPlanStatusMessage:
          formalPlanStatusMessage ?? this.formalPlanStatusMessage,
      formalAiPlan: identical(formalAiPlan, _unchanged)
          ? this.formalAiPlan
          : formalAiPlan as FormalAiPlan?,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      reminderTimeLabel: reminderTimeLabel ?? this.reminderTimeLabel,
      reminderStatusMessage:
          reminderStatusMessage ?? this.reminderStatusMessage,
      dailyCheckInStatusMessage:
          dailyCheckInStatusMessage ?? this.dailyCheckInStatusMessage,
      dailyAvailableMinutesOverride:
          dailyAvailableMinutesOverride ?? this.dailyAvailableMinutesOverride,
      dailyWorkStress: dailyWorkStress ?? this.dailyWorkStress,
      dailyTrainingEnvironment:
          dailyTrainingEnvironment ?? this.dailyTrainingEnvironment,
      dailyWeather: dailyWeather ?? this.dailyWeather,
      dailyAdjustmentStatusMessage:
          dailyAdjustmentStatusMessage ?? this.dailyAdjustmentStatusMessage,
      workoutPlayerStepIndex:
          workoutPlayerStepIndex ?? this.workoutPlayerStepIndex,
      workoutPlayerDeloaded:
          workoutPlayerDeloaded ?? this.workoutPlayerDeloaded,
      workoutPlayerFinished:
          workoutPlayerFinished ?? this.workoutPlayerFinished,
      activeWorkoutPlayerDayId: identical(activeWorkoutPlayerDayId, _unchanged)
          ? this.activeWorkoutPlayerDayId
          : activeWorkoutPlayerDayId as String?,
      workoutPlayerEvents: workoutPlayerEvents ?? this.workoutPlayerEvents,
      workoutPlayerStatusMessage:
          workoutPlayerStatusMessage ?? this.workoutPlayerStatusMessage,
      workoutPlayerRemainingSeconds:
          workoutPlayerRemainingSeconds ?? this.workoutPlayerRemainingSeconds,
      workoutPlayerTimerRunning:
          workoutPlayerTimerRunning ?? this.workoutPlayerTimerRunning,
      workoutPlayerVoiceEnabled:
          workoutPlayerVoiceEnabled ?? this.workoutPlayerVoiceEnabled,
      workoutPlayerVoiceQueue:
          workoutPlayerVoiceQueue ?? this.workoutPlayerVoiceQueue,
      workoutPlayerVoiceStatusMessage: workoutPlayerVoiceStatusMessage ??
          this.workoutPlayerVoiceStatusMessage,
      workoutPlayerScreenAwakeRequested: workoutPlayerScreenAwakeRequested ??
          this.workoutPlayerScreenAwakeRequested,
      workoutPlayerScreenAwakeStatusMessage:
          workoutPlayerScreenAwakeStatusMessage ??
              this.workoutPlayerScreenAwakeStatusMessage,
      mealScenario: mealScenario ?? this.mealScenario,
      logs: logs ?? this.logs,
      painLogs: painLogs ?? this.painLogs,
      motionAnalysisResults:
          motionAnalysisResults ?? this.motionAnalysisResults,
      motionAnalysisStatusMessage:
          motionAnalysisStatusMessage ?? this.motionAnalysisStatusMessage,
      userInsightStatusMessage:
          userInsightStatusMessage ?? this.userInsightStatusMessage,
      userInsightTableState:
          userInsightTableState ?? this.userInsightTableState,
      savedWeeklyReports: savedWeeklyReports ?? this.savedWeeklyReports,
      weeklyReportSaveStatusMessage:
          weeklyReportSaveStatusMessage ?? this.weeklyReportSaveStatusMessage,
      weeklyReportExportRecords:
          weeklyReportExportRecords ?? this.weeklyReportExportRecords,
      weeklyReportExportStatusMessage: weeklyReportExportStatusMessage ??
          this.weeklyReportExportStatusMessage,
      coachAdvices: coachAdvices ?? this.coachAdvices,
      scheduledTodayWorkout: identical(scheduledTodayWorkout, _unchanged)
          ? this.scheduledTodayWorkout
          : scheduledTodayWorkout as ScheduledWorkout?,
    );
  }
}

class TrainingMvpController extends Notifier<TrainingMvpState> {
  Timer? _workoutPlayerTimer;

  WeeklyReportRepository? _weeklyReportRepositoryInstance;

  WeeklyReportRepository get _weeklyReportRepository {
    return _weeklyReportRepositoryInstance ??= PersistedWeeklyReportRepository(
      ref.read(localStorageServiceProvider),
    );
  }

  WeeklyReportExportRepository? _weeklyReportExportRepositoryInstance;

  WeeklyReportExportRepository get _weeklyReportExportRepository {
    return _weeklyReportExportRepositoryInstance ??=
        PersistedWeeklyReportExportRepository(
      ref.read(localStorageServiceProvider),
    );
  }

  UserInsightRepository? _userInsightRepositoryInstance;

  UserInsightRepository get _userInsightRepository {
    return _userInsightRepositoryInstance ??= PersistedUserInsightRepository(
      ref.read(localStorageServiceProvider),
    );
  }

  FormalAiPlanRepository? _formalAiPlanRepositoryInstance;

  FormalAiPlanRepository get _formalAiPlanRepository {
    return _formalAiPlanRepositoryInstance ??= PersistedFormalAiPlanRepository(
      ref.read(localStorageServiceProvider),
    );
  }

  MotionAnalysisRepository? _motionAnalysisRepositoryInstance;

  MotionAnalysisRepository get _motionAnalysisRepository {
    return _motionAnalysisRepositoryInstance ??=
        PersistedMotionAnalysisRepository(
      ref.read(localStorageServiceProvider),
    );
  }

  final TrainingPlanRepository _planRepository =
      InMemoryTrainingPlanRepository();

  List<TrainingPlan> _basePlansFor(bool profileCompleted) {
    if (!profileCompleted) {
      return _planRepository.listPlans();
    }
    return <TrainingPlan>[
      ref.read(fourWeekPlanControllerProvider).activePlan,
    ];
  }

  final ExerciseRepository _exerciseRepository = InMemoryExerciseRepository();
  KnowledgeRepository? _knowledgeRepositoryInstance;

  KnowledgeRepository get _knowledgeRepository {
    return _knowledgeRepositoryInstance ??= PersistedKnowledgeRepository(
      ref.read(localStorageServiceProvider),
    );
  }

  final MealGuideRepository _mealGuideRepository =
      InMemoryMealGuideRepository();
  final MotionCheckRepository _motionCheckRepository =
      InMemoryMotionCheckRepository();
  RaceRepository? _raceRepositoryInstance;

  RaceRepository get _raceRepository {
    return _raceRepositoryInstance ??= PersistedRaceRepository(
      ref.read(localStorageServiceProvider),
    );
  }

  StarterProgramRepository? _starterProgramRepositoryInstance;

  StarterProgramRepository get _starterProgramRepository {
    return _starterProgramRepositoryInstance ??=
        PersistedStarterProgramRepository(
      storageService: ref.read(localStorageServiceProvider),
    );
  }

  ImportedWorkoutRepository? _importedWorkoutRepositoryInstance;

  ImportedWorkoutRepository get _importedWorkoutRepository {
    return _importedWorkoutRepositoryInstance ??=
        PersistedImportedWorkoutRepository(
      ref.read(localStorageServiceProvider),
    );
  }

  PainLogRepository? _painLogRepositoryInstance;

  PainLogRepository get _painLogRepository {
    return _painLogRepositoryInstance ??= PersistedPainLogRepository(
      ref.read(localStorageServiceProvider),
    );
  }

  final AiTrainingService _aiTrainingService = AiTrainingService();
  final FormalAiPlanService _formalAiPlanService = FormalAiPlanService();
  final ActivityImportService _activityImportService = ActivityImportService();
  final RaceImportService _raceImportService = RaceImportService();
  final KnowledgeImportService _knowledgeImportService =
      KnowledgeImportService();
  final MotionAnalysisService _motionAnalysisService = MotionAnalysisService();
  final MotionPoseImportService _motionPoseImportService =
      MotionPoseImportService();
  @override
  TrainingMvpState build() {
    ref.onDispose(() {
      _stopWorkoutPlayerTimer();
    });

    final PlanAdjustmentState planAdjustmentState =
        ref.read(planAdjustmentControllerProvider);
    ref.listen<PlanAdjustmentState>(
      planAdjustmentControllerProvider,
      (PlanAdjustmentState? previous, PlanAdjustmentState next) {
        scheduleMicrotask(() {
          if (!ref.mounted) {
            return;
          }
          state = state.copyWith(
            plans: _applyPlanAdjustments(
              _basePlansFor(state.profileCompleted),
              next.adjustments,
            ),
            planAdjustments: next.adjustments,
            planAdjustmentStatusMessage: next.statusMessage,
          );
        });
      },
    );
    final UserProfileState profileState =
        ref.read(userProfileControllerProvider);
    final FourWeekPlanState fourWeekPlanState =
        ref.read(fourWeekPlanControllerProvider);
    ref.listen<UserProfileState>(
      userProfileControllerProvider,
      (UserProfileState? previous, UserProfileState next) {
        final TrainingMvpState profileUpdatedState = state.copyWith(
          profileCompleted: next.isCompleted,
          profile: next.profile,
          plans: _applyPlanAdjustments(
            next.isCompleted
                ? <TrainingPlan>[
                    ref.read(fourWeekPlanControllerProvider).activePlan,
                  ]
                : _planRepository.listPlans(),
            state.planAdjustments,
          ),
        );
        state = profileUpdatedState.copyWith(
          coachAdvices: _aiTrainingService.buildMockCoachAdvice(
            profile: profileUpdatedState.profile,
            todayWorkout: profileUpdatedState.todayWorkout,
            todayMealGuide: profileUpdatedState.activeMealGuide,
            latestLog: profileUpdatedState.latestLog,
            latestPainLog: profileUpdatedState.latestPainLog,
          ),
        );
      },
    );
    ref.listen<FourWeekPlanState>(
      fourWeekPlanControllerProvider,
      (FourWeekPlanState? previous, FourWeekPlanState next) {
        scheduleMicrotask(() {
          if (!ref.mounted || !state.profileCompleted) {
            return;
          }
          if (next.executionLocked) {
            _switchSkillExecutionToFallback(
              next,
              reason: next.executionLockReason,
            );
            return;
          }
          final TrainingMvpState planUpdatedState = state.copyWith(
            plans: _applyPlanAdjustments(
              <TrainingPlan>[next.activePlan],
              state.planAdjustments,
            ),
          );
          state = planUpdatedState.copyWith(
            coachAdvices: _aiTrainingService.buildMockCoachAdvice(
              profile: planUpdatedState.profile,
              todayWorkout: planUpdatedState.todayWorkout,
              todayMealGuide: planUpdatedState.activeMealGuide,
              latestLog: planUpdatedState.latestLog,
              latestPainLog: planUpdatedState.latestPainLog,
            ),
          );
        });
      },
    );
    final TrainingScheduleState scheduleState =
        ref.read(trainingScheduleControllerProvider);
    ref.listen<TrainingScheduleState>(
      trainingScheduleControllerProvider,
      (TrainingScheduleState? previous, TrainingScheduleState next) {
        scheduleMicrotask(() {
          if (!ref.mounted) return;
          final ScheduledWorkout? scheduled = next.workoutFor(DateTime.now());
          final TrainingMvpState nextState = state.copyWith(
            scheduledTodayWorkout: scheduled,
            dailyAvailableMinutesOverride: scheduled?.allocatedMinutes ??
                state.dailyAvailableMinutesOverride,
          );
          state = nextState.copyWith(
            coachAdvices: _aiTrainingService.buildMockCoachAdvice(
              profile: nextState.profile,
              todayWorkout: nextState.todayWorkout,
              todayMealGuide: nextState.activeMealGuide,
              latestLog: nextState.latestLog,
              latestPainLog: nextState.latestPainLog,
            ),
          );
        });
      },
    );
    final DailyAdjustmentState dailyAdjustmentState =
        ref.read(dailyAdjustmentControllerProvider);
    ref.listen<DailyAdjustmentState>(
      dailyAdjustmentControllerProvider,
      (DailyAdjustmentState? previous, DailyAdjustmentState next) {
        unawaited(Future<void>.microtask(() {
          if (!ref.mounted) {
            return;
          }
          final DailyAdjustmentContext context = next.context;
          state = state.copyWith(
            dailyAvailableMinutesOverride: context.availableMinutes,
            dailyWorkStress: context.workStress,
            dailyTrainingEnvironment: context.environment,
            dailyWeather: context.weather,
            dailyAdjustmentStatusMessage: next.statusMessage,
          );
        }));
      },
    );
    final ReminderSettingsState reminderSettingsState =
        ref.read(reminderSettingsControllerProvider);
    ref.listen<ReminderSettingsState>(
      reminderSettingsControllerProvider,
      (ReminderSettingsState? previous, ReminderSettingsState next) {
        unawaited(Future<void>.microtask(() {
          if (!ref.mounted) {
            return;
          }
          state = state.copyWith(
            remindersEnabled: next.settings.enabled,
            reminderTimeLabel: next.settings.preferredTimeLabel,
            reminderStatusMessage: next.statusMessage,
          );
        }));
      },
    );
    final MealPreference mealPreference =
        ref.read(mealPreferenceControllerProvider);
    ref.listen<MealPreference>(
      mealPreferenceControllerProvider,
      (MealPreference? previous, MealPreference next) {
        scheduleMicrotask(() {
          if (!ref.mounted) {
            return;
          }
          final TrainingMvpState nextState = state.copyWith(
            mealScenario: next.scenario,
          );
          state = nextState.copyWith(
            coachAdvices: _aiTrainingService.buildMockCoachAdvice(
              profile: nextState.profile,
              todayWorkout: nextState.todayWorkout,
              todayMealGuide: nextState.activeMealGuide,
              latestLog: nextState.latestLog,
              latestPainLog: nextState.latestPainLog,
            ),
          );
        });
      },
    );
    final BodyMetricState bodyMetricState =
        ref.read(bodyMetricControllerProvider);
    final BodyMetricExportState bodyMetricExportState =
        ref.read(bodyMetricExportControllerProvider);
    ref.listen<BodyMetricExportState>(
      bodyMetricExportControllerProvider,
      (BodyMetricExportState? previous, BodyMetricExportState next) {
        scheduleMicrotask(() {
          if (!ref.mounted) {
            return;
          }
          state = state.copyWith(
            bodyMetricExportRecords: next.records,
            bodyMetricExportStatusMessage: next.statusMessage,
          );
        });
      },
    );
    final AchievementState achievementState =
        ref.read(achievementControllerProvider);
    ref.listen<AchievementState>(
      achievementControllerProvider,
      (AchievementState? previous, AchievementState next) {
        scheduleMicrotask(() {
          if (!ref.mounted) {
            return;
          }
          state = state.copyWith(
            achievementDefinitions: next.definitions,
            achievementRecords: next.records,
            achievementRecordStatusMessage: next.statusMessage,
          );
        });
      },
    );
    final List<TrainingLog> trainingLogs =
        ref.read(trainingLogControllerProvider);
    ref.listen<List<TrainingLog>>(
      trainingLogControllerProvider,
      (List<TrainingLog>? previous, List<TrainingLog> next) {
        scheduleMicrotask(() {
          if (!ref.mounted) {
            return;
          }
          state = state.copyWith(logs: next);
        });
      },
    );
    final WorkoutPlayerAssistState workoutPlayerAssistState =
        ref.read(workoutPlayerAssistControllerProvider);
    ref.listen<WorkoutPlayerAssistState>(
      workoutPlayerAssistControllerProvider,
      (WorkoutPlayerAssistState? previous, WorkoutPlayerAssistState next) {
        scheduleMicrotask(() {
          if (!ref.mounted) {
            return;
          }
          _projectWorkoutPlayerAssist(next);
        });
      },
    );
    ref.listen<BodyMetricState>(
      bodyMetricControllerProvider,
      (BodyMetricState? previous, BodyMetricState next) {
        final bool persisted = previous == null ||
            previous.persistenceVersion != next.persistenceVersion;
        scheduleMicrotask(() {
          if (!ref.mounted) {
            return;
          }
          state = state.copyWith(
            bodyMetrics: next.metrics,
            bodyMetricRevisions: next.revisions,
            pendingBodyMetric: next.pendingMetric,
            bodyMetricManualStatusMessage: next.manualStatusMessage,
            bodyMetricSnapshotStatusMessage: next.snapshotStatusMessage,
            bodyMetricImportResults: next.importResults,
            bodyMetricImportStatusMessage: next.importStatusMessage,
            dailyCheckInStatusMessage: next.dailyCheckInStatusMessage,
          );
          if (persisted) {
            _syncAchievementRecordsForCurrentState();
            if (next.metrics.isNotEmpty) {
              unawaited(
                ref
                    .read(growthEvidenceControllerProvider.notifier)
                    .syncBodyMetric(
                      profile: state.profile,
                      metric: next.metrics.first,
                    ),
              );
            }
          }
        });
      },
    );
    final UserProfile profile = profileState.profile;
    final List<PlanAdjustment> planAdjustments =
        planAdjustmentState.adjustments;
    final List<TrainingPlan> plans = _applyPlanAdjustments(
      profileState.isCompleted
          ? <TrainingPlan>[fourWeekPlanState.activePlan]
          : _planRepository.listPlans(),
      planAdjustments,
    );
    final List<Exercise> exercises = _exerciseRepository.listExercises();
    final List<TrainingBook> knowledgeBooks = _knowledgeRepository.listBooks();
    final List<BookQuote> bookQuotes = _knowledgeRepository.listQuotes();
    final List<CitationLink> citationLinks =
        _knowledgeRepository.listCitationLinks();
    final List<MealGuide> mealGuides = _mealGuideRepository.listMealGuides();
    final List<MotionCheckRule> motionChecks =
        _motionCheckRepository.listMotionChecks();
    final List<RacePlan> races = _raceRepository.listRaces();
    final List<BodyMetric> bodyMetrics = bodyMetricState.metrics;
    final List<BodyMetricRevision> bodyMetricRevisions =
        bodyMetricState.revisions;
    final List<BodyMetricExportRecord> bodyMetricExportRecords =
        bodyMetricExportState.records;
    final List<AchievementDefinition> achievementDefinitions =
        achievementState.definitions;
    final List<AchievementRecord> achievementRecords = achievementState.records;
    final List<StarterProgramDay> starterProgramDays =
        _starterProgramRepository.listDays();
    final StarterProgramProgress starterProgramProgress =
        _starterProgramRepository.getProgress();
    final List<TrainingLog> logs = trainingLogs;
    final List<ImportedWorkout> importedWorkouts =
        _importedWorkoutRepository.listWorkouts();
    final List<PainLog> painLogs = _painLogRepository.listPainLogs();
    final List<WeeklyReport> savedWeeklyReports =
        _weeklyReportRepository.listReports();
    final List<WeeklyReportExportRecord> weeklyReportExportRecords =
        _weeklyReportExportRepository.listRecords();
    final UserInsightTableState userInsightTableState =
        _userInsightRepository.getTableState();
    final FormalAiPlan? savedFormalAiPlan = _formalAiPlanRepository.getPlan();
    final bool savedFormalPlanUnlocked =
        _formalAiPlanRepository.isUnlocked() && savedFormalAiPlan != null;
    final List<MotionAnalysisResult> savedMotionAnalysisResults =
        _motionAnalysisRepository.listResults();
    final ScheduledWorkout? scheduledTodayWorkout =
        scheduleState.workoutFor(DateTime.now());
    WorkoutDay initialWorkout = plans.first.workoutDays.first;
    if (scheduledTodayWorkout != null) {
      for (final TrainingPlan plan in plans) {
        for (final WorkoutDay day in plan.workoutDays) {
          if (day.id == scheduledTodayWorkout.workoutDayId) {
            initialWorkout = applyScheduledWorkout(day, scheduledTodayWorkout);
          }
        }
      }
    }
    final int initialWorkoutPlayerRemainingSeconds = buildWorkoutPlayerSteps(
      initialWorkout,
      deloaded: false,
    ).first.estimatedSeconds;
    final List<String> coachAdvices = _aiTrainingService.buildMockCoachAdvice(
      profile: profile,
      todayWorkout: initialWorkout,
      todayMealGuide: _mealGuideRepository.findByScenario(
        mealPreference.scenario,
      ),
      latestPainLog: painLogs.isEmpty ? null : painLogs.first,
    );

    final TrainingMvpState initialState = TrainingMvpState(
      profileCompleted: profileState.isCompleted,
      profile: profile,
      plans: plans,
      planAdjustments: planAdjustments,
      planAdjustmentStatusMessage: planAdjustmentState.statusMessage,
      exercises: exercises,
      knowledgeBooks: knowledgeBooks,
      bookQuotes: bookQuotes,
      citationLinks: citationLinks,
      knowledgeSearchQuery: '',
      knowledgeImportStatusMessage: '可粘贴一条书籍和引文，写入本地知识库。',
      mealGuides: mealGuides,
      motionChecks: motionChecks,
      races: races,
      raceImportStatusMessage: '已读取本地 races ${races.length} 场；可粘贴赛事信息导入。',
      bodyMetrics: bodyMetrics,
      bodyMetricRevisions: bodyMetricRevisions,
      pendingBodyMetric: bodyMetricState.pendingMetric,
      bodyMetricManualStatusMessage: bodyMetricState.manualStatusMessage,
      bodyMetricImportResults: bodyMetricState.importResults,
      bodyMetricImportStatusMessage: bodyMetricState.importStatusMessage,
      bodyMetricSnapshotStatusMessage: bodyMetricState.snapshotStatusMessage,
      bodyMetricExportRecords: bodyMetricExportRecords,
      bodyMetricExportStatusMessage: bodyMetricExportState.statusMessage,
      achievementDefinitions: achievementDefinitions,
      achievementRecords: achievementRecords,
      achievementRecordStatusMessage: achievementState.statusMessage,
      importedWorkouts: importedWorkouts,
      activityImportStatusMessage: importedWorkouts.isEmpty
          ? '粘贴 GPX 或 FIT 摘要后，可写入 workout_logs。'
          : '已读取本地 imported_workouts ${importedWorkouts.length} 条，可继续导入 GPX 或 FIT 摘要。',
      starterProgramDays: starterProgramDays,
      starterProgramGoal: starterProgramProgress.goal,
      starterProgramDayIndex: starterProgramProgress.dayIndex,
      starterProgramStreak: starterProgramProgress.streak,
      starterProgramRescueMode: starterProgramProgress.rescueMode,
      starterProgramStatusMessage: starterProgramProgress.statusMessage,
      formalPlanUnlocked: savedFormalPlanUnlocked,
      formalPlanStatusMessage: savedFormalPlanUnlocked
          ? '已读取正式 AI 个性化周期：${savedFormalAiPlan.title}。'
          : starterProgramProgress.streak >= 30
              ? '毕业报告已生成，可以一键切换到正式 AI 个性化周期。'
              : '30 天毕业后可切换到正式 AI 个性化周期。',
      formalAiPlan: savedFormalAiPlan,
      remindersEnabled: reminderSettingsState.settings.enabled,
      reminderTimeLabel: reminderSettingsState.settings.preferredTimeLabel,
      reminderStatusMessage: reminderSettingsState.statusMessage,
      dailyCheckInStatusMessage: bodyMetricState.dailyCheckInStatusMessage,
      dailyAvailableMinutesOverride:
          dailyAdjustmentState.context.availableMinutes,
      dailyWorkStress: dailyAdjustmentState.context.workStress,
      dailyTrainingEnvironment: dailyAdjustmentState.context.environment,
      dailyWeather: dailyAdjustmentState.context.weather,
      dailyAdjustmentStatusMessage: dailyAdjustmentState.statusMessage,
      workoutPlayerStepIndex: 0,
      workoutPlayerDeloaded: false,
      workoutPlayerFinished: false,
      activeWorkoutPlayerDayId: null,
      workoutPlayerEvents: const [],
      workoutPlayerStatusMessage: '点击“开始跟练”后，按步骤完成今日训练。',
      workoutPlayerRemainingSeconds: initialWorkoutPlayerRemainingSeconds,
      workoutPlayerTimerRunning: false,
      workoutPlayerVoiceEnabled: workoutPlayerAssistState.voiceEnabled,
      workoutPlayerVoiceQueue: workoutPlayerAssistState.voiceQueue,
      workoutPlayerVoiceStatusMessage:
          workoutPlayerAssistState.voiceStatusMessage,
      workoutPlayerScreenAwakeRequested:
          workoutPlayerAssistState.screenAwakeRequested,
      workoutPlayerScreenAwakeStatusMessage:
          workoutPlayerAssistState.screenAwakeStatusMessage,
      mealScenario: mealPreference.scenario,
      logs: logs,
      painLogs: painLogs,
      motionAnalysisResults: savedMotionAnalysisResults,
      motionAnalysisStatusMessage: savedMotionAnalysisResults.isEmpty
          ? '尚未接入真实视频识别；可先用 8 动作本地规则模拟一次分析。'
          : '已读取 ${savedMotionAnalysisResults.length} 条本地 Motion Vision Mock 分析结果。',
      userInsightStatusMessage: userInsightTableState.weeklyTasks.isEmpty
          ? '画像仅保存在本地；置信度不足时系统会明说不确定。'
          : '已读取 ${userInsightTableState.weeklyTasks.length} 次周度画像任务快照。',
      userInsightTableState: userInsightTableState,
      savedWeeklyReports: savedWeeklyReports,
      weeklyReportSaveStatusMessage: savedWeeklyReports.isEmpty
          ? '尚未保存周报；可先把当前周报归档到本地。'
          : '已保存 ${savedWeeklyReports.length} 份周报归档。',
      weeklyReportExportRecords: weeklyReportExportRecords,
      weeklyReportExportStatusMessage: weeklyReportExportRecords.isEmpty
          ? '尚未登记周报导出；导出 Markdown 或 PNG 后会写入本地记录。'
          : '已登记 ${weeklyReportExportRecords.length} 条周报导出记录。',
      coachAdvices: coachAdvices,
      scheduledTodayWorkout: scheduledTodayWorkout,
    );
    final Map<String, WorkoutDay> workoutsById = <String, WorkoutDay>{
      for (final TrainingPlan plan in plans)
        for (final WorkoutDay workout in plan.workoutDays) workout.id: workout,
      initialWorkout.id: initialWorkout,
    };
    unawaited(Future<void>.microtask(() async {
      if (!ref.mounted) return;
      await ref.read(growthEvidenceControllerProvider.notifier).reconcile(
            profile: profile,
            logs: logs,
            bodyMetrics: bodyMetrics,
            painLogs: painLogs,
            workoutsById: workoutsById,
            fallbackWorkout: initialWorkout,
          );
    }));
    return initialState;
  }

  void importRaceText(String rawText) {
    try {
      final RacePlan race = _raceImportService.parse(rawText);
      _raceRepository.saveRace(race);
      final List<RacePlan> races = _raceRepository.listRaces();
      ref.invalidate(fourWeekPlanControllerProvider);
      final FourWeekPlanState planState =
          ref.read(fourWeekPlanControllerProvider);
      final TrainingMvpState nextState = state.copyWith(
        races: races,
        plans: state.profileCompleted
            ? _applyPlanAdjustments(
                <TrainingPlan>[planState.activePlan],
                state.planAdjustments,
              )
            : state.plans,
        raceImportStatusMessage: '已导入 ${race.name}，并写入本地 races；自动排期会按比赛日期重算。',
      );
      state = nextState.copyWith(
        coachAdvices: _aiTrainingService.buildMockCoachAdvice(
          profile: nextState.profile,
          todayWorkout: nextState.todayWorkout,
          todayMealGuide: nextState.activeMealGuide,
          latestLog: nextState.latestLog,
          latestPainLog: nextState.latestPainLog,
        ),
      );
    } on FormatException catch (error) {
      state = state.copyWith(raceImportStatusMessage: error.message);
    } catch (_) {
      state = state.copyWith(raceImportStatusMessage: '导入失败：请检查赛事文本格式。');
    }
  }

  /// 确认正式比赛成绩。返回空值表示保存成功，否则返回可展示的中文错误。
  String? confirmOfficialRaceResult({
    required String raceId,
    required String trainingLogId,
    required String durationText,
    DateTime? confirmedAt,
  }) {
    final RacePlan? race = state.findRace(raceId);
    if (race == null) {
      return '未找到这场比赛，请刷新后重试。';
    }

    TrainingLog? linkedLog;
    for (final TrainingLog log in state.logs) {
      if (log.id == trainingLogId) {
        linkedLog = log;
        break;
      }
    }
    if (linkedLog == null) {
      return '未找到所选训练记录，请重新选择。';
    }
    if (!linkedLog.canConfirmOfficialRaceResult) {
      return '所选记录不是已完成且包含实际时长或距离的正式训练记录。';
    }
    if (!race.isOnRaceDate(linkedLog.date)) {
      return '所选训练记录与比赛日期不一致，请选择比赛当天的记录。';
    }

    final int durationSeconds;
    try {
      durationSeconds = OfficialRaceResult.parseDurationSeconds(durationText);
    } on FormatException catch (error) {
      return error.message;
    }

    final RacePlan updatedRace = race.confirmOfficialRaceResult(
      durationSeconds: durationSeconds,
      confirmedAt: confirmedAt ?? DateTime.now(),
      trainingLogId: linkedLog.id,
      workoutDayId: linkedLog.workoutDayId,
    );
    try {
      _raceRepository.saveRace(updatedRace);
      state = state.copyWith(
        races: _raceRepository.listRaces(),
        raceImportStatusMessage:
            '已确认 ${race.name} 的正式比赛成绩 ${updatedRace.officialRaceResult!.durationLabel}。',
      );
      return null;
    } catch (_) {
      return '正式比赛成绩保存失败，本次确认未生效，请稍后重试。';
    }
  }

  /// 撤销正式比赛成绩确认。撤销后该成绩不再以 PB 展示。
  String? revokeOfficialRaceResult({
    required String raceId,
    DateTime? revokedAt,
  }) {
    final RacePlan? race = state.findRace(raceId);
    if (race == null) {
      return '未找到这场比赛，请刷新后重试。';
    }
    if (!race.hasActiveOfficialRaceResult) {
      return '这场比赛当前没有可撤销的正式成绩。';
    }

    final RacePlan updatedRace =
        race.revokeOfficialRaceResult(revokedAt ?? DateTime.now());
    try {
      _raceRepository.saveRace(updatedRace);
      state = state.copyWith(
        races: _raceRepository.listRaces(),
        raceImportStatusMessage: '已撤销 ${race.name} 的正式比赛成绩确认。',
      );
      return null;
    } catch (_) {
      return '正式比赛成绩撤销失败，原确认仍然保留，请稍后重试。';
    }
  }

  void _syncAchievementRecordsForCurrentState({
    bool showNoChangeMessage = false,
  }) {
    ref.read(achievementControllerProvider.notifier).sync(
          state.achievementProgressList,
          showNoChangeMessage: showNoChangeMessage,
        );
  }

  void setKnowledgeSearchQuery(String query) {
    state = state.copyWith(
      knowledgeSearchQuery: query,
      knowledgeImportStatusMessage: query.trim().isEmpty
          ? state.knowledgeImportStatusMessage
          : '已筛选到 ${state.copyWith(knowledgeSearchQuery: query).knowledgeSearchMatchCount} 本相关书籍。',
    );
  }

  void importKnowledgeText(String rawText) {
    try {
      final KnowledgeImportResult result = _knowledgeImportService.parse(
        rawText,
      );
      _knowledgeRepository.saveImportedEntry(result);
      state = state.copyWith(
        knowledgeBooks: _knowledgeRepository.listBooks(),
        bookQuotes: _knowledgeRepository.listQuotes(),
        citationLinks: _knowledgeRepository.listCitationLinks(),
        knowledgeImportStatusMessage:
            '${result.summary} 当前本地书库 ${_knowledgeRepository.listBooks().length} 本。',
      );
    } on FormatException catch (error) {
      state = state.copyWith(knowledgeImportStatusMessage: error.message);
    } catch (_) {
      state = state.copyWith(knowledgeImportStatusMessage: '导入失败：请检查书籍和引文字段。');
    }
  }

  void savePainLog({
    required String bodyPart,
    required int painLevel,
    required PainTiming timing,
    String note = '',
  }) {
    final DateTime now = DateTime.now();
    final PainLog painLog = PainLog(
      id: 'pain-${now.millisecondsSinceEpoch}',
      bodyPart: bodyPart,
      painLevel: painLevel,
      timing: timing,
      note: note,
      date: now,
      createdAt: now,
    );
    _painLogRepository.savePainLog(painLog);
    final List<PainLog> painLogs = _painLogRepository.listPainLogs();
    final TrainingMvpState nextState = state.copyWith(painLogs: painLogs);
    state = nextState.copyWith(
      coachAdvices: _aiTrainingService.buildMockCoachAdvice(
        profile: nextState.profile,
        todayWorkout: nextState.todayWorkout,
        todayMealGuide: nextState.activeMealGuide,
        latestLog: nextState.latestLog,
        latestPainLog: painLogs.first,
      ),
    );
    _syncAchievementRecordsForCurrentState();
  }

  void analyzeMotionCheck(String ruleId) {
    final MotionCheckRule? rule = state.findMotionCheck(ruleId);
    if (rule == null) {
      state = state.copyWith(motionAnalysisStatusMessage: '动作分析失败：找不到对应动作规则。');
      return;
    }

    final DateTime now = DateTime.now();
    final Exercise? exercise =
        rule.exerciseId == null ? null : state.findExercise(rule.exerciseId!);
    final MotionAnalysisResult result = _motionAnalysisService.buildMockResult(
      rule: rule,
      capturedAt: now,
      bodyProfile: exercise?.bodyEngineProfile,
    );
    _motionAnalysisRepository.saveResult(result);
    final List<MotionAnalysisResult> results =
        _motionAnalysisRepository.listResults();
    state = state.copyWith(
      motionAnalysisResults: results,
      motionAnalysisStatusMessage:
          '已完成 Motion Vision Mock 分析：${rule.type.label} · ${result.riskLevel.label}，并写入今日决策输入。',
      dailyAdjustmentStatusMessage:
          '动作质量风险已更新：${result.suggestedImpact.label}。打开每日调整可查看重算结果。',
    );
  }

  void analyzeMotionCheckWithPose(String ruleId) {
    final MotionCheckRule? rule = state.findMotionCheck(ruleId);
    if (rule == null) {
      state = state.copyWith(motionAnalysisStatusMessage: '动作分析失败：找不到对应动作规则。');
      return;
    }
    _analyzeMotionCheckWithPoseFrame(
      rule: rule,
      frame: MotionPoseAnalysisService.sampleFrameFor(rule.type),
      statusPrefix: '已完成本地关键点几何分析',
    );
  }

  void analyzeMotionCheckFromPoseJson({
    required String ruleId,
    required String rawJson,
  }) {
    final MotionPoseImportResult importResult =
        _motionPoseImportService.parse(rawJson);
    if (!importResult.isValid) {
      state = state.copyWith(
        motionAnalysisStatusMessage:
            '关键点导入失败：${importResult.errorMessage ?? '数据无效。'}',
      );
      return;
    }
    final MotionCheckRule? rule = state.findMotionCheck(ruleId);
    if (rule == null) {
      state = state.copyWith(motionAnalysisStatusMessage: '动作分析失败：找不到对应动作规则。');
      return;
    }
    _analyzeMotionCheckWithPoseFrame(
      rule: rule,
      frame: importResult.frame!,
      statusPrefix: '已导入并完成关键点几何分析',
    );
  }

  /// 将用户确认的云端动作评分转换为既有本地动作分析记录。
  void applyAiMotionArtifact({
    required AiArtifact artifact,
    required String ruleId,
  }) {
    final AiMotionScore? score = artifact.motionScore;
    final MotionCheckRule? rule = state.findMotionCheck(ruleId);
    if (artifact.decision != AiArtifactDecision.accepted ||
        score == null ||
        rule == null) {
      state = state.copyWith(
        motionAnalysisStatusMessage: '无法应用 AI Motion 结果，请先确认评分卡和动作类型。',
      );
      return;
    }
    final MotionAnalysisResult fallback =
        _motionAnalysisService.buildMockResult(
      rule: rule,
      capturedAt: artifact.generatedAt,
      bodyProfile: rule.exerciseId == null
          ? null
          : state.findExercise(rule.exerciseId!)?.bodyEngineProfile,
    );
    final MotionRiskLevel riskLevel = motionRiskLevelFromJson(score.riskLevel);
    final TrainingDecisionImpact suggestedImpact = switch (riskLevel) {
      MotionRiskLevel.low => TrainingDecisionImpact.keep,
      MotionRiskLevel.medium => TrainingDecisionImpact.deload,
      MotionRiskLevel.high => TrainingDecisionImpact.technique,
    };
    final MotionAnalysisResult result = MotionAnalysisResult(
      id: 'ai-motion-${artifact.id}',
      sourceRuleId: rule.id,
      type: rule.type,
      title: '${rule.type.label}AI 图片分析',
      score: score.score,
      riskLevel: riskLevel,
      capturedAt: artifact.generatedAt,
      detectedErrors: score.detectedErrors.isEmpty
          ? fallback.detectedErrors
          : score.detectedErrors,
      involvedAreas: fallback.involvedAreas,
      bodyEngineSummary: score.corrections.isEmpty
          ? fallback.bodyEngineSummary
          : 'AI 建议：${score.corrections.join('；')}',
      decisionImpact: riskLevel == MotionRiskLevel.high
          ? 'AI 图片复核提示高风险，今天应转为技术练习或停止相关负重。'
          : riskLevel == MotionRiskLevel.medium
              ? 'AI 图片复核提示中风险，今天建议降级并优先处理动作质量。'
              : 'AI 图片复核未见明显高风险，仍需按本地反馈决定训练强度。',
      suggestedImpact: suggestedImpact,
      replacementActions: score.replacements.isEmpty
          ? fallback.replacementActions
          : score.replacements,
      evidenceSources: fallback.evidenceSources,
      analysisSource: 'AI Motion 图片分析（用户确认上传）',
      analysisConfidence: score.confidence,
      angleMetrics: score.corrections,
    );
    _motionAnalysisRepository.saveResult(result);
    final List<MotionAnalysisResult> results =
        _motionAnalysisRepository.listResults();
    state = state.copyWith(
      motionAnalysisResults: results,
      motionAnalysisStatusMessage:
          '已采用 AI Motion 图片分析：${rule.type.label} · ${result.riskLevel.label}。',
      dailyAdjustmentStatusMessage:
          'AI Motion 已写入本地决策输入：${result.suggestedImpact.label}。',
    );
  }

  /// 将已确认的 AI Trainer 卡片保存为本地个性化计划，不覆盖种子计划。
  void applyAiTrainerArtifact(AiArtifact artifact) {
    final AiTrainerPlan? plan = artifact.trainerPlan;
    if (artifact.decision != AiArtifactDecision.accepted || plan == null) {
      state = state.copyWith(
        formalPlanStatusMessage: '无法采用该 AI Trainer 卡片，请先确认结果。',
      );
      return;
    }
    final List<String> weeklyFocus = <String>[
      for (final AiTrainerWorkoutCard card in plan.workoutCards)
        '${card.title} · ${card.durationMinutes} 分钟 · ${card.focus.join(' / ')}',
    ];
    final FormalAiPlan localPlan = FormalAiPlan(
      id: 'ai-trainer-${artifact.id}',
      generatedAt: artifact.generatedAt,
      title: plan.cycleLabel,
      goalLabel: state.todayWorkout.title,
      durationLabel: '${plan.workoutCards.length} 张训练卡',
      weeklyStructure: plan.weeklyStructure,
      progressionRule: '每次只在动作质量、恢复和日程允许时推进一个最小变量。',
      safetyRule: plan.safetyNotes.join('；'),
      weeklyFocus: weeklyFocus,
      decisionRules: <String>[
        ...plan.safetyNotes,
        for (final AiTrainerWorkoutCard card in plan.workoutCards)
          card.safetyNote,
      ],
    );
    _formalAiPlanRepository.savePlan(localPlan);
    state = state.copyWith(
      formalPlanUnlocked: true,
      formalAiPlan: localPlan,
      formalPlanStatusMessage: '已采用 AI Trainer 计划：${localPlan.title}。种子计划未改变。',
    );
  }

  void _analyzeMotionCheckWithPoseFrame({
    required MotionCheckRule rule,
    required MotionPoseFrame frame,
    required String statusPrefix,
  }) {
    final DateTime now = DateTime.now();
    final Exercise? exercise =
        rule.exerciseId == null ? null : state.findExercise(rule.exerciseId!);
    final MotionAnalysisResult result = _motionAnalysisService.buildPoseResult(
      rule: rule,
      frame: frame,
      capturedAt: now,
      bodyProfile: exercise?.bodyEngineProfile,
    );
    _motionAnalysisRepository.saveResult(result);
    final List<MotionAnalysisResult> results =
        _motionAnalysisRepository.listResults();
    state = state.copyWith(
      motionAnalysisResults: results,
      motionAnalysisStatusMessage:
          '$statusPrefix：${rule.type.label} · ${result.riskLevel.label}；结果不代表相机识别。',
      dailyAdjustmentStatusMessage:
          '关键点几何风险已更新：${result.suggestedImpact.label}。打开每日调整可查看重算结果。',
    );
  }

  void markInsightNeedsCorrection(UserProfileInsight insight) {
    state = state.copyWith(
      userInsightStatusMessage:
          '已记录修正：${insight.title}。后续画像更新会降低该结论置信度，并继续走保守策略。',
    );
  }

  void generateWeeklyUserInsightTask() {
    final UserInsightTableState tableState =
        _userInsightRepository.saveWeeklySnapshot(
      profile: state.profile,
      profileEvents: state.profileEvents,
      userProfiles: state.userProfileInsights,
      predictionLogs: state.predictionLogs,
    );
    final UserInsightWeeklyTask? task = tableState.latestWeeklyTask;
    state = state.copyWith(
      userInsightTableState: tableState,
      userInsightStatusMessage: task == null
          ? '周度画像任务未生成：当前没有可写入的画像快照。'
          : '已生成 ${task.weekLabel} 周度画像任务：profile_events ${task.profileEventCount} 条，user_profiles ${task.userProfileCount} 条，prediction_logs ${task.predictionLogCount} 条。',
    );
  }

  void importActivityText(String rawText) {
    _importActivity(() => _activityImportService.parse(rawText));
  }

  void importGpxDocument(String rawText, {required String fileName}) {
    _importActivity(
      () => _activityImportService.parseGpx(rawText, fileName: fileName),
    );
  }

  void removeImportedRouteShape(String workoutId) {
    final bool removed = _importedWorkoutRepository.removeRouteShape(workoutId);
    state = state.copyWith(
      importedWorkouts: _importedWorkoutRepository.listWorkouts(),
      activityImportStatusMessage:
          removed ? '本地路线数据已删除；训练摘要和成长证据继续保留。' : '这条训练没有可删除的路线数据。',
    );
  }

  void setActivityImportStatusMessage(String message) {
    state = state.copyWith(activityImportStatusMessage: message);
  }

  void _importActivity(ImportedWorkout Function() parseWorkout) {
    try {
      final ImportedWorkout importedWorkout = parseWorkout();
      final bool alreadyImported = state.importedWorkouts.any(
        (ImportedWorkout existing) =>
            existing.id == importedWorkout.id ||
            (importedWorkout.sourceFingerprint.isNotEmpty &&
                existing.sourceFingerprint ==
                    importedWorkout.sourceFingerprint),
      );
      if (alreadyImported) {
        state = state.copyWith(
          activityImportStatusMessage:
              '这项 ${importedWorkout.source.label} 训练已导入过，未重复生成训练日志。',
        );
        return;
      }
      final DateTime now = DateTime.now();
      final TrainingLog log = TrainingLog(
        id: 'import-log-${importedWorkout.id}',
        workoutDayId: state.todayWorkout.id,
        date: importedWorkout.startedAt,
        completed: true,
        rpe: _rpeForTrainingEffect(importedWorkout.trainingEffect),
        fatigueLevel: _rpeForTrainingEffect(importedWorkout.trainingEffect),
        sleepQuality: 7,
        painNote: null,
        userNote:
            '[训练文件导入] ${importedWorkout.source.label} · ${importedWorkout.summary} · 爬升 ${importedWorkout.elevationGainMeters} m · 平均心率 ${importedWorkout.averageHeartRate} bpm',
        createdAt: now,
        kind: TrainingLogKind.activityImport,
        actualDurationMinutes: importedWorkout.durationMinutes,
        distanceKm: importedWorkout.distanceKm,
        completionPercentage: 100,
        averageHeartRate: importedWorkout.averageHeartRate,
        averagePaceSecondsPerKm: importedWorkout.distanceKm <= 0
            ? 0
            : ((importedWorkout.durationMinutes * 60) /
                    importedWorkout.distanceKm)
                .round(),
      );
      final List<TrainingLog> logs =
          ref.read(trainingLogControllerProvider.notifier).save(log);
      _importedWorkoutRepository.saveWorkout(importedWorkout);
      final List<ImportedWorkout> importedWorkouts =
          _importedWorkoutRepository.listWorkouts();
      state = state.copyWith(
        importedWorkouts: importedWorkouts,
        logs: logs,
        activityImportStatusMessage:
            '已导入 ${importedWorkout.source.label}：${importedWorkout.summary}，并写入 imported_workouts 和 workout_logs。',
        coachAdvices: _aiTrainingService.buildMockCoachAdvice(
          profile: state.profile,
          todayWorkout: state.todayWorkout,
          todayMealGuide: state.activeMealGuide,
          latestLog: logs.first,
          latestPainLog: state.latestPainLog,
        ),
      );
      _syncGrowthForTrainingLog(log, workout: state.todayWorkout);
    } on FormatException catch (error) {
      state = state.copyWith(activityImportStatusMessage: error.message);
    } catch (_) {
      state = state.copyWith(
        activityImportStatusMessage: '导入失败：请检查文件或摘要格式。',
      );
    }
  }

  void setStarterProgramGoal(StarterProgramGoal goal) {
    _formalAiPlanRepository.clearPlan();
    final TrainingMvpState nextState = state.copyWith(
      starterProgramGoal: goal,
      starterProgramDayIndex: 1,
      starterProgramStreak: 0,
      starterProgramRescueMode: false,
      starterProgramStatusMessage: '已切换到${goal.label}，从第 1 天重新开始。',
      formalPlanUnlocked: false,
      formalPlanStatusMessage: '30 天毕业后可切换到正式 AI 个性化周期。',
      formalAiPlan: null,
      reminderStatusMessage: '已按${state.reminderTimeLabel}继续提醒新的 30 天引导目标。',
    );
    _saveStarterProgramProgress(nextState);
    state = nextState;
  }

  void completeStarterProgramDay(StarterProgramFeedback feedback) {
    final int nextDay = state.starterProgramDayIndex >= 30
        ? 30
        : state.starterProgramDayIndex + 1;
    final int nextStreak =
        (state.starterProgramStreak + 1).clamp(0, 30).toInt();
    final String message = switch (feedback) {
      StarterProgramFeedback.tooTired => '已记录“太累了”：明天不加量，恢复优先。',
      StarterProgramFeedback.justRight => '已记录“刚好”：明天按计划推进。',
      StarterProgramFeedback.tooEasy => '已记录“太轻松”：明天只增加 1 个最小变量。',
    };
    final TrainingMvpState nextState = state.copyWith(
      starterProgramDayIndex: nextDay,
      starterProgramStreak: nextStreak,
      starterProgramRescueMode: false,
      starterProgramStatusMessage: state.starterProgramDayIndex >= 30
          ? '毕业测试已完成，可以切换到正式 AI 个性化计划。'
          : message,
      formalPlanStatusMessage: nextStreak >= 30
          ? '毕业报告已生成，可以一键切换到正式 AI 个性化周期。'
          : state.formalPlanStatusMessage,
    );
    _saveStarterProgramProgress(nextState);
    state = nextState;
    _syncAchievementRecordsForCurrentState();
  }

  void unlockFormalAiPlanFromGraduation() {
    final StarterGraduationReport report = state.starterGraduationReport;
    final FormalAiPlan formalPlan = _formalAiPlanService.generatePlan(
      graduationReport: report,
      starterGoal: state.starterProgramGoal,
      profile: state.profile,
      trainingStatusLabel: state.trainingStatusLabel,
      readinessScore: state.readinessScore,
    );
    _formalAiPlanRepository.savePlan(formalPlan);
    state = state.copyWith(
      formalPlanUnlocked: true,
      formalAiPlan: formalPlan,
      formalPlanStatusMessage: '已生成正式 AI 个性化周期：${formalPlan.title}。',
      reminderStatusMessage: '提醒已切换为正式 AI 周期确认，不再推送新手引导任务。',
    );
  }

  void postponeStarterProgramDay() {
    final TrainingMvpState nextState = state.copyWith(
      starterProgramRescueMode: false,
      starterProgramStatusMessage: '计划已顺延：今天仍保留当前任务，完成后计入累计成长日。',
    );
    _saveStarterProgramProgress(nextState);
    state = nextState;
  }

  void useStarterRescueVersion() {
    final TrainingMvpState nextState = state.copyWith(
      starterProgramRescueMode: true,
      starterProgramStatusMessage: '已切换 5 分钟补救版，完成后计入累计成长日。',
    );
    _saveStarterProgramProgress(nextState);
    state = nextState;
  }

  void _saveStarterProgramProgress(TrainingMvpState nextState) {
    _starterProgramRepository.saveProgress(
      StarterProgramProgress(
        goal: nextState.starterProgramGoal,
        dayIndex: nextState.starterProgramDayIndex,
        streak: nextState.starterProgramStreak,
        rescueMode: nextState.starterProgramRescueMode,
        statusMessage: nextState.starterProgramStatusMessage,
      ),
    );
  }

  List<String> _nextWorkoutPlayerVoiceQueue(String cue) {
    ref.read(workoutPlayerAssistControllerProvider.notifier).enqueueCue(cue);
    final WorkoutPlayerAssistState assist =
        ref.read(workoutPlayerAssistControllerProvider);
    _projectWorkoutPlayerAssist(assist);
    return assist.voiceQueue;
  }

  String _voiceStatusFor(String cue) {
    return ref.read(workoutPlayerAssistControllerProvider).voiceStatusMessage;
  }

  void _requestScreenAwake(bool requested) {
    final String message = state.workoutPlayerScreenAwakeStatusMessage;
    ref.read(workoutPlayerAssistControllerProvider.notifier).setScreenAwake(
          requested,
          enabledMessage: message,
          disabledMessage: message,
        );
    _projectWorkoutPlayerAssist(
      ref.read(workoutPlayerAssistControllerProvider),
    );
  }

  void _projectWorkoutPlayerAssist(WorkoutPlayerAssistState assist) {
    state = state.copyWith(
      workoutPlayerVoiceEnabled: assist.voiceEnabled,
      workoutPlayerVoiceQueue: assist.voiceQueue,
      workoutPlayerVoiceStatusMessage: assist.voiceStatusMessage,
      workoutPlayerScreenAwakeRequested: assist.screenAwakeRequested,
      workoutPlayerScreenAwakeStatusMessage: assist.screenAwakeStatusMessage,
    );
  }

  void toggleWorkoutPlayerVoice() {
    ref.read(workoutPlayerAssistControllerProvider.notifier).toggleVoice();
    _projectWorkoutPlayerAssist(
      ref.read(workoutPlayerAssistControllerProvider),
    );
  }

  void toggleWorkoutPlayerScreenAwake() {
    ref
        .read(workoutPlayerAssistControllerProvider.notifier)
        .toggleScreenAwake();
    _projectWorkoutPlayerAssist(
      ref.read(workoutPlayerAssistControllerProvider),
    );
  }

  bool startWorkoutPlayer({String? workoutDayId}) {
    if (!_ensureSkillExecutionIsCurrent()) return false;
    _stopWorkoutPlayerTimer();
    final WorkoutDay selectedWorkout = workoutDayId == null
        ? state.todayWorkout
        : state.findWorkoutDay(workoutDayId) ?? state.todayWorkout;
    final WorkoutDay workout = state.withEquipmentConstraint(selectedWorkout);
    final List<WorkoutPlayerStep> steps = buildWorkoutPlayerSteps(
      workout,
      deloaded: false,
    );
    final WorkoutPlayerStep firstStep = steps.first;
    final int remainingSeconds = firstStep.estimatedSeconds;
    final String voiceCue = '准备开始：${workout.title}。${firstStep.voiceCue}';
    ref
        .read(workoutPlayerAssistControllerProvider.notifier)
        .replaceQueueWithCue(voiceCue);
    _projectWorkoutPlayerAssist(
      ref.read(workoutPlayerAssistControllerProvider),
    );
    state = state.copyWith(
      workoutPlayerStepIndex: 0,
      workoutPlayerDeloaded: false,
      workoutPlayerFinished: false,
      activeWorkoutPlayerDayId: workoutDayId,
      workoutPlayerEvents: const [],
      workoutPlayerRemainingSeconds: remainingSeconds,
      workoutPlayerTimerRunning: false,
      workoutPlayerVoiceQueue: state.workoutPlayerVoiceQueue,
      workoutPlayerVoiceStatusMessage: _voiceStatusFor(voiceCue),
      workoutPlayerScreenAwakeRequested: true,
      workoutPlayerScreenAwakeStatusMessage:
          '已请求浏览器屏幕常亮；不支持 Wake Lock 的环境会保持普通显示。',
      workoutPlayerStatusMessage: '已进入跟练模式：可启动真实倒计时，动作、休息和语音提示按步骤推进。',
    );
    _requestScreenAwake(true);
    return true;
  }

  void startWorkoutPlayerCountdown() {
    if (!_ensureSkillExecutionIsCurrent()) return;
    if (state.workoutPlayerFinished || state.workoutPlayerTimerRunning) {
      return;
    }
    final int remainingSeconds = state.workoutPlayerRemainingSeconds <= 0
        ? state.activeWorkoutPlayerStep.estimatedSeconds
        : state.workoutPlayerRemainingSeconds;
    final String voiceCue =
        '开始计时：${state.activeWorkoutPlayerStep.title}，${state.activeWorkoutPlayerStep.voiceCue}';
    state = state.copyWith(
      workoutPlayerRemainingSeconds: remainingSeconds,
      workoutPlayerTimerRunning: true,
      workoutPlayerVoiceQueue: _nextWorkoutPlayerVoiceQueue(voiceCue),
      workoutPlayerVoiceStatusMessage: _voiceStatusFor(voiceCue),
      workoutPlayerStatusMessage:
          '倒计时进行中：${state.activeWorkoutPlayerStep.title} 剩余 ${_formatCountdownSeconds(remainingSeconds)}。',
    );
    _workoutPlayerTimer?.cancel();
    _workoutPlayerTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tickWorkoutPlayerCountdown(),
    );
  }

  void pauseWorkoutPlayerCountdown() {
    _stopWorkoutPlayerTimer();
    final String voiceCue =
        '暂停计时：${state.activeWorkoutPlayerStep.title}，剩余 ${state.workoutPlayerRemainingLabel}。';
    state = state.copyWith(
      workoutPlayerTimerRunning: false,
      workoutPlayerVoiceQueue: _nextWorkoutPlayerVoiceQueue(voiceCue),
      workoutPlayerVoiceStatusMessage: _voiceStatusFor(voiceCue),
      workoutPlayerStatusMessage:
          '已暂停倒计时：${state.activeWorkoutPlayerStep.title} 剩余 ${state.workoutPlayerRemainingLabel}。',
    );
  }

  void resetWorkoutPlayerCountdown() {
    _stopWorkoutPlayerTimer();
    final String voiceCue = '已重置：${state.activeWorkoutPlayerStep.title}。';
    state = state.copyWith(
      workoutPlayerRemainingSeconds:
          state.activeWorkoutPlayerStep.estimatedSeconds,
      workoutPlayerTimerRunning: false,
      workoutPlayerVoiceQueue: _nextWorkoutPlayerVoiceQueue(voiceCue),
      workoutPlayerVoiceStatusMessage: _voiceStatusFor(voiceCue),
      workoutPlayerStatusMessage:
          '已重置当前步骤倒计时：${state.activeWorkoutPlayerStep.title}。',
    );
  }

  void _tickWorkoutPlayerCountdown() {
    if (!_ensureSkillExecutionIsCurrent()) return;
    if (state.workoutPlayerFinished || !state.workoutPlayerTimerRunning) {
      _stopWorkoutPlayerTimer();
      return;
    }
    final int nextRemaining = state.workoutPlayerRemainingSeconds - 1;
    if (nextRemaining <= 0) {
      completeWorkoutPlayerStep(autoCompleted: true);
      return;
    }
    if (nextRemaining <= 3) {
      final String countdownCue = '倒数 $nextRemaining';
      state = state.copyWith(
        workoutPlayerRemainingSeconds: nextRemaining,
        workoutPlayerVoiceQueue: _nextWorkoutPlayerVoiceQueue(countdownCue),
        workoutPlayerVoiceStatusMessage: _voiceStatusFor(countdownCue),
        workoutPlayerStatusMessage:
            '倒计时进行中：${state.activeWorkoutPlayerStep.title} 剩余 ${_formatCountdownSeconds(nextRemaining)}。',
      );
      return;
    }
    state = state.copyWith(
      workoutPlayerRemainingSeconds: nextRemaining,
      workoutPlayerStatusMessage:
          '倒计时进行中：${state.activeWorkoutPlayerStep.title} 剩余 ${_formatCountdownSeconds(nextRemaining)}。',
    );
  }

  void _stopWorkoutPlayerTimer() {
    _workoutPlayerTimer?.cancel();
    _workoutPlayerTimer = null;
  }

  void completeWorkoutPlayerStep({bool autoCompleted = false}) {
    if (!_ensureSkillExecutionIsCurrent()) return;
    _stopWorkoutPlayerTimer();
    final WorkoutPlayerStep step = state.activeWorkoutPlayerStep;
    final List<WorkoutPlayerStep> steps = state.workoutPlayerSteps;
    final bool isLastStep = state.workoutPlayerSafeIndex >= steps.length - 1;
    final int nextStepIndex = isLastStep
        ? state.workoutPlayerSafeIndex
        : state.workoutPlayerSafeIndex + 1;
    final List<TrainingLog> logs = _saveWorkoutPlayerLog(
      event: autoCompleted ? '计时完成：${step.title}' : '完成：${step.title}',
      completed: true,
      rpe: state.workoutPlayerDeloaded ? 4 : 6,
    );
    final List<String> events = [
      ...state.workoutPlayerEvents,
      autoCompleted ? '计时完成 ${step.title}' : '完成 ${step.title}',
    ];
    final String voiceCue = isLastStep
        ? '本次跟练完成，请记录训练反馈。'
        : '已完成 ${step.title}。下一步：${steps[nextStepIndex].title}，${steps[nextStepIndex].voiceCue}';

    state = state.copyWith(
      logs: logs,
      coachAdvices: _aiTrainingService.buildMockCoachAdvice(
        profile: state.profile,
        todayWorkout: state.activeWorkoutPlayerWorkout,
        todayMealGuide: state.activeMealGuide,
        latestLog: logs.first,
        latestPainLog: state.latestPainLog,
      ),
      workoutPlayerStepIndex: isLastStep
          ? state.workoutPlayerSafeIndex
          : state.workoutPlayerSafeIndex + 1,
      workoutPlayerFinished: isLastStep,
      workoutPlayerEvents: events,
      workoutPlayerRemainingSeconds:
          isLastStep ? 0 : steps[nextStepIndex].estimatedSeconds,
      workoutPlayerTimerRunning: false,
      workoutPlayerVoiceQueue: _nextWorkoutPlayerVoiceQueue(voiceCue),
      workoutPlayerVoiceStatusMessage: _voiceStatusFor(voiceCue),
      workoutPlayerScreenAwakeRequested:
          isLastStep ? false : state.workoutPlayerScreenAwakeRequested,
      workoutPlayerScreenAwakeStatusMessage: isLastStep
          ? '本次跟练已完成，已释放屏幕常亮意图。'
          : state.workoutPlayerScreenAwakeStatusMessage,
      workoutPlayerStatusMessage: isLastStep
          ? '本次跟练已完成，执行记录已写入 workout_logs。'
          : autoCompleted
              ? '${step.title}倒计时结束，已自动进入下一步。'
              : '已完成${step.title}，自动进入下一步。',
    );
    if (isLastStep) {
      _requestScreenAwake(false);
    }
    _syncAchievementRecordsForCurrentState();
  }

  void skipWorkoutPlayerStep() {
    if (!_ensureSkillExecutionIsCurrent()) return;
    _stopWorkoutPlayerTimer();
    final WorkoutPlayerStep step = state.activeWorkoutPlayerStep;
    final List<WorkoutPlayerStep> steps = state.workoutPlayerSteps;
    final bool isLastStep = state.workoutPlayerSafeIndex >= steps.length - 1;
    final int nextStepIndex = isLastStep
        ? state.workoutPlayerSafeIndex
        : state.workoutPlayerSafeIndex + 1;
    final List<TrainingLog> logs = _saveWorkoutPlayerLog(
      event: '跳过：${step.title}',
      completed: false,
      rpe: 5,
    );
    final List<String> events = [
      ...state.workoutPlayerEvents,
      '跳过 ${step.title}',
    ];
    final String voiceCue = isLastStep
        ? '本次跟练已结束，跳过记录已写入日志。'
        : '已跳过 ${step.title}。下一步：${steps[nextStepIndex].title}，${steps[nextStepIndex].voiceCue}';

    state = state.copyWith(
      logs: logs,
      coachAdvices: _aiTrainingService.buildMockCoachAdvice(
        profile: state.profile,
        todayWorkout: state.activeWorkoutPlayerWorkout,
        todayMealGuide: state.activeMealGuide,
        latestLog: logs.first,
        latestPainLog: state.latestPainLog,
      ),
      workoutPlayerStepIndex: isLastStep
          ? state.workoutPlayerSafeIndex
          : state.workoutPlayerSafeIndex + 1,
      workoutPlayerFinished: isLastStep,
      workoutPlayerEvents: events,
      workoutPlayerRemainingSeconds:
          isLastStep ? 0 : steps[nextStepIndex].estimatedSeconds,
      workoutPlayerTimerRunning: false,
      workoutPlayerVoiceQueue: _nextWorkoutPlayerVoiceQueue(voiceCue),
      workoutPlayerVoiceStatusMessage: _voiceStatusFor(voiceCue),
      workoutPlayerScreenAwakeRequested:
          isLastStep ? false : state.workoutPlayerScreenAwakeRequested,
      workoutPlayerScreenAwakeStatusMessage: isLastStep
          ? '本次跟练已结束，已释放屏幕常亮意图。'
          : state.workoutPlayerScreenAwakeStatusMessage,
      workoutPlayerStatusMessage: isLastStep
          ? '本次跟练已结束，跳过记录已写入 workout_logs。'
          : '已跳过${step.title}，继续下一步。',
    );
    if (isLastStep) {
      _requestScreenAwake(false);
    }
    _syncAchievementRecordsForCurrentState();
  }

  void deloadWorkoutPlayer() {
    if (!_ensureSkillExecutionIsCurrent()) return;
    _stopWorkoutPlayerTimer();
    final WorkoutPlayerStep step = state.activeWorkoutPlayerStep;
    final List<WorkoutPlayerStep> deloadedSteps = buildWorkoutPlayerSteps(
      state.activeWorkoutPlayerWorkout,
      deloaded: true,
    );
    final List<TrainingLog> logs = _saveWorkoutPlayerLog(
      event: '太累了：${step.title}，剩余内容降级',
      completed: false,
      rpe: 8,
    );
    final String voiceCue =
        '已切换低强度版本。下一步：${deloadedSteps[3].title}，${deloadedSteps[3].voiceCue}';
    state = state.copyWith(
      logs: logs,
      coachAdvices: _aiTrainingService.buildMockCoachAdvice(
        profile: state.profile,
        todayWorkout: state.activeWorkoutPlayerWorkout,
        todayMealGuide: state.activeMealGuide,
        latestLog: logs.first,
        latestPainLog: state.latestPainLog,
      ),
      workoutPlayerStepIndex: 3,
      workoutPlayerDeloaded: true,
      workoutPlayerFinished: false,
      workoutPlayerRemainingSeconds: deloadedSteps[3].estimatedSeconds,
      workoutPlayerTimerRunning: false,
      workoutPlayerVoiceQueue: _nextWorkoutPlayerVoiceQueue(voiceCue),
      workoutPlayerVoiceStatusMessage: _voiceStatusFor(voiceCue),
      workoutPlayerEvents: [
        ...state.workoutPlayerEvents,
        '太累了 ${step.title}，剩余内容降级',
      ],
      workoutPlayerStatusMessage: '已一键降级剩余内容：改为低强度版，优先保证安全和可持续执行。',
    );
    _syncAchievementRecordsForCurrentState();
  }

  bool _ensureSkillExecutionIsCurrent() {
    final FourWeekPlanState planState =
        ref.read(fourWeekPlanControllerProvider);
    final String? activeVersionId = planState.activeVersionId;
    final bool activeVersionIsSkill = activeVersionId != null &&
        planState.history.any(
          (version) =>
              version.id == activeVersionId && version.isSkillGenerated,
        );
    if (!activeVersionIsSkill) return true;

    final PreExerciseClearance? clearance =
        ref.read(preExerciseClearanceControllerProvider).value?.clearance;
    final DateTime now = ref.read(trainingExecutionClockProvider)();
    if (clearance?.isValidAt(now) == true) return true;

    final TrainingPlan fallbackPlan = planState.fallbackGeneration.plan;
    if (state.activePlan.id == fallbackPlan.id) {
      return true;
    }
    _switchSkillExecutionToFallback(
      planState,
      reason: clearance?.blockingReasonAt(now) ?? '筛查状态暂不可验证。',
    );
    return false;
  }

  void _switchSkillExecutionToFallback(
    FourWeekPlanState planState, {
    String? reason,
  }) {
    _stopWorkoutPlayerTimer();
    final List<TrainingPlan> fallbackPlans = _applyPlanAdjustments(
      <TrainingPlan>[planState.fallbackGeneration.plan],
      state.planAdjustments,
    );
    final WorkoutDay fallbackWorkout = fallbackPlans.first.workoutDays.first;
    final int remainingSeconds = buildWorkoutPlayerSteps(
      fallbackWorkout,
      deloaded: false,
    ).first.estimatedSeconds;
    state = state.copyWith(
      plans: fallbackPlans,
      workoutPlayerStepIndex: 0,
      workoutPlayerDeloaded: false,
      workoutPlayerFinished: false,
      activeWorkoutPlayerDayId: null,
      workoutPlayerEvents: <String>[
        ...state.workoutPlayerEvents,
        '筛查状态失效，旧 Skill 跟练已停止',
      ],
      workoutPlayerRemainingSeconds: remainingSeconds,
      workoutPlayerTimerRunning: false,
      workoutPlayerScreenAwakeRequested: false,
      workoutPlayerScreenAwakeStatusMessage: '旧 Skill 跟练已停止，屏幕常亮已释放。',
      workoutPlayerStatusMessage:
          '${reason ?? '筛查状态当前无效。'}旧 Skill 跟练已停止，并已切换到本地安全计划。',
    );
    _requestScreenAwake(false);
  }

  void saveTodayLog({
    required bool completed,
    required int rpe,
    String? userNote,
  }) {
    final DateTime now = DateTime.now();
    final TrainingLog log = TrainingLog(
      id: 'log-${now.millisecondsSinceEpoch}',
      workoutDayId: state.todayWorkout.id,
      planItemId:
          state.scheduledTodayWorkout?.workoutDayId == state.todayWorkout.id
              ? state.scheduledTodayWorkout?.id
              : null,
      date: now,
      completed: completed,
      rpe: rpe,
      fatigueLevel: rpe.clamp(1, 10),
      sleepQuality: 7,
      painNote: null,
      userNote: userNote,
      createdAt: now,
      kind: TrainingLogKind.manual,
    );
    final List<TrainingLog> logs =
        ref.read(trainingLogControllerProvider.notifier).save(log);
    state = state.copyWith(
      logs: logs,
      coachAdvices: _aiTrainingService.buildMockCoachAdvice(
        profile: state.profile,
        todayWorkout: state.todayWorkout,
        todayMealGuide: state.activeMealGuide,
        latestLog: logs.first,
        latestPainLog: state.latestPainLog,
      ),
    );
    _syncAchievementRecordsForCurrentState();
    _syncGrowthForTrainingLog(log, workout: state.todayWorkout);
  }

  void saveWorkoutSessionReview({
    required int actualDurationMinutes,
    required int completionPercentage,
    required int rpe,
    required int averageHeartRate,
    required int averagePaceSecondsPerKm,
    required int plannedSetCount,
    required int completedSetCount,
    List<ExerciseExecutionRecord> exerciseRecords = const [],
    String? interruptionReason,
    String? userNote,
    bool abortedByUser = false,
    SessionFeel? sessionFeel,
    int? focusQuality,
  }) {
    final DateTime now = DateTime.now();
    final int safeDuration = actualDurationMinutes.clamp(5, 360).toInt();
    final int safeCompletion = completionPercentage.clamp(0, 100).toInt();
    final int safeRpe = rpe.clamp(1, 10).toInt();
    final int safeHeartRate = averageHeartRate.clamp(0, 260).toInt();
    final int safePace = averagePaceSecondsPerKm.clamp(0, 3600).toInt();
    final int safePlannedSets = plannedSetCount.clamp(0, 99).toInt();
    final int safeCompletedSets =
        completedSetCount.clamp(0, safePlannedSets).toInt();
    final List<ExerciseExecutionRecord> safeExerciseRecords =
        List<ExerciseExecutionRecord>.unmodifiable(
      exerciseRecords.map((ExerciseExecutionRecord item) {
        final String exerciseId = item.exerciseId?.trim() ?? '';
        final List<StrengthSetExecutionRecord> safeSets =
            List<StrengthSetExecutionRecord>.unmodifiable(
          item.sets.indexed.map(
            ((int, StrengthSetExecutionRecord) indexed) {
              final StrengthSetExecutionRecord set = indexed.$2;
              final double? rpe = set.rpe;
              final int? durationSeconds = set.durationSeconds;
              return StrengthSetExecutionRecord(
                setIndex: indexed.$1 + 1,
                repetitions: set.repetitions.clamp(0, 999).toInt(),
                weightKg: set.weightKg.clamp(0, 500).toDouble(),
                rpe: rpe?.clamp(1, 10).toDouble(),
                durationSeconds: durationSeconds?.clamp(1, 3600).toInt(),
              );
            },
          ),
        );
        return ExerciseExecutionRecord(
          exerciseId: exerciseId.isEmpty ? null : exerciseId,
          exerciseName: item.exerciseName.trim().isEmpty
              ? '未命名动作'
              : item.exerciseName.trim(),
          plannedSetCount: item.plannedSetCount.clamp(0, 99).toInt(),
          completedSetCount: safeSets.isEmpty
              ? item.completedSetCount.clamp(0, 99).toInt()
              : safeSets.length,
          repetitionsPerSet: item.repetitionsPerSet.clamp(0, 999).toInt(),
          weightKg: safeSets.isEmpty
              ? item.weightKg.clamp(0, 500).toDouble()
              : safeSets
                  .map((StrengthSetExecutionRecord set) => set.weightKg)
                  .reduce((double first, double second) =>
                      first > second ? first : second),
          sets: safeSets,
        );
      }),
    );
    final String reason = interruptionReason?.trim() ?? '';
    final String note = userNote?.trim() ?? '';
    final String dayKey =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final TrainingLog log = TrainingLog(
      id: 'session-review-${state.activeWorkoutPlayerWorkout.id}-$dayKey',
      workoutDayId: state.activeWorkoutPlayerWorkout.id,
      planItemId: state.scheduledTodayWorkout?.workoutDayId ==
              state.activeWorkoutPlayerWorkout.id
          ? state.scheduledTodayWorkout?.id
          : null,
      date: now,
      completed: safeCompletion == 100,
      rpe: safeRpe,
      fatigueLevel: safeRpe,
      sleepQuality: 7,
      painNote: state.latestPainLog == null
          ? null
          : '${state.latestPainLog!.bodyPart} ${state.latestPainLog!.painLevel}/10',
      userNote: note.isEmpty ? null : note,
      createdAt: now,
      kind: TrainingLogKind.sessionReview,
      actualDurationMinutes: safeDuration,
      completionPercentage: safeCompletion,
      averageHeartRate: safeHeartRate,
      averagePaceSecondsPerKm: safePace,
      plannedSetCount: safePlannedSets,
      completedSetCount: safeCompletedSets,
      interruptionReason: reason.isEmpty ? null : reason,
      downgradeAccepted: state.workoutPlayerDeloaded,
      abortedByUser: abortedByUser && safeCompletion < 100,
      exerciseRecords: safeExerciseRecords,
      sessionFeel: sessionFeel,
      focusQuality: focusQuality?.clamp(1, 5).toInt(),
    );
    final List<TrainingLog> logs =
        ref.read(trainingLogControllerProvider.notifier).save(log);
    final CoachFeedback feedback =
        const CoachFeedbackPolicy().buildTrainingReceipt(
      current: log,
      workoutLabel: state.activeWorkoutPlayerWorkout.title,
    );
    state = state.copyWith(
      logs: logs,
      coachAdvices: _aiTrainingService.buildMockCoachAdvice(
        profile: state.profile,
        todayWorkout: state.activeWorkoutPlayerWorkout,
        todayMealGuide: state.activeMealGuide,
        latestLog: logs.first,
        latestPainLog: state.latestPainLog,
      ),
      workoutPlayerStatusMessage: feedback.text,
    );
    _syncAchievementRecordsForCurrentState();
    _syncGrowthForTrainingLog(
      log,
      workout: state.activeWorkoutPlayerWorkout,
    );
    unawaited(ref.read(petControllerProvider.notifier).refreshToday());
  }

  TrainingLog saveTrainingRecord(TrainingRecordSaveRequest request) {
    request.validate();
    final DateTime createdAt = DateTime.now();
    final String dayKey =
        '${request.date.year}${request.date.month.toString().padLeft(2, '0')}'
        '${request.date.day.toString().padLeft(2, '0')}';
    final String recordId = request.source == TrainingRecordSource.planned
        ? 'session-review-${request.workoutDayId.trim()}-$dayKey'
        : 'session-review-extra-${createdAt.microsecondsSinceEpoch}';
    final String? planItemId = request.source == TrainingRecordSource.planned
        ? request.planItemId ??
            (state.scheduledTodayWorkout?.workoutDayId == request.workoutDayId
                ? state.scheduledTodayWorkout?.id
                : null)
        : null;
    final List<ExerciseExecutionRecord> exerciseRecords =
        List<ExerciseExecutionRecord>.unmodifiable(
      request.exerciseRecords.map(_normalizedExerciseRecord),
    );
    final String customActivityName = request.customActivityName?.trim() ?? '';
    final String deviceWorkoutId = request.deviceWorkoutId?.trim() ?? '';
    final String reason = request.interruptionReason?.trim() ?? '';
    final String note = request.userNote?.trim() ?? '';
    final TrainingLog log = TrainingLog(
      id: recordId,
      workoutDayId: request.workoutDayId.trim(),
      planItemId: planItemId,
      date: request.date,
      completed: request.completionPercentage == 100,
      rpe: request.rpe,
      fatigueLevel: request.rpe,
      sleepQuality: 7,
      painNote: state.latestPainLog == null
          ? null
          : '${state.latestPainLog!.bodyPart} ${state.latestPainLog!.painLevel}/10',
      userNote: note.isEmpty ? null : note,
      createdAt: createdAt,
      kind: TrainingLogKind.sessionReview,
      actualDurationMinutes: request.actualDurationMinutes,
      completionPercentage: request.completionPercentage,
      averageHeartRate: request.averageHeartRate,
      averagePaceSecondsPerKm: request.averagePaceSecondsPerKm,
      plannedSetCount: request.plannedSetCount,
      completedSetCount: request.completedSetCount,
      interruptionReason: reason.isEmpty ? null : reason,
      downgradeAccepted: request.source == TrainingRecordSource.planned &&
          state.workoutPlayerDeloaded,
      abortedByUser:
          request.abortedByUser && request.completionPercentage < 100,
      exerciseRecords: exerciseRecords,
      sessionFeel: request.sessionFeel,
      focusQuality: request.focusQuality,
      activityType: request.activityType,
      customActivityName:
          customActivityName.isEmpty ? null : customActivityName,
      energyKcal: request.energyKcal,
      energySource: request.energySource,
      deviceWorkoutId: deviceWorkoutId.isEmpty ? null : deviceWorkoutId,
    );
    final List<TrainingLog> logs =
        ref.read(trainingLogControllerProvider.notifier).save(log);
    final WorkoutDay relatedWorkout =
        state.findWorkoutDay(request.workoutDayId) ?? state.todayWorkout;
    final String workoutLabel =
        request.activityType == TrainingActivityType.custom
            ? customActivityName
            : request.activityType.label;
    final CoachFeedback feedback =
        const CoachFeedbackPolicy().buildTrainingReceipt(
      current: log,
      workoutLabel: workoutLabel,
    );
    state = state.copyWith(
      logs: logs,
      coachAdvices: _aiTrainingService.buildMockCoachAdvice(
        profile: state.profile,
        todayWorkout: relatedWorkout,
        todayMealGuide: state.activeMealGuide,
        latestLog: logs.first,
        latestPainLog: state.latestPainLog,
      ),
      workoutPlayerStatusMessage: feedback.text,
    );
    _syncAchievementRecordsForCurrentState();
    _syncGrowthForTrainingLog(log, workout: relatedWorkout);
    unawaited(ref.read(petControllerProvider.notifier).refreshToday());
    return log;
  }

  void savePsychologyWeeklyReport({
    required WeeklyPsychCheckIn psychCheckIn,
  }) {
    final WeeklyReport report = WeeklyReportService().buildWeeklyReport(
      profile: state.profile,
      todayWorkout: state.todayWorkout,
      logs: state.logs,
      bodyMetrics: state.bodyMetrics,
      readinessScore: state.readinessScore,
      trainingStatusLabel: state.trainingStatusLabel,
      trainingStatusReason: state.trainingStatusReason,
      recoveryCountdownLabel: state.recoveryCountdownLabel,
      recoveryAdvice: state.recoveryAdvice,
      achievementSummaryLabel: state.achievementSummaryLabel,
      psychCheckIn: psychCheckIn,
      plannedWorkoutsForWeek: state.activePlan.workoutDays
          .where(
            (WorkoutDay workout) =>
                workout.weekIndex == state.todayWorkout.weekIndex,
          )
          .toList(growable: false),
    );
    _weeklyReportRepository.saveReport(report);
    state = state.copyWith(
      savedWeeklyReports: _weeklyReportRepository.listReports(),
      weeklyReportSaveStatusMessage: '周报状态已保存在本地，可继续选择下周方向。',
    );
  }

  void selectWeeklyReportOption({
    required String reportId,
    required String optionId,
  }) {
    WeeklyReport? target;
    for (final WeeklyReport report in state.savedWeeklyReports) {
      if (report.id == reportId) {
        target = report;
        break;
      }
    }
    if (target == null ||
        !target.options.any((WeeklyReportOption item) => item.id == optionId)) {
      state = state.copyWith(
        weeklyReportSaveStatusMessage: '下周方向保存失败：选项不存在。',
      );
      return;
    }
    _weeklyReportRepository.saveReport(
      target.copyWith(selectedOptionId: optionId),
    );
    state = state.copyWith(
      savedWeeklyReports: _weeklyReportRepository.listReports(),
      weeklyReportSaveStatusMessage: '已保存你选择的下周方向。',
    );
  }

  void _syncGrowthForTrainingLog(
    TrainingLog log, {
    required WorkoutDay workout,
  }) {
    PainLog? painLog;
    for (final PainLog item in state.painLogs) {
      if (_isSameDate(item.date, log.date)) {
        painLog = item;
        break;
      }
    }
    unawaited(
      ref.read(growthEvidenceControllerProvider.notifier).syncTrainingLog(
            profile: state.profile,
            log: log,
            workout: workout,
            painLog: painLog,
          ),
    );
  }

  List<TrainingLog> _saveWorkoutPlayerLog({
    required String event,
    required bool completed,
    required int rpe,
  }) {
    final DateTime now = DateTime.now();
    final TrainingLog log = TrainingLog(
      id: 'player-log-${now.millisecondsSinceEpoch}',
      workoutDayId: state.activeWorkoutPlayerWorkout.id,
      planItemId: state.scheduledTodayWorkout?.workoutDayId ==
              state.activeWorkoutPlayerWorkout.id
          ? state.scheduledTodayWorkout?.id
          : null,
      date: now,
      completed: completed,
      rpe: rpe,
      fatigueLevel: rpe.clamp(1, 10),
      sleepQuality: 7,
      painNote: state.latestPainLog == null
          ? null
          : '${state.latestPainLog!.bodyPart} ${state.latestPainLog!.painLevel}/10',
      userNote: '[跟练执行] $event',
      createdAt: now,
      kind: TrainingLogKind.playerStep,
    );
    return ref.read(trainingLogControllerProvider.notifier).save(log);
  }
}

double _average(Iterable<double> values) {
  if (values.isEmpty) {
    return 0;
  }
  double total = 0;
  int count = 0;
  for (final double value in values) {
    total += value;
    count += 1;
  }
  return total / count;
}

String _csvCell(String value) {
  final bool needsQuote =
      value.contains(',') || value.contains('"') || value.contains('\n');
  if (!needsQuote) {
    return value;
  }
  return '"${value.replaceAll('"', '""')}"';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final double kilobytes = bytes / 1024;
  final int digits = kilobytes >= 10 ? 0 : 1;
  return '${kilobytes.toStringAsFixed(digits)} KB';
}

List<TrainingPlan> _applyPlanAdjustments(
  List<TrainingPlan> plans,
  List<PlanAdjustment> adjustments,
) {
  final Map<String, PlanAdjustment> latestAdjustments =
      <String, PlanAdjustment>{};
  for (final PlanAdjustment adjustment in adjustments) {
    latestAdjustments.putIfAbsent(adjustment.workoutDayId, () => adjustment);
  }
  return plans.map((TrainingPlan plan) {
    return plan.copyWith(
      workoutDays: plan.workoutDays.map((WorkoutDay workout) {
        final PlanAdjustment? adjustment = latestAdjustments[workout.id];
        if (adjustment == null || !adjustment.isActive) {
          return workout;
        }
        return workout.copyWith(
          estimatedMinutes: adjustment.adjustedEstimatedMinutes,
          intensity: adjustment.adjustedIntensity,
        );
      }).toList(),
    );
  }).toList();
}

String _formatCountdownSeconds(int seconds) {
  final int safeSeconds = seconds < 0 ? 0 : seconds;
  final int minutes = safeSeconds ~/ 60;
  final int remainingSeconds = safeSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
}

DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

bool _isSameDate(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

double _intensityFactor(WorkoutDay workout) {
  if (workout.decisionType == TrainingDecisionType.rest) {
    return 0.1;
  }
  if (workout.decisionType == TrainingDecisionType.recovery) {
    return 0.35;
  }
  if (workout.decisionType == TrainingDecisionType.deload) {
    return 0.55;
  }
  switch (workout.trainingType) {
    case TrainingType.intervalRun:
    case TrainingType.tempoRun:
    case TrainingType.hyrox:
      return 1.15;
    case TrainingType.strength:
      return 0.95;
    case TrainingType.longRun:
      return 0.9;
    case TrainingType.easyRun:
    case TrainingType.crossTraining:
      return 0.75;
    case TrainingType.mobility:
    case TrainingType.rehab:
      return 0.35;
    case TrainingType.rest:
      return 0.1;
  }
}

int _rpeForTrainingEffect(TrainingEffectLabel effect) {
  switch (effect) {
    case TrainingEffectLabel.recovery:
      return 3;
    case TrainingEffectLabel.aerobic:
      return 6;
    case TrainingEffectLabel.anaerobic:
      return 8;
  }
}

const String sampleGpxImportText = '''
<gpx version="1.1" creator="TrainFlow AI">
  <trk>
    <name>晨跑样例</name>
    <trkseg>
      <trkpt lat="31.2304" lon="121.4737">
        <ele>8</ele>
        <time>2026-07-09T06:30:00Z</time>
        <extensions><gpxtpx:hr>128</gpxtpx:hr></extensions>
      </trkpt>
      <trkpt lat="31.2354" lon="121.4837">
        <ele>16</ele>
        <time>2026-07-09T06:42:00Z</time>
        <extensions><gpxtpx:hr>142</gpxtpx:hr></extensions>
      </trkpt>
      <trkpt lat="31.2404" lon="121.4937">
        <ele>23</ele>
        <time>2026-07-09T06:56:00Z</time>
        <extensions><gpxtpx:hr>148</gpxtpx:hr></extensions>
      </trkpt>
    </trkseg>
  </trk>
</gpx>
''';

const String sampleFitSummaryImportText = '''
title=手表 FIT 摘要样例
started_at=2026-07-09T07:10:00
distance_km=5.20
duration_minutes=32
elevation_gain_m=46
avg_hr=146
''';

const String sampleRaceImportText = '''
赛事：杭州半程马拉松备赛
类型：路跑
日期：2026-11-08
目标：半马 2:05 内稳定完赛
赛道：城市路跑，后半程需要控制配速漂移。
''';

const String sampleBodyMetricCsvImportText = '''
measured_at,weight_kg,body_fat_percentage,resting_heart_rate,hrv_ms,sleep_hours,fatigue_level,soreness_level
2026-07-06,74.2,18.8,60,48,6.8,5,4
2026-07-07,74.0,18.7,59,50,7.0,4,3
2026-07-08,73.7,18.6,58,52,7.3,3,3
''';

const String sampleBodyMetricSnapshotText = '''
体脂秤截图 2026-07-09
体重 73.6 kg
体脂率 18.5 %
静息心率 57 bpm
HRV 54 ms
睡眠 7.2 h
疲劳 3
酸痛 3
''';

const String sampleKnowledgeImportText = '''
书名：Atomic Habits 训练习惯摘录
作者：James Clear
版本：本地笔记
领域：习惯,恢复
摘要：用于解释为什么训练计划要降低启动摩擦。
章节：环境设计
页码：p. 72-79
引文：让好习惯显而易见、容易执行，坏习惯难以发生。
适用：用于 30 天渐进引导和漏练补救，先降低行动门槛再追求强度。
''';
