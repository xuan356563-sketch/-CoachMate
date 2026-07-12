import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/plan_adjustment.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/data/seed/seed_training_plans.dart';
import 'package:trainflow_ai/features/training_plan/application/plan_adjustment_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  ProviderContainer createContainer(InMemoryLocalStorageService storage) {
    return ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
  }

  test('初始状态显示空计划调整记录', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);

    final PlanAdjustmentState state =
        container.read(planAdjustmentControllerProvider);

    expect(state.adjustments, isEmpty);
    expect(state.statusMessage, '尚未手动调整训练日；可按当天时间和状态微调时长与强度。');
  });

  test('首次调整会记录本地学习信号', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);
    final WorkoutDay workout = _workoutDay(minutes: 45, intensity: '中等');

    container
        .read(planAdjustmentControllerProvider.notifier)
        .saveManualAdjustment(
          workout: workout,
          adjustedMinutes: 30,
          adjustedIntensity: '轻松',
          reason: '加班',
        );

    final PlanAdjustmentState state =
        container.read(planAdjustmentControllerProvider);
    final PlanAdjustment adjustment = state.adjustments.single;
    expect(adjustment.originalEstimatedMinutes, 45);
    expect(adjustment.adjustedEstimatedMinutes, 30);
    expect(adjustment.originalIntensity, 'RPE 4-5');
    expect(adjustment.adjustedIntensity, '轻松');
    expect(adjustment.reason, '加班');
    expect(adjustment.kind, PlanAdjustmentKind.adjusted);
    expect(state.statusMessage, '已记录为本地学习信号：低强度有氧跑 调整为 30 分钟 · 轻松。');
  });

  test('连续调整始终保留首条记录的原始计划值', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);
    final PlanAdjustmentController controller =
        container.read(planAdjustmentControllerProvider.notifier);
    final WorkoutDay workout = _workoutDay(minutes: 45, intensity: '中等');

    controller.saveManualAdjustment(
      workout: workout,
      adjustedMinutes: 30,
      adjustedIntensity: '轻松',
      reason: '加班',
    );
    controller.saveManualAdjustment(
      workout: workout.copyWith(estimatedMinutes: 30, intensity: '轻松'),
      adjustedMinutes: 20,
      adjustedIntensity: '恢复',
      reason: '疲劳',
    );

    final PlanAdjustment latest =
        container.read(planAdjustmentControllerProvider).adjustments.first;
    expect(latest.originalEstimatedMinutes, 45);
    expect(latest.originalIntensity, 'RPE 4-5');
    expect(latest.adjustedEstimatedMinutes, 20);
    expect(latest.adjustedIntensity, '恢复');
  });

  test('恢复原计划会保存 restored 记录', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);
    final PlanAdjustmentController controller =
        container.read(planAdjustmentControllerProvider.notifier);
    final WorkoutDay workout = _workoutDay(minutes: 45, intensity: '中等');

    controller.saveManualAdjustment(
      workout: workout,
      adjustedMinutes: 30,
      adjustedIntensity: '轻松',
      reason: '加班',
    );
    controller.restoreOriginalPlan(
      workout.copyWith(estimatedMinutes: 30, intensity: '轻松'),
    );

    final PlanAdjustmentState state =
        container.read(planAdjustmentControllerProvider);
    final PlanAdjustment restored = state.adjustments.first;
    expect(restored.kind, PlanAdjustmentKind.restored);
    expect(restored.originalEstimatedMinutes, 45);
    expect(restored.adjustedEstimatedMinutes, 45);
    expect(restored.originalIntensity, 'RPE 4-5');
    expect(restored.adjustedIntensity, 'RPE 4-5');
    expect(restored.reason, '用户恢复原计划。');
    expect(state.statusMessage, '已恢复原计划并记录为本地学习信号：低强度有氧跑。');
  });

  test('调整时长超出范围不会写入记录', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);

    container
        .read(planAdjustmentControllerProvider.notifier)
        .saveManualAdjustment(
          workout: _workoutDay(minutes: 45, intensity: '中等'),
          adjustedMinutes: 4,
          adjustedIntensity: '轻松',
          reason: '加班',
        );

    final PlanAdjustmentState state =
        container.read(planAdjustmentControllerProvider);
    expect(state.adjustments, isEmpty);
    expect(state.statusMessage, '调整时长需在 5 到 180 分钟之间。');
  });

  test('缺少强度或原因不会写入记录', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);
    final PlanAdjustmentController controller =
        container.read(planAdjustmentControllerProvider.notifier);
    final WorkoutDay workout = _workoutDay(minutes: 45, intensity: '中等');

    controller.saveManualAdjustment(
      workout: workout,
      adjustedMinutes: 30,
      adjustedIntensity: '  ',
      reason: '加班',
    );
    controller.saveManualAdjustment(
      workout: workout,
      adjustedMinutes: 30,
      adjustedIntensity: '轻松',
      reason: '  ',
    );

    final PlanAdjustmentState state =
        container.read(planAdjustmentControllerProvider);
    expect(state.adjustments, isEmpty);
    expect(state.statusMessage, '请补充调整后的强度和原因。');
  });

  test('新的 ProviderContainer 会读取已持久化记录', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer firstContainer = createContainer(storage);
    firstContainer
        .read(planAdjustmentControllerProvider.notifier)
        .saveManualAdjustment(
          workout: _workoutDay(minutes: 45, intensity: '中等'),
          adjustedMinutes: 30,
          adjustedIntensity: '轻松',
          reason: '加班',
        );
    firstContainer.dispose();

    final ProviderContainer restoredContainer = createContainer(storage);
    addTearDown(restoredContainer.dispose);
    final PlanAdjustmentState restoredState =
        restoredContainer.read(planAdjustmentControllerProvider);

    expect(restoredState.adjustments, hasLength(1));
    expect(restoredState.adjustments.single.adjustedEstimatedMinutes, 30);
    expect(restoredState.statusMessage, '已读取 1 条本地计划调整记录。');
  });

  test('保存调整只使用基础训练日的规范字段', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);
    final WorkoutDay canonical = seedTrainingPlans.first.workoutDays.first;
    final WorkoutDay projected = canonical.copyWith(
      planId: '伪造计划',
      title: '伪造训练日',
      estimatedMinutes: 90,
      intensity: '极高',
    );

    container
        .read(planAdjustmentControllerProvider.notifier)
        .saveManualAdjustment(
          workout: projected,
          adjustedMinutes: 30,
          adjustedIntensity: '轻松',
          reason: '加班',
        );

    final PlanAdjustment adjustment =
        container.read(planAdjustmentControllerProvider).adjustments.single;
    expect(adjustment.planId, canonical.planId);
    expect(adjustment.workoutDayId, canonical.id);
    expect(adjustment.workoutTitle, canonical.title);
    expect(adjustment.originalEstimatedMinutes, canonical.estimatedMinutes);
    expect(adjustment.originalIntensity, canonical.intensity);
  });

  test('训练日不存在时不会保存或恢复调整', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);
    final WorkoutDay missingWorkout = _workoutDay(
      minutes: 45,
      intensity: '中等',
    ).copyWith(id: 'missing-workout');
    final PlanAdjustmentController controller =
        container.read(planAdjustmentControllerProvider.notifier);

    controller.saveManualAdjustment(
      workout: missingWorkout,
      adjustedMinutes: 30,
      adjustedIntensity: '轻松',
      reason: '加班',
    );

    PlanAdjustmentState state =
        container.read(planAdjustmentControllerProvider);
    expect(state.adjustments, isEmpty);
    expect(state.statusMessage, '无法保存调整：没有找到对应训练日。');

    controller.restoreOriginalPlan(missingWorkout);

    state = container.read(planAdjustmentControllerProvider);
    expect(state.adjustments, isEmpty);
    expect(state.statusMessage, '无法恢复原计划：没有找到对应训练日。');
  });
}

WorkoutDay _workoutDay({required int minutes, required String intensity}) {
  return seedTrainingPlans.first.workoutDays.first.copyWith(
    estimatedMinutes: minutes,
    intensity: intensity,
  );
}
