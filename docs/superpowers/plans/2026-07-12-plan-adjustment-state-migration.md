# Plan Adjustment State Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** 将本地训练日调整记录从 TrainingMvpController 迁移到独立应用状态，同时保持计划展示、恢复原计划和本地学习信号行为不变。

**Architecture:** PlanAdjustmentController 独占调整记录的读取、输入校验、记录生成和持久化。训练控制器保留基础计划与 _applyPlanAdjustments，使用初始读取和 ref.listen 局部投影记录、状态文案和已调整计划；训练日详情弹窗直接调用新控制器。

**Tech Stack:** Flutter、Dart、flutter_riverpod、shared_preferences、flutter_test。

## Global Constraints

- 保持 trainflow.plan_adjustments.v1、schemaVersion、记录 JSON 和最多 120 条裁剪规则不变。
- 保持既有路由、弹窗、输入范围、中文状态文案、训练计划规则审计和本地 MVP 边界不变。
- TrainingMvpState.plans、planAdjustments 和 planAdjustmentStatusMessage 暂时保留，供未迁移模块兼容读取。
- 保存只能局部更新 TrainingMvpState；不得重建并清空播放器、日志、知识搜索或其它临时状态。
- 不新增依赖、后端、云同步、计划编排或自动改写未来训练日。

---

### Task 1: Plan Adjustment Application State

**Files:**
- Create: lib/features/training_plan/application/plan_adjustment_controller.dart
- Create: test/features/training_plan/application/plan_adjustment_controller_test.dart

**Interfaces:**
- Consumes: PlanAdjustmentRepository、PersistedPlanAdjustmentRepository、WorkoutDay、PlanAdjustment、localStorageServiceProvider。
- Produces: planAdjustmentRepositoryProvider、planAdjustmentControllerProvider、PlanAdjustmentState、PlanAdjustmentController.saveManualAdjustment()、PlanAdjustmentController.restoreOriginalPlan()。

- [ ] **Step 1: Write failing controller tests**

Create tests with InMemoryLocalStorageService overriding localStorageServiceProvider. Cover initial empty state, a first adjustment, a second adjustment of the same workout, restore, invalid minutes, missing intensity/reason, and a fresh ProviderContainer reading persisted records.

~~~dart
test('连续调整始终保留首条记录的原始计划值', () {
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
  final PlanAdjustment latest = state.adjustments.first;
  expect(latest.originalEstimatedMinutes, 45);
  expect(latest.originalIntensity, '中等');
});
~~~

- [ ] **Step 2: Run test to verify it fails**

Run: flutter test test/features/training_plan/application/plan_adjustment_controller_test.dart --reporter compact

Expected: FAIL because the controller/provider do not exist.

- [ ] **Step 3: Implement the state and repository provider**

~~~dart
final planAdjustmentRepositoryProvider = Provider<PlanAdjustmentRepository>(
  (Ref ref) => PersistedPlanAdjustmentRepository(
    ref.watch(localStorageServiceProvider),
  ),
);

final planAdjustmentControllerProvider =
    NotifierProvider<PlanAdjustmentController, PlanAdjustmentState>(
  PlanAdjustmentController.new,
);

class PlanAdjustmentState {
  final List<PlanAdjustment> adjustments;
  final String statusMessage;

  const PlanAdjustmentState({
    required this.adjustments,
    required this.statusMessage,
  });
}
~~~

Implement build() with repository.listAdjustments(). Use the existing empty/read status messages: 尚未手动调整训练日；可按当天时间和状态微调时长与强度。 and 已读取 N 条本地计划调整记录。.

- [ ] **Step 4: Implement write operations with original-value preservation**

~~~dart
void saveManualAdjustment({
  required WorkoutDay workout,
  required int adjustedMinutes,
  required String adjustedIntensity,
  required String reason,
}) {
  final String intensity = adjustedIntensity.trim();
  final String normalizedReason = reason.trim();
  if (adjustedMinutes < 5 || adjustedMinutes > 180) {
    _setStatus('调整时长需在 5 到 180 分钟之间。');
    return;
  }
  if (intensity.isEmpty || normalizedReason.isEmpty) {
    _setStatus('请补充调整后的强度和原因。');
    return;
  }
  final PlanAdjustment? previous = _latestFor(workout.id);
  final int originalMinutes =
      previous?.originalEstimatedMinutes ?? workout.estimatedMinutes;
  final String originalIntensity =
      previous?.originalIntensity ?? workout.intensity;
  final DateTime now = DateTime.now();
  ref.read(planAdjustmentRepositoryProvider).saveAdjustment(
    PlanAdjustment(
      id: 'plan-adjustment-\${workout.id}-\${now.millisecondsSinceEpoch}',
      planId: workout.planId,
      workoutDayId: workout.id,
      workoutTitle: workout.title,
      originalEstimatedMinutes: originalMinutes,
      adjustedEstimatedMinutes: adjustedMinutes,
      originalIntensity: originalIntensity,
      adjustedIntensity: intensity,
      reason: normalizedReason,
      kind: PlanAdjustmentKind.adjusted,
      adjustedAt: now,
    ),
  );
  _refresh(
    '已记录为本地学习信号：\${workout.title} 调整为 '
    '\$adjustedMinutes 分钟 · \$intensity。',
  );
}
~~~

Implement restoreOriginalPlan(WorkoutDay workout) with the same _latestFor fallback, PlanAdjustmentKind.restored, reason 用户恢复原计划。 and the existing restore success message. _refresh must reread the repository and preserve its sorted records.

- [ ] **Step 5: Run focused tests and static analysis**

Run:

~~~bash
flutter test test/features/training_plan/application/plan_adjustment_controller_test.dart --reporter compact
flutter analyze
~~~

Expected: all new tests pass and analyzer reports no issues.

- [ ] **Step 6: Commit Task 1**

~~~bash
git add lib/features/training_plan/application/plan_adjustment_controller.dart \
  test/features/training_plan/application/plan_adjustment_controller_test.dart
git commit -m "refactor: 独立计划调整状态管理"
~~~

### Task 2: Training Compatibility Bridge and Detail-Page Writes

**Files:**
- Modify: lib/features/dashboard/training_mvp_controller.dart
- Modify: lib/features/training_plan/workout_detail_page.dart
- Create: test/features/training_plan/application/plan_adjustment_training_bridge_test.dart
- Create: test/features/training_plan/workout_detail_page_test.dart

**Interfaces:**
- Consumes: planAdjustmentControllerProvider and PlanAdjustmentState from Task 1.
- Produces: compatibility projection into TrainingMvpState.plans, planAdjustments, and planAdjustmentStatusMessage; all plan-adjustment writes leave TrainingMvpController.

- [ ] **Step 1: Write failing bridge and page-entry tests**

Use a ProviderContainer with in-memory storage. Start the workout player and add a temporary knowledge-search query. Save an adjustment through planAdjustmentControllerProvider, then assert the displayed workout has the adjusted minutes/intensity, the latest adjustment is active, and player day/step/events/search query remain unchanged. Restore through the new provider and assert the displayed workout returns to its base minutes/intensity.

~~~dart
expect(updated.todayWorkout.estimatedMinutes, 20);
expect(updated.latestPlanAdjustmentFor(workout.id)?.isActive, isTrue);
expect(updated.activeWorkoutPlayerDayId, before.activeWorkoutPlayerDayId);
expect(updated.workoutPlayerStepIndex, before.workoutPlayerStepIndex);
expect(updated.knowledgeSearchQuery, before.knowledgeSearchQuery);
~~~

In the widget test, open a workout detail sheet, enter a valid adjustment, tap save, then assert the active-adjustment card and status text. Reopen the sheet, tap restore, and assert the card disappears after the provider update.

- [ ] **Step 2: Run new tests to verify they fail**

Run:

~~~bash
flutter test test/features/training_plan/application/plan_adjustment_training_bridge_test.dart test/features/training_plan/workout_detail_page_test.dart --reporter compact
~~~

Expected: FAIL because the new controller is not connected to training state or the page writes still use TrainingMvpController.

- [ ] **Step 3: Replace direct repository ownership with a local compatibility listener**

Remove the plan-adjustment repository import, _planAdjustmentRepositoryInstance, _planAdjustmentRepository, saveManualPlanAdjustment, restoreOriginalWorkoutPlan, and _refreshPlanAdjustments from TrainingMvpController.

In build(), read initial state and listen without watching:

~~~dart
final PlanAdjustmentState planAdjustmentState =
    ref.read(planAdjustmentControllerProvider);
ref.listen<PlanAdjustmentState>(
  planAdjustmentControllerProvider,
  (PlanAdjustmentState? previous, PlanAdjustmentState next) {
    scheduleMicrotask(() {
      if (!ref.mounted) return;
      state = state.copyWith(
        plans: _applyPlanAdjustments(
          _planRepository.listPlans(),
          next.adjustments,
        ),
        planAdjustments: next.adjustments,
        planAdjustmentStatusMessage: next.statusMessage,
      );
    });
  },
);
~~~

Use planAdjustmentState.adjustments to construct initial plans, planAdjustments, and status message. Leave _applyPlanAdjustments as the pure compatibility helper in this file.

- [ ] **Step 4: Move the detail-sheet writes**

Import the new controller in workout_detail_page.dart. Replace the TrainingMvpController save call with:

~~~dart
ref.read(planAdjustmentControllerProvider.notifier).saveManualAdjustment(
  workout: widget.workout,
  adjustedMinutes: adjustedMinutes,
  adjustedIntensity: _selectedIntensity,
  reason: reason,
);
~~~

Replace restore with restoreOriginalPlan(widget.workout). Retain current field-level dialog validation, existing messages, and Navigator.of(context).pop() timing.

- [ ] **Step 5: Run focused and full verification**

Run:

~~~bash
flutter test test/features/training_plan/application/plan_adjustment_controller_test.dart test/features/training_plan/application/plan_adjustment_training_bridge_test.dart test/features/training_plan/workout_detail_page_test.dart --reporter compact
flutter analyze
flutter test --reporter compact
~~~

Expected: all targeted tests and the full suite pass.

- [ ] **Step 6: Commit Task 2**

~~~bash
git add lib/features/dashboard/training_mvp_controller.dart \
  lib/features/training_plan/workout_detail_page.dart \
  test/features/training_plan/application/plan_adjustment_training_bridge_test.dart \
  test/features/training_plan/workout_detail_page_test.dart
git commit -m "refactor: 将计划调整写入迁出训练控制器"
~~~

### Task 3: Repository Test Split, Documentation, and Release Verification

**Files:**
- Create: test/data/repositories/plan_adjustment_repository_test.dart
- Modify: test/widget_test.dart
- Modify: README.md

**Interfaces:**
- Consumes: existing PersistedPlanAdjustmentRepository, TestHarness, and Task 1 controller tests.
- Produces: focused repository test ownership and updated test-coverage documentation.

- [ ] **Step 1: Move the existing persistence test without weakening assertions**

Move the 计划调整仓库会保留训练日修改与恢复历史 test from test/widget_test.dart into test/data/repositories/plan_adjustment_repository_test.dart. Reuse TestHarness().storageService rather than real device storage. Preserve the existing assertions for record order, restored kind, original values, and persisted reload. Remove only imports now unique to that test from widget_test.dart.

- [ ] **Step 2: Update the README test description**

Extend the existing generic test paragraph so it explicitly states that plan adjustment coverage includes repository persistence, state controller, training compatibility bridge, and detail-page adjustment/restore interaction. Do not add a fixed test count.

- [ ] **Step 3: Run split-test verification**

Run:

~~~bash
flutter test test/data/repositories/plan_adjustment_repository_test.dart test/features/training_plan/application/plan_adjustment_controller_test.dart test/features/training_plan/application/plan_adjustment_training_bridge_test.dart test/features/training_plan/workout_detail_page_test.dart --reporter compact
flutter analyze
~~~

Expected: all focused tests pass and analyzer reports no issues.

- [ ] **Step 4: Run final acceptance checks**

Run:

~~~bash
find . -name '._*' -delete
flutter pub get
flutter analyze
flutter test --coverage
flutter build web --no-wasm-dry-run
git status --short
rg -n "PlanAdjustmentRepository|_planAdjustmentRepository|saveManualPlanAdjustment|restoreOriginalWorkoutPlan" lib/features/dashboard/training_mvp_controller.dart
~~~

Expected: dependency resolution, analysis, coverage tests, and Web build pass; the final search produces no matches; the working tree only contains this plan's files before commit and is clean after commit.

- [ ] **Step 5: Commit Task 3**

~~~bash
git add test/data/repositories/plan_adjustment_repository_test.dart \
  test/widget_test.dart README.md
git commit -m "test: 拆分计划调整状态测试"
~~~
