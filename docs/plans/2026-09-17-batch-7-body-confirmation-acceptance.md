# Batch 7：完整身体记录确认入库与重启回读

日期：2026-09-17。遵守一次只执行一个 Batch，本批停在身体记录待确认入口，不推进下一批。

## 范围与基线

本批覆盖“粘贴或输入完整身体指标 → 识别预览 → 手动确认 → 持久化 → 训练投影读取 → 重启回读”，以及共用确认入口的异常值确认。准备度公式、阈值、身体字段、筛查、计划、云同步协议和数据库表保持原样。

起始状态保存于 `/tmp/trainmate-batch7-start-status.txt`；涉及既有文件的批前副本在 `/tmp/trainmate-batch7-before`。保留用户未提交更改，未创建分支、提交、推送、部署或升级依赖。

实施前身体数据与准备度基线 37 项通过，日志 `/tmp/trainmate-batch7-baseline.log`。这不代表写入失败已覆盖：新增四项反例在旧代码全部失败，见 `/tmp/trainmate-batch7-red.log`。

## 修改与审查

1. 旧确认逻辑先写入仓储缓存、清除待确认记录并通知训练投影，再等待磁盘。因此失败可能留下错误的界面成功状态和未持久化事实。
2. 仓储新增确认专用异步方法，候选记录沿用原同日覆盖及修订规则；持久化成功后才发布共享仓储缓存。失败补写原文档，首次记录失败则移除新文档；待确认内容保留供重试。恢复也失败时明确提示磁盘状态不确定，并阻止该仓储继续写入，要求重启检查。
3. 控制器提交全程沿用插件操作锁，包括失败恢复；保存期间阻止重复确认、替换识别内容、其他同日覆盖与清除。页面禁用确认按钮，显示等待或失败信息。
4. 审查测试发现，Riverpod 重建 Notifier 时仅检查 `mounted` 仍会让迟到回调更新新状态。增加构建标识，成功、失败和收尾均验证同一构建；账号清理后待确认内容与旧指标不回显。
5. 模拟器发现文字框使用当前文本作为 `ValueKey`，每次输入重建控件并丢失焦点。新增逐次输入反例复现，见 `/tmp/trainmate-batch7-input-red.log`。改用页面内的文本控制器并在销毁时释放；普通输入保留光标，样例与外部恢复通过现有 provider 同步，失败保留文字。

本批没有将所有身体数据写入统一改造。普通快录、CSV 和签到原有写入路径的独立失败恢复仍需后续批次审查；本批只增加它们在确认提交进行中的互斥保护。原同步仓储接口保留。

## 自动验证

新增 9 项测试覆盖等待期间不发布指标、重复确认、同步及异步失败、首次失败、恢复失败、重试修订、插件停用与账号切换阻断、账号清理、重建后迟到回调、训练投影及计划不变、输入焦点、失败重试、样例同步，以及两种本地存储回读。

|检查|本批最终结果|证据|
|---|---|---|
|身体确认、准备度、身体数据、签到、账号协调、仓储、健康生命周期|59 项通过，0 失败|`/tmp/trainmate-batch7-final-tests.log`|
|`flutter analyze`|无问题|`/tmp/trainmate-batch7-analyze.log`|
|内容目录只读校验|6 个分域通过|`/tmp/trainmate-batch7-catalog.log`|
|最终源码 iOS 模拟器构建|通过|`/tmp/trainmate-batch7-ios.log`|
|差异空白检查|通过|`git diff --check`|

首次扩大回归时误写不存在的 `body_data_lifecycle_test.dart`，产生加载失败；更正为已有 `health_data_lifecycle_test.dart` 后重跑完整命令。未删除测试或降低断言。各轮数量不累加。

```bash
scripts/run_flutter_tests_clean_copy.sh \
  test/features/training_loop/body_confirmation_batch_test.dart \
  test/features/training_loop/body_confirmation_storage_test.dart \
  test/features/training_loop/readiness_batch_test.dart \
  test/features/training_loop/readiness_evidence_test.dart \
  test/features/data_center test/features/daily_check_in \
  test/features/auth/account_switch_coordinator_test.dart \
  test/data/repositories/body_metric_repository_test.dart \
  test/plugins/lifecycle/health_data_lifecycle_test.dart \
  --reporter expanded
scripts/run_flutter_analyze_clean_copy.sh
scripts/verify_content_catalog.sh
```

SQLite 自动测试使用真实文档适配器及其写队列，底层网关注入故障；SharedPreferences 使用真实适配器及平台替身。它们验证失败恢复与重建读取，不冒充物理磁盘故障测试。设置合成账号绑定后检查身体文档不产生云同步写入。

## 模拟器验收

沿用隔离设备 `F1C9B27E-6D81-43A4-938D-136966C40F94`（TrainMate Batch2 课程调整 20260915）及其合成资料。没有访问真实健康资料或上传指标。

1. 批前 SQLite 有 14 个业务文档，没有身体数据文档。新版本构建、安装并进入已授权的本地体验；未改线上认证。
2. 从“我的 → 查看身体数据”进入文字识别。修复输入焦点后，连续键入现有解析器支持的英文标签和合成指标：日期 2026-09-17、体重 70 kg、体脂率 18%、静息心率 60、HRV 50、睡眠 7 小时、疲劳 3、酸痛 2。系统显示识别 7 项、待确认。
3. 确认前只读 SQLite 对照：没有身体文档，所有业务文档原文均与批前相同。证据 `/tmp/trainmate-batch7-before-confirm.json`。
4. 手动点击确认后，界面显示一条完整记录。数据库只有 `trainflow.body_metrics.v1` 与既有首次身体记录成就 `trainflow.achievement_records.v1` 改变；有效计划、训练日志、每日调整、周报、档案与插件设置原文不变。保存 7 项实际字段、0 条修订，见 `/tmp/trainmate-batch7-after-confirm.json`。
5. 终止 App 后重新启动，再由“我的 → 查看身体数据”读取：仍为 70 kg、60 bpm、50 ms、7 小时、2026-09-17、一条记录。重启后的全部业务文档与保存后完全一致，没有再次点击保存。证据 `/tmp/trainmate-batch7-restart-ui.json`、`/tmp/trainmate-batch7-restart-persistence.json`。
6. 当日状态未确认，重启后“我的”准备度仍为“无法评估”；身体记录本身没有替用户确认今日状态或修改计划。既有首次身体记录成就使 XP 从 27 变为 32，未产生训练完成记录。

剪贴板自动化读取超时，最终使用分段键入英文标签完成；不把失败的粘贴当成录入证据。完整中文输入法与纯触摸操作未新增验收。保留这一条合成记录供后续批次，未删除数据或恢复整库快照。

构建副本位置在 `/tmp/trainmate-batch7-ios-path.txt`；与当前工程核对依赖声明和锁文件一致后同步最终源码。SQLite 对照副本为 `/tmp/trainmate-batch7-before-ui.db` 和 `/tmp/trainmate-batch7-saved-ui.db`，仅作只读证据。临时文件可能被系统清理。

## 修改文件

|文件|原因|
|---|---|
|`lib/data/repositories/body_metric_repository.dart`|确认专用持久化、失败恢复、仓储缓存发布及写入互斥|
|`lib/features/data_center/application/body_metric_controller.dart`|等待确认完成、保留待确认内容、并发及迟到回调保护|
|`lib/features/data_center/data_center_page.dart`|禁用等待中的确认按钮、修复文本输入焦点并释放控制器|
|`test/features/training_loop/body_confirmation_batch_test.dart`|7 项确认、生命周期、训练投影和界面回归|
|`test/features/training_loop/body_confirmation_storage_test.dart`|2 项存储队列、重启回读、清理及同步边界回归|
|本记录、`2026-09-12-training-loop-implementation.md`|实际证据、范围及未验证门槛|

## 边界、后续缺口与回滚

- 本批通过的是确认入库路径；持续磁盘故障、进程在补写恢复中崩溃、设备账号切换和真机效果未验证。失败恢复为原文档补写，不宣称跨进程事务保证。
- 身体页面现有“样例”来源隔离与少量记录的质量解释需要下一批核查：模拟器一条记录同时显示“记录偏少”和“近 7 日记录连续”，不能将后者视为已验证事实。现有固定指标目标也未在本批验收，不扩展为个体化健康建议。
- 登录页既有 `Not Found` 保留；Apple 健康、真实模型、语音和跑姿视频发布门槛未改变。不能据此宣称整体正式发布。
- 回滚仅撤回本批确认入口、仓储方法和输入控件实现，保留 `trainflow.body_metrics.v1` 原有格式、修订和历史。无需数据库迁移，不清空记录，不恢复整库。
