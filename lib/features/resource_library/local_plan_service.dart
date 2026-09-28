import '../../services/four_week_plan_generator.dart';
import '../../services/resource_workout_binding_service.dart';
import '../../data/models/generated_training_plan.dart';
import '../../data/models/plan_generation_context_snapshot.dart';
import '../../data/models/race.dart';
import '../../data/models/user_profile.dart';
import '../../data/models/training_rule_audit.dart';
import '../../data/seed/seed_exercises.dart';
import '../../plugins/core/plugin_ref.dart';
import '../../plugins/sports/sport_capability_directory.dart';
import '../../services/plan_context_digest_service.dart';
import '../../services/training_rule_audit_service.dart';
import '../../services/training_prescription_safety_audit_service.dart';
import 'local_plan_draft.dart';
import 'resource_catalog.dart';
import 'resource_plan_preview.dart';

class LocalPlanService {
  static const compilerVersion = 'resource-local-v3';
  static DateTime monday(DateTime now) => DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - 1));
  RacePlan? selectRace(List<RacePlan> races, UserProfile profile, DateTime now,
      SportCapabilityDirectory sports) {
    final selected = races
        .where((r) =>
            !DateTime(r.raceDate.year, r.raceDate.month, r.raceDate.day)
                .isBefore(DateTime(now.year, now.month, now.day)) &&
            profile.mainSports
                .any((s) => sports.find(s)?.matchesRace(r.type) ?? false))
        .toList()
      ..sort((a, b) => a.raceDate.compareTo(b.raceDate));
    return selected.isEmpty ? null : selected.first;
  }

  String fingerprint(
          {required UserProfile profile,
          required DateTime startsOn,
          required RacePlan? race,
          required String? baseVersionId,
          required TrainingPlanResource resource,
          required List<PluginRef> refs}) =>
      const PlanContextDigestService().buildCanonicalDigest({
        'profile': profile.toJson(),
        'startsOn': startsOn.toIso8601String(),
        'race': race?.toJson(),
        'baseVersionId': baseVersionId,
        'resource': resource.ref.toJson(),
        'plugins': refs.map((r) => r.toJson()).toList(),
        'compiler': compilerVersion
      });
  LocalPlanDraft create(
      {required String id,
      required DateTime now,
      required UserProfile profile,
      required TrainingPlanResource resource,
      required SportCapabilityDirectory sports,
      required String? baseVersionId,
      required ResourcePlanPreview preview,
      RacePlan? race,
      required List<PluginRef> Function(List<PluginRef>) decorate}) {
    final startsOn = monday(now);
    final generation = preview.generate(
        resource: resource,
        profile: profile,
        startsOn: startsOn,
        sports: sports,
        race: race);
    final refs = decorate(generation.pluginRefs);
    final rule = TrainingRuleAuditService().buildReport(generation.plan,
        exercises: seedExercises,
        availableMinutes: profile.dailyAvailableMinutes);
    final safety = TrainingPrescriptionSafetyAuditService().auditCompiledPlan(
        plan: generation.plan,
        profile: profile,
        enforceFourWeekDeload: race == null,
        racePhaseOverride: race != null);
    final failures = [
      ...const ResourceWorkoutBindingService().issues(generation.plan, profile),
      for (final item in rule.items)
        if (item.severity == TrainingRuleAuditSeverity.fail) item.description,
      ...safety.failures
    ];
    return LocalPlanDraft(
        id: id,
        plan: generation.plan,
        createdAt: now,
        weekPhases: generation.weeks.map((w) => w.phase.jsonValue).toList(),
        resourceRef: resource.ref,
        pluginRefs: refs,
        baseVersionId: baseVersionId,
        contextFingerprint: fingerprint(
            profile: profile,
            startsOn: startsOn,
            race: race,
            baseVersionId: baseVersionId,
            resource: resource,
            refs: refs),
        businessFingerprint: const PlanContextDigestService()
            .buildLocalFingerprint(
                profile: profile, startsOn: startsOn, race: race),
        auditSummary: PlanAuditSummary(
            passCount: rule.passCount + (safety.canActivate ? 1 : 0),
            warningCount: rule.warningCount + safety.warnings.length,
            failCount: failures.length,
            blockingReasons: failures),
        warnings: [
          for (final item in rule.items)
            if (item.severity == TrainingRuleAuditSeverity.warning)
              item.description,
          ...safety.warnings
        ],
        contextSnapshot: PlanGenerationContextSnapshot(
            weeklyTrainingDays: profile.weeklyTrainingDays,
            availableMinutes: profile.dailyAvailableMinutes,
            equipmentCodes: switch (profile.equipmentAccessType) {
              EquipmentAccessType.none => ['bodyweight'],
              EquipmentAccessType.basicHome => ['bodyweight', 'dumbbell'],
              _ => [
                  'bodyweight',
                  'dumbbell',
                  'barbell',
                  'kettlebell',
                  'machines',
                  'cardio_machines'
                ]
            },
            raceTypeCode: race?.type.jsonValue,
            raceDate: race?.raceDate,
            racePhaseCode: race?.currentPhase));
  }
}
