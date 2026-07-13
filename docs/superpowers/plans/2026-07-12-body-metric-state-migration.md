# 身体记录核心状态迁移实施计划

> **供执行代理使用：** 必须按任务逐项实现、验证和复核；每一项使用复选框跟踪。

**目标：** 将身体指标、修订、确认、截图、CSV、每日签到和清除从训练全局控制器迁移为独立 Riverpod 状态，保持存储和用户行为不变。

**架构：** `BodyMetricController` 拥有身体记录仓库的所有写入，状态保留待确认指标和用户可见文案。`TrainingMvpController` 仅订阅控制器并投影旧字段，只有 `persistenceVersion` 变化时才同步既有成就。导出审计继续留在全局控制器。

**技术栈：** Flutter、flutter_riverpod、shared_preferences、flutter_test。

## 全局约束

- 不新增或升级依赖，不接后端、数据库、穿戴设备、真实 OCR、文件选择器、系统保存或分享。
- 保持 `trainflow.body_metrics.v1`、`schemaVersion: 1`、`metrics`、`revisions`、默认种子指标和旧 JSON 回退不变。
- 保持同日覆盖修订、体重变化超过 2 kg、静息心率偏离 7 日均值至少 20 bpm 的现有规则不变。
- 保持导出审计、导出预览、导出状态、路由、页面文案、趋势/质量/目标/洞察算法不变。
- 所有新增代码注释、测试名称、文档和错误提示使用中文。
- Flutter 命令前先删除外接卷可能生成的 `._*` 文件。

---

### Task 1：建立独立身体记录核心控制器

**文件：**
- 新建：`lib/features/data_center/application/body_metric_controller.dart`
- 新建：`test/features/data_center/application/body_metric_controller_test.dart`

**接口：**
- 输入：`BodyMetricRepository`、既有截图识别服务、既有 CSV 导入服务和 `userProfileControllerProvider`。
- 输出：`bodyMetricRepositoryProvider`、`bodyMetricControllerProvider`、`BodyMetricState` 和七个身体记录写入方法。
- 兼容：状态持有既有 `BodyMetric`、`BodyMetricRevision`、`BodyMetricImportResult`，不改模型或仓库 JSON。

- [x] **步骤 1：写出独立控制器测试。**

```dart
test('保存和重启会保留指标与同日修订', () {
  final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
  final ProviderContainer first = ProviderContainer(
    overrides: [localStorageServiceProvider.overrideWithValue(storage)],
  );
  final BodyMetric initial = first.read(bodyMetricControllerProvider).metrics.first;
  first.read(bodyMetricControllerProvider.notifier).saveManualMetric(
        weightKg: initial.weightKg + 1.0,
        restingHeartRate: initial.restingHeartRate + 2,
        hrvMs: initial.hrvMs,
        sleepHours: initial.sleepHours,
        fatigueLevel: initial.fatigueLevel,
        measuredAt: initial.measuredAt,
      );
  expect(first.read(bodyMetricControllerProvider).revisions, hasLength(1));
  first.dispose();

  final ProviderContainer restored = ProviderContainer(
    overrides: [localStorageServiceProvider.overrideWithValue(storage)],
  );
  addTearDown(restored.dispose);
  expect(restored.read(bodyMetricControllerProvider).revisions, hasLength(1));
});
```

另写独立测试覆盖：异常值先进入 `pendingMetric` 且版本不变；确认后写入并递增版本；截图识别
只待确认；有效和无效 CSV；两种每日签到；清除指标/修订但保留导入历史。

- [x] **步骤 2：先运行新测试，确认 Provider 尚不存在。**

运行：`flutter test test/features/data_center/application/body_metric_controller_test.dart`

预期：无法编译，提示未定义 `bodyMetricControllerProvider`。

- [x] **步骤 3：实现状态、Provider 和控制器。**

```dart
final bodyMetricRepositoryProvider = Provider<BodyMetricRepository>(
  (Ref ref) => PersistedBodyMetricRepository(
    ref.watch(localStorageServiceProvider),
  ),
);

final bodyMetricControllerProvider =
    NotifierProvider<BodyMetricController, BodyMetricState>(
  BodyMetricController.new,
);

class BodyMetricState {
  final List<BodyMetric> metrics;
  final List<BodyMetricRevision> revisions;
  final BodyMetric? pendingMetric;
  final String manualStatusMessage;
  final String snapshotStatusMessage;
  final List<BodyMetricImportResult> importResults;
  final String importStatusMessage;
  final String dailyCheckInStatusMessage;
  final int persistenceVersion;

  const BodyMetricState({
    required this.metrics,
    required this.revisions,
    required this.pendingMetric,
    required this.manualStatusMessage,
    required this.snapshotStatusMessage,
    required this.importResults,
    required this.importStatusMessage,
    required this.dailyCheckInStatusMessage,
    required this.persistenceVersion,
  });

  BodyMetric? get latestMetric => metrics.isEmpty ? null : metrics.first;
}
```

`build()` 从仓库读取指标和修订，使用原全局状态的初始文案：

```dart
return BodyMetricState(
  metrics: repository.listMetrics(),
  revisions: repository.listRevisions(),
  pendingMetric: null,
  manualStatusMessage: '默认预填上次值；可选择今天、昨天或前天补录。',
  snapshotStatusMessage: '可粘贴体脂秤、手表或健康 App 截图中的文字，识别后需确认入库。',
  importResults: const [],
  importStatusMessage: '可粘贴 Apple 健康、手表或表格导出的身体数据 CSV。',
  dailyCheckInStatusMessage: '根据当前画像，今天可以先使用预填签到。',
  persistenceVersion: 0,
);
```

逐字迁入旧规则到以下新方法：

```dart
void saveManualMetric({
  required double weightKg,
  required int restingHeartRate,
  required int hrvMs,
  required double sleepHours,
  required int fatigueLevel,
  DateTime? measuredAt,
  bool forceSave = false,
});
void confirmPendingMetric();
void recognizeSnapshotText(String rawText);
void confirmDailyCheckInSameAsYesterday();
void recordTiredDailyCheckIn();
void importCsv(String rawText);
void clear();
```

保存、确认、每日签到、CSV 和清除后从仓库重新读取 `metrics`/`revisions`，并使
`persistenceVersion` 加一。待确认、截图识别失败和 CSV 格式错误不递增。每日偏累签到通过
`ref.read(userProfileControllerProvider).profile.weightKg` 取得体重兜底。`clear()` 必须保留
`importResults`，并设置文案“身体数据已清除，CSV 导入历史仍保留在本次会话状态中。”。

- [x] **步骤 4：运行控制器测试和静态检查。**

运行：

```bash
find . -name '._*' -delete
flutter test test/features/data_center/application/body_metric_controller_test.dart
flutter analyze
```

预期：测试通过，静态检查无问题。

- [x] **步骤 5：提交独立控制器。**

```bash
git add lib/features/data_center/application/body_metric_controller.dart
git add test/features/data_center/application/body_metric_controller_test.dart
git commit -m "refactor: 独立身体记录核心状态管理"
```

### Task 2：迁移训练兼容桥和页面写入

**文件：**
- 修改：`lib/features/dashboard/training_mvp_controller.dart`
- 修改：`lib/features/data_center/data_center_page.dart`
- 修改：`lib/features/daily_check_in/daily_check_in_page.dart`
- 新建：`test/features/data_center/application/body_metric_training_bridge_test.dart`
- 新建：`test/features/data_center/data_center_page_test.dart`
- 新建：`test/features/daily_check_in/daily_check_in_page_test.dart`

**接口：**
- 输入：`bodyMetricControllerProvider` 的 `BodyMetricState`。
- 输出：旧身体字段投影和既有成就同步。
- 删除：训练控制器中的 `BodyMetricRepository` 实例/getter、身体指标导入和七个已迁移写入方法。

- [x] **步骤 1：写出训练兼容桥回归测试。**

```dart
test('身体记录控制器同步旧状态和成就并保留训练会话', () async {
  final ProviderContainer container = ProviderContainer(
    overrides: [
      localStorageServiceProvider.overrideWithValue(InMemoryLocalStorageService()),
    ],
  );
  addTearDown(container.dispose);
  final TrainingMvpController training =
      container.read(trainingMvpProvider.notifier);
  training.startWorkoutPlayer(workoutDayId: 'workout-week1-day2');
  training.setKnowledgeSearchQuery('跑步');
  training.analyzeMotionCheck(container.read(trainingMvpProvider).featuredMotionCheck.id);
  training.generateWeeklyUserInsightTask();
  final TrainingMvpState before = container.read(trainingMvpProvider);

  container.read(bodyMetricControllerProvider.notifier).saveManualMetric(
        weightKg: before.latestBodyMetric!.weightKg,
        restingHeartRate: before.latestBodyMetric!.restingHeartRate,
        hrvMs: before.latestBodyMetric!.hrvMs,
        sleepHours: before.latestBodyMetric!.sleepHours,
        fatigueLevel: before.latestBodyMetric!.fatigueLevel,
        measuredAt: before.latestBodyMetric!.measuredAt,
      );
  await Future<void>.delayed(Duration.zero);

  final TrainingMvpState after = container.read(trainingMvpProvider);
  expect(after.bodyMetricRevisions.length, before.bodyMetricRevisions.length + 1);
  expect(after.bodyDataQualityReport.metricCount, after.bodyMetrics.length);
  expect(after.activeWorkoutPlayerDayId, before.activeWorkoutPlayerDayId);
  expect(after.knowledgeSearchQuery, before.knowledgeSearchQuery);
  expect(after.motionAnalysisResults.map((item) => item.id),
      before.motionAnalysisResults.map((item) => item.id));
  expect(after.userInsightTableState.latestWeeklyTask?.id,
      before.userInsightTableState.latestWeeklyTask?.id);
});
```

另写截图识别测试：待确认指标同步旧状态但成就记录数量不变；确认后成就同步。

- [x] **步骤 2：先运行桥接和页面测试，确认旧写入路径无法满足新断言。**

运行：

```bash
flutter test test/features/data_center/application/body_metric_training_bridge_test.dart
flutter test test/features/data_center/data_center_page_test.dart
flutter test test/features/daily_check_in/daily_check_in_page_test.dart
```

预期：新 Provider 或页面写入断言失败。

- [x] **步骤 3：将训练控制器改为兼容桥。**

删除 `body_metric_repository.dart` 导入、`_bodyMetricRepositoryInstance`、
`_bodyMetricRepository`、`_bodyMetricSnapshotService`、`_bodyMetricImportService` 和七个已迁移
身体记录方法。保留 `BodyMetricExportRepository` 及导出审计方法。

在 `build()` 中读取初始身体状态并监听变化：

```dart
final BodyMetricState bodyMetricState =
    ref.read(bodyMetricControllerProvider);
ref.listen<BodyMetricState>(
  bodyMetricControllerProvider,
  (BodyMetricState? previous, BodyMetricState next) {
    final bool persisted =
        previous == null || previous.persistenceVersion != next.persistenceVersion;
    scheduleMicrotask(() {
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(
        bodyMetrics: next.metrics,
        bodyMetricRevisions: next.revisions,
        pendingBodyMetric: next.pendingMetric,
        bodyMetricManualStatusMessage: next.manualStatusMessage,
        bodyMetricSnapshotStatusMessage: next.snapshotStatusMessage,
        bodyMetricImportResults: next.importResults,
        bodyMetricImportStatusMessage: next.importStatusMessage,
        dailyCheckInStatusMessage: next.dailyCheckInStatusMessage,
      );
      if (persisted) {
        _syncAchievementRecordsForCurrentState();
      }
    });
  },
);
```

初始 `TrainingMvpState` 必须使用 `bodyMetricState` 的全部八个投影字段；导出审计初始读取
和字段保持原样。

- [x] **步骤 4：迁移数据中心和每日签到页写入入口。**

`DataCenterPage` 新增控制器导入，并把以下调用替换为
`ref.read(bodyMetricControllerProvider.notifier)`：

```dart
saveManualMetric(weightKg: weight, restingHeartRate: restingHr, hrvMs: hrv,
    sleepHours: sleep, fatigueLevel: fatigue, measuredAt: measuredAt);
confirmPendingMetric();
recognizeSnapshotText(ref.read(bodyMetricSnapshotTextProvider));
importCsv(ref.read(bodyMetricCsvImportTextProvider));
clear();
```

`DailyCheckInPage` 的两个按钮分别调用：

```dart
ref.read(bodyMetricControllerProvider.notifier)
    .confirmDailyCheckInSameAsYesterday();
ref.read(bodyMetricControllerProvider.notifier).recordTiredDailyCheckIn();
```

数据读取继续使用 `trainingMvpProvider`，导出审计按钮继续使用原训练控制器。

- [x] **步骤 5：实现页面交互测试。**

数据中心测试挂载 `DataCenterPage`，触发“保存身体数据”或“确认保存异常值”，断言独立
控制器和旧训练投影的指标/待确认状态一致。每日签到测试挂载 `DailyCheckInPage`，点击
“今天偏累，建议轻松版”，断言控制器指标、旧每日签到文案和训练投影同步。

- [x] **步骤 6：运行定向测试和静态检查。**

运行：

```bash
find . -name '._*' -delete
flutter test test/features/data_center/application/body_metric_training_bridge_test.dart
flutter test test/features/data_center/data_center_page_test.dart
flutter test test/features/daily_check_in/daily_check_in_page_test.dart
flutter analyze
```

预期：全部通过；桥接不会重置无关训练状态。

- [x] **步骤 7：提交兼容桥和页面迁移。**

```bash
git add lib/features/dashboard/training_mvp_controller.dart
git add lib/features/data_center/data_center_page.dart
git add lib/features/daily_check_in/daily_check_in_page.dart
git add test/features/data_center/application/body_metric_training_bridge_test.dart
git add test/features/data_center/data_center_page_test.dart
git add test/features/daily_check_in/daily_check_in_page_test.dart
git commit -m "refactor: 将身体记录写入迁出训练控制器"
```

### Task 3：拆分仓库测试并完成验收

**文件：**
- 新建：`test/data/repositories/body_metric_repository_test.dart`
- 修改：`test/widget_test.dart`
- 修改：`README.md`

**接口：**
- 继续验证既有 `PersistedBodyMetricRepository` 的指标、修订和 `trainflow.body_metrics.v1` JSON。
- `test/widget_test.dart` 不再包含身体记录仓库测试或仅由它使用的导入。

- [x] **步骤 1：迁出仓库测试并补齐旧 JSON 覆盖。**

```dart
test('身体记录仓库会兼容缺少列表的旧 JSON', () {
  final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
  storage.saveJson('trainflow.body_metrics.v1', {
    'schemaVersion': 1,
    'metrics': <dynamic>[],
  });
  final PersistedBodyMetricRepository repository =
      PersistedBodyMetricRepository(storage);
  expect(repository.listMetrics(), isEmpty);
  expect(repository.listRevisions(), isEmpty);
});
```

另加 `revisions` 存在但 `metrics` 缺失的旧 JSON；保留并迁出已有种子指标、同日覆盖、修订、
重新读取和清除断言。

- [x] **步骤 2：从 `test/widget_test.dart` 删除已迁出的测试和无用导入。**

运行：

```bash
flutter test test/data/repositories/body_metric_repository_test.dart
flutter test test/widget_test.dart
```

预期：两个入口均通过，导出审计测试仍留在 `widget_test.dart`。

- [x] **步骤 3：更新 README 测试说明。**

在测试说明中补充身体记录仓库、控制器、兼容桥和页面写入覆盖；不写死测试总数，不改变功能
描述或未完成边界。

- [x] **步骤 4：运行完整验收和迁移断言。**

运行：

```bash
find . -name '._*' -delete
flutter pub get
flutter analyze
flutter test --coverage
flutter build web --no-wasm-dry-run
rg -n "BodyMetricRepository|_bodyMetricRepository|saveBodyMetric|confirmPendingBodyMetric|recognizeBodyMetricSnapshotText|confirmDailyCheckInSameAsYesterday|recordTiredDailyCheckIn|clearBodyMetrics|importBodyMetricCsv" lib/features/dashboard/training_mvp_controller.dart
git status --short
```

预期：所有 Flutter 命令成功；`rg` 无输出；导出审计的 `BodyMetricExportRepository` 与相关方法
仍在；工作目录只包含本计划内文件。

- [x] **步骤 5：提交测试拆分和验收说明。**

```bash
git add test/data/repositories/body_metric_repository_test.dart
git add test/widget_test.dart
git add README.md
git commit -m "test: 拆分身体记录核心状态测试"
```
