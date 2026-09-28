# Batch 8：身体数据样例只读展示与七日覆盖说明

日期：2026-09-17。本批实施、审查、修复和相关验证完成；遵守一次只执行一个 Batch，在此停止。

## 范围与基线

处理 Batch 7 留下的两个问题：内置身体样例默认填入可保存表单；一条记录却显示“近 7 日记录连续”。同时修复默认留空后的 CSV 连续输入焦点问题。不改变准备度公式、训练处方、既有异常阈值、账号权限、数据库结构、云端协议或同步范围。

起始工作区 393 条未提交状态，记录在 `/tmp/trainmate-batch8-start-status.txt`；修改前涉及文件备份在 `/tmp/trainmate-batch8-before`。保留此前未提交修改，未创建分支、提交、推送、部署或升级依赖。

实施前身体数据、准备度及确认持久化基线 46 项通过，日志 `/tmp/trainmate-batch8-baseline.log`。新增最初 7 项反例全部复现失败，日志 `/tmp/trainmate-batch8-red.log`；之后补充固定时间的自然日边界测试。

## 修改与审查结论

### 内置样例

- 截图文字与身体 CSV 输入 provider 默认空字符串；移除两个把样例填入可执行表单的 `useSample` 方法。
- “查看截图文字样例”“查看 CSV 格式样例”打开独立只读窗口，明确是演示数据，仅供查看格式。只有关闭按钮，不生成待确认记录、不写入仓储、不覆盖已有输入。
- 样例常量和原业务解析服务保留；本批没有删除真实文字识别或 CSV 导入能力。
- CSV 原先也使用输入文本作为 `ValueKey`，连续输入会重建控件。沿用 Batch 7 的文本控制器方式，保持焦点与光标；外部文本恢复仍同步，页面销毁时释放控制器。
- Batch 7 测试改用普通外部文本恢复检查同步，不再调用已移除的样例填入入口；原保存等待、失败重试和焦点断言保留。

本批保证的是**内置样例查看流程不自动进入事实输入**，不是对用户手动填写内容的真实性鉴定。旧版本保存的记录没有可靠的样例溯源标识时，不能仅凭数值相似批量认定为演示数据；没有改写旧来源或删除历史，也不宣称已验证所有历史记录来源。已有 `sourceVerified == false`、无有效字段和未来数据在本质量窗口排除。

### 质量说明

- 观察窗口固定为本地今天及前六个自然日，增加可选 `now` 参数以测试边界。
- `recordCount` 仍表示保存的总记录数；`coveredDays` 改为本窗口有有效字段的不同自然日数，显示 `n/7`。同日重复、旧窗口、未来时间、来源未确认和无有效字段不能增加覆盖。
- 只有七个自然日均有记录才说明日期覆盖连续，并明确不等于各字段完整或健康状态正常。零日显示“无法评估”，无风险警告且不足七日显示“记录不足”。
- 体重与静息心率分别检查字段可用性；每项使用各日最近的有效值，缺失不按零计算。不足两日无法比较，不再用“未发现明显异常”概括空证据。
- 保留原质量系数 `0.35 + 覆盖率 × 0.65` 与原异常扣分，覆盖率使用实际日期；仍使用原体重变化 `> 2 kg`、心率偏离均值 `> 20 bpm` 等判断，没有新健康阈值。窗口和缺失说明不新增扣分。
- 质量分仍是记录质量的工程估算，不是准备度分数、能力等级或健康结论。本批未改准备度服务。

审查两次发现文案包含否定形式的“记录连续”，改成直接说明“日期覆盖尚不完整”；保留反例断言。新增说明令长页面更高，旧删除确认测试点击落在屏幕外；改为等待布局完成、滚动到目标、再实际点击，继续断言取消保留记录、确认后才删除，没有屏蔽点击警告或降低断言。

## 自动验证

新增 8 项测试：空记录、一日不足、重复日期与完整七日、陈旧／未来／不可用来源、逐项缺失、自然日零点与未来分钟边界、跨日缺口及原异常阈值，以及样例查看不写入与 CSV 连续输入。

|检查|最终结果|证据|
|---|---|---|
|身体数据、质量与样例、保存、准备度、解析器、签到、伙伴事实读取|68 项通过，0 失败|`/tmp/trainmate-batch8-final-tests.log`|
|`flutter analyze`|无问题|`/tmp/trainmate-batch8-analyze.log`|
|内容目录只读校验|6 个分域通过|`/tmp/trainmate-batch8-catalog.log`|
|最终源码 iOS 模拟器构建|通过|`/tmp/trainmate-batch8-ios.log`|
|差异空白检查|通过|`git diff --check`|

```bash
scripts/run_flutter_tests_clean_copy.sh \
  test/features/data_center \
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
  --reporter expanded
scripts/run_flutter_analyze_clean_copy.sh
scripts/verify_content_catalog.sh
```

各轮数量不相加。CSV 写入失败恢复并未因为解析器测试通过就视为完成，仍属后续批次。

## 模拟器与数据对照

使用既有隔离设备 `F1C9B27E-6D81-43A4-938D-136966C40F94`（TrainMate Batch2 课程调整 20260915）及 Batch 7 保存的一条合成记录，未新增、删除或重新保存身体数据。

1. 安装修复版并进入已授权的本地体验，从“我的 → 查看身体数据”读取原记录。
2. 页面显示记录数 1、质量状态“记录不足”、`1/7 日有有效记录`，观察窗口 2026-09-11 至 2026-09-17，体重与心率均说明不足两日、无法比较。原 70 kg、60 bpm、50 ms、7 小时和日期保留。
3. 两个输入框均为空。分别实际打开截图文字样例和 CSV 格式样例，看到演示与只读说明、关闭按钮；关闭后表单仍为空，没有出现待确认记录。
4. 只读 SQLite 对比批前与查看后：15 个业务文档原文全部相同，身体记录仍为一条。有效计划、日志、每日调整、周报、成就、档案和插件设置未改变。

证据：`/tmp/trainmate-batch8-quality-ui.json`、`/tmp/trainmate-batch8-before-ui.db`、`/tmp/trainmate-batch8-after-ui.json`。`/tmp/trainmate-batch8-example-ui.json` 返回空目标，不能作为样例通过证据；两个样例窗口及关闭后的空白输入以本轮对话中的实际截图验证。后半段模拟器可访问性树没有返回内容，使用当前截图与坐标点击完成查看／关闭，没有依赖失效的元素编号。CSV 输入焦点由 widget 测试验证，本轮设备流程没有重新提交 CSV。

构建副本路径在 `/tmp/trainmate-batch8-ios-path.txt`。先核对当前项目依赖声明和锁文件一致，再同步本批源码构建；临时日志可能被系统清理。

## 修改文件

|文件|原因|
|---|---|
|`lib/features/dashboard/training_mvp_controller.dart`|两个输入默认留空、移除样例填入方法|
|`lib/features/data_center/data_center_page.dart`|样例只读窗口和 CSV 输入焦点保护|
|`lib/services/body_data_quality_service.dart`|实际七日覆盖、来源／时间过滤及逐项缺失说明|
|`lib/data/models/body_data_quality.dart`|零覆盖和不足覆盖状态文案|
|`test/features/training_loop/body_quality_batch_test.dart`|7 项质量事实与边界反例|
|`test/features/training_loop/body_examples_batch_test.dart`|样例不影响输入与业务状态、无写入及连续输入|
|`test/features/training_loop/body_confirmation_batch_test.dart`|保持外部文本恢复验证，适配样例只读入口|
|`test/features/data_center/data_center_page_test.dart`|长页面实际滚动后验证删除确认与取消|
|本记录、`2026-09-12-training-loop-implementation.md`|范围、证据与剩余门槛|

## 后续边界与回滚

- 普通快录、CSV、签到各自的失败恢复与互斥仍待独立批次，不据本批结果宣称全部写入可靠性完成。
- 原身体趋势与固定指标目标的解释未在本批整体审查；历史记录真伪无法由本地规则自动证明。
- 真机、Apple 健康、语音、真实模型、线上登录与跑姿视频门槛未改变；登录页既有 `Not Found` 保留。
- 回滚仅撤回本批界面和质量计算；不清空记录，不改数据库表，不恢复整库快照。若需要保持样例隔离，可单独保留只读样例入口。
