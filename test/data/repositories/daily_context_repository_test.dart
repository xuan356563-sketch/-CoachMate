import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/daily_adjustment.dart';
import 'package:trainflow_ai/data/repositories/daily_context_repository.dart';

import '../../support/test_harness.dart';

void main() {
  test('每日调整仓库会持久化 daily_context', () {
    final TestHarness harness = TestHarness();
    final PersistedDailyContextRepository repository =
        PersistedDailyContextRepository(harness.storageService);

    expect(repository.getContext(defaultAvailableMinutes: 35).availableMinutes,
        35);
    expect(repository.getContext().workStress, WorkStressLevel.normal);

    repository.saveContext(
      const DailyAdjustmentContext(
        availableMinutes: 20,
        workStress: WorkStressLevel.extreme,
        environment: TrainingEnvironment.outdoor,
        weather: WeatherCondition.rain,
        statusMessage: '测试现实约束',
      ),
    );

    final PersistedDailyContextRepository restoredRepository =
        PersistedDailyContextRepository(harness.storageService);

    expect(restoredRepository.getContext().availableMinutes, 20);
    expect(restoredRepository.getContext().workStress, WorkStressLevel.extreme);
    expect(restoredRepository.getContext().environment,
        TrainingEnvironment.outdoor);
    expect(restoredRepository.getContext().weather, WeatherCondition.rain);
    expect(restoredRepository.getContext().statusMessage, '测试现实约束');

    restoredRepository.saveContext(
      const DailyAdjustmentContext(
        availableMinutes: 999,
        workStress: WorkStressLevel.high,
        environment: TrainingEnvironment.noEquipment,
        weather: WeatherCondition.poorAir,
        statusMessage: '',
      ),
    );

    final PersistedDailyContextRepository normalizedRepository =
        PersistedDailyContextRepository(harness.storageService);

    expect(normalizedRepository.getContext().availableMinutes, 180);
    expect(normalizedRepository.getContext().statusMessage, '尚未应用今日现实约束调整。');

    normalizedRepository.clearContext();

    final PersistedDailyContextRepository clearedRepository =
        PersistedDailyContextRepository(harness.storageService);

    expect(
        clearedRepository
            .getContext(defaultAvailableMinutes: 50)
            .availableMinutes,
        50);
    expect(clearedRepository.getContext().environment, TrainingEnvironment.gym);
  });
}
