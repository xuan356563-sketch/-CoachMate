import '../data/models/training_plan.dart';
import '../data/models/training_metrics.dart';
import '../data/models/training_schedule.dart';
import '../data/models/workout_day.dart';

class TrainingScheduleService {
  List<ScheduledWorkout> build({
    required TrainingPlan plan,
    required List<TrainingAvailabilitySlot> availability,
    required int weeklyTrainingDays,
    required DateTime now,
  }) {
    final DateTime start = _mondayOf(now);
    final int durationWeeks = plan.durationWeeks.clamp(1, 52).toInt();
    final DateTime end = start.add(Duration(days: durationWeeks * 7));
    final List<TrainingAvailabilitySlot> slots = availability
        .where((TrainingAvailabilitySlot item) =>
            !item.date.isBefore(start) && item.date.isBefore(end))
        .toList()
      ..sort((a, b) {
        final int dateOrder = a.date.compareTo(b.date);
        return dateOrder == 0
            ? a.startMinute.compareTo(b.startMinute)
            : dateOrder;
      });
    final List<WorkoutDay> allTemplates = plan.workoutDays
        .where(
            (WorkoutDay item) => item.decisionType != TrainingDecisionType.rest)
        .toList();
    if (allTemplates.isEmpty) {
      return const <ScheduledWorkout>[];
    }

    final List<ScheduledWorkout> result = <ScheduledWorkout>[];
    for (int week = 0; week < durationWeeks; week += 1) {
      final DateTime weekStart = start.add(Duration(days: week * 7));
      final List<WorkoutDay> weekTemplates = allTemplates
          .where((WorkoutDay item) => item.weekIndex == week + 1)
          .take(weeklyTrainingDays.clamp(1, 7))
          .toList();
      final List<WorkoutDay> templates = weekTemplates.isEmpty
          ? allTemplates
              .where((WorkoutDay item) => item.weekIndex == 1)
              .take(weeklyTrainingDays.clamp(1, 7))
              .toList()
          : weekTemplates;
      if (templates.isEmpty) {
        continue;
      }
      final List<TrainingAvailabilitySlot> weekSlots = slots
          .where((item) =>
              !item.date.isBefore(weekStart) &&
              item.date.isBefore(weekStart.add(const Duration(days: 7))))
          .toList();
      final Set<String> usedDates = <String>{};
      for (int index = 0; index < templates.length; index += 1) {
        final WorkoutDay workout = templates[index];
        final TrainingAvailabilitySlot? slot = _selectSlot(
          workout: workout,
          slots: weekSlots,
          usedDates: usedDates,
          previous: result.isEmpty ? null : result.last,
        );
        if (slot == null) {
          continue;
        }
        usedDates.add(_dateKey(slot.date));
        final ScheduledWorkoutVersion version = _versionFor(workout, slot);
        final int allocated = version == ScheduledWorkoutVersion.full
            ? workout.estimatedMinutes
            : slot.durationMinutes.clamp(15, workout.estimatedMinutes).toInt();
        result.add(ScheduledWorkout(
          id: 'schedule-${weekStart.millisecondsSinceEpoch}-${workout.id}',
          workoutDayId: workout.id,
          scheduledDate: slot.date,
          startMinute: slot.startMinute,
          allocatedMinutes: allocated,
          period: slot.period,
          version: version,
          discipline: _disciplineFor(workout.trainingType),
          primaryTargetKind: CompletionTargetKind.duration,
          targetMinutes: allocated,
        ));
      }
    }
    return result;
  }

  TrainingAvailabilitySlot? _selectSlot({
    required WorkoutDay workout,
    required List<TrainingAvailabilitySlot> slots,
    required Set<String> usedDates,
    required ScheduledWorkout? previous,
  }) {
    final List<TrainingAvailabilitySlot> candidates = slots.where((slot) {
      if (slot.durationMinutes < 15 ||
          usedDates.contains(_dateKey(slot.date))) {
        return false;
      }
      if (_isHard(workout) && slot.period == TrainingTimePeriod.lateNight) {
        return false;
      }
      if (_isHard(workout) &&
          previous != null &&
          slot.date.difference(previous.scheduledDate).inDays < 2) {
        return false;
      }
      return true;
    }).toList();
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort((a, b) {
      final int aFit = a.durationMinutes >= workout.estimatedMinutes ? 0 : 1;
      final int bFit = b.durationMinutes >= workout.estimatedMinutes ? 0 : 1;
      if (aFit != bFit) return aFit.compareTo(bFit);
      return a.date.compareTo(b.date);
    });
    return candidates.first;
  }

  ScheduledWorkoutVersion _versionFor(
    WorkoutDay workout,
    TrainingAvailabilitySlot slot,
  ) {
    if (slot.period == TrainingTimePeriod.lateNight) {
      return ScheduledWorkoutVersion.recovery;
    }
    if (slot.durationMinutes >= workout.estimatedMinutes &&
        slot.period != TrainingTimePeriod.midday) {
      return ScheduledWorkoutVersion.full;
    }
    if (slot.durationMinutes >= 25) {
      return ScheduledWorkoutVersion.compact;
    }
    return ScheduledWorkoutVersion.recovery;
  }

  bool _isHard(WorkoutDay workout) =>
      workout.decisionType == TrainingDecisionType.normal &&
      (workout.intensity.contains('7') ||
          workout.intensity.contains('8') ||
          workout.trainingType == TrainingType.hyrox);

  WorkoutDiscipline _disciplineFor(TrainingType type) {
    return switch (type) {
      TrainingType.easyRun ||
      TrainingType.tempoRun ||
      TrainingType.intervalRun ||
      TrainingType.longRun =>
        WorkoutDiscipline.roadRun,
      TrainingType.strength => WorkoutDiscipline.strength,
      TrainingType.hyrox => WorkoutDiscipline.hyrox,
      TrainingType.mobility ||
      TrainingType.rehab ||
      TrainingType.rest ||
      TrainingType.crossTraining =>
        WorkoutDiscipline.other,
    };
  }

  DateTime _mondayOf(DateTime value) {
    final DateTime date = DateTime(value.year, value.month, value.day);
    return date.subtract(Duration(days: date.weekday - DateTime.monday));
  }

  String _dateKey(DateTime value) =>
      '${value.year}-${value.month}-${value.day}';
}
