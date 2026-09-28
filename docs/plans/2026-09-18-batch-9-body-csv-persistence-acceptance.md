# Batch 9：身体 CSV 整批保存与失败恢复验收

日期：2026-09-18。按用户要求，本次只执行一个 Batch，完成实施、审查、修复及验证后停止。

## 范围与基线

本批仅处理身体 CSV 的整批持久化及提交期间保护。普通快录、签到的独立失败恢复和跨文档一致性另批处理。保留 CSV 解析规则：无效行跳过，合法行组成一次保存；缺失字段仍可沿用既有历史值，但不计为本次实际测量。

开始时工作区有 397 条未提交状态，快照为 `/tmp/trainmate-batch9-start-status.txt`；本批涉及的已有文件另存于 `/tmp/trainmate-batch9-before/`，以此核对增量。没有覆盖既有改动、创建分支、提交、推送、部署、改表或升级依赖。隔离构建副本的 `pubspec.yaml`、`pubspec.lock` 与工作区逐字节一致。

基线定向测试 41 项通过。本批新增 6 项故障／界面测试在旧实现上全部失败：同步失败被吞掉、异步失败遗留记录、首次失败仍有文档、等待期间共享仓储提前发布、重复提交未阻断（等待超时）、导入按钮未禁用。未降低已有断言。

## 实施与审查

1. 在独立候选仓储内计算本次所有有效行及修订，只向真实存储提交一次完整身体文档。等待 `flush` 成功后更新共享仓储和业务投影。原单条确认入口复用同一提交实现。
2. 同步／异步写入失败均恢复导入前的原文档；首次导入失败移除本次新文档。恢复失败时明确显示磁盘状态无法确认，并阻止当前仓储继续写入。
3. 控制器等待提交完成并捕获异步错误。失败保留 CSV、待确认截图、原指标、修订、导入历史和持久化版本，允许安全重试。
4. 提交期间禁用导入和确认按钮，拒绝重复导入、快录、截图确认、身体记录清理及复制昨日。沿用功能提交锁阻止停用和换账号；沿用代际判断，使控制器重建后的迟到结果不更新新状态。
5. 审查确认：解析错误仍不写入；成功提示保留原契约；没有改训练算法、CSV 字段、来源标记、数据库结构或同步范围。两种存储复用原文档恢复方式，没有新增绕过授权的写入通道。

“整批”仅指本次解析成功的记录一起提交，不改变无效行跳过规则。成功后再次主动导入相同 CSV，仍沿用原有同日覆盖及修订语义；本批防止的是提交中重复操作和失败重试产生多余修订。

## 修改文件

|文件|本批修改原因|
|---|---|
|`lib/data/repositories/body_metric_repository.dart`|增加整批确认保存，复用原候选文档、恢复和写锁|
|`lib/features/data_center/application/body_metric_controller.dart`|等待整批提交，忙状态、失败提示与迟到结果保护|
|`lib/features/data_center/data_center_page.dart`|提交中禁用导入和身体记录确认按钮|
|`test/features/training_loop/body_csv_batch_test.dart`|新增六项整批故障、重试、生命周期与实际组件测试|
|`test/features/training_loop/body_confirmation_storage_test.dart`|新增 SQLite 文档适配器和 SharedPreferences 各一项 CSV 失败恢复、重试、重启及清理测试|
|`docs/plans/2026-09-12-training-loop-implementation.md`|更新当前批次状态，保留旧批次记录|
|本文|记录范围、证据与未验证边界|

## 自动验证

|检查|本次实际结果|日志|
|---|---|---|
|修改前基线|41 通过|`/tmp/trainmate-batch9-baseline.log`|
|新增测试在旧代码上的复现|6 失败，包含重复提交未阻断导致的超时|`/tmp/trainmate-batch9-red.log`|
|首次修复后 CSV 与单条确认回归|13 通过|`/tmp/trainmate-batch9-green.log`|
|最终定向回归|87 通过、0 失败|`/tmp/trainmate-batch9-final-tests.log`|
|`flutter analyze`|无问题|`/tmp/trainmate-batch9-analyze.log`|
|内容目录只读校验|6 个分域通过|`/tmp/trainmate-batch9-catalog.log`|
|iOS 模拟器构建|通过|`/tmp/trainmate-batch9-ios.log`|
|差异空白检查|通过|`/tmp/trainmate-batch9-diff-check.log`|

不同测试集合不加总。最终测试涵盖数据中心、身体仓储、CSV／截图解析、单条确认、样例只读、质量说明、准备度、签到、伙伴事实读取、健康功能生命周期及账号缓存清理。

SQLite 测试使用真实 `DatabaseLocalStorageService` 缓存／写队列，在底层数据库网关注入故障；SharedPreferences 使用真实适配器与合成平台存储。测试验证故障恢复后重新创建存储读取、失败重试仅一次有效修订、清理后无旧身体记录，以及 SQLite 云同步写调用为零。这不是物理磁盘损坏、进程被强杀或真实跨账号云会话的设备验证。

复现命令：

```sh
scripts/run_flutter_tests_clean_copy.sh \
  test/features/data_center \
  test/data/repositories/body_metric_repository_test.dart \
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

设备：`TrainMate Batch2 课程调整 20260915`，iOS 26.5，UDID `F1C9B27E-6D81-43A4-938D-136966C40F94`。安装本批修复版，通过既已授权的本地体验执行，无云端账号创建或真实健康资料输入。

- 导入前：15 个业务文档，1 条 9 月 17 日合成截图记录，0 条修订。
- 在真实 CSV 表单输入 9 月 15／16 日两条合成记录，体重分别 70.2／70.1 kg；保留既有 9 月 17 日记录。模拟器键盘录入带下划线表头有偏差，提交前已清空并改用解析器支持的短字段：`date,weight,hrv,sleep,fatigue,soreness`。
- 页面明确显示解析 2 条、跳过 0 行；两行共四个字段沿用历史值（体脂率、静息心率），没有把继承字段标为实际测量。
- 持久化后：3 条身体记录、0 条修订；仅 `trainflow.body_metrics.v1` 变化。原计划、训练日志、调整、周报及其他 14 个业务文档原文不变。
- 停止并重启 App，重新进入身体数据页：3 条记录、3/7 日覆盖、7 日体重均值 70.1 kg；静息心率仍只有 1 个有效测量日，因此“无法比较”。页面保留“记录不足”。
- 重启前后全部 15 个业务文档原文一致，没有额外修订或重复写入。既有成长投影按两条新增身体记录从 32 XP 变为 42 XP，未修改其算法；训练准备度仍为“无法评估”。

只读数据库对照证据：`/tmp/trainmate-batch9-before-ui.json`、`/tmp/trainmate-batch9-after-ui.json`、`/tmp/trainmate-batch9-saved-documents.json`、`/tmp/trainmate-batch9-restart.json`。未恢复或替换整库。

重启后质量说明截图：`/var/folders/35/g00sx__534bf30jg1y8l59d00000gn/T/screenshot_optimized_df14c033-0fab-4816-b231-0fb327349825.jpg`。完整页面内容由 CUA 的实际画面及可访问文本确认；另一次 Xcode 快照只有操作目标摘要，不能单独证明指标内容。临时文件可能被系统清理。

## 边界与后续

本批通过 CSV 工程链路和上述模拟器正常导入／重启门槛；故障、停用、账号切换由自动测试覆盖，未在真机注入磁盘故障。持续磁盘失败或保存中强杀进程不承诺跨进程原子恢复。

普通快录／签到的独立恢复与先行提交交错、身体趋势和固定指标目标的整体解释审查仍待后续批次。旧身体样例来源未追认或删除。登录页仍有既有 `Not Found`，本批不代表线上登录验收。Apple 健康、语音和真实模型／真机验证未完成，跑姿视频正式入口继续关闭。项目整体发布门槛尚未全部通过。
