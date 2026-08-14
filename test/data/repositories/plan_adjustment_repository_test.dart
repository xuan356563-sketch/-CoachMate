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
      sourceProposalId: 'proposal-acwr-test',
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
    expect(records.last.sourceProposalId, 'proposal-acwr-test');
  });

  test('删除健康数据时只清理建议产生的调整，保留手动调整', () {
    final TestHarness harness = TestHarness();
    final PersistedPlanAdjustmentRepository repository =
        PersistedPlanAdjustmentRepository(harness.storageService);
    repository.saveAdjustment(
      PlanAdjustment(
        id: 'manual',
        planId: 'plan-test',
        workoutDayId: 'manual-day',
        workoutTitle: '手动调整',
        originalEstimatedMinutes: 40,
        adjustedEstimatedMinutes: 30,
        originalIntensity: 'RPE 5',
        adjustedIntensity: 'RPE 4',
        reason: '用户手动修改',
        kind: PlanAdjustmentKind.adjusted,
        adjustedAt: DateTime(2026, 7, 10, 8),
      ),
    );
    repository.saveAdjustment(
      PlanAdjustment(
        id: 'health-derived',
        planId: 'plan-test',
        workoutDayId: 'health-day',
        workoutTitle: '负荷建议调整',
        originalEstimatedMinutes: 60,
        adjustedEstimatedMinutes: 60,
        originalIntensity: 'RPE 7',
        adjustedIntensity: 'RPE 6',
        reason: 'ACWR 建议',
        kind: PlanAdjustmentKind.adjusted,
        adjustedAt: DateTime(2026, 7, 10, 9),
        sourceProposalId: 'proposal-acwr-test',
      ),
    );

    expect(repository.clearHealthDerivedAdjustments(), 1);

    final List<PlanAdjustment> records =
        PersistedPlanAdjustmentRepository(harness.storageService)
            .listAdjustments();
    expect(records, hasLength(1));
    expect(records.single.id, 'manual');
    expect(records.single.sourceProposalId, isNull);
  });

  test('周总量建议的多训练日差异在一次持久化后完整恢复', () {
    final TestHarness harness = TestHarness();
    final PersistedPlanAdjustmentRepository repository =
        PersistedPlanAdjustmentRepository(harness.storageService);
    final DateTime at = DateTime(2026, 7, 15, 13);
    repository.saveAdjustmentsAtomically(<PlanAdjustment>[
      PlanAdjustment(
        id: 'weekly-a',
        planId: 'plan-a',
        workoutDayId: 'day-a',
        workoutTitle: '轻松跑',
        originalEstimatedMinutes: 40,
        adjustedEstimatedMinutes: 36,
        originalIntensity: 'RPE 4',
        adjustedIntensity: 'RPE 4',
        reason: '周总量降低 10%',
        kind: PlanAdjustmentKind.adjusted,
        adjustedAt: at,
        sourceProposalId: 'proposal-weekly',
      ),
      PlanAdjustment(
        id: 'weekly-b',
        planId: 'plan-a',
        workoutDayId: 'day-b',
        workoutTitle: '力量训练',
        originalEstimatedMinutes: 60,
        adjustedEstimatedMinutes: 54,
        originalIntensity: 'RPE 6',
        adjustedIntensity: 'RPE 6',
        reason: '周总量降低 10%',
        kind: PlanAdjustmentKind.adjusted,
        adjustedAt: at,
        sourceProposalId: 'proposal-weekly',
      ),
    ]);

    final List<PlanAdjustment> restored =
        PersistedPlanAdjustmentRepository(harness.storageService)
            .listAdjustments();

    expect(restored, hasLength(2));
    expect(
      restored.fold<int>(
        0,
        (int total, PlanAdjustment item) =>
            total + item.adjustedEstimatedMinutes,
      ),
      90,
    );
    expect(
      restored.every(
        (PlanAdjustment item) => item.sourceProposalId == 'proposal-weekly',
      ),
      isTrue,
    );
  });
}
