import 'package:trainflow_ai/features/companion/domain/companion_models.dart';

/// 关系状态只从上下文推导，不写回训练、健康、计划或宠物表。
RelationshipState resolveState(CompanionContext context) {
  if (context.isInjured) return RelationshipState.injured;
  if (context.wasAwayYesterday && context.hasSignalToday) {
    return RelationshipState.returning;
  }
  if (context.daysSinceLastActivity >= 7) return RelationshipState.lapsed;
  if (context.daysSinceLastActivity >= 3) return RelationshipState.dormant;
  final int? daysToRace = context.daysToRace;
  if (daysToRace != null && daysToRace >= 0 && daysToRace <= 21) {
    return RelationshipState.peaking;
  }
  if (context.relationshipDays <= 3) return RelationshipState.onboarding;
  if (context.missedInLast7Days >= 2 && context.daysSinceLastActivity <= 2) {
    return RelationshipState.slipping;
  }
  if (context.currentStreak >= 7) return RelationshipState.streak;
  return RelationshipState.steady;
}
