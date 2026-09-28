# Batch 22：健康概览恢复字段的日期与来源边界

日期：2026-09-20。本批完成首页健康概览中睡眠、静息心率及 HRV 的实现、审查、修复和限定验收；停止在本批。

## 基线与范围

起始工作区 421 条未提交状态，快照 `/tmp/trainmate-batch22-start-status.txt`。已有改动保留；未创建分支、提交、推送、部署、升级依赖或修改数据库结构。

修改前，健康概览从全部健康摘要取最新日期，不检查是否今日、同步时间或来源血缘；非空零值也直接显示。身体回退读取最新历史记录，只检查大于零，忽略实际字段和来源。状态条虽然已经采用当日口径，健康概览仍可能把昨日 7 小时、60 次/分和 50 ms 显示为当前恢复数据。

本批仅修改三项恢复字段及其说明、首页传参。不修改活动摘要与趋势、成长计数、健康授权、同步、身体仓储、计划或签到提交。

## 修改内容

- 三项恢复数据按当前本地自然日读取；身体记录还必须非未来、时间有效，并通过现有 `hasValue` 的来源和实际字段检查。首页传入与状态条相同的 `currentDecisionBodyMetric`。
- 健康摘要检查日期及同步时间，拒绝未来同步、无效同步时间和同步早于所属日的摘要；同日按最近同步排序。
- 最近摘要必须具有现有第二版样本血缘及非空样本标识，才用于新展示。旧版来源不明的摘要不当作当日观测，历史存储及读取不改变。此检查确认的是已有来源元数据，不代表重新验证传感器准确性。
- 各字段单独检查正值和有限数；保持健康摘要优先、身体记录补缺。最近摘要的缺失或未知来源不从旧同步摘要中补回；身体侧也不跨多条记录补齐。
- 卡片显示逐项日期、Apple 健康摘要或身体记录来源；缺失显示“今日无可用记录”。不展示样本 UUID，不把记录存在解释为今日状态已确认，也不输出恢复正常或临床判断。
- 无睡眠时由“待同步”改为“暂无数据”，与支持手动记录的实际路径一致。

## 修改文件

|文件|原因|
|---|---|
|`lib/features/dashboard/widgets/today_health_overview.dart`|三项逐字段有效性、日期、来源与最近同步选择；卡片说明|
|`lib/features/dashboard/today_training_page.dart`|复用当日身体记录，移除仅为旧回退使用的变量|
|`test/features/dashboard/widgets/today_health_overview_test.dart`|修正无来源且无效恢复零值的旧期望，继续保留真实活动零值断言|
|`test/features/training_loop/health_overview_evidence_batch_test.dart`|新增 20 项来源、字段、时间、混合来源、首页接线及窄屏入口验证|
|`docs/plans/2026-09-12-training-loop-implementation.md`|最新批次和停止点|
|本文|审查、自动测试、模拟器证据与剩余范围|

## 审查与自动验证

|检查|结果|日志|
|---|---|---|
|修改前既有相关测试|18 通过|`/tmp/trainmate-batch22-baseline.log`|
|新增测试对旧实现|2 通过、15 失败，复现本批边界问题|`/tmp/trainmate-batch22-red.log`|
|首轮修复与既有概览测试|20 通过|`/tmp/trainmate-batch22-green.log`|
|审查后最终定向回归|115 通过、0 失败|`/tmp/trainmate-batch22-final-tests.log`|
|静态分析|无问题|`/tmp/trainmate-batch22-analyze.log`|
|内容目录只读校验|6 个分域通过|`/tmp/trainmate-batch22-catalog.log`|
|iOS 模拟器构建|通过|`/tmp/trainmate-batch22-ios.log`|
|差异检查|`git diff --check` 通过|本轮执行|

集合不累加。审查对照本批修改前副本，差异保存在 `/tmp/trainmate-batch22-review.diff`。审查补充了混合来源的文字断言、晚间 UTC 表示及跨午夜边界、真实首页读取当日记录和浏览不写入验证。320 宽、两倍字号下，实际滚动到恢复卡说明并检查可见、无布局异常，再点击进入签到回调；不是只检查屏外组件存在。

原测试把没有来源血缘且睡眠／心率／HRV 全零的快照期望为有效恢复值。本批明确改为缺失，并增加有效健康优先、身体逐字段补缺以及非有限值反例；活动真实零值断言保留，没有用删除反例或宽松断言掩盖失败。

```sh
scripts/run_flutter_tests_clean_copy.sh \
  test/features/training_loop/health_overview_evidence_batch_test.dart \
  test/features/dashboard/widgets/today_health_overview_test.dart \
  test/features/training_loop/check_in_evidence_batch_test.dart \
  test/features/training_loop/readiness_evidence_test.dart \
  test/features/training_loop/recovery_evidence_batch_test.dart \
  test/features/dashboard/today_training_page_test.dart \
  test/data/repositories/health_snapshot_repository_test.dart \
  test/features/profile/application/health_data_gateway_io_test.dart \
  test/features/profile/application/health_sync_controller_test.dart --reporter expanded
scripts/run_flutter_analyze_clean_copy.sh
scripts/verify_content_catalog.sh
```

Batch 19 的旧端到端“应用今日调整”入口失败、Batch 21 的首页其他区域大字布局溢出，本批未修复或重跑对应失败场景。115 项通过不代表全库通过，也不代表整个首页两倍字号验收完成。

## 模拟器与数据不变性

使用隔离模拟器 `TrainMate Batch2 课程调整 20260915`，iOS 26.5，UDID `F1C9B27E-6D81-43A4-938D-136966C40F94`。先检查会话默认值，干净构建副本的依赖声明与锁文件逐字节一致。

沿用已授权本地体验，打开今日页并滚动到健康概览：

- 恢复卡三项实际显示“暂无数据”，逐项显示“今日无可用记录”，不再沿用昨日合成身体数值。
- 完整说明在屏幕内可见；点击恢复卡实际进入精简签到页。
- 签到仍显示 2026-09-19 的历史来源及当日待填写，证明历史可读而非被清除。
- 未触发健康授权、同步、签到保存或训练／计划操作。安装、启动、浏览前后 `legacy_documents` 的 **17 份业务文档原文完全相同**。

证据：

- `/tmp/trainmate-batch22-before-ui.json`
- `/tmp/trainmate-batch22-after-ui.json`
- 恢复卡截图：`/var/folders/35/g00sx__534bf30jg1y8l59d00000gn/T/screenshot_optimized_8789ae2d-5e46-41ac-a849-4a913b3648e9.jpg`

有效健康数值、混合来源和异常时间由合成自动测试验证；模拟器没有真实 Apple 健康样本。本批不能代替真机权限、传感器准确性或线上服务验收。

## 下一批与回滚

下一批优先检查“和昨天一样”的日期选择与实际保存语义：目前入口名称指向昨日，底层仍沿用最新记录，需要独立复现、审查与持久化验收。本批不进入该项。

健康概览的活动趋势、连击、其他训练统计仍有各自的数据边界，未因本批三项恢复字段通过而被一并验收。整页大字布局、旧端到端失败、真机及整体发布门槛仍待处理。

如需回滚，仅恢复本批两处生产文件中的健康概览展示及传参差异；不整文件覆盖用户其他修改，不恢复整库快照，不清空记录、计划或配置。
