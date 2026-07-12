# Task 3 验收报告：拆分照吃偏好状态测试

## 改动

- 新增 `test/data/repositories/meal_preference_repository_test.dart`，把照吃偏好仓库测试从 `test/widget_test.dart` 迁出。
- 新仓库测试覆盖：
  - 默认值为外卖；
  - 保存 `MealPreference`；
  - 通过新仓库实例重启读取；
  - 清除后回到外卖；
  - `trainflow.meal_preference.v1`；
  - `schemaVersion: 1`；
  - `preference.scenario`；
  - 缺少 `preference` 的旧 JSON 回退外卖；
  - 缺少 `scenario` 的旧 JSON 回退外卖；
  - 未知 `scenario: 'unknown'` 回退外卖。
- 修改 `test/widget_test.dart`，删除已迁出的照吃偏好仓库测试，并只删除该测试造成的无用导入。
- 修改 `README.md`，只在验证说明中补充照吃偏好仓库、控制器、兼容桥和照吃页交互覆盖说明；未写死测试总数，未改产品功能描述。

## 验证命令实际结果

| 命令 | 实际结果 |
| --- | --- |
| `find . -name '._*' -delete` | 已执行；构建后外接卷再次生成 `._*`，已清理。最终 `find . -name '._*' -print` 无输出。 |
| `flutter test test/data/repositories/meal_preference_repository_test.dart` | 通过，`+3: All tests passed!`。 |
| `flutter test test/widget_test.dart` | 通过，`+40: All tests passed!`。 |
| `flutter pub get` | 通过，`Got dependencies!`；输出 25 个依赖有可用更新但受约束不升级。 |
| `flutter analyze` | 通过，`No issues found!`。 |
| `flutter test --coverage` | 通过，`+80: All tests passed!`。 |
| `flutter build web --no-wasm-dry-run` | 通过，`✓ Built build/web`；存在 Flutter 字体提示。 |
| `COPYFILE_DISABLE=1 flutter build web --no-wasm-dry-run` | 清理 `._*` 后重跑通过，`✓ Built build/web`；外接卷仍生成 `._*`，命令后已清理。 |
| `rg -n "MealPreferenceRepository\|_mealPreferenceRepository\|setMealScenario" lib/features/dashboard/training_mvp_controller.dart` | 无输出，退出码 1，符合迁移断言预期。 |
| `git status --short` | 提交前仅包含计划内文件：`README.md`、`test/widget_test.dart`、`test/data/repositories/meal_preference_repository_test.dart` 和本报告。 |

## 迁移断言

- `test/widget_test.dart` 不再包含 `PersistedMealPreferenceRepository`、`MealPreference` 或 `MealScenario` 的仓库测试断言。
- `test/widget_test.dart` 已删除 `meal_guide.dart` 与 `meal_preference_repository.dart` 两个仅由旧仓库测试使用的导入。
- `training_mvp_controller.dart` 中 `MealPreferenceRepository`、`_mealPreferenceRepository`、`setMealScenario` 迁移断言无输出。

## 提交

- 提交信息：`test: 拆分照吃偏好状态测试`
- 提交号：提交完成后以 `git log -1 --format=%H` 为准。

## 自检

- 未修改模型、仓库实现、训练控制器、页面或其他测试。
- 未新增依赖，未升级依赖。
- 保持 `trainflow.meal_preference.v1`、`schemaVersion: 1`、`preference.scenario` 与外卖默认值。
- README 只补充测试覆盖说明，没有写死测试总数，没有改产品功能描述。
- concern：Web 构建在外接卷上会生成 `._*` AppleDouble 元数据文件；已按要求清理。Flutter Web 构建仍输出现有字体提示，未影响构建成功。
