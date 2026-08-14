import 'race.dart';
import 'training_log.dart';
import 'training_schedule.dart';
import 'weekly_report.dart';
import 'generated_training_plan.dart';
import 'plan_generation_context_snapshot.dart';

class PlanRevisionTriggerSnapshot {
  final int completedSessions;
  final int missedSessions;
  final int changedScheduleDays;
  final bool equipmentChanged;
  final bool remainingCycleConflict;
  final List<DateTime> changedScheduleDates;
  final List<String> reasonCodes;
  final List<String> safetyConstraintCodes;
  final String completionRateBand;
  final String loadTrendCode;
  final String recoveryRiskCode;
  final String? selectedDirectionCode;
  final bool localSafetyOnly;

  const PlanRevisionTriggerSnapshot({
    required this.completedSessions,
    required this.missedSessions,
    required this.changedScheduleDays,
    required this.equipmentChanged,
    required this.remainingCycleConflict,
    required this.changedScheduleDates,
    required this.reasonCodes,
    required this.safetyConstraintCodes,
    required this.completionRateBand,
    required this.loadTrendCode,
    required this.recoveryRiskCode,
    required this.selectedDirectionCode,
    required this.localSafetyOnly,
  });

  bool get shouldSuggest =>
      localSafetyOnly ||
      missedSessions >= 2 ||
      changedScheduleDays >= 2 ||
      equipmentChanged ||
      remainingCycleConflict;

  String get dedupeKey => <Object?>[
        completedSessions,
        missedSessions,
        changedScheduleDays,
        equipmentChanged,
        remainingCycleConflict,
        reasonCodes.join(','),
        recoveryRiskCode,
        selectedDirectionCode,
      ].join('|');
}

class PlanRevisionTriggerService {
  const PlanRevisionTriggerService();

  PlanRevisionTriggerSnapshot evaluate({
    required GeneratedPlanVersion activeVersion,
    required List<ScheduledWorkout> schedule,
    required List<TrainingLog> logs,
    required List<String> currentEquipmentCodes,
    required RacePlan? currentRace,
    required WeeklyReport? latestWeeklyReport,
    required DateTime now,
  }) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime cycleStart = _latestDate(
      DateTime(
        activeVersion.activatedAt.year,
        activeVersion.activatedAt.month,
        activeVersion.activatedAt.day,
      ),
      DateTime(
        activeVersion.plan.createdAt.year,
        activeVersion.plan.createdAt.month,
        activeVersion.plan.createdAt.day,
      ),
    );
    final Set<String> planWorkoutIds = activeVersion.plan.workoutDays
        .map((item) => item.id)
        .where((String id) => id.isNotEmpty)
        .toSet();
    final List<TrainingLog> cycleLogs = logs
        .where(
          (TrainingLog item) =>
              !item.date.isBefore(cycleStart) &&
              !item.date.isAfter(now) &&
              planWorkoutIds.contains(item.workoutDayId),
        )
        .toList(growable: false);
    final Set<String> completedWorkoutIds = cycleLogs
        .where((TrainingLog item) => item.completed)
        .map((TrainingLog item) => item.workoutDayId)
        .toSet();
    final List<ScheduledWorkout> cycleSchedule = schedule
        .where(
          (ScheduledWorkout item) =>
              !item.scheduledDate.isBefore(cycleStart) &&
              planWorkoutIds.contains(item.workoutDayId),
        )
        .toList(growable: false);
    final int missedSessions = cycleSchedule
        .where(
          (ScheduledWorkout item) =>
              item.scheduledDate.isBefore(today) &&
              !completedWorkoutIds.contains(item.workoutDayId),
        )
        .length;
    final List<ScheduledWorkout> nextWeek = cycleSchedule
        .where(
          (ScheduledWorkout item) =>
              !item.scheduledDate.isBefore(today) &&
              item.scheduledDate.isBefore(today.add(const Duration(days: 7))),
        )
        .toList(growable: false);
    final int expectedDays =
        activeVersion.generationContextSnapshot?.weeklyTrainingDays ??
            activeVersion.plan.workoutDays.length.clamp(0, 7);
    final int actualDays = nextWeek
        .map((ScheduledWorkout item) => _dateOnly(item.scheduledDate))
        .toSet()
        .length;
    final int changedScheduleDays = (expectedDays - actualDays).abs();
    final List<DateTime> changedDates = nextWeek
        .map((ScheduledWorkout item) => item.scheduledDate)
        .take(changedScheduleDays.clamp(0, 14))
        .toList(growable: false);
    final PlanGenerationContextSnapshot? context =
        activeVersion.generationContextSnapshot;
    final bool equipmentChanged = context != null &&
        !_sameStringSet(context.equipmentCodes, currentEquipmentCodes);
    final bool raceConflict = context != null &&
        (context.raceTypeCode != currentRace?.type.jsonValue ||
            !_sameDateOrNull(context.raceDate, currentRace?.raceDate));
    final bool painRedLine = cycleLogs.any(
      (TrainingLog item) => (item.painNote?.trim().isNotEmpty ?? false),
    );
    final String recoveryRiskCode =
        latestWeeklyReport?.psychRiskLevel.jsonValue ?? 'normal';
    final String? directionCode = _directionCode(
      latestWeeklyReport?.selectedOptionId,
    );
    final bool localSafetyOnly = painRedLine ||
        recoveryRiskCode == 'protect' ||
        directionCode == 'protect_pause' ||
        directionCode == 'protect_review';
    final List<String> reasons = <String>[
      if (missedSessions >= 2) 'consecutive_missed',
      if (changedScheduleDays >= 2) 'schedule_changed',
      if (equipmentChanged) 'equipment_changed',
      if (raceConflict) 'remaining_cycle_conflict',
      if (painRedLine) 'pain_red_line',
      if (recoveryRiskCode == 'protect') 'protective_weekly_report',
    ];
    return PlanRevisionTriggerSnapshot(
      completedSessions: completedWorkoutIds.length,
      missedSessions: missedSessions,
      changedScheduleDays: changedScheduleDays,
      equipmentChanged: equipmentChanged,
      remainingCycleConflict: raceConflict,
      changedScheduleDates: changedDates,
      reasonCodes: List<String>.unmodifiable(reasons),
      safetyConstraintCodes: <String>[
        'keep_recovery_spacing',
        if (missedSessions >= 2 || raceConflict) 'no_increase',
        if (recoveryRiskCode == 'advise') 'limit_duration',
      ],
      completionRateBand: _completionRateBand(latestWeeklyReport),
      loadTrendCode: _loadTrendCode(latestWeeklyReport?.loadTrendLabel),
      recoveryRiskCode: recoveryRiskCode,
      selectedDirectionCode: directionCode,
      localSafetyOnly: localSafetyOnly,
    );
  }
}

String _completionRateBand(WeeklyReport? report) {
  if (report == null) return 'unknown';
  if (report.completionRate < 0.5) return 'low';
  if (report.completionRate < 0.8) return 'medium';
  return 'high';
}

String _loadTrendCode(String? value) {
  if (value == null || value.trim().isEmpty) return 'unknown';
  if (value.contains('上升') || value.contains('偏高')) return 'rising';
  if (value.contains('下降') || value.contains('降低')) return 'falling';
  return 'stable';
}

String? _directionCode(String? value) => switch (value) {
      'keep_schedule' ||
      'keep_one_focus' ||
      'recovery_first' ||
      'reduce_one_session' ||
      'protect_pause' ||
      'protect_review' =>
        value,
      _ => null,
    };

bool _sameStringSet(List<String> first, List<String> second) =>
    first.toSet().length == second.toSet().length &&
    first.toSet().containsAll(second);

bool _sameDateOrNull(DateTime? first, DateTime? second) {
  if (first == null || second == null) return first == second;
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

DateTime _latestDate(DateTime first, DateTime second) =>
    first.isAfter(second) ? first : second;

String _dateOnly(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
