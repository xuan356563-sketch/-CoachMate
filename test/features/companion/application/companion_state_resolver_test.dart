import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/features/companion/application/companion_state_resolver.dart';
import 'package:trainflow_ai/features/companion/domain/companion_models.dart';

void main() {
  CompanionContext context({
    int relationshipDays = 10,
    int daysSinceLastActivity = 0,
    int missedInLast7Days = 0,
    int currentStreak = 0,
    bool wasAwayYesterday = false,
    bool hasSignalToday = false,
    int? daysToRace,
    int? latestPainScore,
    bool hasUnresolvedSeverePain = false,
  }) {
    return CompanionContext(
      relationshipDays: relationshipDays,
      daysSinceLastActivity: daysSinceLastActivity,
      missedInLast7Days: missedInLast7Days,
      currentStreak: currentStreak,
      wasAwayYesterday: wasAwayYesterday,
      hasSignalToday: hasSignalToday,
      daysToRace: daysToRace,
      latestPainScore: latestPainScore,
      hasUnresolvedSeverePain: hasUnresolvedSeverePain,
    );
  }

  group('resolveState', () {
    test('覆盖九种关系状态', () {
      expect(resolveState(context(relationshipDays: 1)),
          RelationshipState.onboarding);
      expect(resolveState(context()), RelationshipState.steady);
      expect(resolveState(context(currentStreak: 7)), RelationshipState.streak);
      expect(
        resolveState(context(missedInLast7Days: 2, daysSinceLastActivity: 2)),
        RelationshipState.slipping,
      );
      expect(resolveState(context(daysSinceLastActivity: 3)),
          RelationshipState.dormant);
      expect(resolveState(context(daysSinceLastActivity: 7)),
          RelationshipState.lapsed);
      expect(
        resolveState(context(wasAwayYesterday: true, hasSignalToday: true)),
        RelationshipState.returning,
      );
      expect(
          resolveState(context(latestPainScore: 4)), RelationshipState.injured);
      expect(resolveState(context(daysToRace: 21)), RelationshipState.peaking);
    });

    test('严格按已确认优先级仲裁', () {
      expect(
        resolveState(context(
          latestPainScore: 7,
          wasAwayYesterday: true,
          hasSignalToday: true,
          daysSinceLastActivity: 8,
          daysToRace: 2,
        )),
        RelationshipState.injured,
      );
      expect(
        resolveState(context(
          wasAwayYesterday: true,
          hasSignalToday: true,
          daysSinceLastActivity: 8,
        )),
        RelationshipState.returning,
      );
      expect(
        resolveState(context(daysSinceLastActivity: 7, daysToRace: 2)),
        RelationshipState.lapsed,
      );
      expect(
        resolveState(context(daysSinceLastActivity: 3, daysToRace: 2)),
        RelationshipState.dormant,
      );
      expect(
        resolveState(context(
          relationshipDays: 2,
          missedInLast7Days: 2,
          currentStreak: 10,
        )),
        RelationshipState.onboarding,
      );
      expect(
        resolveState(context(missedInLast7Days: 2, currentStreak: 10)),
        RelationshipState.slipping,
      );
    });

    test('过期比赛不会进入冲刺状态，未解除的七分疼痛仍为伤病状态', () {
      expect(resolveState(context(daysToRace: -1)), RelationshipState.steady);
      expect(
        resolveState(context(hasUnresolvedSeverePain: true, daysToRace: 1)),
        RelationshipState.injured,
      );
    });
  });
}
