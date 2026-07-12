# 照吃偏好状态迁移设计

## 背景

当前照吃偏好只包含外卖、食堂、自炊三种场景。`TrainingMvpController`
直接构造 `PersistedMealPreferenceRepository`，读取本地偏好、写入新场景，并在
保存后更新首页照吃卡和 AI 教练建议。该职责应与此前已迁移的用户资料、每日调整和
计划调整一样，改由独立应用状态承担。

本设计是渐进式重构，不增加营养功能，也不改变用户可见行为。

## 目标

- 将照吃偏好的读取、保存和清除迁移到独立 Riverpod 控制器。
- 保持 `trainflow.meal_preference.v1`、`schemaVersion: 1` 和
  `preference.scenario` 的 JSON 结构不变。
- 保持外卖为缺失或未知场景的默认值。
- 让旧 `TrainingMvpState.mealScenario` 继续可用，并在偏好变化后同步首页照吃卡和
  AI 教练建议。
- 把仓库测试从 `test/widget_test.dart` 拆出，并补齐控制器、兼容桥和页面交互测试。

## 非目标

- 不增加热量、营养素、忌口、过敏原、餐食记录、餐食数据库或营养追踪。
- 不修改三种模板、路由、页面文案、种子数据、AI 建议算法或存储键。
- 不接入后端、登录、云端同步、支付、推送或新的依赖。
- 不迁移静态 `MealGuideRepository`；它继续为照吃模板提供只读数据。

## 接口

新增 `lib/features/meal_guide/application/meal_preference_controller.dart`：

```dart
final mealPreferenceRepositoryProvider = Provider<MealPreferenceRepository>(...);

final mealPreferenceControllerProvider =
    NotifierProvider<MealPreferenceController, MealPreference>(...);

class MealPreferenceController extends Notifier<MealPreference> {
  void saveScenario(MealScenario scenario);
  void clear();
}
```

`mealPreferenceRepositoryProvider` 默认创建
`PersistedMealPreferenceRepository(ref.read(localStorageServiceProvider))`。
控制器构建时读取仓库的当前偏好；`saveScenario()` 保存新的 `MealPreference` 并用仓库
返回值更新状态；`clear()` 清除仓库后重新读取默认偏好。

## 兼容桥

`TrainingMvpController` 移除私有 `MealPreferenceRepository` 实例、getter 和
`setMealScenario()`。它在 `build()` 中读取
`mealPreferenceControllerProvider` 作为初始 `mealScenario`，并监听此 Provider。

监听回调只更新：

- `TrainingMvpState.mealScenario`
- 依赖 `activeMealGuide` 的 `coachAdvices`

其他状态，尤其跟练会话、日志、身体数据、计划调整和搜索状态，不得因场景变更被重置。
`mealGuides` 继续来自原有只读 `MealGuideRepository`，由旧状态的
`activeMealGuide` getter 根据投影后的 `mealScenario` 选择模板。

## 页面行为

`MealGuidePage` 使用 `select` 仅订阅
`mealPreferenceControllerProvider` 的 `scenario`，作为下拉框当前值。用户切换外卖、
食堂或自炊时，页面调用
`mealPreferenceControllerProvider.notifier.saveScenario(value)`。

页面的当前指令卡和三种模板仍从 `trainingMvpProvider` 读取，因此不改变视觉结构、路由
或文案。首页照吃卡通过训练兼容桥继续更新。

## 错误与数据兼容

现有仓库已经把缺少 `preference`、缺少 `scenario` 或未知 `scenario` 解析为外卖。迁移
必须复用该行为，不能清除或改写旧 JSON。控制器不新增错误状态：本地同步仓库没有可恢复
的异步失败通道，页面也不需要新增提示文案。

## 测试与验收

新增或拆分以下测试：

1. `test/data/repositories/meal_preference_repository_test.dart`：默认值、保存、重新读取、
   清除，以及旧 JSON 缺字段和未知场景兼容。
2. `test/features/meal_guide/application/meal_preference_controller_test.dart`：通过
   `InMemoryLocalStorageService` 覆盖存储 Provider，验证初始状态、保存、跨容器重新读取和
   清除。
3. `test/features/meal_guide/application/meal_preference_training_bridge_test.dart`：保存场景后
   验证 `trainingMvpProvider` 的 `mealScenario`、`activeMealGuide` 与 AI 建议同步，且既有
   跟练会话和日志保留。
4. `test/features/meal_guide/meal_guide_page_test.dart`：切换下拉框后验证新控制器状态和
   训练兼容状态。

完整验收必须通过：

```bash
flutter analyze
flutter test --coverage
flutter build web --no-wasm-dry-run
```

并确认 `TrainingMvpController` 不再直接依赖 `MealPreferenceRepository`，也不定义
`setMealScenario()`；活跃业务代码没有新增餐食记录或营养追踪。
