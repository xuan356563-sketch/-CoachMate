# Task 2 报告：照吃偏好状态迁移

## 修改内容

- 训练控制器移除对 `MealPreferenceRepository` 的直接依赖，不再持有私有仓库实例，不再暴露 `setMealScenario()`。
- 训练控制器在 `build()` 中直接读取并监听 `mealPreferenceControllerProvider`，把独立照吃偏好投影到旧 `TrainingMvpState.mealScenario`。
- 照吃偏好变化时仅同步 `mealScenario` 和基于当前 `activeMealGuide` 的 `coachAdvices`，不重置跟练会话、日志、知识搜索或其他训练状态。
- 照吃页改为选择性订阅 `mealPreferenceControllerProvider` 的当前场景，下拉框写入独立偏好控制器。
- 新增桥接测试和页面交互测试，覆盖偏好写入、旧状态投影、照吃卡同步、建议同步和跟练状态保留。

## 修改文件

- `lib/features/dashboard/training_mvp_controller.dart`
- `lib/features/meal_guide/meal_guide_page.dart`
- `test/features/meal_guide/application/meal_preference_training_bridge_test.dart`
- `test/features/meal_guide/meal_guide_page_test.dart`
- `.superpowers/sdd/task-2-report.md`

## 测试结果

- 已先执行 `find . -name '._*' -delete` 清理 AppleDouble 副文件。
- `flutter test test/features/meal_guide/application/meal_preference_training_bridge_test.dart`：通过，`All tests passed!`
- 已再次执行 `find . -name '._*' -delete`。
- `flutter test test/features/meal_guide/meal_guide_page_test.dart`：通过，`All tests passed!`
- 已再次执行 `find . -name '._*' -delete`。
- `flutter analyze`：通过，`No issues found!`
- 验证结束后已再次清理 `._*` 副文件。

## 提交号

- 最终提交号见完成回复；提交哈希依赖报告文件内容，无法在同一个提交内可靠写入自身哈希。

## 自检

- 未修改三种照吃模板、路由、文案、AI 算法、存储键或 schema。
- 未新增依赖。
- 受限代码文件中已无 `setMealScenario` 调用。
- 训练控制器受限文件中已无 `MealPreferenceRepository` / `meal_preference_repository.dart` 直接依赖。
- 当前变更限定在任务允许的 5 个文件内。
