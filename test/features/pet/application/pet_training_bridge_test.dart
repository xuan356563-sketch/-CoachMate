import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/daily_adjustment.dart';
import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/features/pet/application/pet_training_bridge.dart';

void main() {
  const PetTrainingBridge bridge = PetTrainingBridge();

  test('只有结算日已确认的减量、恢复或休息决策算恢复事实', () {
    final DateTime confirmedAt = DateTime.utc(2026, 8, 1, 8);

    for (final TrainingDecisionType decisionType in <TrainingDecisionType>[
      TrainingDecisionType.deload,
      TrainingDecisionType.recovery,
      TrainingDecisionType.rest,
    ]) {
      final PetTrainingDayFacts facts = bridge.factsForDate(
        localDate: '2026-08-01',
        trainingLogs: const <TrainingLog>[],
        appliedDecisions: <AppliedDailyDecisionFact>[
          AppliedDailyDecisionFact(
            localDate: '2026-08-01',
            decisionType: decisionType,
            confirmedAt: confirmedAt,
          ),
        ],
      );

      expect(
        facts.hasAcceptedRecoveryDecision,
        isTrue,
        reason: '$decisionType 应计为已确认恢复事实',
      );
    }

    for (final TrainingDecisionType decisionType in <TrainingDecisionType>[
      TrainingDecisionType.normal,
      TrainingDecisionType.technique,
    ]) {
      final PetTrainingDayFacts facts = bridge.factsForDate(
        localDate: '2026-08-01',
        trainingLogs: const <TrainingLog>[],
        appliedDecisions: <AppliedDailyDecisionFact>[
          AppliedDailyDecisionFact(
            localDate: '2026-08-01',
            decisionType: decisionType,
            confirmedAt: confirmedAt,
          ),
        ],
      );

      expect(
        facts.hasAcceptedRecoveryDecision,
        isFalse,
        reason: '$decisionType 不应计为恢复事实',
      );
    }

    final PetTrainingDayFacts differentDay = bridge.factsForDate(
      localDate: '2026-08-02',
      trainingLogs: const <TrainingLog>[],
      appliedDecisions: <AppliedDailyDecisionFact>[
        AppliedDailyDecisionFact(
          localDate: '2026-08-01',
          decisionType: TrainingDecisionType.recovery,
          confirmedAt: confirmedAt,
        ),
      ],
    );
    expect(differentDay.hasAcceptedRecoveryDecision, isFalse);
  });

  test('有效训练严格排除步骤记录、预览、49% 和用户中止', () {
    final List<TrainingLog> invalidLogs = <TrainingLog>[
      _log(
        id: 'player-step',
        kind: TrainingLogKind.playerStep,
        completionPercentage: 100,
      ),
      _log(
        id: 'preview',
        completed: false,
        completionPercentage: 0,
      ),
      _log(id: 'forty-nine', completionPercentage: 49),
      _log(
        id: 'aborted',
        completionPercentage: 100,
        abortedByUser: true,
      ),
      _log(
        id: 'different-day',
        date: DateTime(2026, 8, 2, 9),
        completionPercentage: 100,
      ),
    ];

    final PetTrainingDayFacts facts = bridge.factsForDate(
      localDate: '2026-08-01',
      trainingLogs: invalidLogs,
      appliedDecisions: const <AppliedDailyDecisionFact>[],
    );

    expect(facts.hasValidTraining, isFalse);
    expect(facts.hasAcceptedRecoveryDecision, isFalse);
  });

  test('同日一条或多条达到 50% 的会话记录都只输出 true', () {
    final PetTrainingDayFacts oneLog = bridge.factsForDate(
      localDate: '2026-08-01',
      trainingLogs: <TrainingLog>[
        _log(id: 'valid-50', completionPercentage: 50),
      ],
      appliedDecisions: const <AppliedDailyDecisionFact>[],
    );
    final PetTrainingDayFacts multipleLogs = bridge.factsForDate(
      localDate: '2026-08-01',
      trainingLogs: <TrainingLog>[
        _log(id: 'valid-50', completionPercentage: 50),
        _log(id: 'valid-100', completionPercentage: 100),
      ],
      appliedDecisions: const <AppliedDailyDecisionFact>[],
    );

    expect(oneLog.hasValidTraining, isTrue);
    expect(multipleLogs.hasValidTraining, isTrue);
  });
}

TrainingLog _log({
  required String id,
  DateTime? date,
  bool completed = true,
  TrainingLogKind kind = TrainingLogKind.sessionReview,
  int completionPercentage = 0,
  bool abortedByUser = false,
}) {
  final DateTime logDate = date ?? DateTime(2026, 8, 1, 9);
  return TrainingLog(
    id: id,
    workoutDayId: 'day-1',
    date: logDate,
    completed: completed,
    rpe: 5,
    fatigueLevel: 3,
    sleepQuality: 4,
    painNote: null,
    userNote: null,
    createdAt: logDate,
    kind: kind,
    completionPercentage: completionPercentage,
    abortedByUser: abortedByUser,
  );
}
