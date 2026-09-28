# TrainMate 插件维护指南

日期：2026-09-04  
适用范围：随应用发行并经过审核的内置插件。运行时下载第三方代码、插件市场和远程更新不在当前能力范围内。

## 1. 目录、清单与稳定身份

原有 33 个业务目录，加上本期新增的核心管理目录 `capabilities`，当前 `lib/features` 共 34 个目录，与 `builtInFeatures` 的 34 项定义一一对应。目录增删必须同时更新发行定义和装配清单，并运行目录一一对应测试。

|目录|稳定插件 ID|归属|
|---|---|---|
|capabilities|`core.capabilities`|新增必需管理入口；历史页面使用 `core.history`|
|activity_import|`feature.activity_import`|活动与健康导入|
|ai_center|`feature.ai_center`|AI 产物与聊天|
|ai_coach|`feature.ai_coach`|只读兼容入口|
|auth|`core.auth`|必需身份认证|
|cloud_sync|`feature.cloud_sync`|云同步|
|companion|`feature.companion`|伙伴、教练记忆|
|daily_adjustment|`feature.daily_adjustment`|每日调整|
|daily_check_in|`feature.daily_check_in`|每日签到|
|dashboard|`core.dashboard`|必需今日装配；动作按实际功能归属|
|data_center|`feature.data_center`|身体数据|
|data_rights|`core.data_rights`|必需数据导出、删除和撤销|
|exercise_library|`feature.exercise_library`|动作读取；执行进入跟练能力|
|first_run_onboarding|`core.first_run_onboarding`|必需首次引导与会员|
|growth|`feature.growth`|成长证据、指标和成就|
|guided_workout|`feature.guided_workout`|课程跟练|
|knowledge_library|`feature.knowledge_library`|知识导入与读取|
|meal_guide|`feature.meal_guide`|饮食指导与偏好|
|motion_check|`feature.motion_check`|动作分析|
|onboarding|`core.onboarding`|必需训练画像|
|pet|`feature.pet`|宠物、每日活动|
|pilot_validation|`feature.pilot_validation`|试点验收|
|profile|`core.profile`|必需我的装配；日程、健康、成就分别归实际功能|
|race_prep|`feature.race_prep`|赛事资料与图片识别|
|rehab|`support.rehab`|康复支持；关闭不影响核心安全规则|
|reminders|`feature.reminders`|训练提醒|
|rhythm|`feature.rhythm`|身体节奏与饮食记录|
|self_use_acceptance|`feature.self_use_acceptance`|自用验收|
|starter_program|`feature.starter_program`|入门项目|
|training_log|`feature.training_log`|训练记录|
|training_plan|`feature.training_plan`|计划生成、调整与日程|
|user_insights|`feature.user_insights`|个人洞察|
|weekly_report|`feature.weekly_report`|周报及结构化报告生成|
|workout_player|`feature.workout_player`|训练播放器|

七个本地计划策略位于 `lib/plugins/sports`：马拉松、越野跑、力量、HYROX、减脂、综合健身、康复。策略 ID 和版本写入计划来源并参与回滚解析，已经发行后不得借重命名改变语义。后端当前只发布六类云端运动/目标提供方，康复仍是本地保守支持，不能据此宣称云端可生成康复处方。

|能力|稳定 ID|首版版本|类型|
|---|---|---|---|
|马拉松|`sport.marathon`|`1.0.0`|运动|
|越野跑|`sport.trail_running`|`1.0.0`|运动，沿用共享跑步模板|
|力量|`sport.strength`|`1.0.0`|运动，接入既有 ABC 编译器|
|HYROX|`sport.hyrox`|`1.0.0`|运动|
|减脂|`goal.fat_loss`|`1.0.0`|目标|
|综合健身|`goal.general_fitness`|`1.0.0`|目标|
|康复支持|`support.rehab`|`1.0.0`|本地支持，与康复功能入口复合|

## 2. 新增功能插件

1. 在 `lib/features/<目录>` 完成业务实现，复用既有仓储、错误和用户确认边界。
2. 在 `built_in_features.dart` 增加唯一 `directory`、稳定 `id`、中文名称、路由、依赖和可选导航贡献；核心能力才允许 `required: true`。
3. 写入或产生外部副作用的控制器通过 `bindFeatureController` 注册；异步写入开始时取得 `FeatureOperation`，提交前再次校验账号 epoch 和完整来源闭包。
4. 初始化返回的注册、订阅、通知和平台资源必须可清理。停用失败要回滚到原状态，不能把真实仓储或业务异常伪装成取消。
5. 页面入口由路由贡献并由宿主守卫；不可用路由回到 `/capabilities?feature=<id>`。新增导航后逐项验证 `pageBuilder`、能力页 `builder` 和动态底栏顺序。
6. 增加装配、依赖预览、确认/取消、停用阻断、生命周期和账号换域测试，再跑全量 clean-copy。

## 3. 新增或修改运动策略

1. 在 `sport_plan_strategy.dart` 的公共契约内实现策略，复用公共偏好、器械和 ABC 编译器，不复制宿主算法。
2. 在 `built_in_sport_plugins.dart` 登记稳定 `PluginRef(id, version)`、显示能力、本地与云端支持事实。跨运动组合由协调器处理，策略不能直接激活计划。
3. 计划仍经过候选生成、审计、用户确认和版本持久化；不得新增绕过确认的写入口。
4. 修改现有同版本策略前先增加新版本或证明输出逐字节等价。使用 `sportPluginFactory` 注入旧发行做回滚演练，正式代码中不保留重复旧算法。
5. 保持原 249 组固定档案、日期、赛事和偏好黄金一致；确有产品需求改变时另立变更说明，不能以更新黄金掩盖回归。

## 4. 生命周期、重绑与依赖锁

2026-09-11 补充：运动、目标及康复支持插件应在 `PluginDescriptor.skills` 显式登记所用技能。本地技能绑定已声明且初始化时真实注册的能力，并与插件发行版本一致；云端技能声明兼容主版本、运动代码及适用的专项片段。康复复合装配必须保留委托插件的技能列表。新增或调整绑定时，执行 `sport_skill_bindings_test.dart`，核对真实策略运动代码和后端主清单。完整契约与此次验证边界见 [ADR-0006：运动插件技能绑定](../architecture/ADR-0006-运动插件技能绑定.md)。

依赖关闭按反向拓扑清理，重新启用按正向拓扑初始化。普通启停失败会尝试恢复前一组合；恢复本身失败时保留明确的恢复状态和不可写保护。账号清理一旦完成，不回填旧账号数据，仅重试新域装配。旧异步结果必须校验操作来源、功能 epoch 和账号 epoch；账号变化后不再落盘。

训练播放器、训练日志和计划在未完成训练期间通过运行时锁阻止停用；计划生成、健康同步、AI、云同步、通知和图片分析在提交期间持有操作租约。锁和租约保护的是正在运行的资源与写入边界，不自动撤销已经保存的数据。

账号重绑先清理旧域资源，再绑定新域并从新账号的本地设置装配。装配失败时保留全局恢复锁，在同一恢复入口重试；不得重复清理旧账号业务数据或 HealthKit 队列。

## 5. 设置、恢复与账号域

设置键为 `trainflow.plugin_settings.v1`，格式为 `{"version":1,"enabledOverrides":{...}}`。版本必须是整数 `1`；只保存与发行默认值不同的开关，位于当前账号本机业务域且不进入云同步 outbox。有效文档中的未知 ID 原样保留、运行时忽略；坏 JSON（包括空字符串）或不支持版本临时按默认组合启动，并保留原文档，直到用户明确恢复默认。依赖不完整由注册表校验，不能静默绕过依赖。

账号绑定键为 `trainflow.account_binding.v1`。排障时分别核对设置键、绑定键和当前账号仓储重读结果；不要只看界面开关，也不要跨账号复制设置。停用不会删除计划、日志、报告、健康事实或授权偏好。

异步取消只通过 `FeatureOperationInvalidation` 类型识别，不匹配错误文案，也不捕获所有 `StateError`。Health ACK 返回后继续使用原导入操作保护成长派生。通知的权限/时区可以并发等待，平台取消和安排按代际串行；停用必须等已开始的平台安排完成清理，不能让旧同步清理新同步的提醒。修改这三条边界时，必须保留对应迟到结果回归。

## 6. 数据来源与历史

本地计划可来自固定发行策略和兼容旧数据；云端处方来自 FastAPI 审核链路，必须有能力协商、会员校验、Skill 来源和显式确认。模拟器 SQLite 夹具只能证明本地 UI 与仓储集成，不能证明真实云端、真实账号、真实模型、APNs 或真机 HealthKit。

核心历史只读取已保存的计划版本、训练日志、兼容周报、成长周报及结构化报告修订。历史读取不得生成 fallback 计划、同步事实、结算成长或补算报告。维护时用稳定主键排序后的规范化快照，在访问历史前后逐表比较，并通过对应 Repository 重读语义对象。

## 7. 发布前验证状态与清单

截至 2026-09-04：Flutter clean-copy 1441 项通过，只有与 P0 逐像素相同的 `01-today`、`02-plans` 两项既有黄金失败；analyze 无问题；后端 85 项、iOS RunnerTests 18 项通过。专用模拟器完成本地管理、依赖确认/取消、阻断、动态导航、重启、历史只读和完整训练反馈。

每次发布至少执行：目录与注册表一致性；运动 249 黄金和同版本发行回滚；设置、账号换域、失败恢复和旧异步；全 Flutter clean-copy 与 analyze；后端处方；iOS RunnerTests；最终构建安装。黄金失败必须比较实际像素，不能只比较文件名或直接更新基线。

当前仍需单独验证：真机 HealthKit 后台投递与授权、真实云账号和会员、真实 AI/Skill 处方确认、真实 APNs、真实外部深链。验证报告要分别标明本地单元/集成测试、模拟器 UI、集成夹具、真实云和真机，不能互相替代。

## 8. 跑姿视频工具链（2026-09-11）

动作分析插件统一拥有本机关键点提取、时序测量、分项评估三项技能；马拉松、越野跑和HYROX仅引用流程，不增加运动计划的强依赖。新入口默认关闭，只有非Release构建可用 `TRAINMATE_RUNNING_VIDEO_PREVIEW=true` 预览。真机与授权视频验收尚未完成，不得纳入正式发行。

新报告键 `trainflow.running_form_reports.v1` 复用现有本地文档存储，不进入云同步。核心历史 `/history/running` 保持只读，动作分析停用后仍可查看。回滚关闭新分析入口，不删除报告或恢复整库。维护规则见[ADR-0007](../architecture/ADR-0007-跑姿视频本机工具链.md)，本次文件清单、验证结果及真实识别缺口见[交付验证记录](2026-09-11-running-video-implementation.md)。
