# Batch 16：身体摘要与趋势图表证据口径验收

日期：2026-09-19。本批仅统一“我的”身体摘要、身体页摘要及 7/30/90 日图表展示；完成审查、修复、测试和限定模拟器验收后停止。

## 基线与范围

起始工作区有 411 条未提交状态，快照 `/tmp/trainmate-batch16-start-status.txt`。修改前两个页面及目标卡测试备份在 `/tmp/trainmate-batch16-before/`，保留已有未提交改动。

原图表以最新一条记录的日期为窗口终点，把各条记录的全部数值直接绘点，按记录顺序等距连线，缺失及历史继承值可能成为新观测。摘要无数据时可能展示 0，把旧记录标为“今日身体状态”。图表还直接将曲线描述为恢复或风险方向。

现有 `TrainingMvpState` 均值方法有其他训练调用方，因此本批没有改动这些公共计算方法。新增只读展示计算供三个界面共用，不写仓储，不扩展健康事实来源，不改变训练规则或准备度算法。

## 实施与审查

- 以当前本地自然日为窗口终点，包含首日午夜，排除窗口外、未来时刻和未知来源记录。
- 体重、静息心率、HRV、睡眠、疲劳分别检查 `hasValue`；每项每个自然日只取最近有效观测。较新记录中的缺失或继承字段不会覆盖同日较早的有效值。
- 均值只计算有效记录日，缺失返回“无有效记录”，不补零；疲劳 0 仍是合法观测。显示覆盖天数、各项最近有效日期及来源。
- 摘要改为“近 7 日身体记录”和“记录日均值”，明确不代表今日状态；不再使用整条最新记录的情绪／来源标签概括所有指标。
- 图表为完整日历窗口保留空日位置，各项独立绘点、空日断线。用实际日期间距替代记录序号间距，单个有效点也保留其真实日期位置。
- 保留三条曲线，明确各线独立缩放、纵向位置不可跨指标比较，图例显示单位、实际数值范围及覆盖日。删除依据线条方向直接判断恢复或风险的文案。
- 图表下方五项摘要与顶部使用同一展示计算；“我的”展示相同的四项均值及证据。
- 审查发现长图例在 1.5 倍字号下横向溢出，已改为可换行。实际画布测试检查绘点横坐标和线段路径，证明缺失日没有被连成完整曲线，而不仅检查说明文字。
- 新摘要增加了“无有效记录”文本。原目标卡测试改为限定目标卡范围内仍严格断言两项缺失，没有降低原业务断言。

## 修改文件

|文件|原因|
|---|---|
|`lib/services/body_metric_display_service.dart`|只读自然日窗口、逐字段观测、均值与来源说明|
|`lib/features/data_center/data_center_page.dart`|身体摘要、真实日期图表、空日断线、图例和明细|
|`lib/features/profile/profile_page.dart`|“我的”身体摘要使用同一展示计算|
|`test/features/training_loop/body_display_evidence_batch_test.dart`|12 项窗口、来源、缺失、绘图路径、切换和页面验证|
|`test/features/training_loop/body_goal_evidence_batch_test.dart`|将原目标卡缺失断言限定到该卡片|
|`docs/plans/2026-09-12-training-loop-implementation.md`|更新本批验收状态|
|本文|范围、证据及停止点|

## 自动验证

|检查|本轮结果|日志|
|---|---|---|
|修改前定向基线|54 通过|`/tmp/trainmate-batch16-baseline.log`|
|新增空记录／过期场景对旧实现|2 失败，复现默认零值与旧展示口径|`/tmp/trainmate-batch16-red.log`|
|首轮修复与数据中心回归|26 通过|`/tmp/trainmate-batch16-green.log`|
|扩展审查|29 通过、3 失败：图例溢出及旧测试匹配范围|`/tmp/trainmate-batch16-review.log`|
|修复后复验|32 通过|`/tmp/trainmate-batch16-review-retry.log`|
|最终相关回归|239 通过、0 失败|`/tmp/trainmate-batch16-final-tests.log`|
|静态分析|无问题|`/tmp/trainmate-batch16-analyze.log`|
|内容目录只读校验|6 个分域通过|`/tmp/trainmate-batch16-catalog.log`|
|iOS 模拟器构建|通过|`/tmp/trainmate-batch16-ios.log`|
|差异检查|`git diff --check` 通过|本轮执行|

最终集合为 Batch 15 的 222 项，加本批 12 项及“我的”既有 5 项页面回归。覆盖原存储、失败恢复、账号与插件回归，不代表整个项目测试集全部通过。

定向复验：

```sh
scripts/run_flutter_tests_clean_copy.sh \
  test/features/training_loop/body_display_evidence_batch_test.dart \
  test/features/training_loop/body_goal_evidence_batch_test.dart \
  test/features/profile/profile_page_test.dart --reporter expanded
scripts/run_flutter_analyze_clean_copy.sh
scripts/verify_content_catalog.sh
```

绘图测试使用四个实际体重观测日及一个疲劳零值日，读取画布真实绘制的圆点和路径：横坐标保留空日间距，中间缺失处有两个独立线段，缺失 HRV 没有补点。另验证 390×844、1.5 倍字号的两个摘要、7/30/90 日切换及浏览不改变计划或本地记录。跨月日历排列通过；未将其称为完整时区和夏令时设备验收。

## 模拟器语义验收

设备：`TrainMate Batch2 课程调整 20260915`，iOS 26.5，UDID `F1C9B27E-6D81-43A4-938D-136966C40F94`。构建前核对会话默认值，干净副本依赖声明及锁文件与工作区逐字节一致。

沿用已授权隔离本地体验，只浏览既有 5 条合成身体记录，不新增或改写记录：

- “我的”与身体页摘要一致：体重 70.4 kg、覆盖 5/7 日；静息心率 60.0 bpm、覆盖 3/7 日，排除两条 CSV 中继承的心率；HRV 49.8 ms、睡眠 7.0 h，均覆盖 5/7 日。各项显示最近有效日期及其真实来源类别。
- 7 日图表窗口为 2026-09-13 至 2026-09-19，实际点仅从 9 月 15 日开始；前两天空白。体重范围 70.0—70.8 kg、HRV 49.0—50.0 ms、疲劳 0.0—3.0/10，各为 5 个观测日。
- 切换 30 日，窗口起点为 8 月 21 日，显示 5/30 日；切换 90 日，起点为 6 月 22 日，显示 5/90 日。五个观测点保留在窗口末端，没有把稀疏数据等距铺满整个窗口。
- 回到默认 7 日。浏览和切换前后，全部 16 份业务文档原文逐字不变，身体记录、计划、日志、签到、修订和报告均未写入。

本次模拟器没有制造窗口中间缺失样例；空日断线由画布自动测试验证。没有以看见新页面代替持久化或算法效果证明。

证据：

- `/tmp/trainmate-batch16-before-ui.json` 与 `/tmp/trainmate-batch16-after-ui.json`：业务文档原文对照。
- `/var/folders/35/g00sx__534bf30jg1y8l59d00000gn/T/screenshot_optimized_c88b19c7-c8c5-408d-b415-d00e816b07ee.jpg`：“我的”逐字段覆盖及来源。
- `/var/folders/35/g00sx__534bf30jg1y8l59d00000gn/T/screenshot_optimized_1af2c0c6-2577-4953-a31e-53696eef895d.jpg`：7 日图表及指标范围。
- `/var/folders/35/g00sx__534bf30jg1y8l59d00000gn/T/screenshot_optimized_dd5a5aa3-848c-4ce0-8209-f810e5ab8670.jpg`：90 日日期位置与覆盖率。

临时证据可能被系统清理。

## 停止点与回滚

本轮停在 Batch 16。共享训练统计接口、身体历史行与导出内容没有在本批统一重构，不能把展示验收扩大为所有消费方的数据口径都已通过。后续先追踪这些调用范围，再圈定下一批。

真机、真实测量、Apple 健康、语音和真实模型未在本批验证；线上登录仍有既有 `Not Found`，本地体验不代表线上验收。跑姿视频正式入口继续关闭，整体发布门槛尚未全部完成。

回滚仅还原本批展示服务与页面装配，不清空设置或历史，不恢复整库快照。没有改数据库表、同步字段、依赖、分支，也未提交、推送或部署。
