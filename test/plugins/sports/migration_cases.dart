import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/models/race.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/data/models/plan_generation_preferences.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';

/// 固定合成输入；黄金摘要来自迁移前备份，不能随实现更新。
Iterable<
    ({
      String id,
      UserProfile profile,
      RacePlan? race,
      PlanGenerationPreferences? preferences
    })> migrationCases() sync* {
  for (final sport in MainSport.values) {
    for (final equipment in EquipmentAccessType.values) {
      for (final ai in [false, true]) {
        final profile = InMemoryUserProfileRepository.defaultProfile.copyWith(
          mainSports: [
            sport,
            sport == MainSport.strength
                ? MainSport.marathon
                : MainSport.strength
          ],
          weeklyTrainingDays: 4,
          dailyAvailableMinutes: 60,
          trainingGoal: '合成迁移验证',
          equipmentAccessType: equipment,
          trainingExperienceLevel: TrainingExperienceLevel.intermediate,
        );
        yield (
          id: '${sport.name}-${equipment.name}-${ai ? 'ai' : 'local'}',
          profile: profile,
          race: null,
          preferences: ai ? _preferences(sport) : null
        );
      }
    }
    for (final days in [1, 2, 7]) {
      yield (
        id: '${sport.name}-days-$days',
        profile: InMemoryUserProfileRepository.defaultProfile.copyWith(
            mainSports: [sport, MainSport.marathon], weeklyTrainingDays: days),
        race: null,
        preferences: null
      );
    }
    for (final type in RaceType.values) {
      for (final offset in [-1, 5, 20, 40, 70, 100]) {
        yield (
          id: '${sport.name}-${type.name}-$offset',
          profile: InMemoryUserProfileRepository.defaultProfile
              .copyWith(mainSports: [sport, MainSport.marathon]),
          race: RacePlan.fromJson({
            'id': 'synthetic-race',
            'name': '合成赛事',
            'type': type.jsonValue,
            'raceDate': DateTime(2026, 7, 13)
                .add(Duration(days: offset))
                .toIso8601String()
          }),
          preferences: null
        );
      }
    }
  }
  for (final primary in [MainSport.marathon, MainSport.hyrox]) {
    final secondary =
        primary == MainSport.marathon ? MainSport.hyrox : MainSport.marathon;
    for (final ai in [false, true]) {
      yield (
        id: "${primary.name}-secondary-race-${ai ? 'ai' : 'local'}",
        profile: InMemoryUserProfileRepository.defaultProfile.copyWith(
            mainSports: [primary, secondary],
            weeklyTrainingDays: 1,
            equipmentAccessType: EquipmentAccessType.gym),
        race: RacePlan.fromJson({
          'id': 'synthetic-secondary-race',
          'name': '合成次目标赛事',
          'type': secondary == MainSport.hyrox ? 'hyrox' : 'road_running',
          'raceDate': '2026-07-18T00:00:00.000'
        }),
        preferences: ai ? _preferences(primary) : null,
      );
    }
  }
}

PlanGenerationPreferences _preferences(MainSport sport) =>
    PlanGenerationPreferences(
      generationId: 'synthetic-prescription',
      cycleFocus: 'base',
      progressionMode: PlanProgressionMode.balanced,
      generationMethod: sport == MainSport.strength
          ? PlanGenerationMethod.abcStrengthCycle
          : PlanGenerationMethod.standard,
      weeklySessions: [
        for (final type in [
          TrainingType.strength,
          TrainingType.tempoRun,
          TrainingType.strength,
          TrainingType.mobility
        ])
          PlanSessionPreference(
              trainingType: type,
              durationMinutes: 45,
              intensityBand: type == TrainingType.tempoRun
                  ? PlanIntensityBand.challenging
                  : type == TrainingType.mobility
                      ? PlanIntensityBand.recovery
                      : PlanIntensityBand.moderate,
              focusCodes: const ['movement_quality']),
      ],
    );
