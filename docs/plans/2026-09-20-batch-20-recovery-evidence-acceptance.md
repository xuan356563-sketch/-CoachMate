# Batch 20：恢复时间工程估算的证据边界

日期：2026-09-20。本批只处理恢复估算的身体／训练记录输入、计时依据和说明展示。完成实现、审查、修复、测试与限定模拟器检查后停止。

## 基线与目标

起始工作区有 418 条未提交状态，快照为 `/tmp/trainmate-batch20-start-status.txt`。保留既有改动，未提交、推送、部署、升级依赖或修改数据库结构。

修改前确认：

- 恢复估算直接使用 `latestBodyMetric`，疲劳和酸痛没有检查是否实际记录，旧日、未知来源及继承值可能增加恢复小时数。
- 直接使用 `logs.first`，跟练步骤默认 RPE、导入推算 RPE 或迟到补录可能覆盖最近有效会话。
- 经过小时数从 `createdAt` 扣除，补录旧训练会在保存时重新开始倒计时。
- 无会话也会展示具体小时；结束文案“已恢复到可评估”及提醒中的“距下次高强度课”容易被误解为训练许可。
- 原 `/reminders` 已兼容跳转到精简签到，当前提醒设置实际由签到页承载。旧提醒页面不作为新 UI 的验收入口。

## 最终实现

### 身体与训练证据

恢复估算复用 `currentDecisionBodyMetric`：按本地自然日选择当日、非未来、来源可信的最新一条身体记录；疲劳、酸痛、睡眠分别检查 `hasValue`。不跨记录补齐缺失字段，不把未填写的数值当作零值观测。合法疲劳／酸痛零值仍可使用。

训练记录新增兼容的本机可选字段 `recoveryEvidenceVerified`，仅来源未确认时写入 `false`。旧记录缺少或无法识别 `logKind`、RPE 非整数，或来源标记明确为假／格式异常时，不作为恢复估算依据；原数值与旧记录阅读保留。明确类型的既有有效记录仍兼容，无需重写全库。

统一 `canEstimateRecoveryAt` 检查来源标记、会话类型、RPE 1–10、执行事实和时间有效性；排除步骤及导入推算，排除未来、无效或保存早于训练的时间。部分完成但存在时长、完成比例或组数的会话可用，不要求全部完成才允许记录主观反馈。

恢复消费者按训练 `date` 选最近有效会话；同一训练时间再按保存时间排序。倒计时和预测对账使用同一训练时间，补录不重置计时。旧记录的 `date` 精度可能有限，页面明确这一限制；不把它伪装成精确传感器结束时间。

### 保留的算法与兼容性

- 课程类型基础小时数、RPE／疲劳／酸痛系数、睡眠 6.5 小时阈值、准备度 82 的减免条件、6–48 小时推荐范围均不变。
- `remainingRecoveryHours` 在无会话证据时返回 0 以避免安排小时提醒；展示及预测另行检查证据存在性，0 不代表已恢复。
- 无会话显示“无法估算”；时段结束显示“估算时段已结束”，始终说明不能据此证明身体恢复。
- 预测仍为待回填状态，不用同一计时公式自证命中。
- 晨报和恢复提醒使用筛选后的会话；提醒的身体输入同步使用当日记录。既有疼痛红线优先，未改变计划、准入审核或训练执行锁。
- 本地标记保存在已有训练日志文档中，不新增表、文档键或云同步字段。云端仍使用原白名单投影。

### 用户展示与审查修复

在“今日 → 签到”的已有主动提醒区域后增加只读“恢复时间工程估算”卡片，展示会话来源／时间／RPE、当日有效身体字段和值、缺失项、准备度参与情况及解释边界。显示跟随 `feature.reminders` 的可用状态，保留 `/reminders` 到签到页的兼容跳转。

审查时撤回了最初放在旧提醒页面的卡片，接入实际运行的签到页，并增加真实路由测试。未新增“我的”入口、未修改旧路由。另收紧来源标记解析：字符串 `"false"` 等异常类型不能当作可信标记。窄屏 390×844、1.5 倍文字的签到页展示测试通过。

## 修改文件

|文件|原因|
|---|---|
|`lib/data/models/training_log.dart`|恢复证据标记兼容读写与统一有效性检查|
|`lib/features/dashboard/training_mvp_controller.dart`|恢复会话选择、身体字段检查、训练时间计时、证据说明与下游输入|
|`lib/services/user_insight_service.dart`|预测使用同一会话证据及训练时间，保持待回填|
|`lib/services/training_reminder_service.dart`|移除倒计时等同高强度训练许可的文案|
|`lib/features/daily_check_in/daily_check_in_page.dart`|在实际用户入口展示只读恢复证据卡|
|`test/features/training_loop/recovery_evidence_batch_test.dart`|新增 15 项边界、公式、重启、来源、下游、展示与路由测试|
|`test/features/training_loop/body_confirmation_storage_test.dart`|新增 SQLite 文档适配器、SharedPreferences 的恢复来源标记重启与清理测试|
|`docs/plans/2026-09-12-training-loop-implementation.md`|登记最新批次及停止点|
|本文|记录范围、验证结果与限制|

## 自动验证

|检查|实际结果|日志|
|---|---|---|
|修改前相关基线|31 通过|`/tmp/trainmate-batch20-baseline.log`|
|新增边界测试对旧实现|0 通过、12 失败|`/tmp/trainmate-batch20-red.log`|
|首轮修复|12 通过|`/tmp/trainmate-batch20-green.log`|
|首次综合审查|107 通过|`/tmp/trainmate-batch20-review.log`|
|最终定向回归|108 通过、0 失败|`/tmp/trainmate-batch20-final-tests.log`|
|静态分析|无问题|`/tmp/trainmate-batch20-analyze.log`|
|资源目录只读校验|6 个分域通过|`/tmp/trainmate-batch20-catalog.log`|
|最终 iOS 模拟器构建|通过|`/tmp/trainmate-batch20-ios.log`|
|差异检查|`git diff --check` 通过|本轮执行|

各测试集合不累加。最终集合覆盖本批 17 项新增测试，身体持久化、准备度、负荷、周报、四运动课程、今日页、提醒生命周期、训练日志模型及云投影回归。SQLite 自动测试使用既有文档适配器和合成网关；不能把它等同于真实 SQLite 引擎故障测试。真实模拟器 SQLite 另做只读原文对照。

```sh
scripts/run_flutter_tests_clean_copy.sh \
  test/features/training_loop/recovery_evidence_batch_test.dart \
  test/features/training_loop/body_confirmation_storage_test.dart \
  test/features/training_loop/readiness_evidence_test.dart \
  test/features/training_loop/readiness_batch_test.dart \
  test/features/training_loop/body_load_evidence_batch_test.dart \
  test/features/training_loop/weekly_facts_batch_test.dart \
  test/features/training_loop/daily_course_test.dart \
  test/features/dashboard/today_training_page_test.dart \
  test/services/training_reminder_psychology_test.dart \
  test/features/reminders/application \
  test/data/models/training_log_metadata_test.dart \
  test/data/models/training_log_psychology_test.dart \
  test/data/models/training_log_strength_sets_test.dart \
  test/data/local/cloud_sync_projection_builder_test.dart --reporter expanded
scripts/run_flutter_analyze_clean_copy.sh
scripts/verify_content_catalog.sh
```

Batch 19 已记录旧 `test/widget_test.dart` 的“TrainFlow AI 默认进入今日训练页”在第 1933 行寻找“应用今日调整”失败，并在修改前副本同位置复现。本批未重跑、未修复该既有失败，不能宣称全套测试通过。

## 模拟器语义检查

设备：`TrainMate Batch2 课程调整 20260915`，iOS 26.5，UDID `F1C9B27E-6D81-43A4-938D-136966C40F94`。构建前读取并配置会话默认值，确认干净构建副本的依赖声明和锁文件与工作区逐字相同。

通过已授权本地体验，从“今日”的状态条实际点击进入签到页、滚动到恢复卡片，看到：

- “恢复时间工程估算”“估算时段已结束”。
- 合成历史训练的记录时间 2026-09-15 06:55、训练复盘 RPE 4。
- 没有当日有效身体字段，疲劳、酸痛、睡眠缺失且未计入，准备度缺失未减免时长。
- “估算时段结束不代表身体已恢复”，要求重新确认当日状态并检查身体记录及疼痛。
- 主动提醒没有为这条已结束的旧训练生成新的小时恢复提醒。

本批模拟器只浏览，没有确认签到、添加训练或调整计划。安装、重启、浏览前后 SQLite `legacy_documents` **17 份文档原文逐字一致**，没有新增／改写／删除文档。

证据：`/tmp/trainmate-batch20-before-ui.json`、`/tmp/trainmate-batch20-after-ui.json`；截图 `/var/folders/35/g00sx__534bf30jg1y8l59d00000gn/T/screenshot_optimized_f88ba354-9984-4c79-87bf-bb5ced4565ee.jpg`。

## 剩余问题与停止点

1. 同屏旧签到提示仍将历史疲劳值显示为“今天确认”，而新恢复卡正确显示无当日身体字段；下一批优先统一今日状态条与签到提示的日期／实际字段口径。本批没有修改它们或确认其数据。
2. 本批只收紧恢复消费者。共享均值、全部训练负荷日志来源以及其他洞察仍需独立审查；明确记录类型不等于已证明生理效果或记录准确性，也无法恢复旧版本已经丢弃的来源信息。
3. 未新增算法、健康阈值或自动计划调整；未验证真机生理恢复、实际系统通知投递、线上服务或整体发布闭环。跑姿视频正式入口保持原状态。
4. 回滚应仅撤下本批展示入口或相关消费变更，并保留新的来源标记读取兼容；不清空记录，不恢复整库快照，不用整文件覆盖其他批次改动。当前没有执行回滚。

本轮完成并停在 Batch 20，未进入下一批。
