# 计划调整状态迁移设计

## 目标

将本地 `plan_adjustments` 的读写、校验和记录生成从 `TrainingMvpController` 迁移到独立应用状态，同时保持训练计划展示、规则审计、训练日详情弹窗和本地存储行为不变。

## 方案选择

采用“调整记录独立、基础计划保留”的渐进迁移：

- `PlanAdjustmentController` 管理已持久化的调整记录和状态文案，复用既有 `PersistedPlanAdjustmentRepository`。
- 新控制器接受当前展示训练日作为输入。对已有记录，始终从该训练日最近记录的 `originalEstimatedMinutes` 与 `originalIntensity` 恢复原始值；首次调整才使用传入训练日。这保证连续调整和恢复不会把已调整值误认为原计划。
- `TrainingMvpController` 保留基础训练计划、`TrainingMvpState.planAdjustments`、`plans` 及其派生 getter；它只初始读取并监听调整状态，局部重新应用记录到基础计划，不能重建播放器、日志或其它临时状态。
- 训练日详情弹窗改为调用新控制器。界面文案、输入范围、路由和弹窗关闭时机维持现状。

未采用“仅抽出仓库读写”的方案，因为校验和写入仍会留在巨型控制器；未迁移基础训练计划仓库，因为会扩大到计划生成、审计和播放器的无关边界。

## 接口与数据流

新增：

```dart
final planAdjustmentRepositoryProvider = Provider<PlanAdjustmentRepository>(...);
final planAdjustmentControllerProvider =
    NotifierProvider<PlanAdjustmentController, PlanAdjustmentState>(...);

class PlanAdjustmentState {
  final List<PlanAdjustment> adjustments;
  final String statusMessage;
}

class PlanAdjustmentController extends Notifier<PlanAdjustmentState> {
  void saveManualAdjustment({
    required WorkoutDay workout,
    required int adjustedMinutes,
    required String adjustedIntensity,
    required String reason,
  });

  void restoreOriginalPlan(WorkoutDay workout);
}
```

- `saveManualAdjustment` 保留现有输入校验：时长为 5-180 分钟，强度和原因去空白后不能为空。
- 找不到/无效输入时只更新 `statusMessage`，不写仓库；成功时由仓库返回记录后刷新 `adjustments`。
- `restoreOriginalPlan` 保存 `restored` 记录，使用该训练日真正的原始时长和强度。
- 兼容桥用 `ref.read` 获取初始状态、`ref.listen` 接收后续变化，以当前 `TrainingMvpState` 为基准局部更新 `plans`、`planAdjustments` 和 `planAdjustmentStatusMessage`。

`trainflow.plan_adjustments.v1` 的键名、`schemaVersion`、记录 JSON 和最多 120 条的裁剪规则均不改变。

## 错误处理与验证

- 保持现有中文状态文案：训练日不存在、时长范围无效、强度/原因缺失、成功保存和恢复成功。
- 控制器测试使用 `InMemoryLocalStorageService`，覆盖初始读取、首次调整、连续调整、恢复、无效输入、重启恢复和旧 JSON 兼容。
- 桥接测试覆盖新 Provider 保存后训练计划展示与最新调整同步，并验证进行中的跟练会话、步骤、事件和临时查询不丢失。
- 页面测试点击保存/恢复入口，断言记录已写入、状态文案与训练日展示同步。
- 完成后执行 `flutter analyze`、`flutter test --coverage` 和 `flutter build web --no-wasm-dry-run`。

## 范围边界

本批不迁移基础训练计划、规则审计、计划生成、云端协作、拖拽编排、动作增删或未来训练日自动改写。后续按用户确认的顺序处理照吃偏好和身体数据。
