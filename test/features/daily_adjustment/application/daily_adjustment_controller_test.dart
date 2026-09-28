import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/daily_adjustment.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/data/repositories/daily_context_repository.dart';
import 'package:trainflow_ai/features/daily_adjustment/application/daily_adjustment_controller.dart';
import 'package:trainflow_ai/features/profile/application/user_profile_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  ProviderContainer createContainer(InMemoryLocalStorageService storage) {
    return ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
  }

  test('初始状态使用资料可训练时长和每日调整默认值', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);

    final UserProfileState profileState =
        container.read(userProfileControllerProvider);
    final DailyAdjustmentState state =
        container.read(dailyAdjustmentControllerProvider);

    expect(state.context.availableMinutes,
        profileState.profile.dailyAvailableMinutes);
    expect(state.context.workStress, WorkStressLevel.normal);
    expect(state.context.environment, TrainingEnvironment.gym);
    expect(state.context.weather, WeatherCondition.good);
    expect(state.statusMessage, '尚未应用今日现实约束调整。');
  });

  test('不存在本地上下文时跟随已保存的资料可训练时长', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);
    final UserProfileState profileState =
        container.read(userProfileControllerProvider);

    container.read(userProfileControllerProvider.notifier).save(
          profileState.profile.copyWith(dailyAvailableMinutes: 75),
        );

    expect(
      container
          .read(dailyAdjustmentControllerProvider)
          .context
          .availableMinutes,
      75,
    );
  });

  test('本地上下文优先于资料默认值，并在更新后规范化和恢复', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer firstContainer = createContainer(storage);
    final DailyContextRepository repository =
        firstContainer.read(dailyContextRepositoryProvider);
    repository.saveContext(
      const DailyAdjustmentContext(
        availableMinutes: 20,
        workStress: WorkStressLevel.high,
        environment: TrainingEnvironment.home,
        weather: WeatherCondition.rain,
        statusMessage: '已保存本地调整。',
      ),
    );

    final UserProfileState profileState =
        firstContainer.read(userProfileControllerProvider);
    firstContainer.read(userProfileControllerProvider.notifier).save(
          profileState.profile.copyWith(dailyAvailableMinutes: 75),
        );
    expect(
      firstContainer
          .read(dailyAdjustmentControllerProvider)
          .context
          .availableMinutes,
      20,
    );

    await firstContainer
        .read(dailyAdjustmentControllerProvider.notifier)
        .setDailyAvailableMinutes(300);
    expect(
      firstContainer
          .read(dailyAdjustmentControllerProvider)
          .context
          .availableMinutes,
      180,
    );
    expect(
      firstContainer.read(dailyAdjustmentControllerProvider).statusMessage,
      '已更新今日可训练时间为 300 分钟。',
    );
    firstContainer.dispose();

    final ProviderContainer restoredContainer = createContainer(storage);
    addTearDown(restoredContainer.dispose);
    final DailyAdjustmentState restoredState =
        restoredContainer.read(dailyAdjustmentControllerProvider);

    expect(restoredState.context.availableMinutes, 180);
    expect(restoredState.statusMessage, '已更新今日可训练时间为 300 分钟。');
  });

  test('应用每日调整决策会持久化原控制器状态文案', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);
    const DailyAdjustmentDecision decision = DailyAdjustmentDecision(
      decisionType: TrainingDecisionType.deload,
      availableMinutes: 30,
      workStress: WorkStressLevel.high,
      environment: TrainingEnvironment.home,
      weather: WeatherCondition.rain,
      decisionLabel: '轻松版',
      reason: '测试原因',
      adjustedMinutes: 20,
      planChangeSummary: '减少训练量',
      constraintBadges: <String>[],
      adjustments: <String>[],
    );

    await container
        .read(dailyAdjustmentControllerProvider.notifier)
        .setDailyWorkStress(WorkStressLevel.high);
    expect(
      container.read(dailyAdjustmentControllerProvider).statusMessage,
      '已更新今日工作压力为高压。',
    );
    await container
        .read(dailyAdjustmentControllerProvider.notifier)
        .setDailyTrainingEnvironment(TrainingEnvironment.home);
    expect(
      container.read(dailyAdjustmentControllerProvider).statusMessage,
      '已更新今日训练场地为家里。',
    );
    await container
        .read(dailyAdjustmentControllerProvider.notifier)
        .setDailyWeather(WeatherCondition.rain);
    expect(
      container.read(dailyAdjustmentControllerProvider).statusMessage,
      '已更新今日天气状态为下雨。',
    );

    await container
        .read(dailyAdjustmentControllerProvider.notifier)
        .applyDailyAdjustmentDecision(decision);

    expect(
      container.read(dailyAdjustmentControllerProvider).statusMessage,
      '建议已记录，计划未改变：轻松版，减少训练量',
    );
    expect(
      container.read(dailyAdjustmentControllerProvider).context.workStress,
      WorkStressLevel.high,
    );
    expect(
      container.read(dailyAdjustmentControllerProvider).context.environment,
      TrainingEnvironment.home,
    );
    expect(
      container.read(dailyAdjustmentControllerProvider).context.weather,
      WeatherCondition.rain,
    );
    final AppliedDailyDecisionFact firstFact = container
        .read(dailyAdjustmentControllerProvider)
        .context
        .appliedDecisions
        .single;
    expect(firstFact.decisionType, TrainingDecisionType.deload);
    expect(firstFact.confirmedAt.isUtc, isTrue);
    expect(firstFact.localDate, _localDateKey(firstFact.confirmedAt.toLocal()));

    await container
        .read(dailyAdjustmentControllerProvider.notifier)
        .setDailyWeather(WeatherCondition.good);
    expect(
      container
          .read(dailyAdjustmentControllerProvider)
          .context
          .appliedDecisions,
      hasLength(1),
    );

    const DailyAdjustmentDecision replacement = DailyAdjustmentDecision(
      decisionType: TrainingDecisionType.normal,
      availableMinutes: 30,
      workStress: WorkStressLevel.normal,
      environment: TrainingEnvironment.gym,
      weather: WeatherCondition.good,
      decisionLabel: '正常训练',
      reason: '状态恢复',
      adjustedMinutes: 30,
      planChangeSummary: '恢复原计划',
      constraintBadges: <String>[],
      adjustments: <String>[],
    );
    await container
        .read(dailyAdjustmentControllerProvider.notifier)
        .applyDailyAdjustmentDecision(replacement);

    final List<AppliedDailyDecisionFact> replacedFacts = container
        .read(dailyAdjustmentControllerProvider)
        .context
        .appliedDecisions;
    expect(replacedFacts, hasLength(1));
    expect(replacedFacts.single.decisionType, TrainingDecisionType.normal);
    expect(
      replacedFacts.single.confirmedAt.isBefore(firstFact.confirmedAt),
      isFalse,
    );

    container.dispose();
    final ProviderContainer restoredContainer = createContainer(storage);
    addTearDown(restoredContainer.dispose);
    expect(
      restoredContainer
          .read(dailyAdjustmentControllerProvider)
          .context
          .appliedDecisions
          .single
          .decisionType,
      TrainingDecisionType.normal,
    );
  });

  test('未点击记录今日建议的恢复文案不会生成决策事实', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);

    await container
        .read(dailyAdjustmentControllerProvider.notifier)
        .applyAiRecoveryRecommendation('今天优先恢复');

    final DailyAdjustmentState state =
        container.read(dailyAdjustmentControllerProvider);
    expect(state.statusMessage, contains('恢复'));
    expect(state.context.appliedDecisions, isEmpty);
  });
}

String _localDateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
