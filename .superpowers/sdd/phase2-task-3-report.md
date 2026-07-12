# Task 3：仓库测试拆分、文档与发布验证实施报告

## 修改文件

- `test/data/repositories/plan_adjustment_repository_test.dart`：承接计划调整仓库的修改、恢复、排序与本地持久化重载测试，并通过 `TestHarness().storageService` 隔离存储。
- `test/widget_test.dart`：仅移除已迁出的计划调整仓库测试及其专属 import。
- `README.md`：补充计划调整的仓库持久化、状态控制器、训练兼容桥和详情页调整/恢复交互覆盖说明。

## 验证命令与结果

- `flutter test test/data/repositories/plan_adjustment_repository_test.dart test/features/training_plan/application/plan_adjustment_controller_test.dart test/features/training_plan/application/plan_adjustment_training_bridge_test.dart test/features/training_plan/workout_detail_page_test.dart --reporter compact`：通过，10 项成功。
- `flutter analyze`：通过，未发现问题。
- `flutter test --reporter compact`：通过，71 项成功。
- 首次完整测试因已删除的 `build/native_assets/macos/._native_assets.json` 生成目录残留中断；清理可再生 `build/native_assets` 后重跑通过。
- `find . -name '._*' -delete`：已执行，macOS 元数据文件已清理。

## 范围确认

- 未修改 `lib`、路由、依赖、schema 或业务行为。
- 未改变计划调整仓库的存储键、记录格式或裁剪规则。

## 发布验收补充记录

- `find . -name '._*' -delete`：在验收前执行，复查无残留；构建和测试生成的 AppleDouble 元数据已在报告更新前再次清理。
- `flutter pub get`：通过，依赖解析完成；提示 25 个包存在受当前约束限制的较新版本，未更新依赖或锁文件。
- `flutter analyze`：通过，`No issues found!`。
- `flutter test --coverage`：通过，71 项测试成功，并生成覆盖率输出。
- `flutter build web --no-wasm-dry-run`：通过，生成 `build/web`。构建输出提示未找到 `packages/cupertino_icons/CupertinoIcons` 字体，仅扫描到 `MaterialIcons`；命令以成功状态完成且 Web 产物已生成，判定为非阻断警告。
- `rg -n "PlanAdjustmentRepository|_planAdjustmentRepository|saveManualPlanAdjustment|restoreOriginalWorkoutPlan" lib/features/dashboard/training_mvp_controller.dart`：无匹配，确认训练控制器不再包含旧仓库所有权或旧写入方法。
- `git status --short`：报告更新前无输出，工作树干净；本次仅修改本报告以记录验收证据。
