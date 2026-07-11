# TrainFlow AI / AI 训练决策辅助系统

这是在 `zhuque-flutter-main` 现有 Flutter UI Demo 底座上改造出的个人训练计划 App MVP。当前目标不是完整后端业务系统，而是先把移动端核心体验跑通：首次进入填写基础资料、采集职业 / 生活分型与作息、首页展示今日训练、查看训练计划、查看动作库、记录训练完成情况，并看到 AI 教练建议的 Mock 版本。

## 当前 MVP 范围

- 今日训练：默认路由 `/dashboard`，展示首次资料填写、今日照吃卡、今日训练五步流程、决策类型、完成记录、训练依据和 AI 教练建议 Mock；确认基础资料后会写入本地持久化 `user_profile`，并根据职业 / 生活分型展示当天策略。
- 首页体验补强：今日训练页展示晨间报告、恢复倒计时、训练状态趋势标签和 CTL/ATL/TSB 训练负荷曲线，帮助用户先判断“今天该不该练、怎么练”。
- 每日调整：路由 `/daily-adjustment`，把今日可训练时间、工作压力、场地器械、天气和身体状态合并，输出正常 / 降级 / 恢复 / 技术 / 休息五类决策之一；今日现实约束会写入本地 `daily_context`。用户档案中的无器械条件会触发结构化动作替代，并在训练说明中保留替代原因。
- 规则引擎校验：训练计划详情页展示本地规则审计，检查引用绑定、训练日依据、五步流程、正式/辅助动作媒体关联、按用户可用分钟数计算的时间预算、跑步提髋/小腿硬性模块和安全表达；超出当前可用时长的训练日会被阻断并要求先调整。
- 主动提醒：路由 `/reminders`，本地 Mock 编排固定时间今日训练提醒、30 天引导提醒、恢复检查、睡眠差轻松版确认和周报提醒；提醒开关和固定时间会写入本地 `reminder_settings`。
- 精简签到：路由 `/daily-check-in`，根据已有身体数据、训练画像和置信度决定今天问 5 项还是 2 项，按疼痛、疲劳、恢复风险和默认值置信度动态排序签到项，并支持“和昨天一样”一键确认。
- 30 天渐进引导：路由 `/starter-program`，提供习惯建立、减脂入门、跑步入门三套本地模板，支持三选一反馈、连击、漏练顺延和 5 分钟补救版，并把当前目标、天数、连击和补救模式写入本地 `starter_progress`。
- 30 天毕业报告：路由 `/starter-graduation`，基于完成率、心率/HRV 变化、主观感受趋势和准备度生成本地评估，并在毕业后生成正式 AI 个性化周期衔接方案，切换后的正式周期会写入本地 `formal_ai_plan`。
- 跟练执行：路由 `/workout-player`，可从今日训练、训练计划详情和训练日详情一键进入逐步播放器，展示当前步骤、真实倒计时、组间休息、最后 3 秒倒数、TTS 提示队列和屏幕常亮意图，并支持完成、跳过和“太累了”一键降级；Web 端关键提示会调用浏览器 Web Speech API，进入跟练时请求 Wake Lock，浏览器不支持时保留文字提示并正常运行；结束后可记录会话级训练复盘，以及主训练动作的完成组数和工作重量。训练日详情会展示已建立的训练-动作关联，播放器会按阶段显示本地动作媒体，加载失败时回退为占位。
- 成就徽章：在“我的”页展示本地成就体系，把 30 天连击、跟练完成、身体数据记录和安全降级转成可见回报。
- 自动周报：路由 `/weekly-report`，本地 Agent Mock 生成完成率、负荷趋势、决策回顾、恢复建议、下周重点，并支持 Markdown 文本导出、PNG 图片卡片生成、本地导出记录和本地周报归档保存。
- 用户画像：路由 `/user-insights`，展示本地学习信号、画像结论、置信度、证据、保守策略、职业 / 生活分型解释、信任回顾和恢复时间预测对账。
- 身体数据：路由 `/data-center`，支持 10 秒快录体重、静息心率、HRV、睡眠和疲劳，支持今天/昨天/前天补录、异常值二次确认、同日覆盖修订留痕、截图文字识别 Mock 和 CSV 批量导入，身体数据和修订留痕会写入本地 `shared_preferences`，并展示 7/30/90 日窗口均值趋势、指标目标、趋势洞察和本地数据质量检查。
- 训练文件导入：路由 `/activity-import`，支持粘贴 GPX 文本或 FIT 摘要，解析配速、心率和爬升，生成训练效果标签并写入本地持久化 `imported_workouts` 与 `workout_logs`。
- 训练计划：路由 `/plans`，展示训练计划列表、计划详情和训练日详情。
- 动作库：路由 `/exercises`，展示首批 80 个 MVP 内置动作说明、本地动作媒体或占位回退、呼吸方式、适用场景、暂停条件和动作详情；扩展种子集中在 `lib/data/seed/seed_exercise_extensions.dart`，替代、退阶和器械条件决策集中在 `ExerciseSubstitutionService`。
- AI 教练：路由 `/ai-coach`，展示 Mock 决策建议和带章节/页码/原文片段的依据来源。
- 书库 / 知识库：路由 `/knowledge`，展示本地书籍、引文和引用关联，支持全文搜索和手动导入知识片段，证明计划、动作、照吃卡和纠错建议可追溯。
- 比赛备战：路由 `/races`，本地 Mock 展示 base→build→specific→taper 周期反推、赛前减量、装备建议、比赛策略、成绩预测和赛后恢复；支持粘贴赛事信息导入并写入本地持久化 `races`。
- 康复记录：路由 `/rehab`，记录疼痛部位、等级和出现时机并写入本地持久化 `rehab_logs`；疼痛会触发训练自动降级，疼痛 ≥7 或持续超过 2 周会提示停止相关训练并就医。
- 照吃指令卡：路由 `/meal-guide`，按外卖、食堂、自炊三类场景给出每日最小饮食指令，并把当前吃饭场景写入本地 `meal_preference`。
- 动作纠错：路由 `/motion-check`，先用本地规则 Mock 覆盖深蹲、弓步蹲、髋铰链、俯卧撑、平板支撑、提踵、高抬腿和跑步侧面姿态 8 个动作；每条规则关联动作库条目，动作库提供呼吸方式、适用场景和暂停条件，并支持从纠错页进入对应安全提示。当前还接入结构化关键点几何计算样例和 JSON 导入校验，输出关节角度、评分、风险和置信度，并明确不等同相机识别。分析结果会把动作质量风险写入每日调整并持久化到本地 `motion_analysis_results`。
- 我的：路由 `/profile`，展示个人资料、训练偏好和最近反馈。
- 14 天自用验收：从“我的”进入 `/self-use-acceptance`，逐日记录身体数据、计划确认、训练执行、反馈、30 天引导检查和阻断问题；记录写入本地 `shared_preferences`，完成 14 天后仍需人工 Gate A 复核。

## 技术栈

- Flutter 3+
- Dart 3+
- Riverpod 本地状态管理
- GoRouter 路由管理
- Flutter ScreenUtil 屏幕适配
- Material 3 组件体系

## 项目结构

```text
lib/
├── main.dart
├── app/
│   ├── app.dart
│   ├── trainflow_app.dart
│   ├── navigation/main_shell.dart
│   └── router/
│       ├── app_router.dart
│       └── app_routes.dart
├── core/
│   ├── constants/app_colors.dart
│   ├── theme/tdesign_theme.dart
│   └── widgets/trainflow_widgets.dart
├── data/
│   ├── models/
│   │   ├── achievement.dart
│   │   ├── body_data_quality.dart
│   │   ├── body_metric.dart
│   │   ├── body_metric_export.dart
│   │   ├── body_metric_goal.dart
│   │   ├── body_metric_import.dart
│   │   ├── body_metric_revision.dart
│   │   ├── body_metric_snapshot.dart
│   │   ├── body_trend_insight.dart
│   │   ├── plan_adjustment.dart
│   │   ├── daily_adjustment.dart
│   │   ├── daily_check_in.dart
│   │   ├── imported_workout.dart
│   │   ├── starter_graduation_report.dart
│   │   ├── user_profile.dart
│   │   ├── user_insight.dart
│   │   ├── user_trust_review.dart
│   │   ├── weekly_report.dart
│   │   ├── weekly_report_export.dart
│   │   ├── training_plan.dart
│   │   ├── workout_day.dart
│   │   ├── exercise.dart
│   │   ├── knowledge_entry.dart
│   │   ├── meal_guide.dart
│   │   ├── motion_check.dart
│   │   ├── race.dart
│   │   ├── starter_program.dart
│   │   ├── training_log.dart
│   │   ├── training_reminder.dart
│   │   ├── training_rule_audit.dart
│   │   ├── workout_player_step.dart
│   │   ├── pain_log.dart
│   │   ├── self_use_acceptance.dart
│   │   └── evidence_source.dart
│   ├── repositories/
│   │   ├── achievement_repository.dart
│   │   ├── body_metric_export_repository.dart
│   │   ├── body_metric_repository.dart
│   │   ├── plan_adjustment_repository.dart
│   │   ├── user_profile_repository.dart
│   │   ├── training_plan_repository.dart
│   │   ├── exercise_repository.dart
│   │   ├── knowledge_repository.dart
│   │   ├── meal_guide_repository.dart
│   │   ├── motion_check_repository.dart
│   │   ├── race_repository.dart
│   │   ├── starter_program_repository.dart
│   │   ├── pain_log_repository.dart
│   │   ├── training_log_repository.dart
│   │   ├── user_insight_repository.dart
│   │   ├── weekly_report_export_repository.dart
│   │   ├── weekly_report_repository.dart
│   │   └── self_use_acceptance_repository.dart
│   └── seed/
│       ├── seed_achievements.dart
│       ├── seed_body_metrics.dart
│       ├── seed_training_plans.dart
│       ├── seed_exercises.dart
│       ├── seed_knowledge_entries.dart
│       ├── seed_meal_guides.dart
│       ├── seed_motion_checks.dart
│       ├── seed_races.dart
│       └── seed_starter_programs.dart
├── services/
│   ├── activity_import_service.dart
│   ├── ai_training_service.dart
│   ├── body_data_quality_service.dart
│   ├── body_metric_goal_service.dart
│   ├── body_metric_import_service.dart
│   ├── body_metric_snapshot_service.dart
│   ├── body_trend_insight_service.dart
│   ├── daily_adjustment_service.dart
│   ├── daily_check_in_service.dart
│   ├── exercise_substitution_service.dart
│   ├── knowledge_import_service.dart
│   ├── starter_graduation_service.dart
│   ├── training_reminder_service.dart
│   ├── training_rule_audit_service.dart
│   ├── user_insight_service.dart
│   ├── user_trust_review_service.dart
│   ├── motion_analysis_service.dart
│   ├── race_auto_schedule_service.dart
│   ├── race_import_service.dart
│   ├── weekly_report_service.dart
│   └── local_storage_service.dart
└── features/
    ├── activity_import/activity_import_page.dart
    ├── data_center/data_center_page.dart
    ├── daily_adjustment/daily_adjustment_page.dart
    ├── daily_check_in/daily_check_in_page.dart
    ├── dashboard/today_training_page.dart
    ├── onboarding/onboarding_page.dart
    ├── training_plan/
    ├── user_insights/user_insight_page.dart
    ├── exercise_library/
    ├── ai_coach/ai_coach_page.dart
    ├── knowledge_library/knowledge_library_page.dart
    ├── meal_guide/meal_guide_page.dart
    ├── motion_check/motion_check_page.dart
    ├── race_prep/race_prep_page.dart
    ├── rehab/rehab_page.dart
    ├── reminders/training_reminder_page.dart
    ├── starter_program/
    │   ├── starter_graduation_page.dart
    │   └── starter_program_page.dart
    ├── workout_player/workout_player_page.dart
    ├── weekly_report/weekly_report_page.dart
    ├── profile/profile_page.dart
    └── self_use_acceptance/self_use_acceptance_page.dart
```

旧组件 Demo 源码仍保留在 `lib/features/basic`、`lib/features/component` 等目录中，当前路由不再暴露这些示例页。这样做是为了降低改造风险，后续确认不需要后可以再做清理。

## 运行

```bash
flutter pub get
flutter run
```

Web 预览可以使用：

```bash
flutter run -d chrome
```

## 验证

```bash
flutter analyze
flutter test
```

测试按功能拆分为 `test/widget_test.dart`、`test/data/repositories/user_profile_repository_test.dart` 和 `test/features/onboarding/onboarding_page_test.dart`；资料状态已独立覆盖资料仓库持久化、旧档案兼容和首次引导交互，实际测试结果以 `flutter test` 输出为准。
测试同时检查计划书当期硬性项：晨间报告、主动提醒、本地 reminder_settings 持久化、精简签到、动态签到项排序、每日调整、本地 daily_context 持久化、规则引擎校验、恢复倒计时、训练状态趋势、CTL/ATL/TSB 训练负荷曲线、成就徽章、本地成就记录表、自动周报、周报 PNG 图片卡片、本地 weekly_report_exports 持久化、用户画像、用户画像三表、周度画像任务、信任回顾、prediction_logs 到期回填、本地 user_profile 持久化、打工人分型选择与旧档案兼容、本地 starter_progress 持久化、本地 formal_ai_plan 持久化、GPX/FIT 导入、本地 imported_workouts 持久化、本地 workout_logs 持久化、训练后会话复盘、主训练动作组数与重量记录、workout_exercises 训练-动作关联、周报按会话完成度计算、本地 rehab_logs 持久化、今日训练五步、每日决策徽章、30 天渐进引导、30 天毕业报告、正式 AI 计划衔接、跟练执行模式、计划训练日一键跟练、训练日手动调整、本地 plan_adjustments 持久化、修改学习信号、跟练真实倒计时、TTS 提示队列、屏幕常亮意图、身体数据 10 秒快录、身体数据补录、异常值确认、身体数据修订留痕、身体截图识别 Mock、身体 CSV 导入、身体数据导出记录、本地 body_metric_exports 持久化、指标目标、数据质量检查、趋势洞察、7/30/90 日趋势窗口与真实趋势图表、书页级训练依据、书库/引文/引用关联、书库全文搜索、书库手动导入、照吃指令卡、本地 meal_preference 持久化、动作纠错 8 动作、Motion Vision Mock 写入决策、本地 motion_analysis_results 持久化、比赛备战 Mock、比赛自动排期、赛事手动导入、本地 races 持久化、健康免责声明，以及疼痛 ≥7 后的康复红线和自动休息决策。

## 当前约束

- 还没有接真实后端、真实 AI 模型或数据库。
- 基础资料最小版已接入 `PersistedUserProfileRepository`，确认后的用户档案和 `profileCompleted` 状态会写入 `shared_preferences` 本地 `user_profile`；当前引导页可选择职业 / 生活分型、作息类型和器械条件，分型策略会进入今日训练、AI 教练和用户画像，无器械条件会进入动作替代规则，但仍未接完整问卷、账号体系或云端用户表。
- 训练推荐逻辑是本地规则，用于 MVP 演示核心闭环。
- 训练日手动调整最小版已接入：用户可按当天时间与状态修改单个训练日的预计时长、执行强度和原因，并可恢复原计划。每次调整或恢复都会写入本地 `plan_adjustments`，作为用户画像可见的学习信号；原始动作、引用和康复安全约束不会被改写。当前未接完整周期拖拽编排、动作增删、云端协作或自动改写未来训练日。
- 30 天渐进引导最小版已接入：支持三套本地模板、每日一屏“做什么 + 怎么吃”、三选一反馈、连击、漏练顺延、5 分钟补救版和毕业报告入口；新增 `StarterProgramProgress` 和 `PersistedStarterProgramRepository`，把当前目标、天数、连击、补救模式和状态文案写入 `shared_preferences` 本地 `starter_progress`。当前未接真实推送、云端引导任务表或正式数据库迁移。
- 30 天毕业报告最小版已接入：新增 `StarterGraduationReport`、`StarterGraduationService`、`FormalAiPlan`、`FormalAiPlanService` 和 `PersistedFormalAiPlanRepository`，从完成率、心率/HRV 变化、主观感受趋势、准备度和训练状态生成能力评估，并在完成 30 天后生成 4 周正式 AI 个性化周期，包含训练结构、渐进规则、安全规则和每周重点；切换后的正式周期会写入 `shared_preferences` 本地 `formal_ai_plan`。当前仍是本地规则推导，未接真实长期数据库、云端 AI 计划生成器或后台任务。
- 主动提醒最小版已接入：新增 `TrainingReminder`、`TrainingReminderSettings`、`TrainingReminderService` 和 `PersistedReminderSettingsRepository`，从今日训练、30 天引导、正式周期衔接、恢复倒计时、睡眠/疲劳信号和周报生成本地提醒编排；提醒开关和固定提醒时间会写入 `shared_preferences` 本地 `reminder_settings`。当前只做 App 内 Mock，不申请系统通知权限、不接 OpenClaw、后台任务或真实推送。
- 精简签到最小版已接入：新增 `DailyCheckInSummary` 和 `DailyCheckInService`，从身体数据、疼痛记录、30 天连击和画像置信度决定今天问 5 项还是 2 项；签到项会按疼痛、疲劳、恢复风险、睡眠/HRV 缺口和默认值置信度动态排序；支持“和昨天一样”和“今天偏累，建议轻松版”写回本地身体数据。当前未接真实 `daily_checkins/profile_events` 表或长期贝叶斯画像更新。
- 跟练执行模式最小版已接入：今日训练、训练计划详情和训练日详情都可一键进入播放器，按泡沫轴放松、动态拉伸、激活、正式训练、训练后放松与反馈推进；支持真实倒计时启动/暂停/重置，到点自动完成当前步骤并进入下一步，也支持完成/跳过/太累了降级，并把步骤结果写入本地持久化 `TrainingLog`。结束后可记录会话级复盘的实际时长、完成度、RPE、平均心率、配速、计划/完成组数、中断原因和备注；主训练文本会自动生成动作记录行，保存每项动作的计划/完成组数、每组目标次数与工作重量。精确匹配的力量日和节奏跑日已接入本地 `workoutExercises`，记录动作库 ID、顺序、模块标签、组数、次数、建议重量/强度和组间休息，并在训练日详情展示；无器械场景会通过 `ExerciseSubstitutionService` 替换可安全替代的结构化动作，并在教练说明中列出替代原因；节奏跑日以 `hipDrive` 与 `calf` 标签表达提髋和小腿硬性模块，存在跑步结构化关联时规则审计以这些标签为准。复盘优先按这些关联生成动作草稿，并把 `exerciseId` 写入执行记录。步骤事件与会话复盘通过 `logKind` 区分，复盘会覆盖当天同一训练日的上一条记录。播放器已接入跨平台平台能力层：Web 端调用浏览器 Web Speech API 和 Wake Lock API，其他平台保留文字提示和常亮意图降级；开始、暂停、重置、完成、跳过和降级都会生成可见播报文案。当前未接全量训练日的结构化关联、每一组的独立次数/重量/时间戳、真实设备同步、原生 TTS 插件或正式日志数据库迁移。
- 训练-动作关联覆盖补强：全部非休息种子训练日的泡沫轴、动态拉伸、激活、热身补充、放松、正式训练和辅助训练均已关联动作库条目、媒体占位与依据来源；规则审计会拒绝缺少五步流程关联、媒体或依据的计划。五步流程内部文字继续作为跟练说明展示，训练后复盘只记录正式与辅助动作。
- 首页体验补强最小版已接入：晨间报告读取最新睡眠、HRV、准备度和今日安排；恢复倒计时按训练日志、RPE、准备度和疲劳规则推导；训练状态趋势用 7 日身体数据与本地日志推导“进步中 / 维持 / 过度风险 / 恢复中”，并展示基于本地 workout_logs、训练日时长和身体信号估算的 CTL/ATL/TSB 训练负荷曲线。当前仍是本地规则 Mock，未接穿戴设备或长期画像任务。
- 每日调整最小版已接入：新增 `DailyAdjustmentContext`、`DailyAdjustmentDecision`、`DailyAdjustmentService` 和 `PersistedDailyContextRepository`，从今日可用时间、工作压力、训练场地、天气、身体数据、疼痛记录和准备度输出五类决策、调整后时长、原因和调整动作；今日现实约束和状态文案会写入 `shared_preferences` 本地 `daily_context`。当前只做 App 内本地重算，不接真实天气 API、日程系统、场馆器械库或自动改写完整训练计划。
- 规则引擎校验最小版已接入：新增 `TrainingRuleAuditReport` 和 `TrainingRuleAuditService`，在训练计划详情页检查引用绑定、训练日依据、五步流程、时间预算、跑步提髋/小腿硬性模块和安全表达；跑步日已有结构化关联时以 `hipDrive` 与 `calf` 标签为准，无结构化关联时才回退到文本关键词。当前基于现有内存训练计划字段推导，未接真实 `workout_exercises/citations` 数据库落库校验、康复豁免记录或 LLM 输出拦截。
- 成就徽章最小版已接入：新增本地 `AchievementDefinition`、`AchievementProgress`、`AchievementRecord` 和 `PersistedAchievementRecordRepository`，支持首次跟练、听身体降级、新手第一天、7/30 天连击、身体数据起步和安全红线识别；已解锁成就会同步写入 `shared_preferences` 本地 `achievements` 记录表，并在“我的”页展示入库状态。当前未接真实云端数据库迁移或成就素材。
- 自动周报最小版已接入：新增 `WeeklyReport`、`WeeklyReportExportRecord`、`WeeklyReportService`、`PersistedWeeklyReportRepository` 和 `PersistedWeeklyReportExportRepository`，从训练会话、身体数据、准备度、趋势标签和成就状态生成完成率、负荷趋势、决策回顾、恢复建议和下周重点；跟练步骤不会被当作完整训练计数，会话复盘按完成度折算。当前支持 Markdown 文本导出、本地 PNG 图片卡片生成、`shared_preferences` 周报导出记录和周报归档保存，未接真实报告 Agent、系统分享或保存到相册。
- 用户理解引擎最小版已接入：新增 `ProfileEvent`、`UserProfileInsight`、`PredictionLog`、`UserTrustReviewReport`、`UserInsightService`、`UserTrustReviewService` 和 `PersistedUserInsightRepository`，从问卷、训练日志、身体数据、疼痛记录、30 天引导和训练文件导入派生画像结论；每条结论带 confidence、证据和保守策略，用户可标记“不准”。当前已增加 `WorkerProfileType`，覆盖久坐办公室、经常加班、倒班 / 熬夜、高压力脑力工作、久站工作、备赛打工人和减脂饮食不稳定等分型，旧本地档案缺少该字段时回落到综合 / 其他。信任回顾会展示预测准确率、承认不确定、数据主权和兑现回顾，并支持本地 prediction_logs 到期自动回填。用户画像页已支持生成周度画像任务，把 `profile_events`、`user_profiles` 和 `prediction_logs` 快照写入 `shared_preferences` 本地三表。当前未接真实云端画像数据库、后台定时任务或长期贝叶斯画像更新。
- 身体数据最小版已接入：支持体重、体脂、静息心率、HRV、睡眠、疲劳和酸痛的本地结构化记录，快录可选择今天/昨天/前天补录；体重较最近记录变化超过 2 kg 或静息心率偏离 7 日均值 20 bpm 以上时先拦截确认；同日覆盖会生成本地修订留痕，记录旧值、新值、来源和原因；身体数据与修订留痕已通过 `shared_preferences` 本地持久化；并提供截图文字识别 Mock、CSV 粘贴导入、JSON/CSV 导出预览、本地导出包摘要、`shared_preferences` 本地导出记录、一键清除、7/30/90 日趋势窗口切换与真实趋势图表。清除身体数据与清除导出记录是独立操作，后者需要二次确认且不会删除身体数据或当前导出预览。新增 `BodyDataQualityReport`、`BodyDataQualityService`、`BodyTrendInsightReport`、`BodyTrendInsightService`、`BodyMetricGoalReport`、`BodyMetricGoalService`、`BodyMetricExportRecord`、`PersistedBodyMetricExportRepository`、`BodyMetricImportResult`、`BodyMetricImportService`、`BodyMetricRevision`、`BodyMetricSnapshotRecognitionResult` 和 `BodyMetricSnapshotRecognitionService`，检查覆盖率、source 口径、体重/静息心率异常、缺失容忍、7/30/90 天窗口说明、体重×训练负荷、静息心率×疲劳、HRV×睡眠、指标目标、里程碑和减脂保护。当前未接真实 `metric_goals` 数据库表、穿戴设备、真实 OCR/相册权限、真实文件选择器、系统保存/分享、正式数据库表迁移或整体数据库持久化。
- GPX/FIT 导入最小版已接入：新增 `ImportedWorkout`、`ActivityImportService`、`PersistedImportedWorkoutRepository` 和 `PersistedTrainingLogRepository`，支持 GPX 轨迹点解析和 FIT 摘要文本解析，计算距离、配速、爬升、平均心率和训练效果标签，并同步写入 `shared_preferences` 本地 `imported_workouts` 与 `workout_logs`；当前未接真实文件选择器、二进制 FIT 解析或厂商 API。
- `data/models` 已保留 `evidenceSources`，训练计划、训练日和动作库都带 Mock 依据来源。
- 书页级引用最小版已接入：`EvidenceSource` 支持 `chapter`、`pageRange`、`doi`，页面显示“章节/页码 + 原文片段 + 适用原因”。
- 书库 / 知识库最小版已接入：支持本地 `books`、`book_quotes`、`citations` 三层结构，页面展示书籍、引文和引用关联；新增 `KnowledgeImportService` 和 `PersistedKnowledgeRepository`，支持按书名/作者/章节/原文/适用原因/引用关联全文搜索，并可手动导入一条书籍+引文写入 `shared_preferences` 本地书库。当前未接真实研究库、文件导入器、向量全文检索或云端数据库。
- 照吃指令卡最小版已接入：支持外卖、食堂、自炊三类场景，只给一条可执行饮食指令；新增 `MealPreference` 和 `PersistedMealPreferenceRepository`，当前吃饭场景会写入 `shared_preferences` 本地 `meal_preference`，并同步影响首页照吃卡和 AI 教练建议。当前不做热量记录、餐食数据库或营养摄入追踪。
- Body Engine 基础层已接入：新增 `ExerciseBodyProfile`，为 8 个动作纠错动作结构化记录动作模式、涉及关节、主要肌群、稳定肌群、常见代偿和风险区域；动作详情页展示结构化身体知识，Motion Vision Mock 优先使用同一份动作资料生成 Body Engine 解释。真实 MediaPipe 图片/视频识别、关键帧标注、视频文件处理和正式数据库落库尚未接入。
- 动作纠错最小版已接入：支持 8 个核心动作的本地规则 Mock，展示角度观察点、主要问题、纠正建议、退阶动作、拍摄建议和依据来源；新增 `MotionPoseFrame`、`MotionPoseAnalysisService`、`MotionPoseImportService`、`MotionAnalysisResult`、`MotionAnalysisService` 和 `PersistedMotionAnalysisRepository`，结构化关键点样例和合法 JSON 输入会计算关节角度、评分、风险和置信度，原始关键点帧与计算结果一起持久化，接入 Body Engine 解释与训练决策影响，并把结果写入每日调整和 `shared_preferences` 本地 `motion_analysis_results`。真实姿态识别结果仍未接入，结构化样例或 JSON 输入不能当作相机识别结果。
- 比赛备战最小版已接入：支持本地 `races` 结构，展示周期反推、赛前减量、装备建议、比赛策略、成绩预测和赛后恢复；新增 `RaceAutoSchedule`、`RaceAutoScheduleService`、`RaceImportService` 和 `PersistedRaceRepository`，可按比赛日期、准备度和疼痛红线自动生成本周阶段、训练任务、补给提示、恢复规则和安全门槛，也可粘贴赛事名称、类型、日期、目标和赛道信息导入本地 `races`。当前未接真实成绩模型、报名平台赛事导入、日历系统或完整训练计划自动改写。
- 当前训练日已显式展示泡沫轴放松、动态拉伸、激活、正式训练、训练后放松与反馈五步流程，并标注正常/降级/恢复/技术/休息五类决策。
- 动作库已接入 `mediaUrl` 占位兼容链路和 `mediaUrls` 本地媒体列表，当前首批 80 个动作均有媒体字段和依据来源；8 个动作纠错核心动作已接入本地媒体，高抬腿已替换为可准确对应的 GIF，A Skip 和跑步侧面姿态仍明确标注为通用参考图。素材来源和许可记录见 `assets/images/exercises/free-exercise-db/来源说明.md`。
- 动作媒体已增加 `mediaStatus` 状态：精确示范、通用参考、媒体占位；页面和回归测试会区分这些状态，不把通用参考图当作精确纠错示范。
- 14 天自用验收记录已接入本地 `self_use_acceptance`，支持每日五项记录、阻断问题和备注持久化；记录按开始日期逐日开放，未来日期不能提前选择或写入；当前尚未开始真实连续 14 天使用，Gate A 不能宣称通过。配套清单见 `14天自用验收清单.md`。
- 康复最小版已接入结构化疼痛记录和 `PersistedPainLogRepository`，记录会写入 `shared_preferences` 本地 `rehab_logs`；疼痛 4-6 分会自动切换为恢复课，疼痛 ≥7 分或持续超过 2 周会切换为休息/就医红线。当前未接真实康复数据库、医生工作流或医疗诊断。
- 真实动作识别、真实动图素材、报名平台赛事导入/日历同步/完整计划改写、书库真实文件导入/向量检索/云端同步、身体数据真实 OCR/相册权限、身体数据真实文件选择、身体数据系统保存/分享、身体数据正式数据库表迁移、系统级推送通知、OpenClaw 提醒编排、毕业报告长期数据版、云端 AI 计划生成器、平台 TTS 插件、系统 Wakelock、成就云端数据库迁移、用户画像云端数据库与后台周度任务、真实 GPX/FIT 文件选择/二进制解析、周报系统分享/保存到相册和整体数据库持久化仍未完成。
- `services/ai_training_service.dart` 和 `services/local_storage_service.dart` 是后续接真实 AI、后端或本地存储的入口。
- 当前 package 名已统一为 `trainflow_ai`。正式产品化时还需要继续统一应用图标、平台 Bundle ID 和发布签名。
