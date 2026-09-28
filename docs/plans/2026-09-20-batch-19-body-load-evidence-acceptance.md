# Batch 19：身体证据进入训练负荷估算的边界验收

日期：2026-09-20。本批只修复“身体记录 → 训练负荷曲线／训练状态”的输入边界与估算说明。完成实现、审查、修复、测试和限定模拟器检查后停止。

## 基线与范围

起始工作区有 416 条未提交状态，快照 `/tmp/trainmate-batch19-start-status.txt`；两个目标源码文件修改前备份在 `/tmp/trainmate-batch19-before/`。保留已有修改，不创建分支、提交、推送、部署或升级依赖。

图谱未提供相关 getter 的有效调用结果，继续读取现场源码并搜索调用方：`trainingLoadCurvePoints` 生成 ATL／CTL，进入 `trainingStatusLabel` 与理由，并被周报、提醒等读取。原日负荷逻辑在无日志时直接读取身体记录全部数值，导致缺失或继承 HRV／睡眠按低值增加惩罚，未知来源也可参与；未来身体日期还会把整条曲线推向未来。

本批不重新设计负荷算法：保留训练日志优先、档案初值、HRV／疲劳初值修正、EWMA、既有系数和阈值、18—95 的身体估算范围，以及无身体依据时的原有当日计划／空日回退。完整有效资料的业务结果必须保持相同。

## 修改与审查

- 身体记录不能决定未来的负荷窗口终点。训练日志日期处理保持原样，没有在本批扩大为日志质量重构。
- 每日身体候选必须来源已确认、时间不晚于当前时刻、本地日期匹配，并至少有一项有效的疲劳、酸痛、睡眠或 HRV。仅体重／体脂等无关记录不能制造身体负荷估算。
- 同日存在多条记录时，取时间最近且具有相关证据的整条记录，不依赖输入列表顺序，也不把多条记录拼接成一次测量。
- 四项计算分别调用现有 `hasValue`：缺失、继承和无效数值不参与对应项；没有有效项则进入原有无身体记录路径。
- 合法疲劳／酸痛 0 仍有效，保留原公式的工程下限 18；这不是实际测量负荷，未将其改写为健康阈值。
- “我的”卡片改为“训练负荷工程估算”，CTL 改称“慢性负荷估算”；说明档案起始值、训练日志优先、有效身体字段／当日计划回退，以及空日 0 输入不代表测量为零。
- 现有页面测试仅同步新标题和标签，保留正向／负向断言数量。没有修改旧“应用今日调整”断言。
- 补充当日状态已确认时的下游检查：加入十三天未知来源记录后，所有曲线点、训练状态、理由及有效计划保持相同。
- 补充当日未来时刻和同一时刻 UTC／本地表示的检查。没有宣称已完成全部时区／夏令时环境验收。

## 修改文件

|文件|原因|
|---|---|
|`lib/features/dashboard/training_mvp_controller.dart`|仅修改曲线日期的身体来源及每日身体估算输入检查|
|`lib/features/profile/widgets/training_load_card.dart`|工程估算说明、ATL／CTL 标签|
|`test/features/training_loop/body_load_evidence_batch_test.dart`|新增 12 项来源、缺失、时间、等价、下游及窄屏大字检查|
|`test/features/dashboard/today_training_page_test.dart`|保持今日页不出现该卡片的断言，与新标题同步|
|`test/widget_test.dart`|三个负荷卡标题／标签断言与新文案同步；其他旧断言不变|
|`docs/plans/2026-09-12-training-loop-implementation.md`|更新批次状态|
|本文|本批证据、已知失败和停止点|

## 自动验证与既有失败

|检查|结果|日志|
|---|---|---|
|修改前相关基线|18 通过|`/tmp/trainmate-batch19-baseline.log`|
|新增测试对旧实现|2 通过、9 失败，复现证据污染与旧文案|`/tmp/trainmate-batch19-red.log`|
|首轮修复回归|29 通过|`/tmp/trainmate-batch19-green.log`|
|下游、今日页及四运动课程回归|56 通过|`/tmp/trainmate-batch19-review.log`|
|补充时间边界后最终相关回归|56 通过、0 失败|`/tmp/trainmate-batch19-final-tests.log`|
|旧端到端单项|1 失败，发生在“应用今日调整”入口|`/tmp/trainmate-batch19-legacy-widget.log`|
|独立副本恢复修改前源码复验旧端到端单项|同一位置 1 失败，确认是既有问题|`/tmp/trainmate-batch19-legacy-before.log`|
|静态分析|无问题|`/tmp/trainmate-batch19-analyze.log`|
|内容目录只读校验|6 个分域通过|`/tmp/trainmate-batch19-catalog.log`|
|iOS 模拟器构建|通过|`/tmp/trainmate-batch19-ios.log`|
|差异检查|`git diff --check` 通过|本轮执行|

各集合不累加。旧端到端测试为 `test/widget_test.dart` 中“TrainFlow AI 默认进入今日训练页”，在第 1933 行滚动查找“应用今日调整”时报 `Bad state: No element`，没有执行到本批负荷卡断言。独立临时副本恢复本批修改前的两个生产源码及原标签断言后，仍在同一位置失败。未修改或降低该入口断言；本批没有解决这个既有失败，不能声称全套测试通过。

业务等价使用固定的合成档案参数和当天锚定数据：每周 3 天、每日 60 分钟，完整身体记录疲劳 4、酸痛 3、睡眠 6、HRV 40。原身体日估算为 58，档案初值为 139；第十四日结果严格对照原 EWMA 闭式值。另验证训练日志优先、真实身体数值改变时结果改变、无效来源／缺失记录与无身体记录的曲线相同。测试未写入有效计划。

```sh
scripts/run_flutter_tests_clean_copy.sh \
  test/features/training_loop/body_load_evidence_batch_test.dart \
  test/features/training_loop/readiness_evidence_test.dart \
  test/features/training_loop/readiness_batch_test.dart \
  test/features/training_loop/weekly_facts_batch_test.dart \
  test/features/training_loop/daily_course_test.dart \
  test/features/profile/profile_page_test.dart \
  test/features/dashboard/today_training_page_test.dart --reporter expanded
scripts/run_flutter_analyze_clean_copy.sh
scripts/verify_content_catalog.sh
```

## 模拟器检查

设备 `TrainMate Batch2 课程调整 20260915`，iOS 26.5，UDID `F1C9B27E-6D81-43A4-938D-136966C40F94`。沿用已授权本地体验；构建前核对会话默认值，干净副本依赖声明及锁文件与工作区逐字节相同。

- 在“我的 → 训练负荷”看到“训练负荷工程估算”，ATL／CTL 使用估算标签，完整显示数据顺序与缺失解释。
- 现有合成场景仍显示“无法评估”，下方说明缺少当日确认或有效恢复记录，未将曲线数值当作当前身体状态或训练进步证明。
- 只浏览，不确认状态、不添加记录、不调整计划。独立只读 SQLite 对照，前后全部 17 份业务文档原文逐字一致。

证据：

- `/tmp/trainmate-batch19-before-ui.json`
- `/tmp/trainmate-batch19-after-ui.json`
- `/var/folders/35/g00sx__534bf30jg1y8l59d00000gn/T/screenshot_optimized_490956d6-7d38-47d7-854b-9e9aa5cac26b.jpg`

模拟器没有注入未知来源、缺失或未来日期反例；这些由合成自动测试覆盖。截图只能证明展示，不证明负荷算法对真实人体的有效性。临时证据可能被系统清理。

## 剩余范围与回滚

本轮停在 Batch 19。恢复倒计时仍存在直接读取最新身体记录的路径，下一批优先检查。共享均值的窗口／同日记录口径、未来训练日志、训练日志的完成量折算、状态标签的效果解释以及整体发布验收仍需独立检查，不能由本批推断已统一。

保留当前估算规则不代表其已完成真实样本效果验证。本期没有新增临床阈值、训练算法或网络字段，没有修改存储结构、授权及同步范围。

回滚只撤销本批两个源码文件的列出片段及对应标签，不覆盖整个已有未提交文件，不删除记录或恢复整库。回滚会重新暴露旧证据准入问题，应保留该限制说明。
