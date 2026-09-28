# Batch 13：指标参考与累计记录日验收

日期：2026-09-19。本批只处理身体数据页的固定指标目标，完成实施、审查、修复、测试和限定模拟器验收后停止。

## 基线与范围

起始工作区有 404 条未提交状态，快照为 `/tmp/trainmate-batch13-start-status.txt`，修改前文件备份在 `/tmp/trainmate-batch13-before/`。先检查目标模型、服务、档案字段、页面及调用关系；图谱与当前源码均表明该报告用于身体数据页展示，没有用户确认体重／心率／HRV 个人目标的持久化定义或确认链路。

旧服务自动按档案体重设定下降 5%，用固定心率 62 → 57 和 HRV 55 计算目标进度，进而显示心肺适应或恢复稳定。它还将最近七条记录当七日均值、累计十四条当连续两周，并用不限时间跨度的体重差推断速度偏快。

本批修复展示及证据口径，不新增个人目标设置功能、健康阈值、训练算法、数据表或同步字段。不自动升级依赖、创建分支、提交、推送或部署。

## 修改与审查

- 保留三个内置参考数值，明确“非个人目标”，不将它们当成健康标准、实际改善或已确认的个人处方。
- 三项身体参考不显示达成进度，不因数值达到固定参考就判定改善；不再由档案体重自动产生目标公斤数。运动和档案体重变化均不能自动确认个人减重目标。
- 当前数值来自本地近 7 个自然日，逐字段筛选实际有效值、可信来源及时间；每个自然日取最近有效值，不将缺失、继承字段、未来值或未知来源计入均值。
- 显示观察窗口、有效覆盖天数和来源。无该字段有效记录时明确显示“无有效记录”，不补零；有数值也不将已记录日期均值说成连续七日或今日状态。
- “连续数据地基”改为“累计记录日”。保留原 14 的习惯积累目标，统计截至当前所有含有效字段的不同自然日，同日重复不增加天数，零散十四日不代表连续两周或足够判断训练成效。
- 移除目标卡中按不限时间跨度的体重差重复推断减重速度的逻辑；变化速度与工程提示继续通过 Batch 12 的趋势洞察展示。本批没有改动该工程提示分界或训练安全链路。
- 新增 `isReference` 为展示模型的可选字段，默认兼容原构造方式；该模型不参与持久化，不修改历史存储格式。`profile` 参数继续保留调用兼容。

## 修改文件

|文件|原因|
|---|---|
|`lib/services/body_metric_goal_service.dart`|参考身份、七日字段统计、累计自然日及去除重复速度判断|
|`lib/data/models/body_metric_goal.dart`|可选参考身份标识，修正 HRV 与累计记录标签|
|`lib/features/data_center/data_center_page.dart`|展示“指标参考与记录”，参考项隐藏进度条，不显示虚构达成比例|
|`test/features/training_loop/body_goal_evidence_batch_test.dart`|15 项来源、窗口、去重、运动档案、只读和页面验证|
|`docs/plans/2026-09-12-training-loop-implementation.md`|登记本批结果与新增已知问题|
|本文|记录范围、验证证据及停止点|

## 自动验证与发现的问题

|检查|本轮结果|日志|
|---|---|---|
|修改前定向基线|46 通过|`/tmp/trainmate-batch13-baseline.log`|
|新增首批测试在旧实现复现|9 失败|`/tmp/trainmate-batch13-red.log`|
|首轮修复及相关页面回归|33 通过|`/tmp/trainmate-batch13-green.log`|
|扩展审查测试|13 通过、2 个页面测试失败，暴露既有快录睡眠零值越界|`/tmp/trainmate-batch13-review.log`|
|隔离参考卡场景复验|本批 15 项通过|`/tmp/trainmate-batch13-review-retry.log`|
|最终相关回归|158 通过、0 失败|`/tmp/trainmate-batch13-final-tests.log`|
|静态分析|无问题|`/tmp/trainmate-batch13-analyze.log`|
|内容目录只读校验|6 个分域通过|`/tmp/trainmate-batch13-catalog.log`|
|iOS 模拟器构建|通过|`/tmp/trainmate-batch13-ios.log`|
|差异空白检查|git diff --check 通过|本轮执行|

**既有问题尚未修复：** 旧身体记录若没有 `sleepHours`，兼容读取为 0；快录 `_DoubleSliderLine` 直接将该值传给最小值 4 的滑块，触发 `Value 0.0 is not between minimum 4.0 and maximum 9.0`。该快录代码在本批前后未改变，问题不能记为“已修复”或用绿色回归掩盖。

为独立验收本批参考卡，页面夹具改为保留历史继承的睡眠 7.0、疲劳 3，但 `recordedFields` 仍只有体重；仍严格断言心率与 HRV 无有效数据、三项均为非个人目标、无虚构达成，并检查浏览不写文档和计划。未降低这些断言。完全缺失睡眠的快录场景单列后续优先修复；最终 158 项通过不表示该边界通过。

最终集合为 Batch 12 的 143 项及本批 15 项。复验可使用 [Batch 12 的完整命令](2026-09-19-batch-12-body-trend-evidence-acceptance.md)，追加 `test/features/training_loop/body_goal_evidence_batch_test.dart`。本批定向复验：

```sh
scripts/run_flutter_tests_clean_copy.sh \
  test/features/training_loop/body_goal_evidence_batch_test.dart \
  test/features/data_center --reporter expanded
scripts/run_flutter_analyze_clean_copy.sh
scripts/verify_content_catalog.sh
```

## 模拟器语义验收

设备：`TrainMate Batch2 课程调整 20260915`，iOS 26.5，UDID `F1C9B27E-6D81-43A4-938D-136966C40F94`。本轮已核对会话默认值，干净构建副本依赖声明和锁文件与原工作区逐字节一致。使用已授权的本地体验和已有合成记录，没有新增、删除或改写数据。

- “我的 → 身体数据”显示“指标参考与记录”，说明未设置个人身体指标目标。
- 体重均值 70.3 kg，覆盖 4/7 日，来源为手动、截图及文件；固定下降 5% 明确标为内置参考。
- 静息心率均值 60.0 bpm，覆盖 2/7 日，仅手动和截图来源，不将 CSV 继承值当实际记录。
- HRV 均值 49.8 ms，覆盖 4/7 日；三项均标“非个人目标”，没有目标达成进度条。
- 累计记录为 4 个自然日，目标为 14 个不同自然日的记录习惯，明确不是连续两周或训练成效判断。
- 浏览前后全部 16 份业务文档逐字一致，计划、日志、身体记录、修订、签到与报告均未变化。

证据：

- `/tmp/trainmate-batch13-before-ui.json` 与 `/tmp/trainmate-batch13-after-ui.json`：全部业务文档原文对照。
- `/var/folders/35/g00sx__534bf30jg1y8l59d00000gn/T/screenshot_optimized_5a584d1c-af96-40cc-ab24-dd3613425b7a.jpg`：参考身份与体重／心率依据。
- `/var/folders/35/g00sx__534bf30jg1y8l59d00000gn/T/screenshot_optimized_3f01cd23-ee38-4967-8b93-e2cc878c1995.jpg`：HRV 与累计记录日。

临时证据可能被系统清理。窄屏 390×844、1.0／1.5 倍文字由自动页面测试覆盖，模拟器使用当前默认字号。

## 停止点与后续

本轮停在 Batch 13。下一批优先处理缺失睡眠的快录边界；趋势图表及摘要整体口径仍待审查。个人身体目标设置与确认流程未新增，不能将内置参考重新当作用户处方。

真机、真实测量准确性、Apple 健康、语音、真实模型及线上登录未在本批验证。工程参考的健康适用性没有在本批验证。跑姿视频正式入口继续关闭，整体发布门槛未全部通过；既有周期重排日期不足两天的失败未纳入本批集合。

回滚仅切换展示服务、模型和卡片代码，保留全部记录，不恢复整库快照，无数据库迁移。
