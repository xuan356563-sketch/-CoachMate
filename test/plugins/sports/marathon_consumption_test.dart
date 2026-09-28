import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/models/weekly_psych_check_in.dart';
import 'package:trainflow_ai/data/repositories/generated_training_plan_repository.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/profile/application/user_profile_controller.dart';
import 'package:trainflow_ai/features/training_plan/application/four_week_plan_controller.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/plugins/sports/marathon_plugin.dart';
import 'package:trainflow_ai/plugins/sports/sport_capability_directory.dart';
import 'package:trainflow_ai/plugins/sports/sport_plan_strategy.dart';
import 'package:trainflow_ai/plugins/sports/sport_workout_template.dart';
import 'package:trainflow_ai/services/four_week_plan_generator.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('已注册马拉松的真实课程沿现有跟练桥进入播放器与周报', () async {
    final registry = PluginRegistry(
        plugins: [MarathonPlugin(strategy: _IdentifiableMarathon())]);
    await registry.initialize();
    final directory = SportCapabilityDirectory.fromRegistry(registry);
    final storage = InMemoryLocalStorageService();
    final container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
      fourWeekPlanNowProvider.overrideWithValue(DateTime(2026, 7, 14, 8)),
      sportCapabilityDirectoryProvider.overrideWithValue(directory),
    ]);
    addTearDown(container.dispose);
    addTearDown(() async {
      await registry.shutdown();
      registry.dispose();
    });
    final profile = container
        .read(userProfileControllerProvider)
        .profile
        .copyWith(
            mainSports: [MainSport.marathon],
            weeklyTrainingDays: 4,
            equipmentAccessType: EquipmentAccessType.gym);
    container.read(userProfileControllerProvider.notifier).save(profile);
    final generated =
        FourWeekPlanGenerator(sportDirectory: directory, structureEnabled: true)
            .generate(profile: profile, startsOn: DateTime(2026, 7, 13));
    // 合成计划以既有历史入口保存，验证读消费不会依赖贡献展示装配。
    GeneratedTrainingPlanRepository(storage).savePlan(generated.plan);
    container.invalidate(fourWeekPlanControllerProvider);
    final training = container.read(trainingMvpProvider);
    expect(training.activePlan.toJson(), generated.plan.toJson());
    expect(training.activeWorkoutPlayerWorkout.title, contains('插件桥接验证'));
    expect(training.workoutPlayerSteps, isNotEmpty);
    expect(
        training.activeWorkoutPlayerWorkout.mainSets,
        generated.plan.workoutDays
            .firstWhere((w) => w.id == training.activeWorkoutPlayerWorkout.id)
            .mainSets);
    await container.read(trainingMvpProvider.notifier).savePsychologyWeeklyReport(
        psychCheckIn: const WeeklyPsychCheckIn(
            motivation: 4, perceivedStress: 2, recoveryFeel: 4));
    final report = container.read(trainingMvpProvider).savedWeeklyReports.first;
    final week = generated.plan.workoutDays
        .where((w) => w.weekIndex == training.todayWorkout.weekIndex);
    expect(report.plannedWorkouts, 4);
    for (final exposure in report.dimensionExposure) {
      expect(
          exposure.plannedSessions,
          week
              .where((w) => w.dimensionFocus.all.contains(exposure.dimension))
              .length);
    }
    expect(report.dimensionExposure.any((e) => e.plannedSessions > 0), isTrue);
    await registry.disable('sport.marathon');
    expect(container.read(trainingMvpProvider).activePlan.toJson(),
        generated.plan.toJson());
    expect(
        container.read(trainingMvpProvider).savedWeeklyReports.first.toJson(),
        report.toJson());
  });
}

class _IdentifiableMarathon extends MarathonPlanStrategy {
  @override
  List<SportWorkoutTemplate> primaryCandidates(SportPlanContext context,
          SportPreferenceCompiler compilePreferences) =>
      super
          .primaryCandidates(context, compilePreferences)
          .map((template) =>
              template.copyWith(title: "插件桥接验证 ${template.title}"))
          .toList();
}
