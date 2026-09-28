import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/data/seed/seed_exercises.dart';
import 'package:trainflow_ai/services/four_week_plan_generator.dart';
import 'package:trainflow_ai/services/training_rule_audit_service.dart';
import 'package:trainflow_ai/services/training_prescription_safety_audit_service.dart';
import 'package:trainflow_ai/services/resource_workout_binding_service.dart';

void main() {
  test('四项运动只缩短第四周时长，保留前三周和强度且通过完整审核', () {
    for (final sport in [
      MainSport.marathon,
      MainSport.trailRunning,
      MainSport.strength,
      MainSport.hyrox
    ]) {
      final profile = InMemoryUserProfileRepository.defaultProfile.copyWith(
          mainSports: [sport],
          injuryHistory: [],
          weeklyTrainingDays: 3,
          dailyAvailableMinutes: 60,
          equipmentAccessType: EquipmentAccessType.gym,
          trainingExperienceLevel: TrainingExperienceLevel.intermediate);
      final generator = FourWeekPlanGenerator();
      final old = generator
          .generate(profile: profile, startsOn: DateTime(2026, 9, 7))
          .plan;
      final bound = generator
          .generate(
              profile: profile,
              startsOn: DateTime(2026, 9, 7),
              bindResourceExercises: true)
          .plan;
      final media = TrainingRuleAuditService()
          .buildReport(bound, exercises: seedExercises, availableMinutes: 60)
          .items
          .singleWhere((item) => item.title == '动作媒体关联');
      expect(media.description, isNot(contains('缺少')), reason: sport.name);
      expect(TrainingRuleAuditService().buildReport(bound, exercises: seedExercises,
          availableMinutes: 60).items.where((i) => i.severity.name == 'fail').map((i) => i.description), isEmpty, reason: sport.name);
      expect(const ResourceWorkoutBindingService().issues(bound, profile),
          isEmpty);
      for (var i = 0; i < old.workoutDays.length; i++) {
        expect(
            bound.workoutDays[i].estimatedMinutes,
            old.workoutDays[i].weekIndex == 4
                ? lessThan(old.workoutDays[i].estimatedMinutes)
                : old.workoutDays[i].estimatedMinutes);
        expect(bound.workoutDays[i].mainSets, old.workoutDays[i].mainSets);
        expect(bound.workoutDays[i].intensity, old.workoutDays[i].intensity);
      }
      final audit = TrainingPrescriptionSafetyAuditService();
      expect(audit.auditCompiledPlan(plan: old, profile: profile).failures,
          contains('第 4 周训练量必须位于峰值周的 40%–60%。'));
      expect(audit.auditCompiledPlan(plan: bound, profile: profile).failures,
          isEmpty);
      int minutes(int week) => bound.workoutDays
          .where((d) => d.weekIndex == week)
          .fold(0, (sum, day) => sum + day.estimatedMinutes);
      final peak =
          [minutes(1), minutes(2), minutes(3)].reduce((a, b) => a > b ? a : b);
      expect(minutes(4) / peak, inInclusiveRange(0.4, 0.6));
    }
  });
  test('上肢推拉不能复用下肢主动作，缺少器械继续阻断', () {
    final profile = InMemoryUserProfileRepository.defaultProfile.copyWith(
        mainSports: [MainSport.strength],
        weeklyTrainingDays: 3,
        dailyAvailableMinutes: 60,
        equipmentAccessType: EquipmentAccessType.gym);
    final plan = FourWeekPlanGenerator()
        .generate(
            profile: profile,
            startsOn: DateTime(2026, 9, 7),
            bindResourceExercises: true)
        .plan;
    final upper = plan.workoutDays.firstWhere((d) => d.title.contains('上肢推拉'));
    expect(
        upper.workoutExercises
            .where((l) => l.module == WorkoutExerciseModule.mainTraining)
            .map((l) => l.exerciseId),
        [
          'exercise-incline-push-up',
          'exercise-seated-cable-row',
          'exercise-scapular-push-up'
        ]);
    expect(
        const ResourceWorkoutBindingService().issues(plan,
            profile.copyWith(equipmentAccessType: EquipmentAccessType.none)),
        isNotEmpty);
  });
}
