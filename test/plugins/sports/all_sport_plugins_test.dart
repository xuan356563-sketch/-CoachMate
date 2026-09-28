import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/plan_generation_preferences.dart';
import 'package:trainflow_ai/data/models/race.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/plugins/sports/built_in_sport_plugins.dart';
import 'package:trainflow_ai/plugins/sports/sport_capability_directory.dart';
import 'package:trainflow_ai/plugins/sports/sport_plan_strategy.dart';
import 'package:trainflow_ai/plugins/sports/strength_plugin.dart';
import 'migration_cases.dart';

void main() {
  const identities = {
    MainSport.marathon: ('sport.marathon', PluginType.sport, 5, '次目标跑步技术'),
    MainSport.trailRunning: (
      'sport.trail_running',
      PluginType.sport,
      5,
      '次目标跑步技术'
    ),
    MainSport.strength: ('sport.strength', PluginType.sport, 4, '次目标全身力量'),
    MainSport.hyrox: ('sport.hyrox', PluginType.sport, 5, '次目标 HYROX 技术'),
    MainSport.fatLoss: ('goal.fat_loss', PluginType.goal, 4, '次目标基础体能'),
    MainSport.generalFitness: (
      'goal.general_fitness',
      PluginType.goal,
      4,
      '次目标基础体能'
    ),
    MainSport.rehab: ('support.rehab', PluginType.support, 2, '次目标恢复维护'),
  };
  for (final sport in MainSport.values) {
    test('${sport.label}发行入口注册独立策略，不再使用临时适配', () async {
      final registry = PluginRegistry(plugins: builtInSportPlugins());
      expect((await registry.initialize()).isSuccess, isTrue);
      addTearDown(() async {
        await registry.shutdown();
        registry.dispose();
      });
      final directory = SportCapabilityDirectory.fromRegistry(registry);
      final strategy = directory.require(sport);
      final expected = identities[sport]!;
      expect(strategy.definition.pluginRef,
          PluginRef(id: expected.$1, version: '1.0.0'));
      expect(registry.descriptors[expected.$1]!.type, expected.$2);
      expect(strategy.definition.cloudSupported, sport != MainSport.rehab);
      expect(strategy.definition.localSupported, isTrue);
      for (final type in RaceType.values) {
        expect(
            strategy.matchesRace(type),
            switch (sport) {
              MainSport.marathon =>
                type == RaceType.marathon || type == RaceType.roadRunning,
              MainSport.trailRunning => type == RaceType.trailRunning,
              MainSport.hyrox => type == RaceType.hyrox,
              _ => false,
            });
      }
      final input = migrationCases()
          .firstWhere((c) => c.profile.mainSports.first == sport);
      final context = SportPlanContext(
          profile: input.profile,
          startsOn: DateTime(2026, 7, 13),
          race: null,
          preferences: null,
          trainingDays: 4);
      final candidates = strategy.primaryCandidates(
          context, (_) => throw StateError('本地模板不能调用 AI 偏好编译'));
      expect(candidates, hasLength(expected.$3));
      expect(strategy.secondaryCandidate(context).title, expected.$4);
      final display = directory.displayFor(sport)!;
      expect(display.workout.id, '${expected.$1}.workout');
      expect(display.workout.slot, 'workout_player');
      expect(display.weeklyReport.reportId, 'weekly_report');
      expect(display.specialty != null,
          strategy.definition.specialtyDisplaySupported);
      expect(display.specialty != null, sport == MainSport.hyrox);
      for (final contribution in display.contributions) {
        expect(
            registry.contributions.map((c) => c.id), contains(contribution.id));
      }
      expect((await registry.disable(expected.$1)).isSuccess, isTrue);
      final remaining = SportCapabilityDirectory.fromRegistry(registry);
      expect(remaining.find(sport), isNull);
      expect(remaining.displayFor(sport), isNull);
      expect(remaining.strategies, hasLength(6));
      expect(
          registry.contributions
              .where((c) => c.id.startsWith('${expected.$1}.')),
          isEmpty);
      expect((await registry.enable(expected.$1)).isSuccess, isTrue);
      expect(
          SportCapabilityDirectory.fromRegistry(registry)
              .require(sport)
              .definition
              .pluginRef,
          strategy.definition.pluginRef);
    });
  }

  test('只有力量策略按处方和器械请求ABC，共用编译回调保持原上下文', () {
    final input = migrationCases().firstWhere((c) => c.id == 'strength-gym-ai');
    for (final equipment in EquipmentAccessType.values) {
      for (final abc in [false, true]) {
        final original = input.preferences!;
        final preferences = PlanGenerationPreferences(
          generationId: original.generationId,
          cycleFocus: original.cycleFocus,
          progressionMode: original.progressionMode,
          generationMethod: abc
              ? PlanGenerationMethod.abcStrengthCycle
              : PlanGenerationMethod.standard,
          weeklySessions: original.weeklySessions,
        );
        final context = SportPlanContext(
          profile: input.profile.copyWith(equipmentAccessType: equipment),
          startsOn: DateTime(2026, 7, 13),
          race: null,
          preferences: preferences,
          trainingDays: 4,
        );
        var calls = 0;
        const StrengthPlanStrategy().primaryCandidates(context, (request) {
          calls++;
          expect(identical(request.profile, context.profile), isTrue);
          expect(identical(request.preferences, preferences), isTrue);
          expect(request.startsOn, context.startsOn);
          expect(request.trainingDays, context.trainingDays);
          expect(
              request.compileAbcStrengthCycle,
              abc &&
                  (equipment == EquipmentAccessType.gym ||
                      equipment == EquipmentAccessType.mixed));
          return [];
        });
        expect(calls, 1);
        expect(context.compileAbcStrengthCycle, isFalse);
        for (final plugin in builtInSportPlugins()
            .where((p) => p.strategy.definition.sport != MainSport.strength)) {
          var otherCalls = 0;
          plugin.strategy.primaryCandidates(context, (request) {
            otherCalls++;
            expect(request.compileAbcStrengthCycle, isFalse);
            return [];
          });
          expect(otherCalls, 1);
        }
      }
    }
  });
}
