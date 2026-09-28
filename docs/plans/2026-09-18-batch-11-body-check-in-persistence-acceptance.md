# Batch 11：身体快录与签到联合保存验收

日期：2026-09-18。遵循每次只执行一个 Batch：本批完成实施、审查、修复、测试及限定模拟器验收后停止。

## 范围与基线

本批处理普通快录和“和昨天一样”涉及的身体记录与签到两份本机文档。保留原有身体覆盖、签到、里程碑及字段来源规则，不新增训练算法，不修改计划。

开始时工作区有 400 条未提交状态，记录于 `/tmp/trainmate-batch11-start-status.txt`。相关文件修改前备份在 `/tmp/trainmate-batch11-before/`。未覆盖既有改动，未创建分支、提交、推送、部署、升级依赖或改表。

基线 70 项通过。新写的首批 8 项测试在旧实现上全部失败，复现身体或签到写入失败后的残留、提前发布及交错写入问题。

## 实现与审查

- 将前两批候选文档的落盘、恢复、发布和解锁逻辑提为共用工具。两仓储先准备各自候选记录，保存两份文档并等待写队列成功后，才发布仓储缓存、页面记录、签到天数和持久化版本。
- 任一同步写入或异步落盘失败，尝试逐份恢复原文档；原来不存在的文档恢复为不存在。即使一份恢复失败，也继续恢复其余文档，不使用整库替换。
- 恢复失败时保留旧页面投影，显示磁盘状态无法确认，并阻止当前仓储继续写入。它不是断电或进程强杀情况下的跨文档原子事务；本批不作该承诺。
- 提交期间禁用保存入口，控制器和仓储阻止重复及交错操作。同一个插件提交操作覆盖两个功能，换账号和停用被阻止；重建控制器后迟到结果不覆盖新页面状态。
- 审查补齐第二仓储准备失败时第一仓储的锁释放，以及内存仓储候选接口的写入保护。两份文档都落盘前，训练读取仍使用旧仓储事实。
- 签到插件已停用时，普通快录仅保存身体记录；“和昨天一样”会写身体数据，因此同时检查身体数据功能可用性。没有增加插件装配强依赖。
- 今日已有签到时保留其原文、类型和累计数，例如既有“按计划恢复”不会被快录覆盖。普通快录仍只将本次输入的 5 项标为实际字段；预填沿用上次字段可用性，不把继承数值变成新增测量。
- 成功后再次主动执行身体预填，仍遵循原同日覆盖规则，产生身体修订；签到天数保持幂等。本批保证提交中不重复、失败重试不多留修订，不声称所有成功后的再次保存都不产生修订。

异常值和截图的待确认入口仍沿用原单身体文档确认流程。补录日期与今日签到的原对应规则未改变。持久化成功后，现有身体记录相关成长投影可以按原规则变化，不将其称为训练完成。

## 修改文件

|文件|修改原因|
|---|---|
|`lib/services/confirmed_local_document_write.dart`|共用候选文档提交、逐份恢复、成功发布和锁释放|
|`lib/data/repositories/body_metric_repository.dart`|准备身体及修订候选，复用单份与联合提交，保持写入保护|
|`lib/data/repositories/daily_check_in_repository.dart`|准备签到候选，复用提交工具，已有签到不重写|
|`lib/features/data_center/application/body_metric_controller.dart`|两入口统一联合提交、忙状态、失败提示和代际保护|
|`lib/features/data_center/data_center_page.dart`|保存期间禁用快录按钮|
|`test/features/training_loop/body_check_in_batch_test.dart`|12 项联合故障、缓存、页面、插件、字段和迟到结果验证|
|`test/features/training_loop/body_confirmation_storage_test.dart`|增加 8 项双存储首／次文档失败、重启、重试及清理验证|
|`docs/plans/2026-09-12-training-loop-implementation.md`|登记最新批次，保留历史记录|
|本文|记录本批范围、证据和未验证边界|

## 自动验证

|检查|实际结果|日志|
|---|---|---|
|修改前基线|70 通过|`/tmp/trainmate-batch11-baseline.log`|
|新增首批测试验证旧实现|8 失败，复现预期问题|`/tmp/trainmate-batch11-red.log`|
|首轮实现回归|60 通过|`/tmp/trainmate-batch11-green.log`|
|双存储及页面补验|28 通过、1 失败：测试页面未提供 Scaffold，错误提示无法展示|`/tmp/trainmate-batch11-storage-ui.log`|
|补齐测试页面容器后|本批 12 项通过，保留失败、输入和重试断言|`/tmp/trainmate-batch11-ui-retry.log`|
|最终定向回归|128 通过，0 失败|`/tmp/trainmate-batch11-final-tests.log`|
|静态分析|无问题|`/tmp/trainmate-batch11-analyze.log`|
|内容目录只读校验|6 个分域通过|`/tmp/trainmate-batch11-catalog.log`|
|iOS 模拟器构建|通过|`/tmp/trainmate-batch11-ios.log`|
|差异空白检查|git diff --check 通过|本轮执行|

最终回归覆盖数据中心、签到、两仓储、前三批持久化、样例与质量、准备度证据、CSV／截图解析、伙伴读取、健康插件生命周期及账号清理。SQLite 测试使用真实文档适配器的缓存与写队列，在底层网关注入失败；SharedPreferences 同样使用真实适配器。实际 SQLite 磁盘读写另由模拟器验证。没有将故障替身测试等同于设备断电恢复验证。

复现最终检查：

```sh
scripts/run_flutter_tests_clean_copy.sh \
  test/features/data_center \
  test/data/repositories/body_metric_repository_test.dart \
  test/data/repositories/daily_check_in_repository_test.dart \
  test/features/training_loop/body_check_in_batch_test.dart \
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

设备为 `TrainMate Batch2 课程调整 20260915`，iOS 26.5，UDID `F1C9B27E-6D81-43A4-938D-136966C40F94`。沿用已授权本地体验及合成数据；构建副本依赖配置和锁文件与工作区逐字节一致。设备本轮开始处于关机状态，启动后读取原 16 份文档再安装新版本，没有清空测试数据。

1. 数据中心将合成体重从 70.0 改为 70.8 kg，保存今日快录。页面显示保存成功；磁盘身体记录由 3 条变 4 条，无修订，实际字段 5 项。已有今日按计划恢复签到原文不变。
2. 进入精简签到，点击“和昨天一样”。身体记录仍为 4 条，新产生 1 条同日修订，最新备注为“精简签到：和昨天一样”，实际字段仍为 5 项。签到文档原文不变，累计／连续仍为 1 天。
3. 两次保存分别对比所有本机文档，只有 `trainflow.body_metrics.v1` 变化；计划、训练日志、调整、周报和插件设置均保持原文。
4. 停止并重新启动 App，进入本地体验和身体数据页。页面回读手动来源、4 条记录及 1 条修订，70.8 kg 与预填备注正确；全部 16 份文档与重启前逐字一致。准备度仍显示无法评估，未补造当日状态确认。

本机证据：

- `/tmp/trainmate-batch11-before-ui.json`：写入前全部文档原文。
- `/tmp/trainmate-batch11-manual-ui.json`：快录后对照。
- `/tmp/trainmate-batch11-prefilled-ui.json`：预填后对照。
- `/tmp/trainmate-batch11-restart-ui.json`：重启后对照。
- `/var/folders/35/g00sx__534bf30jg1y8l59d00000gn/T/screenshot_optimized_9af05e77-2029-46eb-9d2a-ce08b383cab7.jpg`：快录保存成功。
- `/var/folders/35/g00sx__534bf30jg1y8l59d00000gn/T/screenshot_optimized_2c5b77c7-3174-4a80-b061-481495ce2c4f.jpg`：重启后身体摘要。

这些日志与截图是本机临时文件，可能被系统清理。

## 限制与后续

本批停止于 Batch 11。存储故障、提交中停用和换账号通过自动测试验证，未在模拟器中注入磁盘故障。真机、Apple 健康、语音、真实模型和线上登录不属于本批已验收范围，整体发布门槛仍未全部通过。跑姿视频正式入口继续关闭。

跨文档断电／进程强杀恢复未验证；本批只保证可捕获写入失败时的恢复与发布顺序。身体趋势、固定指标目标等解释尚未完成整体审查，未知来源旧数据未被追认为可信测量。既有周期重排日期不足两天的失败未纳入本批集合，未修改其断言。

回滚仅切换本批入口实现，不删身体记录、签到或修订，不恢复整库快照；存储格式与读取兼容保留。下一批范围需单独执行，本轮不继续扩展。
