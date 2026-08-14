import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/body_data_quality.dart';
import 'package:trainflow_ai/data/models/pain_log.dart';
import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/data/models/training_schedule.dart';
import 'package:trainflow_ai/features/companion/application/training_state_reader.dart';
import 'package:trainflow_ai/features/companion/domain/coach_contracts.dart';
import 'package:trainflow_ai/features/profile/application/training_schedule_controller.dart';

void main() {
  final DateTime now = DateTime(2026, 8, 12, 9, 30);

  TrainingScheduleState schedule({bool withToday = true}) {
    return TrainingScheduleState(
      availability: const <TrainingAvailabilitySlot>[],
      workouts: <ScheduledWorkout>[
        if (withToday)
          ScheduledWorkout(
            id: 'scheduled-1',
            workoutDayId: 'day-1',
            scheduledDate: now,
            startMinute: 18 * 60,
            allocatedMinutes: 45,
            period: TrainingTimePeriod.evening,
            version: ScheduledWorkoutVersion.full,
          ),
      ],
      statusMessage: '测试日程',
    );
  }

  TrainingLog completedLog() => TrainingLog(
        id: 'training-log-1',
        workoutDayId: 'day-previous',
        date: now.subtract(const Duration(days: 1)),
        completed: true,
        rpe: 5,
        fatigueLevel: 3,
        sleepQuality: 4,
        painNote: null,
        userNote: '这段自由文本不能进入快照',
        createdAt: now.subtract(const Duration(days: 1)),
        actualDurationMinutes: 40,
      );

  const BodyDataQualityReport quality = BodyDataQualityReport(
    recordCount: 1,
    coveredDays: 1,
    sourceCount: 1,
    qualityScore: 1,
    coverageLabel: '今天',
    sourceLabel: '本机',
    revisionPolicyLabel: '只读',
    issues: <BodyDataQualityIssue>[],
  );

  test('读取器只从结构化状态生成六小时内且不跨日的快照', () {
    final TrainingStateSnapshotV1 snapshot = LocalTrainingStateReader(
      schedule: schedule(),
      trainingLogs: <TrainingLog>[completedLog()],
      painLogs: const <PainLog>[],
      bodyDataQuality: quality,
    ).readCurrent(athleteProfileId: 'athlete-1', now: now);

    expect(snapshot.plannedActionId, 'follow-existing-plan');
    expect(snapshot.plannedDurationMinutes, 45);
    expect(snapshot.completedSessions7d, 1);
    expect(snapshot.sourceRefs, hasLength(2));
    expect(snapshot.validUntil.difference(now),
        lessThanOrEqualTo(const Duration(hours: 6)));
    expect(snapshot.validateAt(now), isEmpty);
    expect(snapshot.toJson().toString(), isNot(contains('这段自由文本')));
  });

  test('疼痛七分由结构化疼痛记录进入红线且不携带备注', () {
    final TrainingStateSnapshotV1 snapshot = LocalTrainingStateReader(
      schedule: schedule(),
      trainingLogs: <TrainingLog>[completedLog()],
      painLogs: <PainLog>[
        PainLog(
          id: 'pain-1',
          bodyPart: '膝盖',
          painLevel: 7,
          timing: PainTiming.ongoing,
          note: '原始健康备注不得进入 Coach 快照',
          date: now,
          createdAt: now,
        ),
      ],
      bodyDataQuality: quality,
    ).readCurrent(athleteProfileId: 'athlete-1', now: now);

    expect(snapshot.severePain, isTrue);
    expect(snapshot.safetyFlags, contains('severe_pain'));
    expect(snapshot.toJson().toString(), isNot(contains('原始健康备注')));
    final TrainingDecisionV1 decision = const CoachKernel().evaluate(
      snapshot: snapshot,
      intent: CoachIntent.todayTraining,
      now: now,
    );
    expect(decision.allowed, isEmpty);
    expect(decision.reasonCodes, contains('pain_redline'));
  });

  test('没有计划与结构化来源时快照明确列出缺失字段', () {
    final TrainingStateSnapshotV1 snapshot = LocalTrainingStateReader(
      schedule: schedule(withToday: false),
      trainingLogs: const <TrainingLog>[],
      painLogs: const <PainLog>[],
      bodyDataQuality: quality,
    ).readCurrent(athleteProfileId: 'athlete-1', now: now);

    expect(
        snapshot.missingFields,
        containsAll(<String>[
          'planned_action',
          'structured_sources',
        ]));
    expect(
      const CoachKernel()
          .evaluate(
            snapshot: snapshot,
            intent: CoachIntent.todayTraining,
            now: now,
          )
          .allowed,
      isEmpty,
    );
  });
}
