# Batch 23：“和昨天一样”的日期选择与保存一致性

日期：2026-09-21。本批完成实现、审查、修复、定向测试及限定模拟器验收后停止。

## 基线与范围

起始工作区 422 条未提交状态，快照 `/tmp/trainmate-batch23-start-status.txt`。保留原有改动，未创建分支、提交、推送、部署、升级依赖或修改数据库结构。

修改前，签到摘要只检查最新记录中的三个字段，保存端直接复制最新记录；今日、前日甚至未来记录都有机会被“和昨天一样”使用。保存端没有独立检查来源及实际字段，也没有核对页面展示后来源是否变化。

本批只处理该预填入口和提交前检查。身体／签到双文档提交、同日修订、失败恢复、插件生命周期、账号清理及计划链路继续复用已有实现。

## 行为变化

- 摘要和保存端共用同一个昨日选择方法：以本地自然日的昨日零点至今日零点为范围，不用过去 24 小时替代，支持跨月及夏令时边界。
- 先取昨日最新一条，再要求睡眠、HRV、疲劳均通过已有来源和实际字段校验。最新一条缺项或来源不明时，不回捞昨日更早的完整值；不选今日、未来或更早日期。
- 今日或未来记录存在时，仍可正确找到有效昨日记录。保存端重新选择并独立校验，不能仅依赖按钮启用状态。
- 确认按钮上方显示来源日期、来源类别及七项身体字段；未知项显示“未记录”。说明点击表示本人确认今日沿用，保存为手动记录，非重新测量。
- 页面传入包含目标自然日和原记录内容的本地比较标记，保存前重新比对；来源或日期改变时要求刷新后重新确认。该标记只在本机内存使用，不进入存储字段、网络摘要或云同步。
- 保存保留原字段可用范围、合法疲劳零值和其他既有值；备注包含原日期、记录 ID、来源及“非重新测量”。不修改有效计划。
- 没有有效昨日记录时，入口禁用；直接调用保存也不会写入。成功提示在原双文档提交完成之后发布。

重复确认仍沿用现有身体同日修订规则，只保留一条当日当前记录，签到天数不重复增加；本批没有把身体修订历史改成完全不写入的幂等操作，也没有改变已有按计划恢复／安全暂停的签到类型。

## 修改文件

|文件|原因|
|---|---|
|`lib/services/daily_check_in_service.dart`|共用昨日选择、逐字段说明及本地确认内容比对|
|`lib/data/models/daily_check_in.dart`|增加可选预填说明与比较标记，兼容既有构造|
|`lib/features/dashboard/training_mvp_controller.dart`|向摘要传入全部身体记录，避免最新记录遮住昨日|
|`lib/features/data_center/application/body_metric_controller.dart`|保存前重新检查日期／来源，记录原始来源，复用双文档提交|
|`lib/features/daily_check_in/daily_check_in_page.dart`|显示将沿用的内容并传递确认比较标记|
|`test/features/training_loop/yesterday_check_in_batch_test.dart`|新增 12 项日期、缺失、来源、旧确认、真实页面与保存测试|
|`test/features/data_center/application/body_metric_controller_test.dart`|原“最新指标”用例改为真实昨日样例与新来源说明|
|`test/features/training_loop/body_check_in_batch_test.dart`|昨日预填使用明确昨日样例，保留插件／提交失败／修订断言|
|`test/features/training_loop/body_confirmation_storage_test.dart`|两种存储提供已落盘的昨日样例，保留重启、失败恢复和清理断言|
|`test/widget_test.dart`|三个成功提示断言改为“按昨日记录”，原调整入口失败断言保留|
|`docs/plans/2026-09-12-training-loop-implementation.md`|最新批次及停止点|
|本文|验证、限制与回滚记录|

## 审查与自动验证

|检查|结果|日志|
|---|---|---|
|修改前定向基线|65 通过|`/tmp/trainmate-batch23-baseline.log`|
|新增测试对旧实现|7 失败，复现日期及来源边界|`/tmp/trainmate-batch23-red.log`|
|首轮实现加载|导入语句位置错误导致加载失败，已移动到文件顶部|`/tmp/trainmate-batch23-green.log`|
|首轮综合审查|70 通过、2 失败；SharedPreferences 新样例未等待落盘|`/tmp/trainmate-batch23-review.log`|
|最终定向回归|109 通过、0 失败|`/tmp/trainmate-batch23-final-tests.log`|
|旧端到端单项复跑|昨日预填／保存段通过；仍在第 1933 行寻找“应用今日调整”时失败|`/tmp/trainmate-batch23-legacy-e2e.log`|
|静态分析|无问题|`/tmp/trainmate-batch23-analyze.log`|
|内容目录只读校验|6 个分域通过|`/tmp/trainmate-batch23-catalog.log`|
|iOS 模拟器构建|通过|`/tmp/trainmate-batch23-ios.log`|
|差异检查|`git diff --check` 通过|本轮执行|

集合不累加。最终定向集合包含全部 12 项新增测试。SharedPreferences 修复发生在样例准备：等待 `flush` 后再构造仓储，确保真实进入注入的失败提交；未删除失败断言。原测试中仅有“今日记录”的昨日预填样例增加真实昨日记录，因此记录数量相应从 1 变为 2，并补充数量断言，修订、失败恢复、云写入为零和账号清理断言保留。

审查差异 `/tmp/trainmate-batch23-review.diff`。确认两处业务调用复用同一选择方法；页面不直接写仓储；来源比较标记不持久化；旧记录可读。固定日期测试覆盖 UTC 等价表示、跨月和夏令时切换日；实际页面在 390×844 默认字号下滚动、检查按钮和点击保存。旧端到端失败在此前 Batch 19 已有修改前复现记录，本批再次运行仍落在相同位置，不计入定向绿色集合，不宣称全库通过。

```sh
scripts/run_flutter_tests_clean_copy.sh \
  test/features/training_loop/yesterday_check_in_batch_test.dart \
  test/features/data_center/application/body_metric_controller_test.dart \
  test/features/training_loop/body_check_in_batch_test.dart \
  test/features/training_loop/body_confirmation_storage_test.dart \
  test/features/daily_check_in/daily_check_in_page_test.dart \
  test/features/training_loop/check_in_evidence_batch_test.dart \
  test/features/training_loop/health_overview_evidence_batch_test.dart \
  test/features/training_loop/body_quick_entry_boundary_batch_test.dart --reporter expanded
scripts/run_flutter_tests_clean_copy.sh test/widget_test.dart \
  --plain-name 'TrainFlow AI 默认进入今日训练页' --reporter expanded
scripts/run_flutter_analyze_clean_copy.sh
scripts/verify_content_catalog.sh
```

## 模拟器验收与数据不变性

隔离设备 `TrainMate Batch2 课程调整 20260915`，iOS 26.5，UDID `F1C9B27E-6D81-43A4-938D-136966C40F94`。构建前检查会话默认值，干净副本的依赖声明与锁文件逐字节一致；最后文案修改也已重新同步构建。

设备显示 9 月 21 日，既有身体记录最新日期为 9 月 19 日，缺少 9 月 20 日记录。沿用已授权的本地体验，实际从今日状态条进入签到，滚动查看完整说明：

- 历史 9 月 19 日记录继续可读，不被称为昨日或今日观测。
- “和昨天一样”按钮实际呈禁用状态，可访问性树也标为 disabled；说明昨日无记录或缺少有效字段／可信来源，应填写今日状态。
- 本批未点击偏累、恢复、暂停或身体保存，不为通过验收修改模拟器历史日期。
- 安装、启动及浏览前后，`legacy_documents` 的 **17 份业务文档原文完全不变**。

证据：

- `/tmp/trainmate-batch23-before-ui.json`
- `/tmp/trainmate-batch23-after-ui.json`
- 截图：`/var/folders/35/g00sx__534bf30jg1y8l59d00000gn/T/screenshot_optimized_dd035409-1faa-4107-b3c0-ed6114487041.jpg`

模拟器本次验收的是缺失昨日时阻断的反例。有效昨日的页面点击与保存、失败恢复、重启读取由合成组件／控制器／存储测试验证，不冒充本次模拟器成功提交或真实健康测量验收。

## 剩余范围与下一批

下一批优先复核旧端到端用例中的“应用今日调整”入口：确认它是过时测试名称、入口展示条件，还是实际用户链路缺口，再针对原因修复。本批不进入该项。

首页其他区域大字布局、活动摘要趋势与连击的独立日期口径、真机及整体发布验收仍待处理。跨文档断电原子性不因本批通过而得到新增保证；今日沿用昨日的值仍是用户确认的手动记录，不代表新传感器测量。

回滚仅撤回本批昨日选择、说明及确认前比对的对应差异，保留历史记录和双文档可靠提交机制；不整文件覆盖用户改动，不清空数据库或恢复整库快照。
