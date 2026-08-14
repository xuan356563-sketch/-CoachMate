import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/training_schedule.dart';
import 'package:trainflow_ai/data/models/training_metrics.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/services/four_week_plan_generator.dart';
import 'package:trainflow_ai/services/training_schedule_service.dart';

void main() {
  test('四周计划只排四周，并使用每周对应的训练内容', () {
    final DateTime startsOn = DateTime(2026, 7, 13);
    final profile = InMemoryUserProfileRepository.defaultProfile.copyWith(
      mainSports: const <MainSport>[MainSport.hyrox],
      weeklyTrainingDays: 4,
    );
    final plan = FourWeekPlanGenerator()
        .generate(profile: profile, startsOn: startsOn)
        .plan;
    final List<TrainingAvailabilitySlot> availability =
        <TrainingAvailabilitySlot>[
      for (int week = 0; week < 12; week += 1)
        for (final int day in const <int>[0, 1, 3, 5])
          TrainingAvailabilitySlot(
            id: 'slot-$week-$day',
            date: startsOn.add(Duration(days: week * 7 + day)),
            startMinute: 18 * 60,
            endMinute: 19 * 60,
            createdAt: startsOn,
            updatedAt: startsOn,
          ),
    ];

    final List<ScheduledWorkout> schedule = TrainingScheduleService().build(
      plan: plan,
      availability: availability,
      weeklyTrainingDays: 4,
      now: startsOn,
    );

    expect(schedule, hasLength(16));
    expect(
      schedule.map((ScheduledWorkout item) => item.id).toSet(),
      hasLength(16),
    );
    for (int week = 0; week < 4; week += 1) {
      final DateTime weekStart = startsOn.add(Duration(days: week * 7));
      final List<ScheduledWorkout> scheduledWeek = schedule.where((item) {
        return !item.scheduledDate.isBefore(weekStart) &&
            item.scheduledDate.isBefore(weekStart.add(const Duration(days: 7)));
      }).toList();
      expect(scheduledWeek, hasLength(4));
      for (final ScheduledWorkout scheduled in scheduledWeek) {
        final WorkoutDay source = plan.workoutDays.singleWhere(
          (WorkoutDay item) => item.id == scheduled.workoutDayId,
        );
        expect(source.weekIndex, week + 1);
        expect(scheduled.primaryTargetKind, CompletionTargetKind.duration);
        expect(scheduled.targetMinutes, scheduled.allocatedMinutes);
        final WorkoutDiscipline expectedDiscipline =
            switch (source.trainingType) {
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
        expect(scheduled.discipline, expectedDiscipline);
      }
    }
  });

  test('新排期持久化明确的 L1 目标，旧 JSON 不补猜缺失字段', () {
    final ScheduledWorkout legacy = ScheduledWorkout.fromJson(
      <String, dynamic>{
        'id': 'legacy-1',
        'workoutDayId': 'day-1',
        'scheduledDate': '2026-07-15T00:00:00.000',
        'startMinute': 1080,
        'allocatedMinutes': 45,
        'period': 'evening',
        'version': 'full',
      },
    );

    expect(legacy.discipline, isNull);
    expect(legacy.primaryTargetKind, isNull);
    expect(legacy.targetMinutes, isNull);

    final ScheduledWorkout current = ScheduledWorkout.fromJson(
      ScheduledWorkout(
        id: 'schedule-1',
        workoutDayId: 'day-1',
        scheduledDate: DateTime(2026, 7, 15),
        startMinute: 1080,
        allocatedMinutes: 45,
        period: TrainingTimePeriod.evening,
        version: ScheduledWorkoutVersion.full,
        discipline: WorkoutDiscipline.roadRun,
        primaryTargetKind: CompletionTargetKind.duration,
        targetMinutes: 45,
      ).toJson(),
    );
    expect(current.discipline, WorkoutDiscipline.roadRun);
    expect(current.primaryTargetKind, CompletionTargetKind.duration);
    expect(current.targetMinutes, 45);
  });
}
