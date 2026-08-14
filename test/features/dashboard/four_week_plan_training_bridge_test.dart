import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/profile/application/user_profile_controller.dart';
import 'package:trainflow_ai/features/training_plan/application/four_week_plan_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('确认档案后主训练状态会从种子计划切换到个性化四周计划', () async {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(
          InMemoryLocalStorageService(),
        ),
        fourWeekPlanNowProvider.overrideWithValue(DateTime(2026, 7, 14, 8)),
      ],
    );
    addTearDown(container.dispose);
    final TrainingMvpState before = container.read(trainingMvpProvider);
    expect(before.activePlan.id, 'plan-hyrox-run-base');

    final UserProfile profile =
        container.read(userProfileControllerProvider).profile.copyWith(
      mainSports: const <MainSport>[MainSport.strength],
      weeklyTrainingDays: 3,
    );
    container.read(userProfileControllerProvider.notifier).save(profile);
    await Future<void>.delayed(Duration.zero);

    final TrainingMvpState after = container.read(trainingMvpProvider);
    expect(after.activePlan.id, startsWith('generated-'));
    expect(after.activePlan.title, contains('健身力量'));
    expect(after.activePlan.workoutDays, hasLength(12));
  });

  test('导入临近赛事后主训练计划会立即切换到比赛倒计时阶段', () async {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(
          InMemoryLocalStorageService(),
        ),
        fourWeekPlanNowProvider.overrideWithValue(DateTime(2026, 7, 14, 8)),
      ],
    );
    addTearDown(container.dispose);
    final UserProfile profile = container
        .read(userProfileControllerProvider)
        .profile
        .copyWith(mainSports: const <MainSport>[MainSport.hyrox]);
    container.read(userProfileControllerProvider.notifier).save(profile);
    final TrainingMvpController controller =
        container.read(trainingMvpProvider.notifier);

    controller.importRaceText('''
赛事：本地 HYROX 测试赛
类型：HYROX
日期：2026-07-25
目标：安全稳定完赛
赛道：室内标准赛道
''');
    await Future<void>.delayed(Duration.zero);

    final TrainingMvpState state = container.read(trainingMvpProvider);
    expect(state.activePlan.description, contains('本地 HYROX 测试赛'));
    expect(state.activePlan.workoutDays.first.title, contains('赛前减量'));
  });
}
