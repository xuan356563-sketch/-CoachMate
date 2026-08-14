import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/features/profile/application/health_data_deletion_coordinator.dart';

void main() {
  test('按结构化事务兼容身体成长刷新顺序完成清理', () async {
    final List<String> calls = <String>[];
    final HealthDataDeletionCoordinator coordinator =
        HealthDataDeletionCoordinator(
      currentAthleteId: () => 'athlete-1',
      clearHealthFactsAndQueue: () async => calls.add('health'),
      clearBodyMetrics: () => calls.add('body'),
      clearGrowthData: (String athleteId) async =>
          calls.add('growth:$athleteId'),
      clearHealthDerivedPlanAdjustments: () => calls.add('plan-adjustments'),
      clearCompatibilityReportsAndBadges: () => calls.add('compatibility'),
      flushStorage: () async => calls.add('flush'),
      resetDerivedState: () => calls.add('reset'),
    );

    await coordinator.clearCurrentAthleteData();

    expect(calls, <String>[
      'health',
      'body',
      'growth:athlete-1',
      'plan-adjustments',
      'compatibility',
      'flush',
      'reset',
    ]);
  });

  test('结构化健康清理失败时不继续清理兼容状态', () async {
    final List<String> calls = <String>[];
    final HealthDataDeletionCoordinator coordinator =
        HealthDataDeletionCoordinator(
      currentAthleteId: () => 'athlete-1',
      clearHealthFactsAndQueue: () async {
        calls.add('health');
        throw StateError('结构化事务失败');
      },
      clearBodyMetrics: () => calls.add('body'),
      clearGrowthData: (String athleteId) async => calls.add('growth'),
      clearHealthDerivedPlanAdjustments: () => calls.add('plan-adjustments'),
      clearCompatibilityReportsAndBadges: () => calls.add('compatibility'),
      flushStorage: () async => calls.add('flush'),
      resetDerivedState: () => calls.add('reset'),
    );

    await expectLater(
      coordinator.clearCurrentAthleteData(),
      throwsStateError,
    );
    expect(calls, <String>['health']);
  });

  test('运动员标识为空时拒绝执行任何清理', () async {
    bool called = false;
    final HealthDataDeletionCoordinator coordinator =
        HealthDataDeletionCoordinator(
      currentAthleteId: () => '',
      clearHealthFactsAndQueue: () async => called = true,
      clearBodyMetrics: () => called = true,
      clearGrowthData: (String athleteId) async => called = true,
      clearHealthDerivedPlanAdjustments: () => called = true,
      clearCompatibilityReportsAndBadges: () => called = true,
      flushStorage: () async => called = true,
      resetDerivedState: () => called = true,
    );

    await expectLater(
      coordinator.clearCurrentAthleteData(),
      throwsStateError,
    );
    expect(called, isFalse);
  });
}
