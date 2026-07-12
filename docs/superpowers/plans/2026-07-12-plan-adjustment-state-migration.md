# 计划调整状态迁移实施计划

> **面向智能体执行者：** 必须使用子技能：建议使用 `superpowers:subagent-driven-development`，或使用 `superpowers:executing-plans`，逐项执行本计划。使用复选框（`- [ ]`）追踪步骤。

**目标：** 将本地训练日调整记录从 `TrainingMvpController` 迁移到独立应用状态，同时保持计划展示、恢复原计划和本地学习信号行为不变。

**架构：** `PlanAdjustmentController` 独占调整记录的读取、输入校验、记录生成和持久化。训练控制器保留基础计划与 `_applyPlanAdjustments`，使用初始读取和 `ref.listen` 局部投影记录、状态文案和已调整计划；训练日详情弹窗直接调用新控制器。

**技术栈：** Flutter、Dart、`flutter_riverpod`、`shared_preferences`、`flutter_test`。

## 全局约束

- 保持 trainflow.plan_adjustments.v1、schemaVersion、记录 JSON 和最多 120 条裁剪规则不变。
- 保持既有路由、弹窗、输入范围、中文状态文案、训练计划规则审计和本地 MVP 边界不变。
- TrainingMvpState.plans、planAdjustments 和 planAdjustmentStatusMessage 暂时保留，供未迁移模块兼容读取。
- 保存只能局部更新 TrainingMvpState；不得重建并清空播放器、日志、知识搜索或其它临时状态。
- 不新增依赖、后端、云同步、计划编排或自动改写未来训练日。

---

### 任务 1：计划调整应用状态

**文件：**
- 新建：`lib/features/training_plan/application/plan_adjustment_controller.dart`
- 新建：`test/features/training_plan/application/plan_adjustment_controller_test.dart`

**接口：**
- 使用：`PlanAdjustmentRepository`、`PersistedPlanAdjustmentRepository`、`TrainingPlanRepository`、`InMemoryTrainingPlanRepository`、`WorkoutDay`、`PlanAdjustment`、`localStorageServiceProvider`。
- 产出：`planAdjustmentRepositoryProvider`、`planAdjustmentControllerProvider`、`PlanAdjustmentState`、`PlanAdjustmentController.saveManualAdjustment()`、`PlanAdjustmentController.restoreOriginalPlan()`。

- [ ] **步骤 1：编写会失败的控制器测试**

使用 `InMemoryLocalStorageService` 覆盖 `localStorageServiceProvider` 创建测试。覆盖初始空状态、首次调整、同一训练日的第二次调整、恢复、无效时长、缺少强度或原因，以及新的 `ProviderContainer` 读取已持久化记录。

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

- [ ] **步骤 2：运行测试并确认失败**

运行：`flutter test test/features/training_plan/application/plan_adjustment_controller_test.dart --reporter compact`

预期：因控制器和 Provider 尚不存在而失败。

- [ ] **步骤 3：实现状态和仓库 Provider**

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

使用 `repository.listAdjustments()` 实现 `build()`。沿用现有的空状态与读取状态文案：“尚未手动调整训练日；可按当天时间和状态微调时长与强度。”和“已读取 N 条本地计划调整记录。”。

- [ ] **步骤 4：实现保留原始值的写入操作**

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
  final WorkoutDay? canonicalWorkout =
      _planRepository.findWorkoutDayById(workout.id);
  if (canonicalWorkout == null) {
    _setStatus('无法保存调整：没有找到对应训练日。');
    return;
  }
  final PlanAdjustment? previous = _latestFor(canonicalWorkout.id);
  final int originalMinutes =
      previous?.originalEstimatedMinutes ?? canonicalWorkout.estimatedMinutes;
  final String originalIntensity =
      previous?.originalIntensity ?? canonicalWorkout.intensity;
  final DateTime now = DateTime.now();
  ref.read(planAdjustmentRepositoryProvider).saveAdjustment(
    PlanAdjustment(
      id: 'plan-adjustment-\${canonicalWorkout.id}-\${now.millisecondsSinceEpoch}',
      planId: canonicalWorkout.planId,
      workoutDayId: canonicalWorkout.id,
      workoutTitle: canonicalWorkout.title,
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
    '已记录为本地学习信号：\${canonicalWorkout.title} 调整为 '
    '\$adjustedMinutes 分钟 · \$intensity。',
  );
}
~~~

`restoreOriginalPlan(WorkoutDay workout)` 也必须先按 ID 查询 `canonicalWorkout`；找不到时写入“无法恢复原计划：没有找到对应训练日。”且不持久化。找到后使用相同的 `_latestFor` 回退逻辑、`PlanAdjustmentKind.restored`、原因“用户恢复原计划。”和现有恢复成功文案。`_refresh` 必须重新读取仓库并保持记录排序。

- [ ] **步骤 5：运行定向测试和静态分析**

运行：

~~~bash
flutter test test/features/training_plan/application/plan_adjustment_controller_test.dart --reporter compact
flutter analyze
~~~

预期：所有新增测试通过，分析器不报告问题。

- [ ] **步骤 6：提交任务 1**

~~~bash
git add lib/features/training_plan/application/plan_adjustment_controller.dart \
  test/features/training_plan/application/plan_adjustment_controller_test.dart
git commit -m "refactor: 独立计划调整状态管理"
~~~

### 任务 2：训练兼容桥接和详情页写入

**文件：**
- 修改：`lib/features/dashboard/training_mvp_controller.dart`
- 修改：`lib/features/training_plan/workout_detail_page.dart`
- 新建：`test/features/training_plan/application/plan_adjustment_training_bridge_test.dart`
- 新建：`test/features/training_plan/workout_detail_page_test.dart`

**接口：**
- 使用：任务 1 的 `planAdjustmentControllerProvider` 和 `PlanAdjustmentState`。
- 产出：投影到 `TrainingMvpState.plans`、`planAdjustments` 和 `planAdjustmentStatusMessage` 的兼容状态；所有计划调整写入均迁出 `TrainingMvpController`。

- [ ] **步骤 1：编写会失败的桥接和页面入口测试**

使用带内存存储的 `ProviderContainer`。启动跟练播放器并添加临时知识搜索词。通过 `planAdjustmentControllerProvider` 保存调整，断言展示训练日的时长和强度已调整、最新调整处于生效状态，并且播放器训练日、步骤、事件和搜索词保持不变。通过新 Provider 恢复，再断言展示训练日恢复为基础时长和强度。

~~~dart
expect(updated.todayWorkout.estimatedMinutes, 20);
expect(updated.latestPlanAdjustmentFor(workout.id)?.isActive, isTrue);
expect(updated.activeWorkoutPlayerDayId, before.activeWorkoutPlayerDayId);
expect(updated.workoutPlayerStepIndex, before.workoutPlayerStepIndex);
expect(updated.knowledgeSearchQuery, before.knowledgeSearchQuery);
~~~

在组件测试中，打开训练日详情面板，输入有效调整并点击保存，然后断言生效调整卡片和状态文本。再次打开面板，点击恢复，并断言 Provider 更新后卡片消失。

- [ ] **步骤 2：运行新增测试并确认失败**

运行：

~~~bash
flutter test test/features/training_plan/application/plan_adjustment_training_bridge_test.dart test/features/training_plan/workout_detail_page_test.dart --reporter compact
~~~

预期：因新控制器尚未连接训练状态，或页面写入仍使用 `TrainingMvpController` 而失败。

- [ ] **步骤 3：使用本地兼容监听器替代直接仓库所有权**

从 `TrainingMvpController` 移除计划调整仓库导入、`_planAdjustmentRepositoryInstance`、`_planAdjustmentRepository`、`saveManualPlanAdjustment`、`restoreOriginalWorkoutPlan` 和 `_refreshPlanAdjustments`。

在 `build()` 中读取初始状态，并在不监听依赖刷新的情况下注册监听器：

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

使用 `planAdjustmentState.adjustments` 构造初始计划、`planAdjustments` 和状态文案。保留本文件中的 `_applyPlanAdjustments` 作为纯兼容辅助函数。

- [ ] **步骤 4：迁移详情面板写入**

在 `workout_detail_page.dart` 导入新控制器。将 `TrainingMvpController` 的保存调用替换为：

~~~dart
ref.read(planAdjustmentControllerProvider.notifier).saveManualAdjustment(
  workout: widget.workout,
  adjustedMinutes: adjustedMinutes,
  adjustedIntensity: _selectedIntensity,
  reason: reason,
);
~~~

将恢复操作替换为 `restoreOriginalPlan(widget.workout)`。保留现有字段级弹窗校验、既有文案和 `Navigator.of(context).pop()` 的调用时机。

- [ ] **步骤 5：运行定向与完整验证**

运行：

~~~bash
flutter test test/features/training_plan/application/plan_adjustment_controller_test.dart test/features/training_plan/application/plan_adjustment_training_bridge_test.dart test/features/training_plan/workout_detail_page_test.dart --reporter compact
flutter analyze
flutter test --reporter compact
~~~

预期：所有定向测试和完整测试套件通过。

- [ ] **步骤 6：提交任务 2**

~~~bash
git add lib/features/dashboard/training_mvp_controller.dart \
  lib/features/training_plan/workout_detail_page.dart \
  test/features/training_plan/application/plan_adjustment_training_bridge_test.dart \
  test/features/training_plan/workout_detail_page_test.dart
git commit -m "refactor: 将计划调整写入迁出训练控制器"
~~~

### 任务 3：仓库测试拆分、文档和发布验证

**文件：**
- 新建：`test/data/repositories/plan_adjustment_repository_test.dart`
- 修改：`test/widget_test.dart`
- 修改：`README.md`

**接口：**
- 使用：既有的 `PersistedPlanAdjustmentRepository`、`TestHarness` 和任务 1 控制器测试。
- 产出：聚焦的仓库测试归属和更新后的测试覆盖说明文档。

- [ ] **步骤 1：迁移既有持久化测试且不削弱断言**

将“计划调整仓库会保留训练日修改与恢复历史”测试从 `test/widget_test.dart` 迁移到 `test/data/repositories/plan_adjustment_repository_test.dart`。复用 `TestHarness().storageService`，不使用真实设备存储。保留记录排序、恢复类型、原始值和持久化重载的现有断言。只从 `test/widget_test.dart` 移除该测试独有的导入。

- [ ] **步骤 2：更新 README 测试说明**

扩展现有通用测试段落，明确计划调整覆盖包括仓库持久化、状态控制器、训练兼容桥接，以及详情页调整/恢复交互。不要添加固定测试数量。

- [ ] **步骤 3：运行拆分测试验证**

运行：

~~~bash
flutter test test/data/repositories/plan_adjustment_repository_test.dart test/features/training_plan/application/plan_adjustment_controller_test.dart test/features/training_plan/application/plan_adjustment_training_bridge_test.dart test/features/training_plan/workout_detail_page_test.dart --reporter compact
flutter analyze
~~~

预期：所有聚焦测试通过，分析器不报告问题。

- [ ] **步骤 4：运行最终验收检查**

运行：

~~~bash
find . -name '._*' -delete
flutter pub get
flutter analyze
flutter test --coverage
flutter build web --no-wasm-dry-run
git status --short
rg -n "PlanAdjustmentRepository|_planAdjustmentRepository|saveManualPlanAdjustment|restoreOriginalWorkoutPlan" lib/features/dashboard/training_mvp_controller.dart
~~~

预期：依赖解析、分析、覆盖率测试和 Web 构建通过；最终搜索没有匹配项；提交前工作树仅包含本计划的文件，提交后保持干净。

- [ ] **步骤 5：提交任务 3**

~~~bash
git add test/data/repositories/plan_adjustment_repository_test.dart \
  test/widget_test.dart README.md
git commit -m "test: 拆分计划调整状态测试"
~~~
