# TrainMate 电子宠物养成系统实施计划

> **供智能执行者使用：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans`，按任务逐项实施。每个步骤使用复选框跟踪；M1、M2、M3、M4 必须分别通过门禁后才能进入下一阶段。

**目标：** 在不改变现有专业成长 XP、训练处方和健康判断的前提下，把步数、站立小时、运动分钟、活动消耗、有效 TrainMate 训练及用户确认的恢复决策，确定性转换成六种原创运动宠物的本地养成进度。

**架构：** 保持现有 feature-first 分层。HealthKit 只负责返回按自然日聚合的活动摘要；`DailyActivitySummaryRepository` 负责字段来源与人工覆盖；`PetEnergyCalculator` 和 `PetProgressionEngine` 保持纯函数；新的独立 `PetDatabaseGateway` 在同一 SQLite 数据库中完成摘要、能量账本和出战宠物锁定事务；Riverpod `PetController` 只协调事实、仓储和页面状态；`PixelPetRenderer` 用 24×24 位掩码矩阵确定性绘制，不读取仓储。实施按 M1 单宠物垂直切片、M2 六宠物图鉴、M3 互动装扮、M4 完整质量门禁推进。

**技术栈：** Flutter、Dart 3、Riverpod 3、GoRouter、sqflite、Swift、HealthKit、Flutter Canvas、Flutter Widget Test、XCTest；不新增第三方依赖。

## 全局约束

- 当前工作区存在大量未提交修改。每个任务开始和结束都运行 `git status --short`，只触碰本计划列出的文件，不执行 `git reset`、`git checkout --`、批量格式化或无关清理。
- 用户未授权 Git 提交，本计划中的实施不自动 `commit`、`push` 或创建分支；每个里程碑只生成可审查差异和验证记录。
- 数据库从当前 v5 升级到 v6；迁移只新增表和索引，不删除或重命名现有表、列、API 或业务字段。
- 宠物能量不得写入 `GrowthEngine`、成长证据 XP、ACWR、恢复评分、比赛准备度或训练处方。
- `WorkoutPlayerPage`、引导训练播放器、计时、TTS 和媒体区域不得出现 `PixelPetRenderer`、宠物能量或养成提示；训练前提示和训练完成结算允许出现。
- 不做死亡、生病、饥饿、离家、掉级、断签责备、随机抽卡、排行榜、付费数值装扮或宠物云同步。
- 普通 HealthKit 修正只补正差额、不追回；只有用户在 App 内明确确认删除健康数据时，才允许减少对应健康派生能量。
- 当天第一次获得正能量后锁定 `recipient_pet_id`；当天切换伙伴不得转移已经结算的能量。
- 24×24 点阵数据只使用 24 位整数，保证 Dart VM 与 Web 的整数行为一致；普通动画严格两帧、500ms 切换。
- 所有宠物、蛋、轮廓、装扮和训练机均为 TrainMate 原创，不复制拓麻歌子名称、角色、外壳或受保护美术。
- 所有新增文档、代码注释和错误提示使用中文；屏幕阅读器语义必须完整，不以颜色作为唯一信息来源。
- 外置卷验证优先使用 `scripts/run_flutter_tests_clean_copy.sh` 和 `scripts/run_flutter_analyze_clean_copy.sh`，避免 `._native_assets.json` 等 AppleDouble 文件被误判为代码回归。

## 文件职责地图

| 层级 | 文件 | 职责 |
|---|---|---|
| 数据模型 | `lib/data/models/daily_activity_summary.dart` | 每日四项活动、目标、逐字段来源与日期/时区上下文 |
| 数据模型 | `lib/data/models/pet.dart` | 物种、阶段、心情、资料、账本、结算、解锁进度和展示状态 |
| 数据库边界 | `lib/data/local/pet_database_gateway.dart` | 宠物与每日摘要专用数据库接口及事务写入对象 |
| SQLite 实现 | `lib/data/local/sqflite_pet_database_gateway.dart` | 四张新表的查询、幂等结算、首蛋、切换和删除事务 |
| 仓储 | `lib/data/repositories/daily_activity_summary_repository.dart` | HealthKit 合并、人工覆盖、恢复自动同步和目标来源优先级 |
| 仓储 | `lib/data/repositories/pet_repository.dart` | 宠物资料、图鉴、账本、累计能量和删除预览 |
| 纯业务 | `lib/services/pet_energy_calculator.dart` | 20/15/15/10、60/100/160 上限与训练/恢复互斥 |
| 纯业务 | `lib/services/pet_progression_engine.dart` | 五阶段、伙伴星、心情和六物种解锁进度 |
| 纯业务 | `lib/services/pet_goal_suggestion_service.dart` | 14 天中位数建议和保守默认值，不自动应用 |
| 应用状态 | `lib/features/pet/application/daily_activity_sync_controller.dart` | 原生摘要同步、字段合并、补录和恢复自动同步 |
| 应用状态 | `lib/features/pet/application/pet_controller.dart` | 首蛋、出战、结算、解锁、互动和页面聚合状态 |
| 训练桥 | `lib/features/pet/application/pet_training_bridge.dart` | 有效训练、恢复/减量确认与宠物结算之间的窄接口 |
| 点阵渲染 | `lib/features/pet/presentation/pixel_pet_renderer.dart` | LCD 网格、主体、表情、装扮、特效与减少动态效果 |
| 点阵数据 | `lib/features/pet/presentation/pixel_frames/` | 六物种、五阶段、每阶段两帧及目录校验 |
| 页面 | `lib/features/pet/presentation/` | 首蛋、伙伴首页、图鉴、档案、装扮、权限与补录 |
| 原生桥 | `ios/Runner/HealthKitSyncCoordinator.swift` | 步数统计与 `HKActivitySummaryQuery` 的自然日聚合 |
| 路由导航 | `lib/app/router/`、`lib/app/navigation/` | 六项等宽底栏和伙伴页面路由 |

---

## M1：数据底座与衡衡狸垂直切片

### 任务 1：建立每日活动和宠物领域模型

**文件：**
- 新建：`lib/data/models/daily_activity_summary.dart`
- 新建：`lib/data/models/pet.dart`
- 新建测试：`test/data/models/daily_activity_summary_test.dart`
- 新建测试：`test/data/models/pet_test.dart`

**接口：**
- 产出：`DailyActivityField`、`ActivityFieldSource`、`DailyActivitySummary`
- 产出：`PetSpecies`、`PetStage`、`PetMood`、`PetProfile`、`PetCompanion`、`PetDailyEnergy`、`PetSettlementResult`、`PetUnlockProgress`
- 约束：所有日期账本使用 `yyyy-MM-dd` 本地日期字符串；所有持久化时间使用 UTC ISO-8601。

- [x] 先写失败测试，覆盖 nullable 健康字段、逐字段来源、时区偏移、JSON 往返、未知旧枚举值的保守降级，以及 `PetSpecies.balanceRaccoon` 的稳定 ID `balance_raccoon`。
- [x] 运行 `scripts/run_flutter_tests_clean_copy.sh test/data/models/daily_activity_summary_test.dart test/data/models/pet_test.dart`；预期因模型不存在而失败。
- [x] 实现最小模型。核心来源枚举固定为：

```dart
enum ActivityFieldSource {
  healthKit,
  manualOverride,
  derivedGoal,
  unavailable,
}

enum DailyActivityField {
  steps,
  stepGoal,
  activeEnergyKcal,
  activeEnergyGoalKcal,
  exerciseMinutes,
  exerciseGoalMinutes,
  standHours,
  standGoalHours,
}
```

- [x] `DailyActivitySummary` 对数值做非负规范化，但不把缺失值转成 0；`sourceFor(field)` 在来源缺失时返回 `unavailable`。
- [x] `PetSpecies` 固定六项：`windFox`、`jumpRabbit`、`steadyTurtle`、`energyDragon`、`strengthBear`、`balanceRaccoon`；`PetStage` 固定 `patternEgg`、`sprout`、`junior`、`advanced`、`champion`。
- [x] 再次运行上述模型测试，预期全部通过。

### 任务 2：实现能量、阶段、心情和解锁纯函数

**文件：**
- 新建：`lib/services/pet_energy_calculator.dart`
- 新建：`lib/services/pet_progression_engine.dart`
- 新建测试：`test/services/pet_energy_calculator_test.dart`
- 新建测试：`test/services/pet_progression_engine_test.dart`

**接口：**
- `PetEnergyCalculator.calculate(PetEnergyInput input) -> PetEnergyBreakdown`
- `PetProgressionEngine.stageForEnergy(int totalEnergy) -> PetStage`
- `PetProgressionEngine.partnerStars(int totalEnergy) -> int`
- `PetProgressionEngine.moodFor({required int todayEnergy, required int daysSinceLastRecord}) -> PetMood`
- `PetProgressionEngine.unlockProgress(PetSpecies species, PetUnlockFacts facts) -> PetUnlockProgress`

- [x] 先写参数化失败测试：每个日常项覆盖 0、50%、100%、超额、缺失目标和目标为 0；覆盖日常上限 60、训练上限 100、总上限 160、训练与恢复互斥。
- [x] 加入以下边界测试：149/150、899/900、2099/2100、3599/3600；3599 为 0 星、3600 为 0 星、3699 为 0 星、3700 为 1 星。
- [x] 加入六种解锁测试：步数 3 天、运动 3 天、站立 5 天、消耗 3 天、有效训练 3 次、同一自然周四项各 4 天达到 60% 且训练或恢复共 2 次。
- [x] 运行 `scripts/run_flutter_tests_clean_copy.sh test/services/pet_energy_calculator_test.dart test/services/pet_progression_engine_test.dart`；预期因服务不存在而失败。
- [x] 实现能量核心，禁止读取 Riverpod、仓储或系统时间：

```dart
int _scaledEnergy(num? value, num? goal, int maximum) {
  if (value == null || goal == null || goal <= 0) return 0;
  final double ratio = (value / goal).clamp(0, 1).toDouble();
  return (maximum * ratio).floor();
}

final int activityTotal = math.min(
  60,
  stepsEnergy + standEnergy + exerciseEnergy + activeEnergy,
);
final int trainingEnergy = input.hasValidTraining ? 100 : 0;
final int recoveryEnergy = input.hasValidTraining
    ? 0
    : input.hasAcceptedRecoveryDecision
        ? 60
        : 0;
final int total = math.min(
  160,
  activityTotal + math.max(trainingEnergy, recoveryEnergy),
);
```

- [x] 阶段和心情使用闭区间规则：0–149 蛋、150–899 萌芽、900–2099 幼练、2100–3599 进阶、3600+ 冠军；今日 80+ 兴奋、30–79 开心、1–29 好奇、0 且最近两天有记录为平静、连续三天无记录为等待。
- [x] 再次运行上述测试，预期全部通过且不需要 Flutter binding。

### 任务 3：把 SQLite 从 v5 追加迁移到 v6

**文件：**
- 修改：`lib/data/local/trainflow_database_schema.dart`
- 修改：`lib/data/local/sqflite_trainflow_database_gateway.dart`
- 修改测试：`test/data/local/trainflow_database_schema_test.dart`
- 修改测试：`test/data/local/trainflow_database_schema_sqlite_test.dart`

**接口：**
- `TrainFlowDatabaseSchema.version` 从 5 升至 6。
- 新增 `version6UpgradeStatements`，并加入 `creationStatements`。
- 新增四表：`daily_activity_summaries`、`pet_profile`、`pet_collection`、`pet_daily_energy`。
- 新增三索引：`idx_daily_activity_summaries_profile_date`、`idx_pet_collection_profile_unlocked`、`idx_pet_daily_energy_recipient_date`。

- [x] 先写失败测试，断言新安装包含四表三索引，v5 数据库升级后旧训练事实仍在，重复执行 `CREATE ... IF NOT EXISTS` 不报错，`PRAGMA foreign_key_check` 和 `quick_check` 返回正常。
- [x] 运行 `scripts/run_flutter_tests_clean_copy.sh test/data/local/trainflow_database_schema_test.dart test/data/local/trainflow_database_schema_sqlite_test.dart`；预期版本和表集合断言失败。
- [x] 新增与设计规范一致的 SQL；外键和约束固定为：

```sql
CREATE TABLE IF NOT EXISTS daily_activity_summaries (
  athlete_profile_id TEXT NOT NULL,
  local_date TEXT NOT NULL,
  time_zone_name TEXT NOT NULL,
  time_zone_offset_minutes INTEGER NOT NULL,
  steps INTEGER,
  step_goal INTEGER,
  active_energy_kcal REAL,
  active_energy_goal_kcal REAL,
  exercise_minutes INTEGER,
  exercise_goal_minutes INTEGER,
  stand_hours INTEGER,
  stand_goal_hours INTEGER,
  field_sources_json TEXT NOT NULL,
  synced_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (athlete_profile_id, local_date),
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS pet_collection (
  pet_id TEXT PRIMARY KEY,
  athlete_profile_id TEXT NOT NULL,
  species_id TEXT NOT NULL,
  nickname TEXT NOT NULL,
  unlocked_at TEXT NOT NULL,
  born_at TEXT NOT NULL,
  selected_accessory_id TEXT,
  selected_badge_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE (athlete_profile_id, species_id),
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS pet_profile (
  athlete_profile_id TEXT PRIMARY KEY,
  active_pet_id TEXT,
  first_egg_species_id TEXT,
  selected_shell_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id) ON DELETE CASCADE,
  FOREIGN KEY (active_pet_id) REFERENCES pet_collection(pet_id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS pet_daily_energy (
  athlete_profile_id TEXT NOT NULL,
  local_date TEXT NOT NULL,
  recipient_pet_id TEXT NOT NULL,
  steps_energy INTEGER NOT NULL CHECK (steps_energy >= 0),
  stand_energy INTEGER NOT NULL CHECK (stand_energy >= 0),
  exercise_energy INTEGER NOT NULL CHECK (exercise_energy >= 0),
  active_energy INTEGER NOT NULL CHECK (active_energy >= 0),
  training_energy INTEGER NOT NULL CHECK (training_energy >= 0),
  recovery_energy INTEGER NOT NULL CHECK (recovery_energy >= 0),
  calculated_total INTEGER NOT NULL CHECK (calculated_total BETWEEN 0 AND 160),
  awarded_total INTEGER NOT NULL CHECK (awarded_total BETWEEN 0 AND 160),
  source_snapshot_json TEXT NOT NULL,
  model_version INTEGER NOT NULL,
  settled_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (athlete_profile_id, local_date),
  FOREIGN KEY (athlete_profile_id) REFERENCES athlete_profiles(id) ON DELETE CASCADE,
  FOREIGN KEY (recipient_pet_id) REFERENCES pet_collection(pet_id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_daily_activity_summaries_profile_date
ON daily_activity_summaries(athlete_profile_id, local_date DESC);

CREATE INDEX IF NOT EXISTS idx_pet_collection_profile_unlocked
ON pet_collection(athlete_profile_id, unlocked_at ASC);

CREATE INDEX IF NOT EXISTS idx_pet_daily_energy_recipient_date
ON pet_daily_energy(recipient_pet_id, local_date DESC);
```

- [x] 在 `onUpgrade` 中仅当 `oldVersion < 6 && newVersion >= 6` 执行 v6 迁移；把表和索引加入完整性校验集合。
- [x] 再次运行数据库 schema 测试，预期新建、v5→v6、重复打开和旧数据保留全部通过。

### 任务 4：实现独立宠物数据库网关和原子结算

**文件：**
- 新建：`lib/data/local/pet_database_gateway.dart`
- 新建：`lib/data/local/sqflite_pet_database_gateway.dart`
- 修改：`lib/data/local/sqflite_trainflow_database_gateway.dart`
- 修改：`lib/data/local/local_storage_bootstrap_coordinator.dart`
- 修改：`lib/data/local/local_storage_bootstrap_io.dart`
- 修改：`lib/data/local/local_storage_bootstrap_stub.dart`
- 新建测试：`test/data/local/pet_database_gateway_test.dart`

**接口：**
- `PetDatabaseGateway` 只暴露宠物需要的行级读写，不暴露 `Database`。
- `SqfliteTrainFlowDatabaseGateway.createPetDatabaseGateway()` 返回同一数据库连接上的 `SqflitePetDatabaseGateway`。
- `LocalStorageBootstrapResult.petDatabaseGateway` 在 SQLite 可写模式下非空，在 SharedPreferences/Web 降级时为空。
- `settleDay(PetSettlementWrite write)` 在一个 SQLite 事务中写摘要、锁定接收宠物、更新账本并返回正差额。

- [x] 先写失败测试，覆盖：首次首蛋事务、重复首蛋拒绝、同物种唯一、首次正能量锁定、0 能量不锁定、同日切换不转移、重复同步差额为 0、上调只补正差额、普通下调不追回、事务中途失败全部回滚、账号隔离。
- [x] 运行 `scripts/run_flutter_tests_clean_copy.sh test/data/local/pet_database_gateway_test.dart`；预期接口或实现不存在而失败。
- [x] 定义事务对象，明确普通同步和明确删除两种模式：

```dart
enum PetSettlementMode { normalSync, explicitHealthDeletion }

class PetSettlementWrite {
  const PetSettlementWrite({
    required this.summary,
    this.athleteProfileId,
    this.localDate,
    required this.activePetId,
    required this.breakdown,
    required this.sourceSnapshot,
    required this.modelVersion,
    required this.settledAt,
    this.mode = PetSettlementMode.normalSync,
  });

  final DailyActivitySummary? summary;
  final String? athleteProfileId;
  final String? localDate;
  final String activePetId;
  final PetEnergyBreakdown breakdown;
  final Map<String, Object?> sourceSnapshot;
  final int modelVersion;
  final DateTime settledAt;
  final PetSettlementMode mode;
}
```

- [x] 事务算法固定为：先读取旧账本；旧账本存在时始终沿用旧 `recipient_pet_id`；旧账本不存在且计算总量为 0 时只保存摘要、不建账本；普通同步的 `awarded_total = max(old.awarded_total, new.calculated_total)`；明确删除的 `awarded_total = new.calculated_total`。
- [x] `source_snapshot_json` 使用 `jsonEncode` 的排序稳定 Map，不保存 HealthKit 原始逐点样本、音频或位置轨迹。
- [x] `replaceBusinessDataAtomically` 继续通过删除 `athlete_profiles` 的外键级联清除账号内宠物数据；不得把宠物加入云同步 outbox。
- [x] 再次运行网关测试及 schema 测试，预期全部通过。

### 任务 5：实现仓储映射、累计查询和删除预览

**文件：**
- 新建：`lib/data/repositories/daily_activity_summary_repository.dart`
- 新建：`lib/data/repositories/pet_repository.dart`
- 新建测试：`test/data/repositories/daily_activity_summary_repository_test.dart`
- 新建测试：`test/data/repositories/pet_repository_test.dart`

**接口：**
- `DailyActivitySummaryRepository.mergeHealthKitSummary(...)`
- `DailyActivitySummaryRepository.saveManualOverride(...)`
- `DailyActivitySummaryRepository.restoreAutomaticField(...)`
- `PetRepository.chooseFirstEgg(...)`、`settleDay(...)`、`switchActivePet(...)`、`unlockSpecies(...)`
- `PetRepository.loadCompanionState(...)` 从账本 `SUM(awarded_total)` 推导阶段与伙伴星。
- `PetRepository.previewHealthDeletionImpact(...)` 返回受影响日期数和将移除的健康派生能量。

- [x] 先写失败测试，覆盖 row/model 往返、HealthKit 合并不覆盖 `manualOverride`、恢复自动后允许下一次 HealthKit 覆盖、累计能量按 `recipient_pet_id` 聚合、阶段不作为可写列、删除预览不包含训练/恢复奖励。
- [x] 运行 `scripts/run_flutter_tests_clean_copy.sh test/data/repositories/daily_activity_summary_repository_test.dart test/data/repositories/pet_repository_test.dart`；预期仓储不存在而失败。
- [x] 实现仓储；人工覆盖更新单个字段和对应来源，其他字段、日期及时区上下文保持不变。
- [x] 明确缺失值语义：数据库 `NULL + unavailable` 在界面显示“未授权/暂无数据”，不得转成 `0`。
- [x] 再次运行仓储和数据库网关测试，预期全部通过。

### 任务 6：扩展原生 HealthKit 每日活动摘要契约

**文件：**
- 修改：`lib/features/profile/application/health_data_gateway_contract.dart`
- 修改：`lib/features/profile/application/native_healthkit_bridge_io.dart`
- 修改：`lib/features/profile/application/native_healthkit_bridge_stub.dart`
- 修改：`lib/features/profile/application/health_data_gateway.dart`
- 修改：`lib/features/profile/application/health_data_gateway_io.dart`
- 修改：`lib/features/profile/application/health_data_gateway_stub.dart`
- 修改：`ios/Runner/HealthKitSyncCoordinator.swift`
- 修改测试：`test/features/profile/application/health_data_gateway_contract_test.dart`
- 修改测试：`test/features/profile/application/health_data_gateway_io_test.dart`
- 修改测试：`ios/RunnerTests/RunnerTests.swift`

**接口：**
- 新增 `HealthDailyActivitySummaryPayload`，不扩张恢复类 `HealthSnapshot`。
- `NativeHealthKitBridge.fetchDailyActivitySummaries(...)` 和 `HealthDataGateway.fetchDailyActivitySummaries(...)` 返回按本地日期排序的摘要列表。
- MethodChannel 新增 `fetchDailyActivitySummaries`；Web/非 iOS 固定返回空列表，不伪造 0。

- [x] 先写 Dart 失败测试，断言 payload 解析保留 `localDate`、`timeZoneName`、`timeZoneOffsetMinutes`、四项值、三个 Apple 活动目标、逐字段可用性和 `syncedAt`。
- [x] 先写 XCTest，断言 analysis 读取集合包含 `stepCount` 与 `activitySummaryType`，但不把活动摘要加入 anchored observer；断言日历日期和单位映射稳定。
- [x] 运行 Dart 契约测试和 `xcodebuild test` 的 `RunnerTests`；预期新增接口/断言失败。
- [x] Swift 新方法并行执行现有 `HKStatisticsCollectionQuery` 步数累计和 `HKActivitySummaryQuery`，再按 `yyyy-MM-dd + 时区` 合并；禁止把 iPhone 与 Apple Watch 原始步数相加。
- [x] 原生返回字段固定为：

```text
localDate, timeZoneName, timeZoneOffsetMinutes,
steps,
activeEnergyKcal, activeEnergyGoalKcal,
exerciseMinutes, exerciseGoalMinutes,
standHours, standGoalHours,
availableFields, syncedAt
```

- [x] 步数目标不由 Apple 活动圆环提供，原生 payload 不伪造 `stepGoal`；Flutter 仓储按用户确认值、14 天建议或 6000 默认值补齐。
- [x] 逐项查询失败只把对应字段标记不可用；只有整个方法通道失败才返回中文错误，不能把部分授权误报成全部失败。
- [x] 再次运行 Dart 测试和 RunnerTests，预期全部通过。

### 任务 7：实现活动同步、手动补录和目标建议

**文件：**
- 新建：`lib/services/pet_goal_suggestion_service.dart`
- 新建：`lib/features/pet/application/daily_activity_sync_controller.dart`
- 修改：`lib/features/profile/application/health_sync_controller.dart`
- 新建测试：`test/services/pet_goal_suggestion_service_test.dart`
- 新建测试：`test/features/pet/application/daily_activity_sync_controller_test.dart`
- 修改测试：`test/features/profile/application/health_sync_controller_test.dart`

**接口：**
- `PetGoalSuggestionService.suggest(List<DailyActivitySummary>)` 只在至少 14 个有效自然日时返回中位数建议。
- `DailyActivitySyncController.refresh({DateTime? start, DateTime? end})`
- `setManualValue(field, value)`、`setManualGoal(field, value)`、`restoreAutomatic(field)`。
- `HealthSyncController` 成功完成 analysis 前台同步或后台批次排空后，只触发活动摘要刷新信号，不直接计算宠物能量。

- [x] 先写失败测试，覆盖 13 天无建议、14 天中位数、默认目标 6000/10/30/300、建议必须用户确认、手动值优先、逐字段恢复、非 iOS 空 payload、重复刷新幂等。
- [x] 运行 `scripts/run_flutter_tests_clean_copy.sh test/services/pet_goal_suggestion_service_test.dart test/features/pet/application/daily_activity_sync_controller_test.dart test/features/profile/application/health_sync_controller_test.dart`；预期新增控制器不存在而失败。
- [x] 实现 `DailyActivitySyncState`，至少包含 `supported`、`syncing`、`summaries`、`latest`、`suggestedGoals`、`statusMessage`；不使用 `connected == false` 推断用户拒绝了某个具体 HealthKit 字段。
- [x] 首次无历史时保存 `derivedGoal` 默认目标；14 天建议只在页面展示，用户点击确认后以 `manualOverride` 来源持久化。
- [x] 再次运行上述测试，预期全部通过。

### 任务 8：持久化“已应用恢复决策”并建立训练窄桥

**文件：**
- 修改：`lib/data/models/daily_adjustment.dart`
- 修改：`lib/data/repositories/daily_context_repository.dart`
- 修改：`lib/features/daily_adjustment/application/daily_adjustment_controller.dart`
- 新建：`lib/features/pet/application/pet_training_bridge.dart`
- 修改测试：`test/data/repositories/daily_context_repository_test.dart`
- 修改测试：`test/features/daily_adjustment/application/daily_adjustment_controller_test.dart`
- 新建测试：`test/features/pet/application/pet_training_bridge_test.dart`

**接口：**
- `DailyAdjustmentContext` 新增 `List<AppliedDailyDecisionFact> appliedDecisions`，每项保存本地日期、决策类型和确认时间；旧 JSON 缺字段时按空列表兼容。
- 只有用户点击“应用今日调整”后，才写入当天的结构化恢复事实。
- `PetTrainingBridge` 只输出 `hasValidTraining` 与 `hasAcceptedRecoveryDecision`，不写数据库。

- [x] 先写失败测试：普通、技术决策不算恢复；`deload/recovery/rest` 只有事实的 `localDate` 匹配结算日才算；同日重复确认按日期覆盖而非追加；历史最多保留 90 个自然日；旧状态文案中出现“恢复”不得被字符串解析成事实。
- [x] 写有效训练测试，固定条件为：`log.isSessionRecord && !log.abortedByUser && log.normalizedCompletionPercentage >= 50`；`playerStep`、预览、49%、中止均无效；同日多条仍只返回 true。
- [x] 运行 `scripts/run_flutter_tests_clean_copy.sh test/data/repositories/daily_context_repository_test.dart test/features/daily_adjustment/application/daily_adjustment_controller_test.dart test/features/pet/application/pet_training_bridge_test.dart`；预期失败。
- [x] 实现兼容历史并保持 `applyDailyAdjustmentDecision` 的现有调用方式；保存时用本地自然日而非 UTC 日期，按日期去重、按日期排序并裁剪到最近 90 天。
- [x] 再次运行上述测试，预期全部通过。

### 任务 9：实现 PetController、首蛋和幂等结算

**文件：**
- 新建：`lib/features/pet/application/pet_controller.dart`
- 修改：`lib/main.dart`
- 修改：`lib/features/dashboard/training_mvp_controller.dart`
- 修改：`lib/features/daily_adjustment/daily_adjustment_page.dart`
- 新建测试：`test/features/pet/application/pet_controller_test.dart`
- 修改测试：`test/features/daily_adjustment/application/daily_adjustment_training_bridge_test.dart`
- 修改测试：`test/features/training_log/application/training_log_training_bridge_test.dart`

**接口：**
- `petDatabaseGatewayProvider` 默认空；启动层用 `LocalStorageBootstrapResult.petDatabaseGateway` 覆盖。
- `petControllerProvider = AsyncNotifierProvider<PetController, PetState>`。
- `chooseFirstEgg(PetSpecies species)`、`refreshToday()`、`reconcileKnownDates()`、`switchActivePet(String petId)`、`acknowledgeSettlement()`。
- `PetState` 明确区分 `needsFirstEgg`、`ready`、`storageUnavailable`、`readOnly`。

- [x] 先写失败测试，使用内存 fake gateway 覆盖：未选蛋、选择衡衡狸、今日 40 日常 + 首次训练 100 = 140、再次刷新差额 0、额外训练不加、恢复 60 与训练 100 取高、切换后当日接收者不变、次日使用新伙伴。
- [x] 加入延迟和跨时区测试：已知摘要、训练日志和恢复事实日期的并集都参与补算；晚到历史摘要写回原 `localDate`；已存在账本沿用固化时区和接收宠物；切换系统时区不得移动旧账本。
- [x] 写控制器测试，确认普通 HealthKit 下调只改变 `calculatedTotal`、不降低 `awardedTotal`；确认 UI 待展示结算只来自本次 `awardedDelta > 0`。
- [x] 运行 `scripts/run_flutter_tests_clean_copy.sh test/features/pet/application/pet_controller_test.dart test/features/daily_adjustment/application/daily_adjustment_training_bridge_test.dart test/features/training_log/application/training_log_training_bridge_test.dart`；预期失败。
- [x] 实现控制器；`reconcileKnownDates()` 遍历仓储摘要、最多 200 条现有训练日志和 90 天已确认决策的日期并集。无旧账本的历史日期使用结算时的当前伙伴，已有账本始终使用锁定接收者。
- [x] 在训练会话反馈保存和每日调整确认后调用 `unawaited(petController.refreshToday())`，失败只能更新宠物状态，不能阻断训练记录或每日调整原业务。
- [x] 启动层只注入网关，不在 `main.dart` 里写任何宠物业务计算。
- [x] 再次运行上述测试，预期全部通过。

### 任务 10：实现 24×24 LCD 渲染器与衡衡狸五阶段

**文件：**
- 修改：`lib/core/constants/app_colors.dart`
- 新建：`lib/features/pet/presentation/pixel_frames/pixel_frame.dart`
- 新建：`lib/features/pet/presentation/pixel_frames/balance_raccoon_frames.dart`
- 新建：`lib/features/pet/presentation/pixel_frames/pet_frame_catalog.dart`
- 新建：`lib/features/pet/presentation/pixel_pet_renderer.dart`
- 新建测试：`test/features/pet/presentation/pixel_pet_renderer_test.dart`
- 新建测试：`test/features/pet/presentation/pet_frame_catalog_test.dart`

**接口：**
- 新增颜色 Token：`#19172C`、`#11101F`、`#FFB27D`、`#FFE2B8`、`#FFFDFC`、`#A3B58C`、`#98AA80`、`#1C2415`。
- `PixelFrame` 固定 24 行，每行只允许低 24 位。
- `PetFormFrames` 用 `(species, stage)` 唯一索引，包含 `frameA` 与 `frameB`。
- `PixelPetRenderer` 接收物种、阶段、心情、帧索引、装扮层、是否反色和完整语义标签。

- [ ] 先写失败测试：非 24 行、超过 24 位、全空主体、A/B 完全相同均拒绝；衡衡狸五阶段恰好 10 个主体帧；绘制顺序为熄灭网格→主体→表情→装扮→特效。
- [ ] 写 Widget 测试：默认 500ms 后切到 B 帧，1000ms 回到 A 帧；`MediaQuery.disableAnimations == true` 时不切帧、不闪烁。
- [ ] 运行 `scripts/run_flutter_tests_clean_copy.sh test/features/pet/presentation/pixel_pet_renderer_test.dart test/features/pet/presentation/pet_frame_catalog_test.dart`；预期失败。
- [ ] 使用 24 位整数矩阵实现 `PixelFrame`：

```dart
class PixelFrame {
  PixelFrame(List<int> rows)
      : assert(rows.length == 24),
        assert(rows.every((int row) => row >= 0 && row < (1 << 24))),
        rows = List<int>.unmodifiable(rows);

  final List<int> rows;

  bool isOn(int x, int y) => (rows[y] & (1 << x)) != 0;
}
```

- [ ] 为衡衡狸的纹样蛋、萌芽体、幼练体、进阶体、冠军体分别录入两张完整原创 24×24 主体矩阵；冠军体 B 帧必须表达跳绳签名动作。
- [ ] `CustomPainter.shouldRepaint` 只比较可见输入；Canvas 不访问 Provider、仓储或系统时间。
- [ ] 再次运行点阵测试，预期全部通过。

### 任务 11：把主导航改成六项等宽并接入伙伴路由

**文件：**
- 修改：`lib/app/router/app_routes.dart`
- 修改：`lib/app/router/app_router.dart`
- 修改：`lib/app/navigation/main_shell.dart`
- 修改：`lib/app/navigation/trainmate_bottom_navigation.dart`
- 修改：`lib/core/theme/trainflow_tokens.dart`
- 修改测试：`test/navigation_test.dart`
- 修改测试：`test/app/trainmate_back_navigation_test.dart`

**接口：**
- 新增路由：`/pet`、`/pet/collection`、`/pet/archive`、`/pet/wardrobe`、`/pet/data`。
- 一级顺序固定：今日(0)、计划(1)、伙伴(2)、AI(3)、动作(4)、我的(5)。
- `TrainMateBottomNavigation` 改为六个等宽目的地；AI 只保留 24dp 圆形描边图标，不再占据中央悬浮间隙。

- [ ] 先更新失败测试，断言六个可点击目的地、语义顺序 0–5、完整 Tooltip、伙伴路由选中索引 2、AI 路由索引 3、动作检测索引 4、健康相关页面索引 5。
- [ ] 加入 393×852 与 430×932 两个 MediaQuery 尺寸测试，断言无 overflow exception、每项 hit-test 尺寸至少 48dp、标签不横向滚动。
- [ ] 运行 `scripts/run_flutter_tests_clean_copy.sh test/navigation_test.dart test/app/trainmate_back_navigation_test.dart`；预期旧 4+1 结构导致失败。
- [ ] 实现六项 Row；保留现有品牌色、选中动画和减少动态效果；删除中央 `Stack` 空隙但不修改业务路由语义。
- [ ] 再次运行导航测试，预期全部通过。

### 任务 12：完成 M1 首蛋、伙伴首页、补录和训练前后入口

**文件：**
- 新建：`lib/features/pet/presentation/pet_first_egg_page.dart`
- 新建：`lib/features/pet/presentation/pet_home_page.dart`
- 新建：`lib/features/pet/presentation/pet_data_settings_page.dart`
- 新建：`lib/features/pet/presentation/widgets/pet_lcd_device.dart`
- 新建：`lib/features/pet/presentation/widgets/pet_energy_breakdown_card.dart`
- 修改：`lib/features/training_plan/workout_detail_page.dart`
- 修改：`lib/features/workout_player/workout_player_page.dart`
- 新建测试：`test/features/pet/presentation/pet_first_egg_page_test.dart`
- 新建测试：`test/features/pet/presentation/pet_home_page_test.dart`
- 新建测试：`test/features/pet/presentation/pet_data_settings_page_test.dart`
- 新建测试：`test/features/workout_player/pet_training_receipt_test.dart`

**接口：**
- M1 首蛋页先开放衡衡狸垂直切片；M2 同一组件扩展为六颗蛋。
- 伙伴首页顺序固定：标题状态→LCD 设备→能量进度→四项来源→三个实体按钮→权限/补录入口。
- 训练详情页只显示轻量训练前提示；播放器执行态不得出现宠物。
- 有效训练反馈保存后，完成卡显示“主食 +100”或本次实际正差额；动画不超过 2 秒且不阻塞 RPE、疼痛和训练反馈。

- [ ] 先写页面失败测试，覆盖未选蛋→选择→首页、四项未授权显示、手动补录单字段、恢复自动同步、今日结算按钮、下一阶段距离和完整语义。
- [ ] 写训练边界测试：`WorkoutPlayerPage` 未完成/进行中找不到 `PixelPetRenderer`；完成且已有有效 session review 时恰好一个宠物结算卡；49% 不展示 +100。
- [ ] 运行 `scripts/run_flutter_tests_clean_copy.sh test/features/pet/presentation test/features/workout_player/pet_training_receipt_test.dart`；预期页面不存在而失败。
- [ ] 实现页面，所有补录输入校验使用中文错误；按钮点击区至少 48dp；未授权值显示“未授权”，不能显示“0 步”。
- [ ] 结算动画使用控制器提供的 `awardedDelta`，结束后调用 `acknowledgeSettlement()`；减少动态效果时直接显示稳定结果。
- [ ] 再次运行上述页面测试，并运行 `scripts/run_flutter_tests_clean_copy.sh test/features/workout_player`；预期通过。

#### M1 门禁

- [ ] 运行任务 1–12 的所有定向测试，确认能量、迁移、原生契约、单宠物、导航和训练边界全部通过。
- [ ] 运行 `scripts/run_flutter_analyze_clean_copy.sh`，确认无本次新增诊断。
- [ ] 在 393px iOS 模拟器手动完成“选衡衡狸→补录→结算→完成 50% 训练→重开 App”，确认账本不重复、训练中无宠物。
- [ ] 只在 M1 通过后进入 M2；失败时修复当前任务，不提前制作其余 50 帧。

---

## M2：六宠物图鉴与 60 帧

### 任务 13：实现六物种目录、首蛋选择和里程碑解锁

**文件：**
- 新建：`lib/features/pet/domain/pet_species_catalog.dart`
- 修改：`lib/services/pet_progression_engine.dart`
- 修改：`lib/features/pet/application/pet_controller.dart`
- 修改：`lib/features/pet/presentation/pet_first_egg_page.dart`
- 修改测试：`test/services/pet_progression_engine_test.dart`
- 修改测试：`test/features/pet/application/pet_controller_test.dart`
- 修改测试：`test/features/pet/presentation/pet_first_egg_page_test.dart`

**接口：**
- 六物种目录固定包含中文名、习惯主题、解锁文案、轮廓语义和冠军动作，不包含稀有度或随机权重。
- `PetController.refreshUnlocks()` 根据事实集合补齐 `pet_collection`；已解锁物种不重复创建。

- [ ] 先写失败测试，断言首蛋页恰好六颗蛋且任一可首选；首选物种绕过里程碑；其他五种按规范条件解锁；同一事实重复刷新不新增宠物。
- [ ] 写自然周边界测试：周一至周日为同一周，跨周数据不能拼接解锁衡衡狸；时区使用摘要固化的本地日期。
- [ ] 运行 `scripts/run_flutter_tests_clean_copy.sh test/services/pet_progression_engine_test.dart test/features/pet/application/pet_controller_test.dart test/features/pet/presentation/pet_first_egg_page_test.dart`；预期失败。
- [ ] 实现稳定目录和解锁协调；默认昵称使用物种中文名，用户后续可编辑；`bornAt` 与 `unlockedAt` 只在首次插入时写入。
- [ ] 再次运行上述测试，预期全部通过。

### 任务 14：补齐六物种五阶段共 60 个主体帧

**文件：**
- 新建：`lib/features/pet/presentation/pixel_frames/wind_fox_frames.dart`
- 新建：`lib/features/pet/presentation/pixel_frames/jump_rabbit_frames.dart`
- 新建：`lib/features/pet/presentation/pixel_frames/steady_turtle_frames.dart`
- 新建：`lib/features/pet/presentation/pixel_frames/energy_dragon_frames.dart`
- 新建：`lib/features/pet/presentation/pixel_frames/strength_bear_frames.dart`
- 修改：`lib/features/pet/presentation/pixel_frames/pet_frame_catalog.dart`
- 修改测试：`test/features/pet/presentation/pet_frame_catalog_test.dart`
- 新建测试：`test/features/pet/presentation/pet_frame_visual_contract_test.dart`

**接口：**
- 目录必须恰好包含 `6 × 5 = 30` 个 `PetFormFrames` 和 `60` 个非空、可区分主体帧。
- 冠军签名动作固定：狐跑步、兔开合跳、龟单腿平衡、龙冲刺、熊哑铃肩推、狸跳绳。

- [ ] 先写目录失败测试，遍历 `PetSpecies.values × PetStage.values`，断言无缺项、无重复键、A/B 不同、每帧点亮像素数量在 12–280 之间、边缘保留至少 1 像素安全区。
- [ ] 写黄金语义测试：每物种五阶段轮廓的 bounding box 随阶段不缩回到蛋阶段；冠军体包含其签名器械/动作层标记。
- [ ] 运行 `scripts/run_flutter_tests_clean_copy.sh test/features/pet/presentation/pet_frame_catalog_test.dart test/features/pet/presentation/pet_frame_visual_contract_test.dart`；预期目录缺 50 帧而失败。
- [ ] 为其余五物种逐一录入五阶段两帧原创 24×24 矩阵；不通过旋转、镜像同一角色冒充不同物种。
- [ ] 生成本地测试总览 Widget（仅测试/QA 使用）逐帧目视审核；发现肢体断裂、动作不清或碰边时只修改对应物种矩阵。
- [ ] 再次运行点阵目录和视觉契约测试，预期全部通过。

### 任务 15：实现图鉴、档案、昵称和出战切换

**文件：**
- 新建：`lib/features/pet/presentation/pet_collection_page.dart`
- 新建：`lib/features/pet/presentation/pet_archive_page.dart`
- 新建：`lib/features/pet/presentation/widgets/pet_stage_timeline.dart`
- 修改：`lib/features/pet/application/pet_controller.dart`
- 修改：`lib/app/router/app_router.dart`
- 新建测试：`test/features/pet/presentation/pet_collection_page_test.dart`
- 新建测试：`test/features/pet/presentation/pet_archive_page_test.dart`
- 修改测试：`test/navigation_test.dart`

**接口：**
- 图鉴展示六项：已解锁显示当前形态，未解锁显示明确计数进度。
- 档案展示累计能量、阶段、出生时间、7/30 天来源、伙伴星和五阶段时间线。
- `renamePet` 只改昵称；`switchActivePet` 改 `pet_profile.active_pet_id`，不改当日已锁定账本。

- [ ] 先写失败测试，覆盖六项唯一、未解锁进度、昵称去空白且长度 1–12、切换后首页宠物变化、当日账本仍显示原接收者、下一日结算给新伙伴。
- [ ] 运行 `scripts/run_flutter_tests_clean_copy.sh test/features/pet/presentation/pet_collection_page_test.dart test/features/pet/presentation/pet_archive_page_test.dart test/navigation_test.dart`；预期失败。
- [ ] 实现图鉴和档案；当日已锁定但切换伙伴时显示非责备说明：“今日已获得的能量仍归原伙伴，新的活动日期将由当前伙伴接收。”
- [ ] 再次运行页面与导航测试，预期全部通过。

#### M2 门禁

- [ ] 运行 `scripts/run_flutter_tests_clean_copy.sh test/features/pet test/services/pet_progression_engine_test.dart test/data/local/pet_database_gateway_test.dart`。
- [ ] 运行点阵目录检查，确认 30 个形态、60 个主体帧、六个冠军签名动作均存在且每个只出现一次。
- [ ] 在 393px 与 430px 视口目视检查六颗蛋、六项图鉴、档案时间线和切换说明。

---

## M3：互动、心情、伙伴星与装扮

### 任务 16：实现确定性心情覆盖层和三种互动

**文件：**
- 新建：`lib/features/pet/presentation/pixel_frames/pet_expression_layers.dart`
- 新建：`lib/features/pet/presentation/pixel_frames/pet_effect_layers.dart`
- 修改：`lib/features/pet/presentation/pixel_pet_renderer.dart`
- 修改：`lib/features/pet/application/pet_controller.dart`
- 修改：`lib/features/pet/presentation/pet_home_page.dart`
- 新建测试：`test/features/pet/presentation/pet_interaction_test.dart`
- 修改测试：`test/features/pet/presentation/pixel_pet_renderer_test.dart`

**接口：**
- 互动固定为：呼唤昵称、练一个动作、查看状态；互动不写能量。
- 表情来自 `PetMood`，不持久化惩罚数值。
- 结算闪烁 2 次、进化反色 8 次，最长 2 秒；减少动态效果时直接显示最终帧。

- [ ] 先写失败测试，连续点击互动后 `awardedTotal` 不变；呼唤只触发转身/抬头层；练动作只切到第二帧；查看状态只打开摘要。
- [ ] 写动画测试，断言 500ms 帧节奏、结算/进化次数和 2 秒上限；禁用动画时计时器不创建。
- [ ] 运行 `scripts/run_flutter_tests_clean_copy.sh test/features/pet/presentation/pet_interaction_test.dart test/features/pet/presentation/pixel_pet_renderer_test.dart`；预期失败。
- [ ] 实现覆盖层和一次性 UI 事件；控制器销毁时取消计时器，避免离页后 setState。
- [ ] 再次运行互动和渲染测试，预期全部通过。

### 任务 17：实现伙伴星、TrainMate Lv.装扮和装扮柜

**文件：**
- 新建：`lib/features/pet/domain/pet_cosmetic_catalog.dart`
- 新建：`lib/features/pet/presentation/pixel_frames/pet_accessory_layers.dart`
- 新建：`lib/features/pet/presentation/pet_wardrobe_page.dart`
- 修改：`lib/features/pet/application/pet_controller.dart`
- 修改：`lib/features/pet/presentation/pixel_pet_renderer.dart`
- 新建测试：`test/features/pet/domain/pet_cosmetic_catalog_test.dart`
- 新建测试：`test/features/pet/presentation/pet_wardrobe_page_test.dart`

**接口：**
- TrainMate Lv.只解锁头带、奖牌和训练机外壳；伙伴星只解锁额外动作帧和纯外观层。
- 当前 Lv.读取 `growthEvidenceControllerProvider.levelState.peakLevel`，不修改 `GrowthEngine`。
- 装扮选择持久化到 `pet_profile` 或 `pet_collection` 现有字段，不维护消费余额。

- [ ] 先写失败测试，覆盖 Lv.门槛、伙伴星门槛、锁定项不可选择、已解锁项选择与重开恢复、装扮不改变能量和阶段。
- [ ] 运行 `scripts/run_flutter_tests_clean_copy.sh test/features/pet/domain/pet_cosmetic_catalog_test.dart test/features/pet/presentation/pet_wardrobe_page_test.dart test/services/growth_engine_test.dart`；预期新目录失败，既有 GrowthEngine 行为必须保持通过。
- [ ] 实现稳定装扮目录，每项包含 ID、中文名、来源类型、门槛和覆盖层；不加入价格、倍率、稀有度。
- [ ] 再次运行上述测试，确认宠物装扮通过且 `GrowthEngine` 无行为变化。

#### M3 门禁

- [ ] 运行全部宠物测试并确认互动不会刷能量、心情不惩罚、装扮无属性。
- [ ] 开启和关闭“减少动态效果”各检查一次结算、进化和普通两帧。
- [ ] 检查 6 个物种在 5 种心情和至少 3 类装扮下无像素越界。

---

## M4：隐私、恢复、无障碍与完整质量门禁

### 任务 18：实现健康删除传播、宠物全删和只读恢复

**文件：**
- 修改：`lib/data/local/trainmate_structured_database_gateway.dart`
- 修改：`lib/data/local/sqflite_trainflow_database_gateway.dart`
- 修改：`lib/data/local/sqflite_pet_database_gateway.dart`
- 修改：`lib/features/profile/application/health_data_deletion_coordinator.dart`
- 修改：`lib/features/profile/profile_page.dart`
- 修改：`lib/features/auth/application/account_switch_coordinator.dart`
- 修改：`lib/data/local/local_storage_bootstrap_coordinator.dart`
- 修改：`lib/data/local/local_storage_bootstrap_io.dart`
- 修改：`lib/app/startup/local_storage_recovery_page.dart`
- 新建：`lib/features/pet/presentation/pet_data_rights_page.dart`
- 修改测试：`test/features/profile/application/health_data_deletion_coordinator_test.dart`
- 修改测试：`test/features/profile/profile_health_permissions_test.dart`
- 修改测试：`test/features/auth/account_switch_coordinator_test.dart`
- 修改测试：`test/data/local/local_storage_bootstrap_coordinator_test.dart`
- 修改测试：`test/app/startup/local_storage_recovery_page_test.dart`

**接口：**
- 健康删除预览显示受影响日期数与健康派生能量，不把训练/恢复奖励算入将删除值。
- 用户确认健康删除后，在现有结构化事务中删除 `daily_activity_summaries`，把账本四项活动能量归零，并将 `calculated_total/awarded_total` 重算为训练与恢复两者最大值；保留宠物资料、昵称、已解锁图鉴和装扮。
- “删除全部宠物数据”只删除 `pet_profile`、`pet_collection`、`pet_daily_energy`；不删除训练记录和 Apple 健康原始数据。
- 只读恢复提供 `PetRecoverySnapshot`，允许从恢复页进入只读伙伴视图；所有结算、补录、切换、改名和装扮按钮禁用。

- [ ] 先写失败测试，构造 40 活动 +100 训练的同日账本；健康删除后保留 100、累计能量减少 40、昵称和图鉴仍在，事务失败时两边都不变。
- [ ] 写全删测试，确认宠物三表清空但训练事实、成长 XP 和每日健康原始事实保持；再次进入回到首蛋选择。
- [ ] 写账号切换测试，确认旧账号 Provider 全部失效、新账号看不到旧宠物；返回旧账号后只读取其本地隔离数据，不从云端上传宠物。
- [ ] 写只读恢复测试，确认恢复快照可展示且所有写操作被中文错误“只读恢复状态下不能修改伙伴数据。”拒绝。
- [ ] 运行相关五组测试；预期失败。
- [ ] 实现删除 SQL 和恢复快照；SQLite 只读打开失败时只显示现有恢复说明，不清空数据库、不退回陈旧 SharedPreferences 宠物副本。
- [ ] 更新删除确认文案，明确“会减少由这些健康摘要产生的伙伴能量，但保留训练奖励、昵称和已解锁伙伴”。
- [ ] 再次运行相关测试，预期全部通过。

### 任务 19：完成无障碍、宽度、性能和跨平台回归

**文件：**
- 修改：`test/navigation_test.dart`
- 修改：`test/features/pet/presentation/pet_home_page_test.dart`
- 修改：`test/features/pet/presentation/pet_collection_page_test.dart`
- 修改：`test/features/pet/presentation/pixel_pet_renderer_test.dart`
- 新建：`test/features/pet/presentation/pet_accessibility_test.dart`
- 新建：`test/features/pet/presentation/pet_no_training_overlay_test.dart`
- 新建：`docs/qa/2026-08-01-TrainMate电子宠物验收报告.md`

**接口：**
- LCD 语义格式至少包含：昵称、物种、阶段、心情、今日能量、下一阶段距离。
- 屏幕阅读器顺序：状态→主画面→进度→今日来源→操作按钮。
- 所有交互点击区至少 48dp；393px、430px 和最大文字缩放无横向溢出。

- [ ] 写无障碍失败测试，读取 Semantics 树并断言完整中文标签、六项导航顺序、未授权不只靠颜色、装扮锁定原因可读。
- [ ] 写“训练中零宠物”全路由测试，覆盖 `WorkoutPlayerPage`、`GuidedWorkoutPlayerPage`、计时和媒体区域，断言不存在 `PixelPetRenderer` 与宠物能量文案。
- [ ] 写性能基线测试：稳定帧下 `PixelPetPainter.shouldRepaint == false`；离屏页面无活动 Timer；目录加载不做文件 I/O 或 JSON 解析。
- [ ] 运行 `scripts/run_flutter_tests_clean_copy.sh test/features/pet test/navigation_test.dart test/features/workout_player test/features/guided_workout`，预期全部通过。
- [ ] 运行 `scripts/run_flutter_analyze_clean_copy.sh`，预期无新增错误或警告。
- [ ] 运行完整测试：`scripts/run_flutter_tests_clean_copy.sh`；若存在任务外基线失败，记录文件、断言和与本任务无关的证据，不修改无关功能掩盖失败。
- [ ] 运行 `flutter build web --no-pub`，确认 24 位矩阵和纯计算可通过 dart2js；Web 宠物页显示“当前平台不支持 Apple 健康，可查看规则但不结算持久化伙伴”，不得伪造健康数据。
- [ ] 运行 `flutter build ios --simulator --debug --no-codesign --no-pub`，确认生成当前源码的 Simulator App。
- [ ] 运行：

```bash
xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=TrainFlow iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

- [ ] 在同一台 393px Simulator 安装并重新启动刚构建的 App，逐页截图：首蛋、伙伴首页、图鉴、档案、装扮、补录、训练前、训练完成、只读恢复；不能用旧进程画面充当新构建证据。
- [ ] 在 430px Simulator 重复检查六项底栏、最大文字缩放、横竖屏恢复、减少动态效果和 VoiceOver 焦点顺序。
- [ ] 真机 iPhone + Apple Watch 验证四项授权、部分授权、重复/延迟同步、后台后前台结算、跨时区和 App 重启；把设备、系统版本、实际数据日期、预期/实际差额写入验收报告。

## 最终完成检查

- [ ] 六种原创宠物、五阶段、每阶段两帧，共 30 个形态和 60 个主体帧，目录测试与人工审核均通过。
- [ ] 四项日常活动、有效训练、恢复/减量确认均按固定公式结算；重复同步、额外训练和当日切换不重复发放。
- [ ] HealthKit 普通修正不追回；App 内明确健康删除会以事务方式移除健康派生能量并保留训练奖励。
- [ ] 专业成长 XP、训练处方、恢复评分、ACWR 和比赛准备度测试无行为变化。
- [ ] 伙伴相关页面可达，训练进行页无宠物，训练完成动画不超过 2 秒。
- [ ] 六项底栏在 393px、430px、最大文字缩放和 VoiceOver 下工整可用。
- [ ] SQLite v5→v6、新安装、账号隔离、只读恢复和关闭重开均有自动化或真机证据。
- [ ] `flutter analyze`、定向测试、完整测试、Web 构建、iOS Simulator 构建和 RunnerTests 的实际结果写入 `docs/qa/2026-08-01-TrainMate电子宠物验收报告.md`。
- [ ] `git diff --name-only` 只包含本计划授权的宠物、HealthKit、导航、训练边界、数据权利、测试和 QA 文件；无依赖升级、后端改动、公共云协议或无关格式化。
