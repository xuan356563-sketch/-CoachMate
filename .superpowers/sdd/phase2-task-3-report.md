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
