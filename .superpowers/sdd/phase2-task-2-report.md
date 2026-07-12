# Task 2：训练兼容桥接与详情页写入实施报告

## TDD 记录

- RED：新增桥接测试后运行目标测试失败。新控制器保存调整后，`TrainingMvpState.todayWorkout` 仍为原始 45 分钟，证明训练控制器尚未订阅独立状态。
- GREEN：训练控制器改为读取初始计划调整状态，并通过局部监听投影兼容字段；详情页改用独立控制器写入后，目标测试 9 项全部通过。

## 修改文件

- `lib/features/dashboard/training_mvp_controller.dart`：移除计划调整仓库和直接写入方法；使用 `ref.read` 获取初始状态、`ref.listen` 局部更新计划、调整记录和状态文案，保留 `_applyPlanAdjustments` 与兼容字段。
- `lib/features/training_plan/workout_detail_page.dart`：保存和恢复改由 `planAdjustmentControllerProvider.notifier` 执行，保留既有弹窗校验、中文文案和关闭时机。
- `test/features/training_plan/application/plan_adjustment_training_bridge_test.dart`：覆盖调整和恢复投影，以及跟练会话、事件、知识查询保持不变。
- `test/features/training_plan/workout_detail_page_test.dart`：覆盖详情页保存、状态文案、当前调整卡片和恢复原计划入口。

## 验证命令与结果

- `flutter test test/features/training_plan/application/plan_adjustment_controller_test.dart test/features/training_plan/application/plan_adjustment_training_bridge_test.dart test/features/training_plan/workout_detail_page_test.dart --reporter compact`：通过，9 项成功。
- `flutter analyze`：通过，未发现问题。
- `flutter test --reporter compact`：通过，71 项成功。
- `find . -name '._*' -delete`：在验证前后执行，清理 macOS 元数据文件。

## 范围确认

- 未修改计划调整仓库 schema、README、依赖、路由或其它业务模块。
- 未使用 `ref.watch` 订阅计划调整状态，避免训练控制器因调整状态变更重建。
