# Batch 12：身体趋势洞察的事实依据验收

日期：2026-09-19。本批按“实施 → 审查 → 修复 → 测试 → 限定模拟器验收”完成后停止。

## 范围与问题

本批只修改身体数据页的趋势洞察报告服务。原实现把整条记录内的继承值和缺失字段参与均值，按最新记录日期移动窗口；单条或同日重复记录也可能产生“基本稳定”“恢复基础稳定”等结论。记录变化还被描述为恢复或有氧基础改善，缺少相应证据。

起始工作区有 402 条未提交状态，保存在 `/tmp/trainmate-batch12-start-status.txt`；修改前相关文件备份在 `/tmp/trainmate-batch12-before/`。读取现有源码及图谱后再修改，保留用户改动，没有升级依赖、改数据库表、创建分支、提交、推送或部署。

## 实现与审查

- 7／30／90 日趋势报告按当前本地自然日确定观察窗口，排除未来时刻、窗口外和未知来源。新增可选 `now` 参数供固定时间验证，现有调用兼容。
- 复用 `BodyMetric.hasValue`，每个字段按自然日选择最新有效记录；同日重复不增加样本日，不把继承字段和零占位值算作实际观测。缺失日期不补零。
- 落实原说明中的至少 3 条记录要求，并按 3 个不同自然日检查；配对展示须有至少 3 个同日有效配对。它是保守的数据充分性门槛，不是生理或临床阈值。
- 体重报告展示窗口日期、来源、有效天数和首末差值。保留原 ±0.5 kg 的方向分界，将“缓慢上升／下降”改为“上升／下降”，避免把绝对差值说成变化速度。
- 心率／疲劳、HRV／睡眠只计算同日成对数据，展示两侧有效天数、配对天数、配对均值及来源。保留既有工程规则的数值分界，移除由均值直接推导“可以维持训练”或“下一课降强度”的处方式表述；未触发不代表今日状态正常。
- 急性负荷接口只有单个分值，没有本窗口样本依据，因此该叠加明确无法评估，不将零值当已观测训练负荷，不新增第二套负荷计算。
- 里程碑保留原实现的 3.5 kg／5 bpm 变化分界并如实说明，修正原说明把 3.5 kg 写成 5% 的不一致，不将其解释为训练改善。
- 每周下降比例仍按原公式和 >1.5% 提示分界，改用首末有效记录的自然日间隔，避免时刻取整及夏令时影响。明确属于工程折算，短窗口不代表已观测一整周，也不作安全保证。
- 审查补齐固定时间、窗口零点、同日未来、同日有效值去重、非配对极值不影响均值及输入不变测试；显示日期统一本地日期。

本批没有修改档案、训练计划、准备度算法、网络协议、云同步或存储格式。固定指标目标、摘要与图表的整体事实口径另批审查，本批结论不代表整个身体数据页已完成验收。

## 修改文件

|文件|原因|
|---|---|
|`lib/services/body_trend_insight_service.dart`|修复窗口、来源与字段筛选、逐日去重、配对计算及可解释报告|
|`test/features/training_loop/body_trend_evidence_batch_test.dart`|新增 15 项事实隔离、日期、规则反例、只读及窄屏测试|
|`docs/plans/2026-09-12-training-loop-implementation.md`|登记最新批次并保留历史|
|本文|记录范围、审查过程、测试证据和未验收边界|

## 自动验证

|检查|本轮结果|日志|
|---|---|---|
|修改前定向基线|38 通过|`/tmp/trainmate-batch12-baseline.log`|
|首轮新测试|夹具档案导入路径错误，编译失败；不是业务红测试|`/tmp/trainmate-batch12-red.log`|
|修正夹具后在旧实现复现|11 失败，均复现预期事实口径问题|`/tmp/trainmate-batch12-red-corrected.log`|
|实现后初步回归|35 通过|`/tmp/trainmate-batch12-green.log`|
|补充审查验证|本批 15 项通过|`/tmp/trainmate-batch12-review-tests.log`|
|最终相关回归|143 通过，0 失败|`/tmp/trainmate-batch12-final-tests.log`|
|静态分析|无问题|`/tmp/trainmate-batch12-analyze.log`|
|内容目录只读校验|6 个分域通过|`/tmp/trainmate-batch12-catalog.log`|
|iOS 模拟器构建|通过|`/tmp/trainmate-batch12-ios.log`|
|差异检查|git diff --check 通过|本轮执行|

最终回归包含 Batch 11 的 128 项相关检查及本批 15 项，涵盖身体记录、签到、失败恢复、账号清理、插件生命周期、准备度和伙伴读取。窄屏测试采用 390×844、1.5 倍文字，滚动至真实页面的趋势洞察卡，检查内容可读且未产生身体或签到写入。既有断言未降低。

复验命令：

```sh
scripts/run_flutter_tests_clean_copy.sh \
  test/features/data_center \
  test/data/repositories/body_metric_repository_test.dart \
  test/data/repositories/daily_check_in_repository_test.dart \
  test/features/training_loop/body_trend_evidence_batch_test.dart \
  test/features/training_loop/body_check_in_batch_test.dart \
  test/features/training_loop/check_in_persistence_batch_test.dart \
  test/features/training_loop/body_csv_batch_test.dart \
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
  test/plugins/lifecycle/health_data_lifecycle_test.dart \
  test/features/auth/account_switch_coordinator_test.dart --reporter expanded
scripts/run_flutter_analyze_clean_copy.sh
scripts/verify_content_catalog.sh
```

## 模拟器语义验收

设备：`TrainMate Batch2 课程调整 20260915`，iOS 26.5，UDID `F1C9B27E-6D81-43A4-938D-136966C40F94`。先核对设备与会话默认值，沿用干净构建副本；依赖声明和锁文件与工作区逐字节一致。重启安装本批版本后，沿用已授权的本地体验及现有合成记录，没有导入或修改数据。

- “我的 → 身体数据 → 趋势洞察”显示观察窗口 2026-09-13 至 2026-09-19，4 日有效体重，来源为手动、截图及文件；首末记录 9 月 15 日至 18 日，变化 +0.6 kg，方向为“上升”。
- 心率只有 2 日有效记录，疲劳 4 日，配对 2 日，明确无法评估；没有把 CSV 继承的心率当作新增样本。
- HRV 与睡眠各有 4 日且配对 4 日，均值分别为 49.8 ms 和 7.0 h，明确工程规则未触发不证明今日状态或相关性。
- 负荷叠加显示缺少样本依据；里程碑与减脂提示说明保留工程边界，旧身体记录仍能阅读。
- 浏览前后全部 16 份业务文档逐字一致：`/tmp/trainmate-batch12-before-ui.json` 与 `/tmp/trainmate-batch12-after-ui.json`。计划、训练日志、签到、修订及报告未改变。

趋势截图：`/var/folders/35/g00sx__534bf30jg1y8l59d00000gn/T/screenshot_optimized_850869f6-b3bf-4c1e-b930-336afeb49f83.jpg`。这些临时证据可能被系统清理。

## 停止点与限制

Batch 12 完成后停止。真机、真实身体测量准确性、Apple 健康、语音、真实模型及线上登录没有在本批验证；本批不验证工程分界的健康有效性。30／90 日窗口反例由自动测试覆盖，模拟器只验收 7 日窗口。

固定目标卡和趋势图表仍待后续批次；不把本批事实口径修复扩称为整个专业训练闭环已可发布。跑姿视频正式入口继续关闭。既有周期重排日期不足两天的测试失败未纳入本批集合，没有更改断言。

回滚仅恢复本批报告服务实现；不恢复整库快照，不清理用户记录。无表结构或持久化字段迁移。
