# Batch 18：身体导出登记持久化与账号生命周期验收

执行时间：2026-09-19 夜间至 2026-09-20 凌晨。本批只处理身体导出登记的保存、清除、失败恢复和账号边界，完成审查、修复、测试与限定模拟器验收后停止。

## 基线与影响范围

起始工作区有 414 条未提交状态，快照 `/tmp/trainmate-batch18-start-status.txt`；四个目标源码文件修改前备份在 `/tmp/trainmate-batch18-before/`。保留已有未提交内容，不创建分支或提交，不推送、部署或升级依赖。

原导出仓储先更新内存，再请求写盘；同步写入或异步落盘失败时，没有恢复内存和文档。控制器没有提交锁，可能在保存期间重复操作或切换账号。账号协调器虽重建导出仓储，却未重置 JSON／CSV 临时预览和导出包摘要。清除确认框还可能跨越账号切换后继续执行。

沿用本地文档 `trainflow.body_metric_exports.v1`、现有 SQLite `legacy_documents` 和 SharedPreferences 白名单，不改表、键、版本或云同步范围。导出登记归属必需的 `core.data_rights`，本批不把它变成可选插件，也不改变身体数据插件启停规则。

## 实施与审查修复

- 仓储增加等待持久化的确认保存／清除接口。生产控制器使用这些接口，保留原同步接口兼容已有调用；经搜索，当前生产导出写入只有该控制器。
- 候选列表复用 `PreparedLocalDocumentWrite` 和 `commitLocalDocumentWrites`：落盘成功后才发布仓储列表；失败补写原文档，首次失败不遗留登记文档。恢复再次失败时阻止继续写入，并显示中文原因。
- 保留原最多 50 条登记及同 ID 替换行为；新确认接口有独立覆盖测试。记录 ID 时间精度提高到微秒，不改变已保存 ID 的读取。
- 控制器登记提交操作到 `core.data_rights`，持有现有运行时提交锁直到写入／恢复结束。期间阻止重复保存、交错清除和账号域替换。
- 增加保存中状态。页面禁用 JSON、CSV、导出包和清除登记按钮；失败保留当前预览与原登记，允许重试；只有持久化成功才显示已登记或已清除。
- 控制器使用已有代际检查模式，重建后的迟到回调不发布到新状态。
- 账号协调器追加失效两个临时预览 provider；不修改认证、账号换绑授权或清理事务规则。
- 清除确认框打开时捕获操作来源，确认后重新检查账号代际。旧账号确认不能删除新账号登记。
- 明确产品文案：当前是本机预览／摘要和登记，系统文件保存与分享尚未接入。摘要预览与登记结果区分。

审查中发现 Widget 账号切换测试触发了原生通知清理，普通 Flutter 测试没有原生插件，导致一项失败。按项目已有模式替换通知网关，并断言清理调用次数大于零；没有跳过账号切换、降低清理或跨账号数据断言，也没有修改生产通知代码。

## 修改文件

|文件|修改原因|
|---|---|
|`lib/data/repositories/body_metric_export_repository.dart`|候选提交、成功后发布、失败恢复和仓储写锁|
|`lib/features/data_center/application/body_metric_export_controller.dart`|等待确认落盘、提交锁、中文状态与代际保护|
|`lib/features/data_center/data_center_page.dart`|保存中禁用、摘要说明及清除对话框账号复查|
|`lib/features/auth/application/account_switch_coordinator.dart`|换账号时重置导出临时预览与摘要|
|`test/features/training_loop/body_export_persistence_batch_test.dart`|10 项故障、并发、页面、账号、迟到回调及数量兼容测试|
|`test/features/training_loop/body_confirmation_storage_test.dart`|复用既有存储适配器故障设施，新增 4 项导出保存／清除验证|
|`docs/plans/2026-09-12-training-loop-implementation.md`|更新当前批次状态|
|本文|本批证据、限制和回滚方式|

## 自动验证

|检查|结果|日志|
|---|---|---|
|修改前相关基线|39 通过|`/tmp/trainmate-batch18-baseline.log`|
|新增故障测试对旧实现|7 失败，复现问题|`/tmp/trainmate-batch18-red.log`|
|首轮修复回归|46 通过|`/tmp/trainmate-batch18-green.log`|
|增加页面与适配器审查|65 通过、1 失败（测试缺少原生通知网关）|`/tmp/trainmate-batch18-review.log`|
|补齐测试网关后复验|66 通过|`/tmp/trainmate-batch18-review-retry.log`|
|补齐确认接口数量兼容后的最终回归|67 通过、0 失败|`/tmp/trainmate-batch18-final-tests.log`|
|静态分析|无问题|`/tmp/trainmate-batch18-analyze.log`|
|内容目录只读校验|6 个分域通过|`/tmp/trainmate-batch18-catalog.log`|
|iOS 模拟器构建|通过|`/tmp/trainmate-batch18-ios.log`|
|差异检查|`git diff --check` 通过|本轮执行|

集合不累加，不代表整个项目测试集全部通过。存储测试使用真实 SQLite 文档适配器／SharedPreferences 实现，在底层网关注入故障；底层存储由测试替身模拟，不等同于真实 SQLite 引擎故障测试。正常原生落盘另由模拟器读取验证。

覆盖同步写入失败、异步 flush 失败、首次失败、恢复再次失败、保持原登记和预览、重试、等待期间不发布事实、重复提交阻断、账号提交锁、旧控制器迟到回调、账号预览清理、旧对话框确认失效、取消不写入、两种存储重新创建读取、业务域清理，以及导出登记不产生同步写入。JSON／CSV 内容沿用 Batch 17 测试。

```sh
scripts/run_flutter_tests_clean_copy.sh \
  test/features/training_loop/body_export_persistence_batch_test.dart \
  test/features/training_loop/body_confirmation_storage_test.dart \
  test/features/data_center \
  test/data/repositories/body_metric_export_repository_test.dart \
  test/features/training_loop/body_history_export_evidence_batch_test.dart \
  test/features/auth/account_switch_coordinator_test.dart --reporter expanded
scripts/run_flutter_analyze_clean_copy.sh
scripts/verify_content_catalog.sh
```

## 模拟器验收

设备：`TrainMate Batch2 课程调整 20260915`，iOS 26.5，UDID `F1C9B27E-6D81-43A4-938D-136966C40F94`。沿用已授权本地体验及 5 条合成身体记录；构建前核对会话默认值，干净副本依赖声明及锁文件与工作区逐字节一致。

1. 新构建读取之前的一条 CSV 登记：5 条身体记录、786 字节。
2. 打开“清除导出记录”对话框并取消。独立只读 SQLite 连接对照，全部 17 份业务文档原文不变。
3. 点击 JSON 导出，显示登记成功：5 条、2750 字节（页面约 2.7 KB）。只有导出登记文档变化，新增一条 JSON 登记；旧 CSV 登记原样保留，其他 16 份文档原文不变。
4. 停止并重新启动 App，重新进入本地体验与身体数据页面，显示已登记 2 条，最新为 JSON。临时 JSON 文本未恢复，符合仅内存预览的现有边界。所有 17 份文档与保存后原文一致，没有重复登记。

证据：

- `/tmp/trainmate-batch18-before-ui.json`：本轮模拟器基线。
- `/tmp/trainmate-batch18-cancel-ui.json`：取消后全部原文相同。
- `/tmp/trainmate-batch18-saved-ui.json`：只增加一条 JSON 登记。
- `/tmp/trainmate-batch18-restarted-ui.json`：重启后与保存后全部文档一致。
- `/var/folders/35/g00sx__534bf30jg1y8l59d00000gn/T/screenshot_optimized_04df7690-de4b-474b-bd72-136fdf487784.jpg`：JSON 成功登记及预览。
- `/var/folders/35/g00sx__534bf30jg1y8l59d00000gn/T/screenshot_optimized_27a677dd-0fd7-4ad2-ba45-bda732f71ae4.jpg`：重启后两条登记。

本次模拟器没有确认删除登记，没有制造磁盘故障或进行真实账号切换；这些竞争和恢复路径由自动测试覆盖。没有以页面截图代替数据库持久化证明。临时证据文件可能被系统清理。

## 停止点与回滚

本轮停在 Batch 18。下一批继续检查共享身体统计进入训练建议的证据口径。系统文件保存／分享、真机与线上账号切换、进程在提交途中被强杀或断电、以及整体训练闭环发布门槛未验收；现有失败补写机制不承诺断电原子性。

回滚只撤销本批列出的源码片段，保留原文档、导出登记、身体记录和计划，不恢复整库快照，不整体覆盖已有未提交文件。原同步兼容接口不提供确认提交的持久化保证，生产调用应继续使用确认接口。
