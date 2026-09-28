import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/models/race.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/plugins/sports/sport_capability_directory.dart';
import 'package:trainflow_ai/plugins/sports/sport_plan_strategy.dart';
import 'package:trainflow_ai/plugins/sports/sport_workout_template.dart';
import 'package:trainflow_ai/plugins/sports/marathon_plugin.dart';
import 'package:trainflow_ai/services/four_week_plan_generator.dart';
import 'migration_cases.dart';

void main() {
  test('马拉松通过注册表提供真实候选入口和可撤销跟练周报贡献', () async {
    final spy = _SpyMarathon();
    final registry = PluginRegistry(plugins: [MarathonPlugin(strategy: spy)]);
    await registry.initialize();
    final directory = SportCapabilityDirectory.fromRegistry(registry);
    final input = migrationCases().firstWhere((c) => c.id == 'marathon-gym-ai');
    final generation = FourWeekPlanGenerator(sportDirectory: directory)
        .generate(
            profile: input.profile,
            startsOn: DateTime(2026, 7, 13),
            preferences: input.preferences);
    expect(spy.primaryCalls, 4);
    expect(spy.preferenceCalls, 4);
    expect(generation.pluginRefs,
        [PluginRef(id: 'sport.marathon', version: '1.0.0')]);
    expect(registry.contributions.whereType<CardContribution>(), hasLength(1));
    expect(
        registry.contributions.whereType<ReportContribution>(), hasLength(1));
    await registry.disable('sport.marathon');
    expect(
        SportCapabilityDirectory.fromRegistry(registry)
            .find(MainSport.marathon),
        isNull);
    expect(registry.contributions, isEmpty);
    await registry.shutdown();
    registry.dispose();
  });
  test('只记录实际参与的主次候选，AI不额外调用次目标', () {
    final generator = FourWeekPlanGenerator();
    for (final days in [1, 2, 4]) {
      final profile = InMemoryUserProfileRepository.defaultProfile.copyWith(
          mainSports: [MainSport.marathon, MainSport.strength],
          weeklyTrainingDays: days);
      final result =
          generator.generate(profile: profile, startsOn: DateTime(2026, 7, 13));
      expect(
          result.pluginRefs.map((r) => r.id),
          days == 1
              ? ['sport.marathon']
              : ['sport.marathon', 'sport.strength']);
    }
  });
  test('AI次运动只贡献赛事匹配时仍记录来源，未贡献时不记录', () {
    final input = migrationCases().firstWhere((c) => c.id == 'marathon-gym-ai');
    final profile = input.profile
        .copyWith(mainSports: [MainSport.marathon, MainSport.hyrox]);
    final race = RacePlan.fromJson({
      'id': 'hyrox-secondary',
      'name': '合成次目标赛事',
      'type': 'hyrox',
      'raceDate': '2026-07-18T00:00:00.000'
    });
    final generator = FourWeekPlanGenerator();
    final generation = generator.generate(
        profile: profile,
        startsOn: DateTime(2026, 7, 13),
        preferences: input.preferences,
        race: race);
    expect(generation.appliedRace?.id, race.id);
    expect(generation.weeks.first.phase, TrainingCyclePhase.raceWeek);
    expect(generation.pluginRefs.map((ref) => ref.id),
        ['sport.marathon', 'sport.hyrox']);
    expect(
        generator
            .generate(
                profile: profile,
                startsOn: DateTime(2026, 7, 13),
                preferences: input.preferences)
            .pluginRefs
            .map((ref) => ref.id),
        ['sport.marathon']);
  });
  test('缺失主策略时中文失败，不产生替代运动候选', () {
    final generator =
        FourWeekPlanGenerator(sportDirectory: SportCapabilityDirectory([]));
    expect(
        () => generator.generate(
            profile: InMemoryUserProfileRepository.defaultProfile
                .copyWith(mainSports: [MainSport.marathon]),
            startsOn: DateTime(2026, 7, 13)),
        throwsA(isA<StateError>()
            .having((e) => e.message, '中文提示', contains('策略未启用或不可用'))));
  });
  test('共享模板保持字段和copyWith语义，马拉松保留赛事映射', () {
    const strategy = MarathonPlanStrategy();
    final input = migrationCases().first;
    final context = SportPlanContext(
        profile: input.profile,
        startsOn: DateTime(2026, 7, 13),
        race: null,
        preferences: null,
        trainingDays: 4);
    final template = strategy.primaryCandidates(context, (_) => []).first;
    final copied = template.copyWith(title: '测试标题');
    expect(copied.trainingType, template.trainingType);
    expect(copied.baseMinutes, template.baseMinutes);
    expect(copied.mainSets, template.mainSets);
    expect(copied.recovery, isFalse);
    expect(copied.abcStrengthSession, isNull);
    expect(strategy.matchesRace(RaceType.roadRunning), isTrue);
    expect(strategy.matchesRace(RaceType.trailRunning), isFalse);
  });
  test('拒绝空候选并提供中文故障，避免编译器除零', () {
    final generator = FourWeekPlanGenerator(
        sportDirectory: SportCapabilityDirectory([_EmptyMarathon()]));
    expect(
        () => generator.generate(
            profile: InMemoryUserProfileRepository.defaultProfile
                .copyWith(mainSports: [MainSport.marathon]),
            startsOn: DateTime(2026, 7, 13)),
        throwsA(isA<StateError>()
            .having((e) => e.message, '中文提示', contains('候选课程'))));
  });
}

class _SpyMarathon extends MarathonPlanStrategy {
  int primaryCalls = 0;
  int preferenceCalls = 0;
  @override
  List<SportWorkoutTemplate> primaryCandidates(
      SportPlanContext context, SportPreferenceCompiler compilePreferences) {
    primaryCalls++;
    if (context.preferences != null) preferenceCalls++;
    return super.primaryCandidates(context, compilePreferences);
  }
}

class _EmptyMarathon extends MarathonPlanStrategy {
  @override
  List<SportWorkoutTemplate> primaryCandidates(SportPlanContext context,
          SportPreferenceCompiler compilePreferences) =>
      [];
}
