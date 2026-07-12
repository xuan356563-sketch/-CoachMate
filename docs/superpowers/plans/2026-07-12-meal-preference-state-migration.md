# 照吃偏好状态迁移实施计划

> **供执行代理使用：** 必须使用按任务逐项执行和复核的方式实施本计划；每一项使用复选框跟踪。

**目标：** 将照吃场景偏好从训练全局控制器迁移为独立 Riverpod 状态，同时保持本地存储、照吃卡和 AI 建议行为不变。

**架构：** 新控制器拥有 `MealPreference` 的读取、保存与清除；训练全局控制器只监听它，并继续向旧 `TrainingMvpState.mealScenario` 投影。照吃页直接写入新控制器，静态照吃模板仍由既有 `MealGuideRepository` 提供。

**技术栈：** Flutter、flutter_riverpod、shared_preferences、flutter_test。

## 全局约束

- 不新增依赖、不升级依赖、不新增后端或数据库迁移。
- 保持 `trainflow.meal_preference.v1`、`schemaVersion: 1`、`preference.scenario` 和外卖默认值不变。
- 保持外卖、食堂、自炊三种模板、现有路由、页面文案和 AI 建议算法不变。
- 不新增热量、忌口、过敏原、餐食记录或营养追踪。
- 所有代码注释、测试名称、文档和错误提示使用中文。
- 每次 Flutter 验证前先删除外接卷可能生成的 `._*` 文件。

---

### Task 1：建立独立照吃偏好应用状态

**文件：**
- 新建：`lib/features/meal_guide/application/meal_preference_controller.dart`
- 新建：`test/features/meal_guide/application/meal_preference_controller_test.dart`

**接口：**
- 输入：`MealPreferenceRepository`、`localStorageServiceProvider`。
- 输出：`mealPreferenceRepositoryProvider`、`mealPreferenceControllerProvider`、`MealPreferenceController.saveScenario()`、`MealPreferenceController.clear()`。
- 兼容：状态类型直接为既有 `MealPreference`，不改模型 JSON。

- [ ] **步骤 1：写出控制器的初始、保存、重启读取和清除测试。**

```dart
test('保存和清除照吃场景会更新独立状态并保留本地兼容', () {
  final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
  final ProviderContainer first = ProviderContainer(
    overrides: [localStorageServiceProvider.overrideWithValue(storage)],
  );
  expect(first.read(mealPreferenceControllerProvider).scenario,
      MealScenario.takeaway);

  first.read(mealPreferenceControllerProvider.notifier)
      .saveScenario(MealScenario.homeCooking);
  expect(first.read(mealPreferenceControllerProvider).scenario,
      MealScenario.homeCooking);
  first.dispose();

  final ProviderContainer restored = ProviderContainer(
    overrides: [localStorageServiceProvider.overrideWithValue(storage)],
  );
  addTearDown(restored.dispose);
  expect(restored.read(mealPreferenceControllerProvider).scenario,
      MealScenario.homeCooking);
  restored.read(mealPreferenceControllerProvider.notifier).clear();
  expect(restored.read(mealPreferenceControllerProvider).scenario,
      MealScenario.takeaway);
});
```

- [ ] **步骤 2：先运行新测试，确认因 Provider 尚不存在而失败。**

运行：

```bash
flutter test test/features/meal_guide/application/meal_preference_controller_test.dart
```

预期：测试无法编译，提示未定义 `mealPreferenceControllerProvider`。

- [ ] **步骤 3：实现最小控制器和仓库 Provider。**

```dart
/// 提供当前本地存储对应的照吃偏好仓库。
final mealPreferenceRepositoryProvider = Provider<MealPreferenceRepository>(
  (Ref ref) => PersistedMealPreferenceRepository(
    ref.watch(localStorageServiceProvider),
  ),
);

/// 管理独立的照吃场景偏好。
final mealPreferenceControllerProvider =
    NotifierProvider<MealPreferenceController, MealPreference>(
  MealPreferenceController.new,
);

class MealPreferenceController extends Notifier<MealPreference> {
  @override
  MealPreference build() {
    return ref.watch(mealPreferenceRepositoryProvider).getPreference();
  }

  /// 保存当前照吃场景。
  void saveScenario(MealScenario scenario) {
    state = ref.read(mealPreferenceRepositoryProvider).savePreference(
          MealPreference(scenario: scenario),
        );
  }

  /// 清除偏好后重新读取仓库默认场景。
  void clear() {
    final MealPreferenceRepository repository =
        ref.read(mealPreferenceRepositoryProvider);
    repository.clearPreference();
    state = repository.getPreference();
  }
}
```

- [ ] **步骤 4：运行控制器测试，确认保存、重启读取和清除通过。**

运行：

```bash
find . -name '._*' -delete
flutter test test/features/meal_guide/application/meal_preference_controller_test.dart
```

预期：全部通过。

- [ ] **步骤 5：提交独立状态实现。**

```bash
git add lib/features/meal_guide/application/meal_preference_controller.dart \
  test/features/meal_guide/application/meal_preference_controller_test.dart
git commit -m "refactor: 独立照吃偏好状态管理"
```

### Task 2：迁移训练兼容桥和照吃页写入

**文件：**
- 修改：`lib/features/dashboard/training_mvp_controller.dart`
- 修改：`lib/features/meal_guide/meal_guide_page.dart`
- 新建：`test/features/meal_guide/application/meal_preference_training_bridge_test.dart`
- 新建：`test/features/meal_guide/meal_guide_page_test.dart`

**接口：**
- 输入：`mealPreferenceControllerProvider` 的 `MealPreference`。
- 输出：旧 `TrainingMvpState.mealScenario`、`activeMealGuide` 和 `coachAdvices` 的同步投影。
- 删除：训练控制器中的 `MealPreferenceRepository` 私有实例、getter 和 `setMealScenario()`。

- [ ] **步骤 1：写出兼容桥测试，先固定必须保留的旧状态。**

```dart
test('照吃偏好控制器同步照吃卡和建议并保留跟练会话', () async {
  final ProviderContainer container = ProviderContainer(
    overrides: [
      localStorageServiceProvider.overrideWithValue(InMemoryLocalStorageService()),
    ],
  );
  addTearDown(container.dispose);
  final TrainingMvpController training =
      container.read(trainingMvpProvider.notifier);
  training.startWorkoutPlayer(workoutDayId: 'workout-week1-day2');
  training.completeWorkoutPlayerStep();
  final TrainingMvpState before = container.read(trainingMvpProvider);

  container.read(mealPreferenceControllerProvider.notifier)
      .saveScenario(MealScenario.homeCooking);
  await Future<void>.delayed(Duration.zero);

  final TrainingMvpState after = container.read(trainingMvpProvider);
  expect(after.mealScenario, MealScenario.homeCooking);
  expect(after.activeMealGuide.scenario, MealScenario.homeCooking);
  expect(after.coachAdvices, contains(contains('按自炊场景执行')));
  expect(after.activeWorkoutPlayerDayId, before.activeWorkoutPlayerDayId);
  expect(after.workoutPlayerStepIndex, before.workoutPlayerStepIndex);
  expect(after.logs, before.logs);
});
```

- [ ] **步骤 2：写出照吃页交互测试。**

```dart
await tester.pumpWidget(
  UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: TDesignTheme.lightTheme, home: const MealGuidePage()),
  ),
);
await tester.tap(find.byType(DropdownButtonFormField<MealScenario>));
await tester.pumpAndSettle();
await tester.tap(find.text('自炊').last);
await tester.pumpAndSettle();

expect(container.read(mealPreferenceControllerProvider).scenario,
    MealScenario.homeCooking);
expect(container.read(trainingMvpProvider).mealScenario,
    MealScenario.homeCooking);
```

- [ ] **步骤 3：先运行两项测试，确认它们因旧写入路径而失败。**

运行：

```bash
flutter test test/features/meal_guide/application/meal_preference_training_bridge_test.dart
flutter test test/features/meal_guide/meal_guide_page_test.dart
```

预期：兼容桥不同步或页面仍调用已删除前的写入路径。

- [ ] **步骤 4：将训练控制器改为监听独立状态。**

删除 `meal_preference_repository.dart` 导入、`_mealPreferenceRepositoryInstance`、
`_mealPreferenceRepository` 和 `setMealScenario()`。添加控制器导入，并在 `build()` 中使用：

```dart
final MealPreference mealPreference =
    ref.read(mealPreferenceControllerProvider);
ref.listen<MealPreference>(
  mealPreferenceControllerProvider,
  (MealPreference? previous, MealPreference next) {
    scheduleMicrotask(() {
      if (!ref.mounted) {
        return;
      }
      final TrainingMvpState nextState = state.copyWith(
        mealScenario: next.scenario,
      );
      state = nextState.copyWith(
        coachAdvices: _aiTrainingService.buildMockCoachAdvice(
          profile: nextState.profile,
          todayWorkout: nextState.todayWorkout,
          todayMealGuide: nextState.activeMealGuide,
          latestLog: nextState.latestLog,
          latestPainLog: nextState.latestPainLog,
        ),
      );
    });
  },
);
```

初始 `TrainingMvpState` 继续以 `mealPreference.scenario` 赋值 `mealScenario`。

- [ ] **步骤 5：将照吃页写入改为独立控制器，并只选择性订阅当前场景。**

```dart
final MealScenario mealScenario = ref.watch(
  mealPreferenceControllerProvider.select(
    (MealPreference preference) => preference.scenario,
  ),
);
// 下拉框使用 initialValue: mealScenario。
ref.read(mealPreferenceControllerProvider.notifier).saveScenario(value);
```

页面仍读取 `trainingMvpProvider` 的 `activeMealGuide` 和 `mealGuides`，不改三种模板卡。

- [ ] **步骤 6：运行桥接与页面测试，确认同步和状态保留通过。**

运行：

```bash
find . -name '._*' -delete
flutter test test/features/meal_guide/application/meal_preference_training_bridge_test.dart
flutter test test/features/meal_guide/meal_guide_page_test.dart
```

预期：全部通过；场景切换会更新照吃卡和建议，跟练会话与日志不变。

- [ ] **步骤 7：提交写入迁移。**

```bash
git add lib/features/dashboard/training_mvp_controller.dart \
  lib/features/meal_guide/meal_guide_page.dart \
  test/features/meal_guide/application/meal_preference_training_bridge_test.dart \
  test/features/meal_guide/meal_guide_page_test.dart
git commit -m "refactor: 将照吃偏好写入迁出训练控制器"
```

### Task 3：拆分仓库测试并完成验收

**文件：**
- 新建：`test/data/repositories/meal_preference_repository_test.dart`
- 修改：`test/widget_test.dart`
- 修改：`README.md`

**接口：**
- 继续测试 `PersistedMealPreferenceRepository.storageKey` 与现有 `MealPreference` JSON。
- `test/widget_test.dart` 不再包含照吃偏好仓库测试或仅为该测试保留的导入。

- [ ] **步骤 1：把仓库测试移至独立文件，并覆盖旧 JSON。**

```dart
test('照吃偏好仓库会兼容旧 JSON 并持久化场景', () {
  final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
  storage.saveJson(PersistedMealPreferenceRepository.storageKey, {
    'schemaVersion': 1,
    'preference': <String, dynamic>{},
  });
  expect(PersistedMealPreferenceRepository(storage).getPreference().scenario,
      MealScenario.takeaway);

  final PersistedMealPreferenceRepository repository =
      PersistedMealPreferenceRepository(storage);
  repository.savePreference(const MealPreference(scenario: MealScenario.canteen));
  expect(PersistedMealPreferenceRepository(storage).getPreference().scenario,
      MealScenario.canteen);
  repository.clearPreference();
  expect(PersistedMealPreferenceRepository(storage).getPreference().scenario,
      MealScenario.takeaway);
});
```

另加一项 `scenario: 'unknown'` 的测试，断言仍回退为外卖。

- [ ] **步骤 2：从 `test/widget_test.dart` 删除已迁出的测试和无用导入。**

运行：

```bash
flutter test test/data/repositories/meal_preference_repository_test.dart
flutter test test/widget_test.dart
```

预期：两个测试入口均通过，迁移前后的断言不丢失。

- [ ] **步骤 3：更新 README 测试说明。**

在测试段落中增加照吃偏好仓库、控制器、兼容桥和照吃页交互覆盖说明；不写死测试数量，
不改变其他 MVP 功能描述。

- [ ] **步骤 4：运行完整验收和迁移断言。**

运行：

```bash
find . -name '._*' -delete
flutter pub get
flutter analyze
flutter test --coverage
flutter build web --no-wasm-dry-run
rg -n "MealPreferenceRepository|_mealPreferenceRepository|setMealScenario" \
  lib/features/dashboard/training_mvp_controller.dart
git status --short
```

预期：前三项 Flutter 命令全部成功；`rg` 无输出；仅出现本计划内文件。

- [ ] **步骤 5：提交测试拆分和验收说明。**

```bash
git add test/data/repositories/meal_preference_repository_test.dart \
  test/widget_test.dart README.md
git commit -m "test: 拆分照吃偏好状态测试"
```
