# Batch 10：签到及成就回执保存验收

日期：2026-09-18。按用户要求，每次只执行一个 Batch。本批完成修改、审查、修复、测试与限定模拟器验收后停止。

## 范围与基线

本批处理签到文档的独立写入：主观偏累、按计划恢复、安全暂停及成就回执收取。普通快录和“和昨天一样”涉及身体记录与签到两个文档，其完整失败恢复和交错写入另批处理。本批没有改变签到规则、累计门槛、训练算法或健康阈值。

当前工作区起始有 398 条未提交状态，快照 `/tmp/trainmate-batch10-start-status.txt`。修改前相关文件备份在 `/tmp/trainmate-batch10-before/`；账号协调器备份为 `/tmp/trainmate-batch10-account-switch-before.dart`。保留既有改动，未创建分支、提交、推送、部署、升级依赖或改数据库结构。

基线 49 项通过。新增的首批 11 项测试在旧实现上全部失败，复现了失败残留、提前显示签到／里程碑、回执收取后无法重试、重复操作及界面按钮未禁用等问题。

## 修改与审查修复

- 签到和成就收取先在候选仓储计算，保存原 `trainflow.daily_check_ins.v1` 文档并等待 `flush` 成功，再更新共享仓储和页面。存储格式仍为原 schemaVersion 2，兼容原 v1 记录。
- 同步／异步保存失败恢复旧文档、原签到天数及未读回执；首次写入失败不遗留签到文档。恢复也失败时提示磁盘状态无法确认，并阻止当前仓储继续写入。
- 同日重复签到、重复收取已读回执不重复写入或增加天数。提交中按钮禁用，仓储与控制器拒绝交错写入；持有既有插件提交锁，禁止提交期间停用和换账号。
- 控制器代际检查阻止重建后的迟到回调覆盖新状态。确认弹窗保留开始时的账号／插件来源，取消不写入，弹窗期间换账号后旧确认失效。
- 首轮测试发现账号切换清理后，签到仓储缓存仍保留旧天数。修复 `AccountSwitchCoordinator`，在重建控制器前失效签到仓储；没有改变认证、授权或账号清理规则。
- “今天偏累”在签到后仍单独保存既有调整说明。本批捕获原操作来源，检查参与功能和账号是否失效，并将后一步失败明确显示为“签到已保存，偏累说明未更新”。这不是两文档原子事务，不会因说明失败而伪称签到未保存；重试不重复计数，也不自动更改计划。

“今天偏累，建议轻松版”是跨签到和每日调整的界面动作，检查两个功能的可用性；没有增加插件装配的强依赖。独立的恢复／暂停记录及成就收取不依赖每日调整。

## 修改文件

|文件|原因|
|---|---|
|`lib/data/repositories/daily_check_in_repository.dart`|新增等待落盘的签到／回执接口，候选提交、恢复、写入保护及幂等|
|`lib/features/data_center/application/body_metric_controller.dart`|统一独立签到提交状态、中文错误、迟到回调防护|
|`lib/features/daily_check_in/daily_check_in_page.dart`|保存中禁用按钮，确认来源校验，区分签到与后续说明的结果|
|`lib/features/auth/application/account_switch_coordinator.dart`|换账号时清除旧签到仓储缓存|
|`test/features/training_loop/check_in_persistence_batch_test.dart`|13 项故障、幂等、生命周期、弹窗、界面及两步结果测试|
|`test/features/training_loop/body_confirmation_storage_test.dart`|新增两种存储的签到／回执失败恢复与重启回读验证|
|`test/features/data_center/application/body_metric_controller_test.dart`|原计划恢复测试等待异步提交完成后检查，原断言不变|
|`docs/plans/2026-09-12-training-loop-implementation.md`|更新最新批次状态，保留历史记录|
|本文|范围、过程、证据和未验证边界|

## 自动验证

|检查|实际结果|证据|
|---|---|---|
|修改前定向基线|49 通过|`/tmp/trainmate-batch10-baseline.log`|
|首批故障测试在旧代码上的复现|11 失败|`/tmp/trainmate-batch10-red.log`|
|首次修复后的回归|34 通过、1 失败，定位账号签到缓存未失效|`/tmp/trainmate-batch10-green.log`|
|账号缓存修复与两种存储测试|17 通过|`/tmp/trainmate-batch10-storage.log`|
|补充界面来源审查|18 通过、1 失败，组件测试缺少原生通知清理平台|`/tmp/trainmate-batch10-review-tests.log`|
|最终定向回归|108 通过、0 失败|`/tmp/trainmate-batch10-final-tests.log`|
|静态分析|无问题|`/tmp/trainmate-batch10-analyze.log`|
|内容目录只读校验|6 个分域通过|`/tmp/trainmate-batch10-catalog.log`|
|iOS 模拟器构建|通过|`/tmp/trainmate-batch10-ios.log`|
|差异空白检查|通过|`/tmp/trainmate-batch10-diff-check.log`|

不同测试集合不加总。组件账号切换测试按项目既有方式注入合成通知网关，仍断言实际调用了资源取消；没有跳过账号清理或放宽断言。一次文件写入命令因本机 claude-mem 钩子解析错误未执行，后续使用文件补丁完成，未修改或安装该插件。

两种存储验证使用真实 `DatabaseLocalStorageService`／SharedPreferences 适配器，并在底层合成网关注入故障。分别验证第七天签到及里程碑、收取失败恢复、重试、重新创建存储读取、账号业务清理；SQLite 云同步写调用为零。这不等同于物理磁盘故障或真实云端账号切换验收。

最终命令：

```sh
scripts/run_flutter_tests_clean_copy.sh \
  test/features/data_center \
  test/data/repositories/body_metric_repository_test.dart \
  test/data/repositories/daily_check_in_repository_test.dart \
  test/features/training_loop/check_in_persistence_batch_test.dart \
  test/features/training_loop/body_csv_batch_test.dart \
  test/features/training_loop/body_quality_batch_test.dart \
  test/features/training_loop/body_examples_batch_test.dart \
  test/features/training_loop/body_confirmation_batch_test.dart \
  test/features/training_loop/body_confirmation_storage_test.dart \
  test/features/training_loop/readiness_batch_test.dart \
  test/features/training_loop/readiness_evidence_test.dart \
  test/services/body_metric_import_service_test.dart \
  test/services/body_metric_snapshot_service_test.dart \
  test/features/daily_check_in \
  test/features/companion/application/training_state_reader_test.dart \
  test/plugins/lifecycle/health_data_lifecycle_test.dart \
  test/features/auth/account_switch_coordinator_test.dart --reporter expanded
scripts/run_flutter_analyze_clean_copy.sh
scripts/verify_content_catalog.sh
```

## 隔离模拟器验收

设备：`TrainMate Batch2 课程调整 20260915`，iOS 26.5，UDID `F1C9B27E-6D81-43A4-938D-136966C40F94`。沿用已授权的本地体验与合成资料。隔离构建副本的 `pubspec.yaml`、`pubspec.lock` 与工作区逐字节一致。

1. 开始为 15 个业务文档、3 条身体记录、0 条签到；今日完成 0%，准备度无法评估，42 XP。
2. 实际打开“今日 → 精简签到 → 按计划恢复”，查看确认说明后取消。只读数据库比较全部 15 个文档原文不变。
3. 再次打开并明确确认，页面显示“已记录今天按计划恢复”，累计／连续 1 天。再次确认，显示同日不增加连续天数。
4. 数据库新增的唯一文档为 `trainflow.daily_check_ins.v1`：1 条 `planned_rest`，0 条里程碑回执。原身体记录、计划、训练日志、调整、周报及其他 15 个文档原文不变。
5. 停止并重启 App，重新进入本地体验和签到页，仍显示累计／连续 1 天。今日完成仍为 0%，准备度仍无法评估，XP 仍为 42；重启前后全部 16 个业务文档原文一致。

证据：`/tmp/trainmate-batch10-before-ui.json`、`/tmp/trainmate-batch10-cancel-ui.json`、`/tmp/trainmate-batch10-after-ui.json`、`/tmp/trainmate-batch10-saved-documents.json`、`/tmp/trainmate-batch10-restart.json`。重启页面截图：`/var/folders/35/g00sx__534bf30jg1y8l59d00000gn/T/screenshot_optimized_f31e8499-f8bd-4743-9993-03ccdacd6265.jpg`。这些本机临时证据可能被系统清理，未用整库恢复替换现有数据。

## 交付边界与下一批

本批通过独立签到／成就回执的自动验证，以及恢复签到的模拟器取消、确认、重复和重启门槛。主观偏累、成就收取、保存失败、插件停用和账号切换由自动测试覆盖，未在本次模拟器逐项重演，也未在真机注入磁盘故障。不承诺持续磁盘失败或保存中强杀进程的跨进程原子恢复。

普通快录和“和昨天一样”的双文档保存、旧路径先行提交与新操作交错仍待下一批；不能把本批视为所有身体与签到写入均已验收。身体趋势、固定目标解释及旧样例来源审查继续保留原状态。登录页既有 `Not Found` 未处理；Apple 健康、语音、真实模型与真机效果未完成验收，跑姿视频正式入口仍关闭。整体发布门槛尚未全部通过。
