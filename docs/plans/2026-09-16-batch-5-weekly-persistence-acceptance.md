# Batch 5：周报保存失败恢复与生命周期保护

日期：2026-09-16。本批只完成兼容教练周报及“下周方向”的可靠保存、失败恢复和账号隔离；完成实施、审查、修复与测试后停止，不进入下一批。

## 基线

- 起始工作区有 389 条未提交状态，快照为 `/tmp/trainmate-batch5-start-status.txt`。本批修改前文件及依赖副本保存在 `/tmp/trainmate-batch5-before`，保留用户已有修改。
- 相关基线 17 项通过，日志为 `/tmp/trainmate-batch5-baseline.log`。新增首轮 7 项测试在修复前为 1 通过、6 失败，日志为 `/tmp/trainmate-batch5-red.log`。
- 检查了周报仓储、聚合控制器、页面、存储写入队列、插件提交保护和账号清理协调器。知识图谱指向旧卷源码，后续以当前工作区为准。

## 发现与修复

|问题|本批处理|
|---|---|
|缓存更新后立即显示成功，磁盘失败未被等待|保存周报和方向改为异步调用；等待 `LocalStorageService.flush()` 成功后再发布报告和成功提示|
|保存失败后仓储内存与文档不一致|保留提交前的报告文档，仅恢复该文档；恢复写入完成后返回中文失败原因，表单内容保留以供重试|
|连续保存或保存期间选方向可以交错|控制器拒绝并发写入；页面等待期间禁用保存及方向按钮，捕获错误，不吞掉持久化失败|
|写入期间缺少插件和账号保护|使用现有 `FeatureOperation.commit`，保存与失败恢复均留在提交保护内；期间停用和换账号会明确阻断|
|账号数据清理后控制器仍沿用旧周报仓储|新增账号切换反例复现旧报告回显，移除周报仓储的跨重建缓存；新账号重新读取当前存储|
|恢复本身失败仍可能误导为已恢复|明确提示磁盘状态无法确认，暂停本控制器后续周报写入，要求重启后检查；不承诺进程崩溃或持续磁盘故障下的自动恢复|
|销毁后的保存完成继续更新旧界面|捕获提交所属的 `Ref`，完成时检查其是否仍存活；页面也检查 `mounted`|

继续沿用同周替换、最多八份报告的既有规则，以及核心历史读取和数据删除入口。没有修改报告格式、存储键、数据库表、训练算法、有效计划、训练日志或云同步协议。同步仓储接口保留，用户写入入口统一经上述等待与恢复链路；“下周方向”仍只保存选择，不应用训练处方。

恢复使用同一存储队列补写旧文档，并非新增数据库事务。已经提交的本地写入不会因离开页面而中断；页面关闭后不更新界面，停用和账号切换须等提交结束再重试。

## 审查与自动验证

最终命令：

```bash
scripts/run_flutter_tests_clean_copy.sh \
  test/features/training_loop \
  test/features/weekly_report \
  test/plugins/lifecycle/report_lifecycle_test.dart \
  test/plugins/lifecycle/plan_execution_lifecycle_test.dart \
  test/plugins/sports/marathon_consumption_test.dart \
  test/plugins/sports/all_sport_consumption_test.dart \
  test/data/local/database_local_storage_service_test.dart \
  test/features/auth/account_switch_coordinator_test.dart \
  --reporter expanded
scripts/run_flutter_analyze_clean_copy.sh
scripts/verify_content_catalog.sh
```

|检查|结果|证据|
|---|---|---|
|最终定向回归|84 项通过、0 失败|`/tmp/trainmate-batch5-final-tests.log`|
|静态分析|无问题|`/tmp/trainmate-batch5-analyze.log`|
|内容目录只读校验|6 个分域通过|`/tmp/trainmate-batch5-catalog.log`|
|当前源码 iOS 模拟器构建|通过|`/tmp/trainmate-batch5-ios.log`|

新增 10 项测试覆盖：延迟提交不提前发布成功、重复请求、同步和异步写失败、首次保存失败、方向写失败与重试、恢复失败、插件停用／重启、保存期间换账号阻断、账号清理后的新账号报告、控制器销毁后迟到完成、页面错误提示与表单保留，以及两种存储的写入队列、重新创建存储后回读和清理。

SQLite 自动测试使用真实 `DatabaseLocalStorageService`，底层网关为可注入故障的合成实现；SharedPreferences 使用实际适配器和内存平台驱动注入失败。它们不能替代物理磁盘故障测试。同步边界测试提供合成账号绑定，确认保存和恢复周报不产生云投影写入；计划与训练日志前后相同。

审查期间先修正测试夹具缺少系统提醒网关的问题，再发现并修复账号清理后的周报缓存问题。一次扩大回归使用了错误测试路径，修正路径后重跑得到上述 84 项通过；没有修改业务断言掩盖失败。各轮测试数字不相加，前批结果不冒充本批重跑。

## 模拟器验收与数据对照

沿用隔离模拟器 `F1C9B27E-6D81-43A4-938D-136966C40F94`，名称为“TrainMate Batch2 课程调整 20260915”，只使用前批合成训练数据。依赖声明与锁文件和本批开始时一致，复用依赖匹配的干净构建副本，同步当前源码后构建、安装。

1. 通过已有本地体验进入“我的 → 打开周报”，不填写评分，保存本周复盘。
2. 选择“保持当前周训练频率”，页面显示选中状态和“已保存你选择的下周方向”。仍显示“无法评估”、0.50/3 次完成单位和 17%，不补出状态评分。
3. 只读 SQLite 对照确认只有 `trainflow.weekly_reports.v1` 变化，仍为一份报告，方向为 `keep_schedule`；其余 12 份业务文档原文未变。
4. 停止并重新启动 App，重新进入周报，没有再次保存。原报告窗口与方向选中状态仍在；报告文档与重启前逐字节一致。

证据：`/tmp/trainmate-batch5-before-ui.db`、`/tmp/trainmate-batch5-persistence.json`、`/tmp/trainmate-batch5-saved-report.json`、`/tmp/trainmate-batch5-restarted-report-ui.json`。构建副本路径记录在 `/tmp/trainmate-batch5-ios-path.txt`；临时证据可能被系统清理。

## 修改文件

|文件|原因|
|---|---|
|`lib/features/dashboard/training_mvp_controller.dart`|异步持久化、单文档恢复、并发保护、生命周期提交保护及去除跨账号周报缓存|
|`lib/features/weekly_report/weekly_report_page.dart`|等待状态、禁用重复操作、中文错误提示、保留填写内容和销毁检查|
|`test/plugins/sports/marathon_consumption_test.dart`、`test/plugins/sports/all_sport_consumption_test.dart`|原策略消费测试等待真实保存完成，保留原业务断言|
|`test/features/training_loop/weekly_persistence_batch_test.dart`|失败恢复、并发、账号、插件及页面回归|
|`test/features/training_loop/weekly_storage_batch_test.dart`|两种存储的队列失败、回读、清理、计划不变和云投影边界|
|本记录、`2026-09-12-training-loop-implementation.md`|本批交付事实和未验收范围|

## 剩余边界与回滚

本批完成工程测试和模拟器的保存／方向选择／重启流程。设备上的账号切换与插件停用全流程、物理磁盘写入失败、真机和线上登录均未新增验收；登录页既有 `Not Found` 仍存在。真实训练效果、Apple 健康、真实模型、跑姿视频发行开关和整体发布门槛没有因本批通过而改变。

回滚只撤回本批控制器和页面改动，不删除报告、计划或训练日志，不恢复整库快照。未创建分支、提交、推送、部署或升级依赖。
