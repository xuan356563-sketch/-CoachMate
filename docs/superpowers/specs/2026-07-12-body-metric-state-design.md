# 身体记录核心状态迁移设计

## 背景

当前 `TrainingMvpController` 直接构造 `PersistedBodyMetricRepository`，同时负责指标
读取、同日覆盖修订、异常值确认、截图文字识别、CSV 导入、每日签到和清除。身体记录的
派生趋势、质量报告、目标和洞察又依赖旧 `TrainingMvpState` 的身体数据字段。

本切片将身体记录核心迁出全局训练控制器，保持旧状态字段为兼容投影。身体数据导出审计
使用独立的 `BodyMetricExportRepository`，不属于本切片，继续保持原实现。

## 目标

- 新建独立 Riverpod 控制器，拥有身体指标、修订留痕、待确认指标和相关状态文案。
- 迁移 10 秒快录、异常确认、截图识别 Mock、CSV 导入、两种每日签到和清除操作。
- 保持 `trainflow.body_metrics.v1`、`schemaVersion: 1`、`metrics`、`revisions`、默认种子
  指标、同日覆盖留痕与异常阈值不变。
- 让 `TrainingMvpState` 的身体字段继续可用，使趋势、质量报告、目标、洞察、首页和既有
  页面不需要重写读取逻辑。
- 在实际持久化身体数据后继续同步既有成就记录，但不重置跟练会话、训练计划、导出审计、
  知识搜索、动作分析或用户画像状态。

## 非目标

- 不迁移 `BodyMetricExportRepository`、JSON/CSV/导出包审计、导出预览输入状态或清除导出
  记录操作。
- 不新增穿戴设备接入、真实 OCR、相册权限、文件选择器、系统保存、分享、后端或数据库。
- 不修改指标模型、种子数据、质量算法、趋势算法、目标算法、页面文案、路由或依赖。

## 接口

新增 `lib/features/data_center/application/body_metric_controller.dart`：

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
}

class BodyMetricController extends Notifier<BodyMetricState> {
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
}
```

`bodyMetricRepositoryProvider` 默认创建
`PersistedBodyMetricRepository(ref.read(localStorageServiceProvider))`。控制器私有复用既有
`BodyMetricSnapshotRecognitionService`、`BodyMetricImportService` 和异常值计算规则，不新增
服务或数据结构。

`persistenceVersion` 是控制器内部的单调计数：只有保存、确认、每日签到、CSV 导入或清除
实际影响仓库后才递增。它不写入本地 JSON，也不展示给用户；兼容桥用它判断何时同步成就，
避免截图识别和异常待确认等未持久化操作触发副作用。

## 兼容桥

`TrainingMvpController` 移除 `BodyMetricRepository` 私有实例、getter、身体指标导入和所有
身体记录写入方法。`build()` 读取并监听 `bodyMetricControllerProvider`。

初始和监听投影以下旧字段：

- `bodyMetrics`
- `bodyMetricRevisions`
- `pendingBodyMetric`
- `bodyMetricManualStatusMessage`
- `bodyMetricSnapshotStatusMessage`
- `bodyMetricImportResults`
- `bodyMetricImportStatusMessage`
- `dailyCheckInStatusMessage`

监听回调只复制上述字段。若 `persistenceVersion` 变化，兼容桥在投影后调用现有
`_syncAchievementRecordsForCurrentState()`；否则不写成就。导出审计字段、训练播放器、训练
计划调整、资料、每日调整、知识查询、动作分析、用户画像和周报字段必须原样保留。

趋势、质量报告、目标、洞察和导出内容继续通过 `TrainingMvpState` 的现有派生 getter 使用
投影后的 `bodyMetrics`，不迁移算法。

## 页面写入

`DataCenterPage` 的 10 秒快录、异常确认、截图识别、截图确认、CSV 导入和清除身体数据
调用新控制器；所有显示内容仍读取 `trainingMvpProvider`，导出审计按钮继续调用训练控制器。

`DailyCheckInPage` 的“和昨天一样”和“今天偏累”改为调用新控制器。输入文本 Provider、
趋势窗口 Provider、导出预览 Provider 和页面结构不改变。

## 数据兼容和安全

仓库现有行为必须保持：没有本地 JSON 时加载种子指标；存储 JSON 缺少 `metrics` 或
`revisions` 时回退为空列表；同一日期保存新指标时写入修订留痕；`clear()` 同时清除指标与
修订，但不触碰导出审计；体重较最近记录变化超过 2 kg、静息心率偏离 7 日均值至少 20 bpm
时先生成待确认指标。

截图识别、异常待确认和 CSV 格式错误只更新控制器状态文案，不写入仓库、不增加成就、也不
清除既有指标。每日签到“和昨天一样”在没有指标时只更新提示文案。

## 测试与验收

新增或拆分：

1. `test/data/repositories/body_metric_repository_test.dart`：把仓库测试从
   `test/widget_test.dart` 迁出，覆盖种子指标、同日覆盖、修订留痕、重新读取、清除和缺失
   `metrics`/`revisions` 的旧 JSON。
2. `test/features/data_center/application/body_metric_controller_test.dart`：使用
   `InMemoryLocalStorageService` 覆盖存储，覆盖保存、异常待确认与确认、截图识别、CSV 导入、
   每日签到、清除和跨容器重启读取。
3. `test/features/data_center/application/body_metric_training_bridge_test.dart`：验证保存后旧
   身体字段、质量和趋势派生结果以及成就同步；验证截图待确认不会同步成就；验证跟练会话、
   计划调整、导出审计、知识查询、动作分析和用户画像保持不变。
4. `test/features/data_center/data_center_page_test.dart` 与
   `test/features/daily_check_in/daily_check_in_page_test.dart`：验证页面写入新控制器并同步旧
   投影。

完整验收必须通过：

```bash
flutter pub get
flutter analyze
flutter test --coverage
flutter build web --no-wasm-dry-run
```

并确认 `TrainingMvpController` 不再直接依赖 `BodyMetricRepository`，也不定义已迁移的身体
记录写入方法；活跃代码没有改变导出审计或存储 JSON 结构。
