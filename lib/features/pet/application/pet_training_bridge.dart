import '../../../data/models/daily_adjustment.dart';
import '../../../data/models/training_log.dart';
import '../../../data/models/workout_day.dart';

class PetTrainingDayFacts {
  const PetTrainingDayFacts({
    required this.hasValidTraining,
    required this.hasAcceptedRecoveryDecision,
  });

  final bool hasValidTraining;
  final bool hasAcceptedRecoveryDecision;
}

/// 把已有训练与每日调整记录收窄为宠物结算所需的两个只读事实。
class PetTrainingBridge {
  const PetTrainingBridge();

  PetTrainingDayFacts factsForDate({
    required String localDate,
    required Iterable<TrainingLog> trainingLogs,
    required Iterable<AppliedDailyDecisionFact> appliedDecisions,
  }) {
    final bool hasValidTraining = trainingLogs.any(
      (TrainingLog log) =>
          _localDateKey(log.date.toLocal()) == localDate &&
          log.isSessionRecord &&
          !log.abortedByUser &&
          log.normalizedCompletionPercentage >= 50,
    );
    final bool hasAcceptedRecoveryDecision = appliedDecisions.any(
      (AppliedDailyDecisionFact fact) =>
          fact.localDate == localDate && _isRecoveryDecision(fact.decisionType),
    );
    return PetTrainingDayFacts(
      hasValidTraining: hasValidTraining,
      hasAcceptedRecoveryDecision: hasAcceptedRecoveryDecision,
    );
  }
}

bool _isRecoveryDecision(TrainingDecisionType decisionType) {
  return switch (decisionType) {
    TrainingDecisionType.deload ||
    TrainingDecisionType.recovery ||
    TrainingDecisionType.rest =>
      true,
    TrainingDecisionType.normal || TrainingDecisionType.technique => false,
  };
}

String _localDateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
