# 运动策略迁移黄金基线

本目录只保存合成资料的固定预期，不包含真实个人或健康数据。

- `migration_golden.json`：249 组规范 JSON 的 SHA-256。
- 输入：`test/plugins/sports/migration_cases.dart`，固定日期为 2026-07-13。
- 原始生成器来源：`/tmp/trainmate-plugin-implementation-20260904/baseline/lib/services/four_week_plan_generator.dart`。
- 原始生成器 SHA-256：`ee1f068b31b6368f7572b0cfc9cfa1d4486551de0a6bc6a26a73ffad8b169f06`。
- 黄金文件 SHA-256：`e9cc2317ff7a85ac4efc403b6a859c6b67f42fc8e3f6d3edd2f9cf7151f1b14f`。

初始 245 项在 P2 生产代码提取前生成；补充 4 项主次赛事与 AI 交叉案例时，同样运行原始生成器，并逐项确认已有 245 个预期保持不变。临时测试入口只重写原始生成器导入路径，不改算法，使用当前工程未变更的模型、种子和通用结构服务。所有案例都开启现有结构编译。

摘要对象包含完整 `TrainingPlan.toJson()`、四周阶段代码与实际赛事 ID。因此动作关联、ABC 处方、时间、器械替换、文字内容和周结构均参与比较。插件来源是本次新增元数据，单独由来源测试断言。

覆盖七类入口、四种器械、本地与 AI、力量 ABC、1/2/7 天边界、主次目标、四类赛事的六个时间阶段、AI 下次运动仅贡献赛事的组合。

验证：`flutter test --no-pub test/plugins/sports/migration_golden_test.dart`。P3 继续使用本基线，禁止用新实现重新计算预期来消除差异。生产旧生成器和捕获测试均未保留在仓库；固定黄金与合成输入长期保留。
