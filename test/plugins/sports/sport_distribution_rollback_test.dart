import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/generated_training_plan.dart';
import 'package:trainflow_ai/data/models/training_reminder.dart';
import 'package:trainflow_ai/data/repositories/generated_training_plan_repository.dart';
import 'package:trainflow_ai/data/repositories/reminder_settings_repository.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/plugins/sports/built_in_sport_plugins.dart';
import 'package:trainflow_ai/plugins/sports/sport_capability_directory.dart';
import 'package:trainflow_ai/plugins/sports/sport_strategy_plugin.dart';
import 'package:trainflow_ai/services/four_week_plan_generator.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/services/plan_context_digest_service.dart';
import 'migration_cases.dart';

void main() {
  test('正式和同版本注入发行均匹配249个原始黄金', () async {
    final expected = jsonDecode(
        File('test/fixtures/plugins/migration_golden.json')
            .readAsStringSync()) as Map;
    expect(expected, hasLength(249));
    for (final injected in [false, true]) {
      final registry = PluginRegistry(
          plugins: builtInDistribution(
              sportPluginFactory:
                  injected ? _sameVersionInjectedSportPlugins : null));
      expect((await registry.initialize()).isSuccess, isTrue);
      try {
        final directory = SportCapabilityDirectory.fromRegistry(registry);
        expect(directory.strategies, hasLength(7));
        for (final c in migrationCases()) {
          final g = FourWeekPlanGenerator(
                  sportDirectory: directory, structureEnabled: true)
              .generate(
            profile: c.profile,
            startsOn: DateTime(2026, 7, 13),
            race: c.race,
            preferences: c.preferences,
          );
          final digest = const PlanContextDigestService().buildCanonicalDigest({
            'plan': g.plan.toJson(),
            'phases': g.weeks.map((w) => w.phase.jsonValue).toList(),
            'race': g.appliedRace?.id,
          });
          expect(digest, expected[c.id],
              reason: '${injected ? '同版本注入发行' : '正式发行'}：${c.id}');
        }
      } finally {
        await registry.shutdown();
        registry.dispose();
      }
    }
  });

  test('同版本发行切换保留康复复合入口、启停意图、真实设置与旧计划历史', () async {
    final storage = _ObservedStorage();
    final input = migrationCases().firstWhere((c) => c.id == 'rehab-gym-local');
    PersistedUserProfileRepository(storage).saveProfile(input.profile);
    PersistedReminderSettingsRepository(storage).saveSettings(
        const TrainingReminderSettings(
            enabled: false, preferredTimeLabel: '18:15'));
    final generation = FourWeekPlanGenerator()
        .generate(profile: input.profile, startsOn: DateTime(2026, 7, 13));
    final repository = GeneratedTrainingPlanRepository(storage);
    repository.savePlan(generation.plan);
    // 使用无来源历史，证明迁移前记录无需当前策略参与也能原样读取。
    storage.saveJson(GeneratedTrainingPlanRepository.versionsStorageKey, {
      'schemaVersion': 1,
      'activeVersionId': 'old-rehab-version',
      'versions': [
        {
          'id': 'old-rehab-version',
          'plan': generation.plan.toJson(),
          'weekPhases': generation.weeks.map((w) => w.phase.jsonValue).toList(),
          'source': GeneratedPlanSource.legacy.jsonValue,
          'createdAt': '2026-07-13T00:00:00.000',
          'activatedAt': '2026-07-13T00:00:00.000',
          'inputDigest': 'old-context',
          'compilerVersion': 'legacy',
          'auditSummary': <String, dynamic>{},
        }
      ],
      'activationEvents': <Map<String, dynamic>>[],
    });
    final before = {
      for (final key in storage.keys) key: jsonEncode(storage.readJson(key))
    };
    storage.mutations = 0;
    Set<String>? enabled;
    Map<String, PluginRef>? refs;
    for (final injected in [false, true, false]) {
      final runtime = PluginRuntime(PluginRegistry(
          plugins: builtInDistribution(
              sportPluginFactory:
                  injected ? _sameVersionInjectedSportPlugins : null)));
      expect((await runtime.initialize(enabledIds: enabled)).isSuccess, isTrue);
      try {
        final currentRefs = {
          for (final d in runtime.registry.descriptors.values) d.id: d.ref
        };
        if (refs != null) expect(currentRefs, refs);
        refs = currentRefs;
        expect(runtime.service('support.rehab'), isNotNull);
        expect(
            runtime.contributions
                .whereType<RouteContribution>()
                .any((c) => c.path == '/rehab'),
            isTrue);
        expect(runtime.sportDirectory.resolveRefs(generation.pluginRefs),
            generation.pluginRefs);
        expect(repository.getPlan()!.toJson(), generation.plan.toJson());
        expect(repository.getHistory().activeVersion!.plan.toJson(),
            generation.plan.toJson());
        expect(repository.getHistory().activeVersion!.pluginRefs, isNull);
        expect(
            PersistedReminderSettingsRepository(storage)
                .getSettings()
                .preferredTimeLabel,
            '18:15');
        expect(
            PersistedReminderSettingsRepository(storage).getSettings().enabled,
            isFalse);
        expect(PersistedUserProfileRepository(storage).getProfile().mainSports,
            input.profile.mainSports);
        if (enabled == null) {
          await runtime.disable('goal.fat_loss');
          enabled = runtime.registry.enabledIds;
        } else {
          expect(runtime.isEnabled('goal.fat_loss'), isFalse);
          expect(runtime.registry.enabledIds, enabled);
        }
      } finally {
        await runtime.shutdown();
        runtime.dispose();
        runtime.registry.dispose();
      }
      expect(storage.mutations, 0);
      expect({
        for (final key in storage.keys) key: jsonEncode(storage.readJson(key))
      }, before);
    }
  });
}

/// 只验证发行工厂可替换性和稳定身份，不在测试中复制已删除的迁移算法。
List<TrainMatePlugin> _sameVersionInjectedSportPlugins() => [
      for (final plugin in builtInSportPlugins())
        _SameVersionInjectedSportPlugin(plugin.descriptor, plugin.strategy),
    ];

class _SameVersionInjectedSportPlugin extends SportStrategyPlugin {
  _SameVersionInjectedSportPlugin(this.descriptor, super.strategy);

  @override
  final PluginDescriptor descriptor;
}

class _ObservedStorage extends InMemoryLocalStorageService {
  final keys = <String>{};
  int mutations = 0;
  @override
  void saveJson(String key, Map<String, dynamic> value) {
    mutations++;
    keys.add(key);
    super.saveJson(key, value);
  }

  @override
  void remove(String key) {
    mutations++;
    keys.remove(key);
    super.remove(key);
  }

  @override
  void clearBusinessData({Set<String> preservedKeys = const {}}) {
    mutations++;
    super.clearBusinessData(preservedKeys: preservedKeys);
  }
}
