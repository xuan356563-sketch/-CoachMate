# TrainMate 双配色 20 动作表情差异化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为两套 20 动作人物增加语义化差异表情、橙桃渐变和少量青色情绪符号，并同步 App 运行时素材。

**Architecture:** 以现有 1254px 单图为每项编辑基准，逐张引用用户主参考图和表情参考图进行受控图像编辑；通过备份、SHA、Alpha、尺寸和小尺寸总览校验保护动作与透明轮廓。App 保持原资源路径，因此只替换 512px 副本，不改业务组件接口。

**Tech Stack:** 图像编辑工具、PNG/Alpha 校验、macOS `sips`、Flutter Widget 测试。

## Global Constraints

- 不新增依赖，不修改路由、Provider、数据库、后端、主题 Token 或公共业务 API。
- 不触碰与人物资产无关的现有未提交改动，不执行 Git 提交。
- 正式源图固定 `1254×1254`，运行时副本固定 `512×512`，全部真实透明 PNG。
- 单项最多重试 2 次；已通过项目不重复生成；同时最多运行 3 个编辑任务。
- 表情、配色和符号严格遵守 `docs/superpowers/specs/2026-07-17-trainmate-expression-differentiation-design.md`。

---

### Task 1: 建立回退基线和验证清单

**Files:**
- Create: `outputs/logos/trainmate-flow/action-set-20/attempts/pre-expression-v2/`
- Create: `outputs/logos/trainmate-flow/action-set-20-peach-light/attempts/pre-expression-v2/`
- Create: `outputs/logos/trainmate-flow/action-expression-v2-manifest.md`

**Interfaces:**
- Consumes: 两套 `individual/*.png` 正式图和两张用户参考图。
- Produces: 40 张覆盖前备份、逐文件 SHA-256、尺寸与 Alpha 基线。

- [ ] 复制两套正式图到对应备份目录，拒绝覆盖已存在且校验值不同的备份。
- [ ] 记录 40 张源图、40 张运行时副本和两张参考图的 SHA-256。
- [ ] 使用 `sips` 检查正式源图均为 `1254×1254` 且 `hasAlpha: yes`。
- [ ] 确认 `git status` 中无与本任务冲突的已跟踪人物文件修改。

### Task 2: 制作五个代表动作样张

**Files:**
- Modify: 两套 `individual/` 中的 `01`、`05`、`07`、`13`、`20`。
- Create: `outputs/logos/trainmate-flow/action-expression-v2-pilot-overview.png`

**Interfaces:**
- Consumes: 现有动作图、主忍者参考图、表情参考图、设计映射。
- Produces: 10 张 1254px 双配色样张和 2×5 纸白样张总览。

- [ ] 按编号逐张编辑，只改变眉眼、嘴、头带/飘带渐变、主体明暗和允许的符号。
- [ ] 墨兰与浅蜜桃同编号使用相同表情与符号位置；浅蜜桃版嘴保持墨兰。
- [ ] 检查动作、器械、身体轮廓、Alpha 外接框和裁切范围未漂移。
- [ ] 生成 2×5 样张总览，分别以 56dp、72dp、96dp 等效尺寸检查可读性。
- [ ] 不通过的单项最多重试 2 次，通过后锁定提示词与表情规则。

### Task 3: 批量完成其余 30 张正式源图

**Files:**
- Modify: 两套 `individual/` 中除代表动作外的 30 张 PNG。

**Interfaces:**
- Consumes: Task 2 锁定的编辑提示和动作表情映射。
- Produces: 两套各 20 张最终 1254px 透明 PNG。

- [ ] 按最多 3 个并行任务分批处理同一语义组，避免跨组复用错误表情。
- [ ] 每完成一批即检查双配色同编号表情一致、器械保留和 Alpha 有效。
- [ ] 对 20 个动作执行逐项肉眼复核，排除多余肢体、错误关节、漂浮器械和背景残留。
- [ ] 对失败单项最多重试 2 次，并在清单中记录实际次数。

### Task 4: 同步 App 副本并重建总览

**Files:**
- Modify: `assets/branding/action-characters/{navy,peach-light}/*.png`
- Modify: `outputs/logos/trainmate-flow/action-set-20/trainmate-flow-action-set-20-overview.png`
- Modify: `outputs/logos/trainmate-flow/action-set-20-peach-light/trainmate-flow-action-set-20-peach-light-overview.png`

**Interfaces:**
- Consumes: 40 张已通过的 1254px 正式图。
- Produces: 40 张 512px App 副本和两张 5×4 总览。

- [ ] 使用 `sips -z 512 512` 从正式源图生成同名运行时副本，保持 Alpha。
- [ ] 按编号从左至右、从上至下确定性排列两张纸白 5×4 总览，不重新设计人物。
- [ ] 验证运行时目录各 20 张、总计 40 张且不存在 `._*` 文件。
- [ ] 确认 `pubspec.yaml` 和 `TrainMateActionAssets.path` 无需修改。

### Task 5: 更新资产说明和自动化验收

**Files:**
- Modify: 两套 `动作资产清单.md`
- Modify: 两套 `验证报告.md`
- Test: `test/core/trainmate_action_character_test.dart`

**Interfaces:**
- Consumes: 最终源图、运行时副本和 SHA 清单。
- Produces: 可追溯报告及不变的 Flutter 资源映射证明。

- [ ] 将“固定圆点眼”更新为“按动作语义分组的眉眼、嘴型与情绪符号”。
- [ ] 报告每项尺寸、Alpha、表情组、符号、覆盖前后 SHA 和重试次数。
- [ ] 运行 `flutter test --no-pub test/core/trainmate_action_character_test.dart test/core/trainflow_visual_system_test.dart test/core/flow_mascot_mapping_test.dart`，预期人物相关测试全部通过。
- [ ] 运行 `flutter analyze --no-pub`，将既有诊断与本次新增诊断分开记录。
- [ ] 运行 `flutter build web --no-pub` 并在 393px 视口检查深色页头与浅色卡片的双配色人物。

