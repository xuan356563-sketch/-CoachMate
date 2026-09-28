# Batch 14：快录缺失值与滑块边界验收

日期：2026-09-19。本批只修复身体数据页快录的预填与控件边界，完成审查、修复、测试和限定模拟器验收后停止。

## 基线与范围

起始工作区有 407 条未提交状态，保存在 `/tmp/trainmate-batch14-start-status.txt`。修改前页面备份为 `/tmp/trainmate-batch14-before/data_center_page.dart`，保留此前批次及用户全部改动。

Batch 13 暴露的旧记录缺少睡眠时，兼容读取为 0，直接进入最小值 4 的滑块而崩溃。本轮确认体重、心率、HRV、睡眠超出原控件范围，以及模型允许的疲劳 0 也有相同风险。仅将值截断到滑块范围会改变记录含义，因此没有使用截断或自动补默认值的修复方式。

## 修改与审查

- 快录逐项使用现有 `BodyMetric.hasValue` 检查体重、静息心率、HRV、睡眠、疲劳。缺失、继承而非实际记录、无效值或未知来源时，不显示预填滑块和保存按钮，列明无法安全预填的字段，引导用完整截图／CSV 补全并确认。
- 只要求快录的五个字段；不把体脂、酸痛等非快录字段增加为新门槛。旧记录仍可读取，页面浏览不写入数据。
- 对有效的范围外值，控件范围包含上次实际值，保持原值。整数滑块仍按整数编辑；浮点控件正常范围保持原分段，扩展范围使用连续滑动，避免按极大历史数值计算分段数量。范围是控件范围，不是健康阈值。
- 疲劳控件支持模型已有的 0—10。没有改变准备度公式、异常值审核、身体／签到提交事务、存储结构或同步边界。
- 补全并确认后快录恢复；恢复前不会保存控件默认值。范围外样例通过实际页面按钮保存，重新创建仓储读取后数值保持一致，原有效计划不变。
- 移除 Batch 13 页面测试中为隔离滑块崩溃而暂存的睡眠／疲劳值；其 1.0／1.5 倍字号场景现在直接覆盖缺失睡眠的旧记录。

审查中发现保存测试滚动后未等待布局，点击未命中，而同值断言可能误把原记录当保存成功。已补布局等待、将未命中点击设为失败，并增加新记录 ID、文档变化、签到文档及重新读取数值断言，不以原值相同代替保存证据。

## 修改文件

|文件|原因|
|---|---|
|`lib/features/data_center/data_center_page.dart`|检查预填字段与来源，扩展控件范围，支持疲劳 0|
|`test/features/training_loop/body_quick_entry_boundary_batch_test.dart`|12 项缺失、来源、范围、保存及补全恢复页面测试|
|`test/features/training_loop/body_goal_evidence_batch_test.dart`|移除上一批隔离崩溃的继承值夹具，保留原断言|
|`docs/plans/2026-09-12-training-loop-implementation.md`|更新本批状态与后续问题|
|本文|记录验证、边界与回滚|

## 自动验证

|检查|结果|日志|
|---|---|---|
|修改前快录与参考卡基线|27 通过|`/tmp/trainmate-batch14-baseline.log`|
|首批新增场景对旧实现|11 失败，复现问题|`/tmp/trainmate-batch14-red.log`|
|首轮修复与回归|38 通过|`/tmp/trainmate-batch14-green.log`|
|审查扩展|26 通过、1 失败；另发现测试点击未命中|`/tmp/trainmate-batch14-review.log`|
|审查修复复验|27 通过|`/tmp/trainmate-batch14-review-retry.log`|
|最终相关回归|170 通过、0 失败|`/tmp/trainmate-batch14-final-tests.log`|
|静态分析|无问题|`/tmp/trainmate-batch14-analyze.log`|
|内容目录只读校验|6 个分域通过|`/tmp/trainmate-batch14-catalog.log`|
|iOS 模拟器构建|通过|`/tmp/trainmate-batch14-ios.log`|
|差异检查|`git diff --check` 通过|本轮执行|

最终集合为 Batch 13 的 158 项及本批 12 项，覆盖原有两种存储、失败恢复、账号切换和插件生命周期回归；不是所有项目测试。定向复验命令：

```sh
scripts/run_flutter_tests_clean_copy.sh \
  test/features/training_loop/body_quick_entry_boundary_batch_test.dart \
  test/features/training_loop/body_goal_evidence_batch_test.dart \
  test/features/training_loop/body_check_in_batch_test.dart --reporter expanded
scripts/run_flutter_analyze_clean_copy.sh
scripts/verify_content_catalog.sh
```

## 独立发现，尚未修复

扩展测试将截图文字“疲劳 0”作为补全输入，发现 `BodyMetricSnapshotRecognitionService` 的既有 `clamp(1, 10)` 会将其变成 1；酸痛也使用相同处理。失败日志保留在审查日志中。该解析器本批未改，不属于滑块修复已通过的范围。

补全恢复测试改用疲劳 3，继续验证缺失睡眠补全前不写入、确认后恢复、原值正确及不生成签到。疲劳 0 的页面显示与实际保存仍由独立范围测试严格断言。不能据本批绿色结果宣称截图零值解析通过。后续批次优先核查截图／CSV 的零值与越界处理，之后再审查趋势图表及摘要。

## 模拟器验收

设备：`TrainMate Batch2 课程调整 20260915`，iOS 26.5，UDID `F1C9B27E-6D81-43A4-938D-136966C40F94`。构建前已核对会话默认值，干净构建副本的依赖声明和锁文件与原工作区逐字节一致。

- 安装并启动新构建，经已授权的本地体验进入“我的 → 身体数据”。线上登录仍显示既有 `Not Found`，本批没有验证线上服务。
- 快录正确预填既有合成记录：体重 70.8 kg、静息心率 60 bpm、HRV 50 ms、睡眠 7.0 h、疲劳 3。
- 将疲劳滑块拖至 0，页面显示 0/10，无崩溃；没有点击保存。随后恢复未保存编辑为 3。
- 浏览及未保存零值编辑后，全部 16 份业务文档与操作前逐字一致，计划、日志、身体记录、修订及签到未变。
- 本次模拟器未制造缺失／超范围历史样例，也未进行新保存。那些边界与保存结果由自动页面测试覆盖，不以本次模拟器浏览代替。

证据：`/tmp/trainmate-batch14-before-ui.json`、`/tmp/trainmate-batch14-after-ui.json`；零值页面截图 `/var/folders/35/g00sx__534bf30jg1y8l59d00000gn/T/screenshot_optimized_f10bb368-e7a0-4350-acbe-66642e25c3f4.jpg`。临时证据可能被系统清理。

## 停止点与回滚

停在 Batch 14，不自动进入下一批。截图／CSV 解析口径、图表与整体发布门槛仍待验证；真机、真实测量、Apple 健康、语音和真实模型效果未在本批验证。跑姿视频正式入口继续关闭。

回滚仅还原本批页面实现；不清空记录、恢复整库快照或改数据库表。没有新增依赖、提交、推送或部署。
