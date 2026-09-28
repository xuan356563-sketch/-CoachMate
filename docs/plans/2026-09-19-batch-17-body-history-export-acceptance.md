# Batch 17：身体历史与 CSV 导出证据口径验收

日期：2026-09-19。本批仅修复身体历史展示与 CSV 内容，完成审查、修复、相关测试和限定模拟器验收后停止。

## 基线与范围

起始工作区有 413 条未提交状态，快照 `/tmp/trainmate-batch17-start-status.txt`。修改前两个源码文件与主记录备份在 `/tmp/trainmate-batch17-before/`，未覆盖用户已有修改。

历史区原先读取近七日且已确认来源的集合，无法读取更早或未知来源的记录；卡片直接显示原始数值，未提供字段的兼容零值及继承值可能被误读为本次测量。CSV 同样直接输出原始数值，未知来源枚举回退后还会被写为 `manual`。

本批没有修改共享训练统计、准备度、计划规则、身体记录写入、导出登记的持久化实现或数据库结构。JSON 继续保留原始记录与现有元数据；不新增网络字段或云同步范围。

## 实施与审查

- 历史区改为“已保存身体记录”，读取全部已保存记录，保留旧日与未知来源记录的阅读入口。说明历史日期与保存时标签不代表当前状态。
- 七项数值分别检查现有 `BodyMetric.hasValue`。缺失、继承、来源未确认或无效字段显示“无有效记录”；有效的疲劳、酸痛 0 原样显示。
- 补齐历史卡片的酸痛字段。来源未确认时显示中文说明，不使用回退的“手动录入”标签。原保存时标签和备注保留可读。
- CSV 保留原来的 11 列表头、列顺序及已有数值格式；不可用数值留空，来源未确认使用 `unknown`。不删除整行，不把空值补成零。
- JSON 格式和序列化路径不变，仍保留原始保留值、`recordedFields` 与 `sourceVerified`。CSV 是有效指标视图，JSON 承担完整记录读取，页面明确说明两者含义。
- 审查补充实际“导出 CSV”按钮测试，检查预览文本、一次导出登记及身体记录／有效计划不变；另检查 CSV 的原备注转义与 JSON 来源标记保留。
- 合成稀疏 CSV 再导入时，只有原来实际提供的体重与疲劳成为本次观测；未知来源行数值全空，再导入被既有解析器拒绝，不能重新变成可信数值。
- 390×844、1.5 倍字号验证旧日与未知来源历史卡片可读，七字段缺失数量与零值显示符合实际记录。

## 修改文件

|文件|原因|
|---|---|
|`lib/features/data_center/data_center_page.dart`|全部历史入口、七字段有效性、未知来源、保存时标签及导出内容说明|
|`lib/features/dashboard/training_mvp_controller.dart`|只修改 CSV getter，逐字段留空与未知来源标记|
|`test/features/training_loop/body_history_export_evidence_batch_test.dart`|9 项 CSV、JSON、再导入、历史、真实按钮及只读边界测试|
|`docs/plans/2026-09-12-training-loop-implementation.md`|更新当前批次状态，保留旧记录|
|本文|本批范围、证据和剩余门槛|

## 自动验证

|检查|结果|日志|
|---|---|---|
|修改前相关基线|30 通过|`/tmp/trainmate-batch17-baseline.log`|
|新增测试对旧实现|2 通过、6 失败，复现 CSV／历史问题|`/tmp/trainmate-batch17-red.log`|
|首轮修复与数据中心回归|32 通过|`/tmp/trainmate-batch17-green.log`|
|审查补充实际按钮后的最终相关回归|66 通过、0 失败|`/tmp/trainmate-batch17-review.log`|
|静态分析|无问题|`/tmp/trainmate-batch17-analyze.log`|
|内容目录只读校验|6 个分域通过|`/tmp/trainmate-batch17-catalog.log`|
|iOS 模拟器构建|通过|`/tmp/trainmate-batch17-ios.log`|
|差异检查|`git diff --check` 通过|本轮执行|

各测试集合不加总。本批未重跑整个项目测试集，未降低现有断言，也未声称其他批次全部回归通过。

```sh
scripts/run_flutter_tests_clean_copy.sh \
  test/features/training_loop/body_history_export_evidence_batch_test.dart \
  test/features/training_loop/body_display_evidence_batch_test.dart \
  test/features/training_loop/body_goal_evidence_batch_test.dart \
  test/features/data_center \
  test/data/repositories/body_metric_export_repository_test.dart \
  test/services/body_metric_import_service_test.dart --reporter expanded
scripts/run_flutter_analyze_clean_copy.sh
scripts/verify_content_catalog.sh
```

## 模拟器验收

沿用已授权的隔离本地体验，设备 `TrainMate Batch2 课程调整 20260915`、iOS 26.5、UDID `F1C9B27E-6D81-43A4-938D-136966C40F94`。构建前检查会话默认值；干净构建副本的依赖声明与锁文件同工作区逐字节一致。安装工具要求模拟器会话默认值，首次参数校验未执行操作；补齐非持久化会话默认值后安装和启动成功。

使用现有 5 条合成身体记录，没有新增身体、签到或训练数据：

1. 历史卡片中，9 月 18 日手动记录的体重、心率、HRV、睡眠、疲劳显示原有效值，继承的体脂与酸痛显示“无有效记录”；9 月 17 日完整记录显示原指标。
2. 历史浏览前后，全部 16 份业务文档原文逐字不变。
3. 点击“导出 CSV”，预览实际包含 5 条记录。9 月 19 日疲劳与酸痛为 0；9 月 18 日体脂与酸痛留空；9 月 15／16 日 CSV 记录的继承体脂和心率留空。保存时标签及备注继续保留。
4. 页面登记 5 条、786 字节。SQLite 独立只读连接确认仅新增 `trainflow.body_metric_exports.v1`，内含一份 CSV 登记；此前 16 份文档，包括身体记录／修订、计划、签到和报告，全部原文不变。

本轮模拟器没有注入未知来源或更早日期记录，这两种情况由合成自动测试覆盖。没有将 CSV 预览或登记称为已生成系统文件；系统保存和分享仍未接入。本轮没有再做 App 重启、账号切换或导出失败恢复演练。

证据文件：

- `/tmp/trainmate-batch17-before-ui.json`：安装与浏览前的 16 份文档。
- `/tmp/trainmate-batch17-history-ui.json`：历史浏览后原文一致。
- `/tmp/trainmate-batch17-after-ui.json`：仅新增一份导出登记，原 16 份不变。
- `/var/folders/35/g00sx__534bf30jg1y8l59d00000gn/T/screenshot_optimized_ba41fefc-d7be-49d6-91a8-aa6ce0a393f4.jpg`：历史有效字段与继承字段区分。
- `/var/folders/35/g00sx__534bf30jg1y8l59d00000gn/T/screenshot_optimized_521d4b24-54a1-4d2c-a360-2d783f757594.jpg`：真实 CSV 预览、留空字段与零值。

临时文件可能被系统清理。

## 剩余范围与回滚

本批停止于历史与导出内容口径。导出登记控制器仍需下一独立批次验证等待持久化、失败恢复、重复操作及账号／插件生命周期；共享训练统计消费方仍待检查。全部历史当前沿用现有列表构建方式，未完成大量历史记录的性能验收。原 CSV 多行备注解析能力未扩展，保留原转义格式不代表所有外部 CSV 能无损往返。

真机、真实健康数据、完整闭环和整体发布门槛仍未完成。没有改依赖、数据库表、分支或提交，没有推送、部署。

如需回滚，仅撤销本批两个源码文件中列出的展示／导出片段，不整体覆盖已有未提交文件，不清空身体记录或导出登记，不恢复数据库快照。恢复旧导出展示也会重新暴露旧字段口径问题，应保留该已知限制说明。
