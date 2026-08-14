import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/daily_adjustment.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
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

  test('旧 daily_context 即使状态文案包含恢复也不会补造结构化事实', () {
    final TestHarness harness = TestHarness();
    harness.storageService.saveJson(
      PersistedDailyContextRepository.storageKey,
      <String, dynamic>{
        'schemaVersion': 1,
        'context': <String, dynamic>{
          'availableMinutes': 30,
          'workStress': 'normal',
          'environment': 'gym',
          'weather': 'good',
          'statusMessage': '已应用恢复训练，但这是旧版本状态文案。',
        },
      },
    );

    final PersistedDailyContextRepository repository =
        PersistedDailyContextRepository(harness.storageService);

    expect(repository.getContext().statusMessage, contains('恢复'));
    expect(repository.getContext().appliedDecisions, isEmpty);
  });

  test('已应用决策按本地日期去重排序，并只保留最近 90 个自然日', () {
    final TestHarness harness = TestHarness();
    final PersistedDailyContextRepository repository =
        PersistedDailyContextRepository(harness.storageService);
    final DateTime firstDay = DateTime.utc(2026, 1, 1);
    final List<AppliedDailyDecisionFact> history = List.generate(
      91,
      (int index) {
        final DateTime date = firstDay.add(Duration(days: index));
        return AppliedDailyDecisionFact(
          localDate: _dateKey(date),
          decisionType: TrainingDecisionType.recovery,
          confirmedAt: date.add(const Duration(hours: 8)),
        );
      },
    )..add(
        AppliedDailyDecisionFact(
          localDate: _dateKey(firstDay.add(const Duration(days: 90))),
          decisionType: TrainingDecisionType.rest,
          confirmedAt: firstDay.add(const Duration(days: 90, hours: 12)),
        ),
      );

    final DailyAdjustmentContext saved = repository.saveContext(
      DailyAdjustmentContext(
        availableMinutes: 30,
        workStress: WorkStressLevel.normal,
        environment: TrainingEnvironment.gym,
        weather: WeatherCondition.good,
        statusMessage: '测试决策历史',
        appliedDecisions: history,
      ),
    );

    expect(saved.appliedDecisions, hasLength(90));
    expect(saved.appliedDecisions.first.localDate, '2026-01-02');
    expect(saved.appliedDecisions.last.localDate, '2026-04-01');
    expect(
      saved.appliedDecisions.last.decisionType,
      TrainingDecisionType.rest,
    );
    expect(
      saved.appliedDecisions
          .map((AppliedDailyDecisionFact fact) => fact.localDate),
      orderedEquals(
        saved.appliedDecisions
            .map((AppliedDailyDecisionFact fact) => fact.localDate)
            .toList()
          ..sort(),
      ),
    );

    final PersistedDailyContextRepository restored =
        PersistedDailyContextRepository(harness.storageService);
    expect(restored.getContext().appliedDecisions, hasLength(90));
    expect(
      restored.getContext().appliedDecisions.last.decisionType,
      TrainingDecisionType.rest,
    );
  });
}

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
