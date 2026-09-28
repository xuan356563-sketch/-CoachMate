# Batch 21：今日状态条与签到提示的证据口径

日期：2026-09-20。本批处理历史身体记录被当成今日数值、签到提示固定显示“今天确认”的问题。完成实现、审查、修复、测试和限定模拟器验收后停止。

## 基线与范围

起始工作区 420 条未提交状态，快照 `/tmp/trainmate-batch21-start-status.txt`。保留已有改动，未提交、推送、部署、升级依赖或修改数据库结构。

修改前：首页状态条直接读取 `latestBodyMetric`；签到服务只检查字段有效性，没有当日与未来时间边界；疲劳和疼痛来源固定显示“今天确认”。这使昨日疲劳 0、睡眠 7 小时可能继续出现在今日状态条，旧高疲劳值也能直接影响今天的提问排序。

本批只修复状态条与签到提示。既有准备度、安全保护、训练计划和身体／签到联合保存链路不变。

## 修改内容

- 首页状态条复用 `currentDecisionBodyMetric`，选择当日、非未来、可信来源的最新一条记录，睡眠／疲劳／酸痛仍逐项检查实际字段。没有当日观测显示“待记录”，合法零值正常显示；不跨记录补齐缺失字段。
- 将状态条“心情”改为“记录标签”。原字段可能保存“截图识别”等导入标签，不能把它解释为心理状态。
- 签到服务增加兼容的可选 `currentBodyMetric` 与 `evaluatedAt` 参数。当前数值及字段相关排序只使用当日实际记录；没有当日字段显示“未记录”，来源说明区分历史记录、未知来源、未来时间和本条缺失。
- 当日有效记录显示日期、来源及“待复核”，不会仅因记录存在就宣称用户已确认今日状态。
- 疼痛历史仍显示部位、等级、日期及“待复核”，保留原安全优先级；无记录显示“当日疼痛待确认”。未来或异常疼痛记录不伪装成有效当前观测，原疼痛保护逻辑未降低。
- 保留原排序与精简条件中的阈值。缺少当日睡眠时直接说明“缺少当日睡眠记录”，不把缺失解释成睡眠低值。
- 原预填按钮仍沿用最新记录的既有逻辑；本批仅在摘要可用性检查中排除未来记录。没有改动实际保存流程，也没有把历史值自动写成今日数据。

## 修改文件

|文件|原因|
|---|---|
|`lib/services/daily_check_in_service.dart`|当日／历史／未来来源说明、实际字段边界、可测试时间参数|
|`lib/features/dashboard/training_mvp_controller.dart`|向签到服务传入与状态条相同的当前记录|
|`lib/features/dashboard/today_training_page.dart`|状态条使用当日实际字段，修正“记录标签”含义|
|`test/features/training_loop/check_in_evidence_batch_test.dart`|新增 15 项来源、日期、缺失、零值、排序、显示和不写入测试|
|`docs/plans/2026-09-12-training-loop-implementation.md`|最新批次与停止点|
|本文|验证明细、已知问题与回滚范围|

## 审查与自动验证

|检查|结果|日志|
|---|---|---|
|修改前相关基线|38 通过|`/tmp/trainmate-batch21-baseline.log`|
|新增测试对旧实现|12 失败；包含 7 项纯计算复现及 5 项页面检查，页面还受到既有大字布局问题干扰|`/tmp/trainmate-batch21-red.log`|
|首轮修复|7 通过、5 个页面测试仍因既有整页大字布局失败|`/tmp/trainmate-batch21-green.log`|
|综合审查|87 通过、1 失败；新状态条测试未正确定位横向列表中的组合文字|`/tmp/trainmate-batch21-review.log`|
|最终定向回归|88 通过、0 失败|`/tmp/trainmate-batch21-final-tests.log`|
|静态分析|无问题|`/tmp/trainmate-batch21-analyze.log`|
|内容目录只读校验|6 个分域通过|`/tmp/trainmate-batch21-catalog.log`|
|iOS 模拟器构建|通过|`/tmp/trainmate-batch21-ios.log`|
|差异检查|`git diff --check` 通过|本轮执行|

集合不累加。最终包含 15 项本批新增测试，并回归签到、准备度、恢复估算、快录、今日页和身体控制器。固定时间测试验证本地自然日、UTC 等价表示、午夜与未来一秒边界；真实当日疲劳变化仍影响原排序。浏览计算不修改身体文档、签到记录或有效计划。

大字验收分开记录：初版测试将整个首页设置为 390×844、1.5 倍字号，在修改前与首轮修改后均出现相同的既有布局溢出，包括 `trainmate_showcase_widgets.dart:690`、`emp_system.dart:361`、`trainmate_primitives.dart:192` 等未修改区域。本批没有修复或忽略这些异常。最终整页使用默认字号验证输入口径；另从真实页面取得实际 `TrainMateStatusStrip`，在同样窄屏、1.5 倍字号下独立渲染并逐项横向滚动，检查实际组合文字可见和无异常。未改任何既有测试断言，不能据此宣称整页大字适配通过。

```sh
scripts/run_flutter_tests_clean_copy.sh \
  test/features/training_loop/check_in_evidence_batch_test.dart \
  test/features/daily_check_in/daily_check_in_page_test.dart \
  test/features/training_loop/readiness_batch_test.dart \
  test/features/training_loop/readiness_evidence_test.dart \
  test/features/training_loop/recovery_evidence_batch_test.dart \
  test/features/training_loop/body_quick_entry_boundary_batch_test.dart \
  test/features/dashboard/today_training_page_test.dart \
  test/features/data_center/application/body_metric_controller_test.dart --reporter expanded
scripts/run_flutter_analyze_clean_copy.sh
scripts/verify_content_catalog.sh
```

此前 Batch 19 已确认旧端到端测试在寻找“应用今日调整”入口时失败，本批没有重跑或修复该项。最终 88 项通过不代表整个测试库无失败。

## 模拟器与数据不变性

使用隔离设备 `TrainMate Batch2 课程调整 20260915`，iOS 26.5，UDID `F1C9B27E-6D81-43A4-938D-136966C40F94`。先检查会话默认值；干净构建副本依赖声明与锁文件和工作区逐字相同。

沿用已授权本地体验，实际打开今日页并点击状态条进入签到：

- 首页首屏可见“睡眠 待记录”；可访问性状态同时返回疲劳、酸痛和记录标签均为“待记录”。横向手势尝试未产生可确认的位置变化；其余项逐项横向可见性由组件测试验证，不冒充模拟器已滚动验收。
- 签到页面实际可见“疲劳：未记录 · 历史记录 2026-09-19（截图识别），当日待填写”，HRV、睡眠也保留历史日期并显示当日未记录。
- 无疼痛记录显示“当日疼痛待确认”，不再固定显示“今天确认”。
- 未点击签到保存、偏累、恢复、暂停或任何计划操作。安装、启动和浏览前后 `legacy_documents` 的 **17 份业务文档原文完全相同**。

证据：

- `/tmp/trainmate-batch21-before-ui.json`
- `/tmp/trainmate-batch21-after-ui.json`
- 首页截图：`/var/folders/35/g00sx__534bf30jg1y8l59d00000gn/T/screenshot_optimized_729f90ed-5b94-4be0-92d5-9d9eab13f98b.jpg`
- 签到截图：`/var/folders/35/g00sx__534bf30jg1y8l59d00000gn/T/screenshot_optimized_02bfa33d-af73-42ae-9aa8-2320ad8fca1b.jpg`

## 剩余风险与下一批

1. 首页健康概览由 `TodayHealthOverviewData.fromSources` 独立合并健康快照和身体数值，仍需核查其日期、来源和实际字段边界；下一批优先处理，不能把本批状态条通过当成该区域也已通过。
2. 整页大字布局的既有溢出另行处理。旧端到端入口失败、真机、线上和整体发布验收仍未完成。
3. “和昨天一样”底层目前实际复制最新记录，并非严格选择昨日记录。本批保留既有保存语义；严格日期选择与名称一致性需要独立批次，不因本批展示修复而声称已解决。
4. 本批没有新增自动训练决策或健康阈值。回滚只针对三个生产文件的本批差异，不覆盖整个聚合控制器、不删除记录、不恢复整库快照。

本轮完成并停在 Batch 21，未开始下一批。
