import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/plan_adjustment.dart';
import 'package:trainflow_ai/data/repositories/plan_adjustment_repository.dart';

import '../../support/test_harness.dart';

void main() {
  test('计划调整仓库会保留训练日修改与恢复历史', () {
    final TestHarness harness = TestHarness();
    final PersistedPlanAdjustmentRepository repository =
        PersistedPlanAdjustmentRepository(harness.storageService);
    final PlanAdjustment adjusted = PlanAdjustment(
      id: 'plan-adjustment-test',
      planId: 'plan-test',
      workoutDayId: 'workout-test',
      workoutTitle: '测试训练日',
      originalEstimatedMinutes: 50,
      adjustedEstimatedMinutes: 35,
      originalIntensity: 'RPE 6',
      adjustedIntensity: 'RPE 4-5',
      reason: '测试午休时间限制',
      kind: PlanAdjustmentKind.adjusted,
      adjustedAt: DateTime(2026, 7, 10, 8),
    );
    final PlanAdjustment restored = PlanAdjustment(
      id: 'plan-restored-test',
      planId: 'plan-test',
      workoutDayId: 'workout-test',
      workoutTitle: '测试训练日',
      originalEstimatedMinutes: 50,
      adjustedEstimatedMinutes: 50,
      originalIntensity: 'RPE 6',
      adjustedIntensity: 'RPE 6',
      reason: '测试恢复原计划',
      kind: PlanAdjustmentKind.restored,
      adjustedAt: DateTime(2026, 7, 10, 9),
    );

    repository.saveAdjustment(adjusted);
    repository.saveAdjustment(restored);

    final PersistedPlanAdjustmentRepository restoredRepository =
        PersistedPlanAdjustmentRepository(harness.storageService);
    final List<PlanAdjustment> records = restoredRepository.listAdjustments();

    expect(records, hasLength(2));
    expect(records.first.kind, PlanAdjustmentKind.restored);
    expect(records.first.isActive, isFalse);
    expect(records.first.originalEstimatedMinutes, 50);
    expect(records.first.originalIntensity, 'RPE 6');
    expect(records.last.adjustedEstimatedMinutes, 35);
    expect(records.last.originalEstimatedMinutes, 50);
    expect(records.last.originalIntensity, 'RPE 6');
  });
}
