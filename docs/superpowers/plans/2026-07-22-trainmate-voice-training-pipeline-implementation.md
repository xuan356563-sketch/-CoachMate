# TrainMate 语音记录训练回执管线实施计划

> **供执行代理使用：** 实施时必须使用 `superpowers:executing-plans`，按任务逐项完成；每个任务遵循测试先行。未经用户明确授权，不提交、不推送、不创建分支。

**目标：** 在 TrainMate iOS 中实现“一句话记录训练”的本地闭环，在必要时用卡片消歧，并复用现有 TrainingLog、HealthKit 结构化事实、成长证据、XP 与训练指标管线生成可撤销回执。

**架构：** 新功能位于 `lib/features/voice_training/`，由领域模型、规则解析器、HealthKit 候选匹配器、Riverpod 会话编排器和页面组成。现有 iOS `SFSpeechRecognizer`、SQLite `workouts`、`GrowthEngine` 与 `TrainingGrowthReceipt` 继续作为唯一事实链；不新增 `training_receipts` 第二套模型，也不调用云端 LLM。

**技术栈：** Flutter、Dart、Riverpod、GoRouter、sqflite、iOS Speech、现有 HealthKit MethodChannel 与成长系统。

## 全局约束

- v1 只支持简体中文 `log_workout`；查询、周报、修改等意图返回 `unsupported`。
- iOS 提供完整语音与 HealthKit 闭环；Android/Web 保留文字手动入口和明确降级，不伪造语音或 HealthKit 能力。
- 不新增第三方依赖；UUID v4 使用 `Random.secure()` 的 16 字节本地实现。
- 规则解析超时为 2 秒；必填槽位为运动类型和发生时间；RPE 必须由用户明确表达或确认。
- 同一时刻全局最多一条 `pending` 会话；新会话原子地放弃旧会话。
- `completed`、`abandoned`、`unsupported` 以及用户放弃重试后的 `failed` 会话必须清空 `raw_transcript` 并写入 `redacted_at`；可重试 `failed` 暂存原文。
- 原始音频不落盘、不上传；转写、槽位、会话和回执数据纳入账号切换、健康数据删除与本地整库清理。
- 保留现有软删除、成长峰值等级与不可变报告规则；撤销只回退当前有效证据，不降低历史峰值等级。
- 当前工作树已有大量未提交修改；每项实施前重新检查 `git status --short`，只修改本计划列出的文件。

---

## 文件结构

### 新增

- `lib/features/voice_training/domain/voice_training_models.dart`：会话、槽位、解析结果、候选与状态机类型。
- `lib/features/voice_training/domain/voice_intent_parser.dart`：中文规则解析与本地模型兜底接口。
- `lib/features/voice_training/domain/voice_workout_matcher.dart`：候选评分、排序与分档。
- `lib/features/voice_training/data/voice_training_database_gateway.dart`：语音会话查询、原子提交、撤销接口和提交 DTO。
- `lib/features/voice_training/application/voice_training_controller.dart`：Riverpod 编排、全局锁、解析、匹配、消歧、提交、重试与撤销。
- `lib/features/voice_training/presentation/voice_training_page.dart`：录音、文字降级、消歧、手动表单和回执页面。
- `lib/features/voice_training/presentation/voice_disambiguation_cards.dart`：候选训练、运动、时间和 RPE 卡片。
- `test/features/voice_training/`：解析、匹配、状态机、控制器和页面测试。
- `test/data/local/voice_training_database_gateway_test.dart`：迁移、幂等、原子提交、脱敏与撤销测试。

### 修改

- `lib/data/local/trainflow_database_schema.dart`：数据库版本 3 升 4，增加 `voice_sessions` 与索引。
- `lib/data/local/sqflite_trainflow_database_gateway.dart`：实现语音数据库能力和事务提交/撤销。
- `lib/data/local/trainmate_structured_database_gateway.dart`：仅补充语音功能需要的结构化查询/写入边界，不暴露 SQLite 对象。
- `lib/data/models/training_log.dart`：增加 `TrainingLogKind.voice`、`voiceSessionId`、来源兼容序列化。
- `lib/features/growth/application/growth_evidence_controller.dart`：增加提交后刷新与撤销后重算的公共入口。
- `lib/features/ai_center/application/voice_input_gateway*.dart`：保留现有 MethodChannel 契约，补充状态可测试性；不重写 Swift STT。
- `lib/app/router/app_routes.dart`、`lib/app/router/app_router.dart`：增加 `/voice-training`。
- `lib/app/navigation/main_shell.dart`：全局悬浮按钮展开“语音记训练 / AI 中心”。
- `lib/features/auth/application/account_switch_coordinator.dart`、`lib/features/profile/application/health_data_deletion_coordinator.dart`：清理或终止语音会话。
- `ios/Runner/Info.plist`、`ios/Runner/AppDelegate.swift`：原则上只核验；仅在权限文案或生命周期清理缺口存在时做最小修改。

---

### 任务 1：锁定数据库 v4 与语音会话持久化边界

**文件：**

- 修改：`lib/data/local/trainflow_database_schema.dart`
- 新增：`lib/features/voice_training/data/voice_training_database_gateway.dart`
- 修改：`lib/data/local/trainmate_structured_database_gateway.dart`
- 修改：`lib/data/local/sqflite_trainflow_database_gateway.dart`
- 测试：`test/data/local/trainflow_database_schema_test.dart`
- 测试：`test/data/local/trainflow_database_schema_sqlite_test.dart`
- 新增测试：`test/data/local/voice_training_database_gateway_test.dart`

**接口：**

```dart
enum VoiceSessionOutcome { pending, completed, abandoned, failed, unsupported }

abstract interface class VoiceTrainingDatabaseGateway {
  Future<VoiceSessionRecord?> readVoiceSession(String sessionId);
  Future<VoiceSessionRecord> beginVoiceSession(VoiceSessionDraft draft);
  Future<void> saveVoiceSessionProgress(VoiceSessionProgress progress);
  Future<VoiceTrainingCommitResult> commitVoiceTraining(
    VoiceTrainingCommit commit,
  );
  Future<VoiceTrainingUndoResult> undoVoiceTraining({
    required String athleteProfileId,
    required String sessionId,
    required DateTime undoneAt,
  });
  Future<void> abandonActiveVoiceSessions({required DateTime abandonedAt});
}
```

- [ ] 先写 schema 测试，断言 `TrainFlowDatabaseSchema.version == 4`，v3→v4 只追加表和索引，旧表列不删除、不重命名。
- [ ] 新增 `voice_sessions`：`id`、`athlete_profile_id`、`created_at`、可空 `raw_transcript`、`parsed_intent`、`slot_state_json`、`confidence`、`disambig_rounds`、`outcome`、`training_log_id`、`workout_id`、`matched_workout_uuid`、`redacted_at`、`updated_at`；外键指向 `athlete_profiles`。
- [ ] 增加 `idx_voice_sessions_outcome_created_at` 和仅允许一条 `pending` 的部分唯一索引。
- [ ] 为网关编写内存/SQLite 契约测试：新会话抢占旧会话、进度快照、可重试失败保留原文、终态脱敏、账号隔离。
- [ ] 实现 sqflite 网关；所有错误使用中文 `FormatException`、`StateError`，不得输出转写原文。
- [ ] 运行：`flutter test --no-pub test/data/local/trainflow_database_schema_test.dart test/data/local/trainflow_database_schema_sqlite_test.dart test/data/local/voice_training_database_gateway_test.dart`；预期全部通过。

### 任务 2：建立领域模型、UUID 与中文规则解析器

**文件：**

- 新增：`lib/features/voice_training/domain/voice_training_models.dart`
- 新增：`lib/features/voice_training/domain/voice_intent_parser.dart`
- 新增测试：`test/features/voice_training/domain/voice_intent_parser_test.dart`

**核心类型：**

```dart
enum VoiceSport { running, cycling, strength, swimming, other }
enum VoiceSlotSource { parsed, healthKit, userPicked, userDefault }
enum VoiceDisambiguationStep { workout, sport, time, rpe, confirming, manual }

class VoiceSlotValue<T> {
  const VoiceSlotValue({
    required this.value,
    required this.source,
    required this.confidence,
  });
  final T value;
  final VoiceSlotSource source;
  final double confidence;
}

abstract interface class LocalIntentFallbackGateway {
  Future<VoiceParseResult?> parse(String transcript);
}
```

- [ ] 先把 PDF 的 8 个解析用例写成表驱动测试，另外覆盖“五点五公里”“一个半小时”“昨晚 00:30 边界提示”“跑步骑车冲突”和 RPE 五档映射。
- [ ] 实现 UUID v4 生成器，断言版本位为 4、variant 位合法，避免新增 `uuid` 包。
- [ ] 实现运动词表、中文/阿拉伯数字、距离、时长、时间提示、疲劳词和 `unsupported` 意图识别。
- [ ] 规则无冲突命中时置信度不低于 0.9；冲突或未命中调用 `LocalIntentFallbackGateway`。
- [ ] 默认注入 `UnavailableLocalIntentFallbackGateway`，返回 `null` 并触发手动表单；不得调用现有云端 AI API。
- [ ] 解析整体用 `Future.timeout(const Duration(seconds: 2))` 包裹；超时返回可诊断失败类型，不抛到 UI。
- [ ] 运行：`flutter test --no-pub test/features/voice_training/domain/voice_intent_parser_test.dart`；预期 8 个规格用例及新增边界用例全部通过。

### 任务 3：复用 HealthKit 结构化事实实现候选匹配

**文件：**

- 新增：`lib/features/voice_training/domain/voice_workout_matcher.dart`
- 修改：`lib/data/local/trainmate_structured_database_gateway.dart`
- 新增测试：`test/features/voice_training/domain/voice_workout_matcher_test.dart`

**接口：**

```dart
abstract interface class VoiceWorkoutCandidateSource {
  Future<List<VoiceWorkoutCandidate>> listCandidates({
    required String athleteProfileId,
    required DateTime startUtc,
    required DateTime endUtc,
  });
}

enum VoiceWorkoutMatchBand { autoSelected, needsChoice, noMatch }
```

- [ ] 先写 PDF 的 6 个 HK 匹配测试：单候选高分、双候选接近、全部低分、未授权空返回、跨午夜时间窗、10km 对 8.1km。
- [ ] 候选源只读取已由 `HealthSyncController` 写入 SQLite 的 `workouts`，过滤 `source_kind=healthKit` 与 `source_deleted_at IS NULL`；不新增第二套 HK 查询。
- [ ] 时间提示解析成本地时间窗后转 UTC，并在两端各扩 2 小时；保存时仍以 UTC 为准。
- [ ] 按 PDF 分值实现：运动 40、距离 30、时长 20、时间 10；缺少声称距离时距离项固定 15 分。
- [ ] `最高分 >= 75 且领先 >= 20` 自动选中；`最高分 >= 45` 或候选接近进入最多 3 条卡片；否则 `noMatch`。
- [ ] HealthKit 不支持、未授权、同步或查询失败均返回空候选并继续语音路径；状态中保留“不含健康指标”的解释。
- [ ] 运行：`flutter test --no-pub test/features/voice_training/domain/voice_workout_matcher_test.dart`；预期全部通过。

### 任务 4：实现会话编排、置信度分流与混合模态状态机

**文件：**

- 新增：`lib/features/voice_training/application/voice_training_controller.dart`
- 新增测试：`test/features/voice_training/application/voice_training_controller_test.dart`
- 修改：`lib/features/ai_center/application/voice_input_gateway.dart`
- 修改：`lib/features/ai_center/application/voice_input_gateway_io.dart`
- 修改：`lib/features/ai_center/application/voice_input_gateway_stub.dart`

**状态接口：**

```dart
final voiceTrainingControllerProvider = AutoDisposeAsyncNotifierProvider<
    VoiceTrainingController, VoiceTrainingState>(VoiceTrainingController.new);

class VoiceTrainingState {
  final VoiceSessionRecord session;
  final VoiceSlotState slots;
  final List<VoiceWorkoutCandidate> candidates;
  final Set<VoiceDisambiguationStep> requiredSteps;
  final bool isListening;
  final String statusMessage;
}
```

- [ ] 先写状态机测试：sport+rpe 同屏、语音覆盖 parsed、语音不覆盖 userPicked、最多 4 轮、点选 workout 后语音补 RPE、中途退出无回执、新会话抢占旧会话。
- [ ] `startSession` 先在数据库中原子放弃旧 `pending`，再启动新会话；原始转写只存于本机。
- [ ] 直达条件严格使用 PDF 阈值：意图 ≥0.85、必填槽位各 ≥0.8、HK 自动选中或明确无数据、RPE 已明确确认。
- [ ] 缺失项按 `workout > sport > time > rpe` 排序，同一屏合并渲染；每次提交卡片/语音修正只增加一轮。
- [ ] 追加语音以换行拼接；只修改被点名槽位；任何 `userPicked` 值都不可被语音覆盖。
- [ ] 第 3 轮后增加汇总确认；超过第 4 轮进入预填手动表单。
- [ ] STT 权限拒绝时保留文字入口；解析超时将转写预填到备注；unsupported 显示对应功能入口并终态脱敏。
- [ ] 运行：`flutter test --no-pub test/features/voice_training/application/voice_training_controller_test.dart`；预期全部通过。

### 任务 5：原子生成现有训练事实、成长回执与幂等重试

**文件：**

- 修改：`lib/data/models/training_log.dart`
- 修改：`lib/features/voice_training/data/voice_training_database_gateway.dart`
- 修改：`lib/data/local/sqflite_trainflow_database_gateway.dart`
- 修改：`lib/features/growth/application/growth_evidence_controller.dart`
- 新增测试：`test/features/voice_training/application/voice_training_commit_test.dart`
- 扩展测试：`test/data/local/voice_training_database_gateway_test.dart`

**提交契约：**

```dart
class VoiceTrainingCommit {
  final VoiceSessionRecord session;
  final TrainingLog trainingLog;
  final LocalTrainingFactWrite localFact;
  final GrowthEvidenceEvent growthEvent;
  final GrowthLevelState nextLevelState;
}
```

- [ ] 先写集成测试：同 requestId 重试只有一条训练日志/结构化 workout/成长事件；来源为 voice；XP 与同值手动记录一致；失败时所有写入回滚。
- [ ] 给 `TrainingLogKind` 增加 `voice('voice')`，给 `TrainingLog` 增加可空 `voiceSessionId`；旧 JSON 缺字段仍按原逻辑读取。
- [ ] 把 PDF `ReceiptGenerator` 适配为现有链：构造 `TrainingLog`，投影 `source_kind=local_voice` 的 workout，调用 `GrowthEngine.buildTrainingEvent` 生成成长证据和 `TrainingGrowthReceipt`。
- [ ] `commitVoiceTraining` 在单个 sqflite 事务内：幂等检查 session、写兼容训练日志文档、写本地 workout/L1 结果、写成长事件/峰值状态、更新 session 为 completed、清空原始转写并写 `redacted_at`。
- [ ] matched HealthKit workout 只做来源关联，不复制为第二条 workout；语音补充 RPE/备注进入 session 和关联训练记录。
- [ ] 事务成功后刷新 TrainingLog、成长证据、指标与报告 Provider；派生指标失败不得回滚已提交训练事实，并显示可重试状态。
- [ ] 回执页展示训练类型、时间、距离/时长、RPE、HealthKit 匹配状态、XP 与证据质量；不展示内部匹配分数。
- [ ] 运行：`flutter test --no-pub test/features/voice_training/application/voice_training_commit_test.dart test/data/local/voice_training_database_gateway_test.dart test/services/growth_engine_test.dart`；预期全部通过。

### 任务 6：实现 3 秒撤销、终态脱敏与恢复

**文件：**

- 修改：`lib/features/voice_training/application/voice_training_controller.dart`
- 修改：`lib/data/local/sqflite_trainflow_database_gateway.dart`
- 修改：`lib/features/growth/application/growth_evidence_controller.dart`
- 新增测试：`test/features/voice_training/application/voice_training_undo_test.dart`

- [ ] 先写测试：提交后 3 秒内撤销成功；重复撤销幂等；超时后入口消失；撤销后 workout 软删、成长证据 revoked、当前 XP 重算、峰值等级不下降、session=abandoned 且原文为空。
- [ ] 撤销事务按 sessionId 精确定位 voice 训练，拒绝撤销其他来源或其他账号的训练。
- [ ] 软删结构化 workout 的 `source_deleted_at`，删除/失效关联 L1 结果和派生指标血缘，撤销成长事件；不物理删除审计 session。
- [ ] 兼容 TrainingLog 文档移除相应 voice log，随后刷新控制器；若撤销事务失败，UI 保留回执并显示“撤销失败，训练记录未改变”。
- [ ] 应用重启时扫描 `pending`/可重试 `failed`：恢复槽位与手动表单；超过 24 小时自动 abandoned 并脱敏，避免长期保留自由文本。
- [ ] 运行：`flutter test --no-pub test/features/voice_training/application/voice_training_undo_test.dart`；预期全部通过。

### 任务 7：接入全局入口、消歧页面和跨平台降级

**文件：**

- 修改：`lib/app/router/app_routes.dart`
- 修改：`lib/app/router/app_router.dart`
- 修改：`lib/app/navigation/main_shell.dart`
- 新增：`lib/features/voice_training/presentation/voice_training_page.dart`
- 新增：`lib/features/voice_training/presentation/voice_disambiguation_cards.dart`
- 新增测试：`test/features/voice_training/presentation/voice_training_page_test.dart`
- 修改测试：`test/navigation_test.dart`

- [ ] 先写 Widget 测试：全局 FAB 展开两个入口；语音记录进入 `/voice-training`；iOS 录音态；Web/Android 文字降级；多槽位同屏；最多 3 条 HK 候选；手动表单预填；回执与撤销倒计时。
- [ ] 保留现有 AI 中心，不替换其路由；FAB 点击后使用项目现有组件显示“语音记训练”和“AI 中心”，不引入 speed-dial 依赖。
- [ ] 页面状态只来自 `voiceTrainingControllerProvider`；Widget 不直接访问 SQLite、HealthKit 或 GrowthEngine。
- [ ] 麦克风按钮开始/停止现有 `trainflow.ai/voice_input` MethodChannel；离开页面时调用 cancel，避免后台继续录音。
- [ ] 卡片使用现有 `TrainFlowPage`、`TrainFlowCard`、主题颜色和中文文案；支持系统大字体、语义标签、48dp 点击区域与减少动态效果。
- [ ] 完全手动表单包含运动、时间、距离、时长、RPE、备注；只校验业务必要项，不增加 PDF 未要求的字段。
- [ ] 运行：`flutter test --no-pub test/features/voice_training/presentation/voice_training_page_test.dart test/navigation_test.dart`；预期全部通过。

### 任务 8：补齐删除、账号切换、iOS 权限与端到端验收

**文件：**

- 修改：`lib/features/auth/application/account_switch_coordinator.dart`
- 修改：`lib/features/profile/application/health_data_deletion_coordinator.dart`
- 核验/必要时修改：`ios/Runner/Info.plist`
- 核验/必要时修改：`ios/Runner/AppDelegate.swift`
- 新增测试：`test/features/voice_training/voice_training_acceptance_test.dart`
- 修改测试：对应账号切换与健康删除测试

- [ ] 先写测试：账号切换终止并脱敏 pending 会话；删除健康数据清除语音会话、voice workout、成长证据和派生指标；其他手动训练不受影响。
- [ ] 确认 `NSSpeechRecognitionUsageDescription` 与 `NSMicrophoneUsageDescription` 均为中文且准确；确认 `requiresOnDeviceRecognition=true`，不增加音频保存。
- [ ] 将会话清理注册到现有账号切换和健康数据删除协调器；清理失败进入只读保护或显式错误，不允许半清理后继续切换账号。
- [ ] 覆盖 PDF 24 个用例并增加隐私、跨平台、数据库迁移、账号隔离、可访问性和 Provider 恢复用例。
- [ ] 运行：`flutter analyze --no-pub`；预期无新增错误或警告。
- [ ] 运行定向测试：`flutter test --no-pub test/features/voice_training test/data/local/voice_training_database_gateway_test.dart`；预期全部通过。
- [ ] 运行项目清洁副本测试：`scripts/run_flutter_tests_clean_copy.sh`；只依据实际输出报告结果。
- [ ] 构建：`flutter build ios --simulator --no-codesign --no-pub` 与 `flutter build web --no-pub`；预期均成功。
- [ ] iOS Simulator 手测：高置信直达、单轮 HK+RPE 消歧、语音修正、权限拒绝、无 HK、失败重试、3 秒撤销、中途退出、账号切换；分别记录 UI、数据、构建和服务状态证据。

---

## 阶段与验收门

1. **决定完成：** 当前计划已确定采用现有事实链、iOS 完整闭环、规则解析、全局入口和终态脱敏。
2. **准备完成：** 任务 1 的 v4 迁移和网关契约通过，才能开始业务逻辑。
3. **执行门 1：** 任务 2-4 的纯逻辑与状态机测试全部通过，才接真实持久化。
4. **执行门 2：** 任务 5-6 的原子提交、幂等与撤销测试通过，才开放全局入口。
5. **验证门：** 任务 7-8 的 Widget、清洁副本、iOS/Web 构建和 Simulator 手测全部完成，才称为 v1 实现完成。
6. **迭代项：** 真实端侧小模型、其他语音意图、多语言与跨端语音放入 v1.1，不在本次实施中夹带。

## 首批行动

1. 建立数据库 v4 迁移失败测试和 `VoiceTrainingDatabaseGateway` 契约测试。
2. 完成规则解析 8 个规格用例，确认中文数字、时间和 RPE 边界。
3. 完成 HealthKit 候选匹配 6 个规格用例，再进入状态机实现。

## 风险与回滚

- **脏工作树冲突：** 实施前逐文件确认现有改动；发现同一段代码被用户修改时停止并请求确认，不覆盖。
- **迁移失败：** 维持现有只读恢复策略；v4 只追加对象，可回滚应用版本但不删除 v4 表。
- **多存储一致性：** iOS 主路径必须走单一 sqflite 事务；Web 仅手动兼容路径，不宣称事务级语音闭环。
- **HealthKit 数据延迟：** 匹配前请求一次现有前台同步；失败按无 HK 数据继续，不阻塞训练记录。
- **误解析：** RPE 不由模糊语气直接落库，userPicked 优先，最多 4 轮，最终回退预填表单。
- **隐私：** 日志、错误与埋点禁止包含原始转写；本地统计只记录 outcome、轮次、置信度区间和匹配分档。

## 明确假设

- 用户回复“好的”视为接受：所有终态脱敏；可重试失败最多保留 24 小时。
- PDF 中的 `training_receipts`、`ReceiptGenerator` 是概念接口；当前仓库以 `TrainingLog + workouts + GrowthEvidenceEvent + TrainingGrowthReceipt` 实现同等能力。
- 现有 iOS 语音 MethodChannel 和权限能力可复用；实施时仍需用当前源码与 Simulator 重新验证，不能把 README 描述当作通过证据。
- 计划不包含依赖升级、云端 API、数据库破坏性迁移、自动提交或推送。
