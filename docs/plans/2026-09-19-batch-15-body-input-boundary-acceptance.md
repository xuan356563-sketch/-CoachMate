# Batch 15：身体数据文字与 CSV 数值边界验收

日期：2026-09-19。本批完成上一批发现的疲劳／酸痛零值改写修复，并检查同一输入链路的负值、小数、非有限值和缺失字段；完成审查、修复、测试与限定模拟器验收后停止。

## 基线与范围

起始工作区 408 条未提交状态，快照为 `/tmp/trainmate-batch15-start-status.txt`；修改前的两个解析服务及 CSV 结果模型备份在 `/tmp/trainmate-batch15-before/`。保留用户和此前批次的未提交改动。

旧截图文字及 CSV 解析均将疲劳、酸痛限制到 1—10，合法的 0 会变成 1，越界值也会被改成边界值。截图原正则仅取无符号数值前缀，负值或错误文字可能被当作缺失并继承历史；整数字段通过四舍五入生成结果。CSV 的浮点字段未拒绝 NaN／Infinity。

本批沿用 `BodyMetric.hasValue` 已有数值定义：疲劳／酸痛为 0—10 的整数，其余指标为正数；所有新输入均须为有限数值。它们是既有数据格式要求，不是新增医学阈值、能力分级或健康判断。

## 修改与审查

- 两种输入共用小型数值校验函数，仅校验本次提供的字段。合法值原样保留，显式无效值返回中文字段原因，不截断、不以历史替代、不生成候选测量。
- 疲劳与酸痛的 0 和 10 原样保留。缺失字段可继续沿用历史值，但 `recordedFields` 不将它们标记为本次观测；历史零值也不会再被改成 1。
- 截图文字完整解析数值及已知紧邻单位，拒绝错误数字尾部，不把指数、负数或小数截成另一个值。浮点字段可读取科学计数；整数字段与 CSV 一致，直接解析整数文本，不接受小数或指数写法，也不四舍五入。
- 审查补强整数精度路径：直接解析整数文本，避免先转为浮点数丢失原整数；超出整数表示范围明确拒绝。
- 混合 CSV 延续“保存有效行、跳过错误行”的既有行为，同时将原有逐行错误通过可选 `rowErrors` 返回，在摘要中显示行号和中文原因。该结果仅用于本地会话展示，不新增持久化字段、数据库表或云端字段。
- 现有控制器的失败清理与提交链路保持不变：错误截图会清除旧待确认结果；有效截图仍需手动确认；CSV 延续原整批有效记录提交和失败恢复。
- 没有修改训练计划、账号权限、准备度公式、插件装配或同步授权，没有增加依赖或升级框架。

## 修改文件

|文件|原因|
|---|---|
|`lib/services/body_metric_input_validation.dart`|两种输入共用既有字段数值要求|
|`lib/services/body_metric_snapshot_service.dart`|保留零值、拒绝显式无效值、完整数值与整数解析|
|`lib/services/body_metric_import_service.dart`|保留零值、校验本次输入、传出逐行跳过原因|
|`lib/data/models/body_metric_import.dart`|可选逐行错误及摘要展示，默认兼容原构造方式|
|`test/features/training_loop/body_input_boundary_batch_test.dart`|52 项解析、来源、精度、拒绝写入、确认与重读验证|
|`docs/plans/2026-09-12-training-loop-implementation.md`|更新本批结果与停止点|
|本文|验收证据、范围与回滚|

## 自动验证

|检查|本轮结果|日志|
|---|---|---|
|修改前相关基线|34 通过|`/tmp/trainmate-batch15-baseline.log`|
|首批新增测试对旧实现|5 通过、36 失败，复现改写及错误接受|`/tmp/trainmate-batch15-red.log`|
|首轮修复与相关回归|75 通过|`/tmp/trainmate-batch15-green.log`|
|扩展审查测试|51 通过|`/tmp/trainmate-batch15-review.log`|
|整数精度修复与解析回归|61 通过|`/tmp/trainmate-batch15-review-retry.log`|
|最终相关回归|222 通过、0 失败|`/tmp/trainmate-batch15-final-tests.log`|
|静态分析|无问题|`/tmp/trainmate-batch15-analyze.log`|
|内容目录只读校验|6 个分域通过|`/tmp/trainmate-batch15-catalog.log`|
|iOS 模拟器构建|通过|`/tmp/trainmate-batch15-ios.log`|
|差异检查|`git diff --check` 通过|本轮执行|

最终集合为 Batch 14 的 170 项加本批 52 项，含两种本地存储的既有失败恢复、账号隔离及插件生命周期回归。没有以修改旧断言掩盖失败，也没有宣称跑过整个项目测试集。

定向复验：

```sh
scripts/run_flutter_tests_clean_copy.sh \
  test/features/training_loop/body_input_boundary_batch_test.dart \
  test/services/body_metric_snapshot_service_test.dart \
  test/services/body_metric_import_service_test.dart --reporter expanded
scripts/run_flutter_analyze_clean_copy.sh
scripts/verify_content_catalog.sh
```

## 模拟器语义验收

设备：`TrainMate Batch2 课程调整 20260915`，iOS 26.5，UDID `F1C9B27E-6D81-43A4-938D-136966C40F94`。构建前核对会话默认值，构建副本依赖声明及锁文件与工作区逐字节一致。

使用已授权的隔离本地体验和合成数据，从“我的 → 身体数据 → 截图文字”操作。这里验证的是手动粘贴文字的解析与确认，页面仍标注“截图识别 Mock”；不代表真实 OCR、相册或测量准确性通过。

1. 输入合成完整指标，疲劳 11、酸痛 0。页面显示“疲劳必须是 0 至 10 的整数，不会自动截断”，没有确认入口；数据库全部 16 份业务文档与操作前逐字一致。
2. 修改为疲劳 0、酸痛 0，其他值为体重 70.8、体脂率 18、静息心率 60、HRV 50、睡眠 7。识别后进入待确认，全部文档仍未变化。
3. 点击“确认写入截图识别数据”成功。仅 `trainflow.body_metrics.v1` 改变，新增 2026-09-19 一条记录；疲劳及酸痛均为 0，且在实际字段清单中。原四条记录及原修订完全保留，其他 15 份文档逐字不变，没有新增签到或改写有效计划。
4. 停止并重启 App，重新进入身体数据。快录从已保存记录显示疲劳 0/10；数据库原文与保存后全部一致，记录数为 5。

新增身体记录使既有派生统计刷新：覆盖日变为 5/7，成长页面显示 52 XP（此前 47）。这是当前身体记录计数的派生展示，未产生训练完成或新增签到文档；本批未改其算法，也不据此证明训练成效。

工具的中文键入未进入模拟器文本框，且粘贴未成功，因此使用现有英文别名重新输入同一组合成数据，操作前逐项核对显示值；未通过直接写数据库伪造验收。

证据：

- `/tmp/trainmate-batch15-before-ui.json`：操作前业务文档原文。
- `/tmp/trainmate-batch15-invalid-ui.json`、`/tmp/trainmate-batch15-preview-ui.json`：错误输入与未确认阶段无写入。
- `/tmp/trainmate-batch15-saved-ui.json`、`/tmp/trainmate-batch15-restarted-ui.json`：保存与重启原文对照。
- `/var/folders/35/g00sx__534bf30jg1y8l59d00000gn/T/screenshot_optimized_aea73a59-0ed6-4a5f-ac75-43c5b73e1118.jpg`：越界输入中文原因。
- `/var/folders/35/g00sx__534bf30jg1y8l59d00000gn/T/screenshot_optimized_fbc324dd-ce15-4f80-8703-23ed3a75a3aa.jpg`：重启后的疲劳零值。

临时证据可能被系统清理。CSV 混合错误行及零值持久化由自动测试覆盖，本次模拟器没有重复进行 CSV 导入。

## 停止点与回滚

本轮停在 Batch 15。下一批回到身体趋势图表与摘要的证据口径；本次没有扩大为任意 OCR 文本、CSV 全语法、日期解析或健康合理性的全面校验。

真机、真实测量、Apple 健康、语音及真实模型未在本批验证；线上登录仍为既有 `Not Found`，使用本地体验不表示线上通过。跑姿视频正式入口继续关闭，整体发布门槛未全部验收。

回滚仅切换新输入解析实现，保留已有记录及历史读取，不清库、不恢复整库快照。没有自动创建分支、提交、推送或部署。
