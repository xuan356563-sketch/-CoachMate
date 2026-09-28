# Batch 6：周报停用后的完整历史阅读

日期：2026-09-16（America/Los_Angeles）。本批完成已保存教练周报的只读展示及功能管理页到核心历史的导航修复。按用户要求，仅推进这一批，完成审查、修复、自动测试和模拟器验证后停止。

## 基线与范围

- 起始工作区 390 条未提交状态，记录在 `/tmp/trainmate-batch6-start-status.txt`。本批修改前文件与依赖备份为 `/tmp/trainmate-batch6-before`，保留用户已有修改。
- 基线历史页、能力管理页和报告生命周期共 11 项通过，日志为 `/tmp/trainmate-batch6-baseline.log`。
- 代码图谱没有返回当前历史页的符号，后续检查当前工作区的页面、报告模型、只读服务和路由。
- 上一批解决了周报保存，但历史页只显示决策和恢复摘要，缺少保存时的事实依据、复盘字段和方向选择。本批补齐这些内容，不重算历史结论、不应用课程调整。

## 修改与审查

|问题|修复|
|---|---|
|停用周报后，核心历史看不到完整复盘|展开历史报告后展示生成日期、原摘要、目标、事实依据、各维度实际／计划次数、手动评分与备注、原亮点和下周方向|
|缺失字段可能被理解为默认评分或当前状态|缺失评分显示“未填写”；旧报告缺少依据或手动复盘时说明未保存，不从当前档案与健康数据补算|
|已保存方向没有展示，来源丢失时可能误选|只使用报告自身保存的选项标签匹配；缺失、空标签或重复匹配不默认选首项。明确方向选择仅是复盘记录，不代表已调整计划|
|从“我的 → 运动与功能 → 历史记录”触发导航断言|模拟器发现 `!keyReservation.contains(key)` 断言，新增相同堆栈路径测试复现；管理页切回历史路由，避免再次压入已存在的底部导航容器|

历史页没有新增编辑、保存或生成按钮。原摘要即使含有旧措辞，也以“原报告摘要”保留，不悄悄改写。管理页进入历史后使用历史页原有的“我的”回退入口，不保留重复的管理页导航堆栈。

本批不修改报告模型、存储键、数据库表、仓储写入逻辑、训练算法、认证或云同步协议。周报功能的启停仍通过现有管理控制器持久化。

## 自动验证

新增 5 项测试：完整历史回读、旧记录缺失字段兼容、方向来源缺失、停用周报深链保护，以及从已有主导航打开管理页再实际点击历史入口。读取测试检查无存储写入、原报告文档不变。

- 实施前，两项新增历史展示反例失败，相关日志 `/tmp/trainmate-batch6-red.log`。
- 首轮路由测试只直接跳转，未覆盖主导航上叠加管理页的场景；模拟器发现错误后补上真实点击路径，修复前复现同一导航断言，日志 `/tmp/trainmate-batch6-navigation-red.log`。
- 修复过程中补齐维度标签扩展导入，并让点击测试定位可见标题，避免测试视口中的卡片中心被底部导航遮挡；没有降低业务断言。

最终验证：

|检查|结果|证据|
|---|---|---|
|历史、能力管理、核心历史、路由、插件设置、周报事实与保存回归|51 项通过、0 失败|`/tmp/trainmate-batch6-final-tests.log`|
|`flutter analyze`|无问题|`/tmp/trainmate-batch6-analyze.log`|
|内容目录只读校验|6 个分域通过|`/tmp/trainmate-batch6-catalog.log`|
|最终源码 iOS 模拟器构建|通过|`/tmp/trainmate-batch6-ios.log`|

最终测试命令：

```bash
scripts/run_flutter_tests_clean_copy.sh \
  test/features/capabilities \
  test/plugins/assembly/core_history_test.dart \
  test/plugins/assembly/router_assembly_test.dart \
  test/plugins/settings \
  test/plugins/lifecycle/report_lifecycle_test.dart \
  test/features/training_loop/weekly_facts_batch_test.dart \
  test/features/training_loop/weekly_persistence_batch_test.dart \
  test/features/training_loop/weekly_storage_batch_test.dart \
  --reporter expanded
scripts/run_flutter_analyze_clean_copy.sh
scripts/verify_content_catalog.sh
```

各轮测试数量不相加，前批 84 项不是本批的重跑总数。

## 模拟器验收

沿用隔离模拟器 `F1C9B27E-6D81-43A4-938D-136966C40F94`（“TrainMate Batch2 课程调整 20260915”）及前批合成数据，没有导入真实训练或健康数据。

1. 在“我的 → 运动与功能”关闭周报，界面显示开关关闭以及历史仍可查看的提示。
2. 实际点击管理页“历史记录”发现导航断言，完成上述回归测试和修复后重新构建、安装、启动。
3. 重启后周报开关仍为关闭；SQLite 中的覆盖项仍为 `feature.weekly_report: false`，报告原文未变。
4. 重新走“我的 → 运动与功能 → 历史记录”，进入正常的核心历史页面，底部导航可见，未再出现断言。
5. 展开 `9/14 - 9/20` 的原报告：生成日期仍为 2026-09-16，原窗口与 0.50/3、17% 保留；可看到维度次数、三项“未填写”、状态无法评估，以及“已保存方向：保持当前周训练频率”。页面明确仅为记录，不表示计划已经调整。
6. 只读 SQLite 对照：只增加或更新 `trainflow.plugin_settings.v1`，其他报告、有效计划、训练日志和课程调整文档原文均未改变。没有重新保存周报来代替回读。
7. 验收结束后，通过管理页恢复周报为启用；界面显示已启用，数据库中的停用覆盖项移除，恢复默认启用。设置文档的 `enabledOverrides` 为空，其余业务文档仍与批前一致，没有清理用户数据。

证据为 `/tmp/trainmate-batch6-before-ui.db`、`/tmp/trainmate-batch6-disabled-persistence.json`、`/tmp/trainmate-batch6-disabled-history-ui.json`、`/tmp/trainmate-batch6-history-persistence.json`、`/tmp/trainmate-batch6-final-persistence.json`。临时证据可能被系统清理。构建副本位置在 `/tmp/trainmate-batch6-ios-path.txt`，复用前批依赖匹配的副本并同步本批最终源码；依赖声明和锁文件保持不变。

模拟器长列表的拖动操作一度不稳定，改用键盘翻页与可访问性点击完成；不据此声称已完成全部纯触摸交互验收。

## 修改文件

|文件|原因|
|---|---|
|`lib/features/capabilities/history_page.dart`|完整只读报告及缺失来源说明|
|`lib/features/capabilities/capabilities_page.dart`|修复从主导航经管理页再次进入核心历史的重复导航|
|`test/features/capabilities/history_page_test.dart`|3 项历史展示和兼容回归，复用原夹具|
|`test/plugins/assembly/router_assembly_test.dart`|2 项停用深链与实际点击路径回归|
|本记录、`2026-09-12-training-loop-implementation.md`|验收结果、导航问题证据和未验证边界|

## 剩余门槛与回滚

本批完成停用、重启、历史阅读和恢复启用的模拟器流程；真机、线上登录、设备账号切换及物理磁盘故障仍未新增验收。登录页既有 `Not Found` 未修复。训练效果与跑姿视频真实样本门槛保持原状态，不因此宣称整体可以正式发布。

回滚只恢复本批两个页面的实现，不删除报告或恢复整库快照；旧数据兼容继续保留。未创建分支、提交、推送、部署或升级依赖。
