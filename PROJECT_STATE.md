# 练搭 CoachMate — 项目状态快照（Agent 交接用）

> **生成时间**：2026-08-15 21:00（本地）
> **生成方式**：实际执行 `flutter analyze` / `flutter test` / `pytest` / `git status` 后写入，非抄录文档。
> **失效条件**：一旦有新提交、`lib/core/theme/trainflow_tokens.dart` 被改动、或工作树被提交/清理，本文件的"实测基线"与"进行中改动"两节即失效，需重跑第 2 节命令。
> **阅读约定**：标注 `[事实]` 的内容有可复现命令或 file:line 证据；标注 `[判断]` 的是产品/工程建议，未经用户确认，不要当作已定结论执行。

---

## 1. 这是什么项目

`[事实]` 本地优先的个性化训练应用，定位是"长期陪伴的 AI Coach agent / 运动搭子"，不是课表型健身 App。

- 用户可见品牌：**练搭 CoachMate**（短名 `练搭`，英文 `CoachMate`，口号 `练，有人陪。`）
- 技术栈：Flutter 3.44.5 / Dart 3.12.2 客户端（iOS / Android / Web）+ FastAPI 后端 + PostgreSQL / Redis / Alembic + Vite 运营后台（`ops-web/`）
- 仓库根：`/Volumes/AI homeSSD/TrainMate/zhuque-flutter-main`（**注意：外置卷，见第 8 节**）

### 命名三层（不要"统一"它们）

| 层 | 取值 | 是否可改 |
|---|---|---|
| 用户可见品牌 | 练搭 CoachMate | 已切换完成 |
| 项目文档 / 历史计划 | 智练 TrainMate、TrainFlow AI | 文档未跟上，可更新 |
| 技术身份 | Dart package `trainflow_ai`、Bundle/appId `com.zhilian.trainmate`、DB 表名、`TrainMate*` 内部类型、`TRAINMATE_*` 环境变量 | **有意保留，禁止批量替换**（见 `docs/superpowers/specs/2026-08-14-coachmate-brand-rename-design.md`） |

---

## 2. 实测基线（2026-08-15）

| 检查项 | 结果 | 复现命令 |
|---|---|---|
| Flutter 静态分析 | **0 问题** | `flutter analyze --no-pub` |
| Flutter 测试 | **952 通过 / 17 失败**（共 969） | `bash scripts/run_flutter_tests_clean_copy.sh` |
| 后端测试 | **257 通过**，1 条第三方弃用警告 | `cd backend && ./.venv/bin/python -m pytest` |
| iOS 真机 / 签名 / TestFlight | **未验证** | — |
| Android 正式签名 | **未验证**，本机无 Android SDK | — |
| SMTP / 短信 / DeepSeek / MiniMax / 生产 PG+Redis | **未联调** | — |

`[事实]` **17 个失败全部同源**：视觉主色令牌冲突（见第 5.1 节）。2 个令牌契约测试 + 15 个 golden 基线，无业务逻辑失败。

<details>
<summary>17 个失败用例清单</summary>

```
test/core/trainflow_visual_system_test.dart: Indore 主标签视觉令牌锁定深浅主题、青柠强调与紧凑布局
test/core/trainflow_visual_system_test.dart: 全页面视觉令牌使用分层圆角与固定间距
test/navigation_test.dart: 导航使用 70% 白色玻璃胶囊、暖黑圆盘与青柠选中态
test/goldens/trainmate_bottom_navigation_golden_test.dart: 单圆槽连续滑行 160ms 的视觉基线
test/goldens/trainmate_bottom_navigation_golden_test.dart: 完整选中状态视觉基线
test/goldens/trainmate_visual_families_golden_test.dart: 01-today / 02-plans / 03-pet / 04-ai / 05-exercises
                                                       / 06-profile / 07-login / 08-onboarding / 09-form
                                                       / 10-detail / 11-report / 12-player  视觉基线（共 12 项）
```
</details>

### 已过期的文档口径（**不要照着执行**）

`docs/智练TrainMate_项目计划书_V1.1_20260815.md` 与 `docs/plans/2026-08-10-trainmate-v1.1-change-log.md` 中：

- "818 通过 / 9 失败" → 实际 952 / 17
- "后端 168 通过" → 实际 257
- "analyze 1 条信息级问题" → 实际 0
- "M0 九个失败用例决策网格"点名的 3 项（路由矩阵 44≠46、动作媒体视频回退、动作库生成图片缺失）**已实测全绿**，该网格整体作废
- "6 个主导航入口 / 46 路由 / 33 页面 / 189+25 测试文件" → 实际 **5 / 45 / 40+ / 206+27**

---

## 3. 仓库与分支状态

`[事实]`

- 当前分支：`codex/trainmate-ios-beta-readiness`
- HEAD：`c50c819 docs: 完善上架全套交付物（法务/元数据/签名/验收）`
- 其他分支：`main`、`codex/phase4-body-metrics`（均有 origin 对应）
- **工作树有 186 条未提交变更**（148 个已跟踪文件改动 + 38 项未跟踪），其中包含发布配置：`ios/Runner/Info.plist`、`ios/Runner.xcodeproj/project.pbxproj`、`android/app/src/main/AndroidManifest.xml`、`ios/StoreKit/TrainMate.storekit`、`web/index.html`、`web/manifest.json`

---

## 4. 进行中的两条未提交改动（关键上下文）

### 4.1 品牌改名：TrainMate → 练搭 CoachMate（基本完成）

- 设计文档：`docs/superpowers/specs/2026-08-14-coachmate-brand-rename-design.md`
- 实施文档：`docs/superpowers/plans/2026-08-14-coachmate-brand-rename-implementation.md`
- 集中常量：`lib/core/constants/app_brand.dart`（`displayName` / `shortName` / `englishName` / `tagline`）
- 契约测试：`test/core/app_brand_contract_test.dart`
- 已改：Flutter 文案、本地通知标题、后端验证码邮件、iOS `CFBundleDisplayName`、Android launcher 名、Web 标题与 manifest、StoreKit 展示名
- 未改（有意）：Bundle ID、applicationId、Dart 包名、数据库表、HealthKit 目录、环境变量
- 新增资产（未跟踪）：`assets/branding/coachmate-official-logo-v1/`、`assets/branding/mate-feast-bag-v2/`、三端图标、`scripts/generate_coachmate_*.py`

> 该设计文档自己写了"交付边界：本次只提交品牌切换所需内容，工作区其他改动不应混入"——**当前实际已混入 4.2 的视觉改动，提交前需拆分**。

### 4.2 视觉体系换色（进行中，是当前唯一红灯来源）

见第 5.1 节。

---

## 5. 已知不一致清单

### 5.1 `[事实|P0]` 主强调色三方冲突 → 17 个测试失败

| 来源 | 取值 | 时间戳 |
|---|---|---|
| 规范文档 `docs/design/trainmate_主标签_Indore_视觉规范.md` | `accent = #E0FF64`，底色 `#181814` | 08-15 19:49 |
| 令牌测试 `test/core/trainflow_visual_system_test.dart:23` | 断言 `#E0FF64` | 08-15 06:37 |
| **代码 `lib/core/theme/trainflow_tokens.dart:11`** | **`accent = #D4FF00`**，底色 `#0A1408`，注释写"CycleGo 方案包主色" | **08-15 20:43** |

代码取自仓库外的 `../# 🚴 CycleGo 健身应用 — 可执行设计方案包.md`（深绿黑 + 荧光黄绿方案），规范文档与 golden 基线均未同步。

**这是一个未定的设计决策直接进了主干，不是 bug。** 修复前必须先由用户拍板主色，然后一次性同步：令牌代码 → 规范文档 → 令牌测试 → `flutter test --update-goldens`。

### 5.2 `[事实|P1]` V1.1 治理流程整体空转

`docs/智练TrainMate_项目计划书_V1.1_20260815.md` §1.5 规定"本轮不修改业务代码、发布配置"，§3.3 规定"不执行 M1～M5 工程改动"，D5（=今天 8/15）为冻结日。实际：

- `docs/plans/2026-08-13-trainmate-po-decisions-v1.1.md`：六项决策**全部"未决"**，决策人全是"D3 填写"
- `docs/plans/2026-08-10-trainmate-external-dependencies-v1.1.md`：五项外部依赖**全部"未确认"**
- 角色矩阵六个岗位全是"D0 必填"
- 同时工作树有 186 条改动，含发布配置

→ D5 五项定稿门禁不可能通过。**该计划书目前不是有效执行基线，需用户决定是重写还是废弃。**

### 5.3 `[事实|P1]` README 与代码脱节

`README.md` 标题仍为 "TrainFlow AI"，"项目结构"章节列约 20 个 feature；实际 `lib/features/` 有 **33 个**，缺记：`pet`、`companion`、`cloud_sync`、`first_run_onboarding`、`auth`、`guided_workout`、`growth`、`rhythm`、`data_rights`、`pilot_validation`、`training_log`。

### 5.4 `[事实|P2]` 商业化口径待定

- `ios/StoreKit/TrainMate.storekit`：仅 **月度 ¥19.9 + 1 周免费试用**，`productID = com.zhilian.trainmate.membership.monthly`，**无年订阅**
- 首启动流程含 `/welcome/membership`（`lib/features/first_run_onboarding/`）
- 但 PO 决策 #3 的预置默认是"内测排除订阅、云同步、付费门禁"

→ 订阅是否进内测未定，直接影响 first-run 流程是否要改。

### 5.5 `[事实|P2]` 仓库卫生

`test/goldens/failures/` 下 **52 个失败对比图被 git 跟踪**，`.gitignore` 无对应规则。每次视觉改动都会产生大量二进制 diff（本次 148 个改动文件中占比很高）。

---

## 6. 代码结构地图

```
lib/
├── app/{router,navigation,startup}      # 45 个路由常量 / 53 个 GoRoute / 5 个底部 tab
├── core/{theme,widgets,constants,config}
├── data/{models,repositories,seed,local}
├── services/                            # 本地规则引擎与领域服务
└── features/                            # 33 个功能目录，377 个 dart 文件
backend/app/{api,services,models,jobs,ai_skills}
ops-web/                                 # 运营后台
test/                                    # 206 个测试文件
```

### 底部导航（5 个，`lib/app/navigation/main_shell.dart:10`）

`运动搭子(/companion)` · `训练计划(/plans)` · `今日训练(/dashboard)` · `动作库(/exercises)` · `我的(/profile)`

### 核心闭环对应的模块（改动时优先看这几处）

| 环节 | 模块 |
|---|---|
| 每日状态采集 | `features/daily_check_in` + `services/daily_check_in_service.dart` |
| 动态调整决策（正常/降级/恢复/技术/休息） | `features/daily_adjustment` + `services/daily_adjustment_service.dart` |
| 安全兜底规则引擎 | `services/training_rule_audit_service.dart` |
| 跟练执行 | `features/workout_player` |
| 长期记忆 / 关系 | `features/companion/`（`coach_memory`、`companion_arbitrator`） |
| 用户画像与信任回顾 | `features/user_insights` + `services/user_insight_service.dart`、`user_trust_review_service.dart` |
| 疼痛红线（≥7 或持续 2 周 → 休息/就医） | `features/rehab` + `data/repositories/pain_log_repository.dart` |
| 宠物养成 | `features/pet/`（6 物种 / 蛋→冠军 5 阶段 / 心情系统） |

### 领域术语

`CONTEXT.md` 是领域词汇表（打工人分型、作息类型、器械条件、学习信号、训练-动作关联等），改业务前先读。

---

## 7. 待用户决策的阻塞项

| # | 决策 | 阻塞什么 | 现状 |
|---|---|---|---|
| D1 | 主强调色定 `#D4FF00` 还是 `#E0FF64` | 17 个失败测试、能否出候选版本 | **未定** |
| D2 | V1.1 计划书重写还是废弃 | 所有里程碑口径 | **未定** |
| D3 | 订阅是否进内测（PO #3） | first-run 流程、StoreKit 是否补年订阅 | **未定** |
| D4 | 186 条改动如何拆提交 | 提交历史可读性 | **未定** |

---

## 8. 操作红线（务必遵守）

1. **禁止 `git reset --hard`、`git clean -fd` 或任何覆盖式回退。** 工作树包含 2026-08-01 灾后恢复的大量未提交增量，见 `../恢复说明.md`。
2. **测试用 `scripts/run_flutter_tests_clean_copy.sh`**，不要直接在工作区跑全量 `flutter test`。外置卷会生成 AppleDouble 文件导致解析失败；该脚本会复制到 `/private/tmp` 干净目录离线执行，不修改原工作区。（单文件 `flutter test --no-pub <path>` 可以直接跑。）
3. **不要为了让测试通过而删除用例或弱化断言**（计划书 §8.1 明文约束）。
4. **不要批量替换 `TrainMate` 字符串**——技术身份层必须保留，见第 1 节表格。
5. **不创建 `backend/.env`、不写入任何密钥**。真实 SMTP / 短信 / DeepSeek / MiniMax 联调依赖被 gitignore 的 `.env`。
6. **不得把 Mock、模拟器构建或测试通过表述为真机、签名或线上验收通过。**
7. **未经用户明确授权不执行 git commit / push。**

---

## 9. `[判断]` 建议的处理顺序（未经用户确认）

1. 用户拍板主色 → 一处改完并同步文档/测试/golden，把 17 个失败清零（唯一红灯）
2. 把 186 条改动拆成"品牌改名 / 视觉体系 / 其余"三个提交；顺手给 `test/goldens/failures/` 加 gitignore
3. 更新 README 与计划书基线数字，作废过期的 M0 失败网格
4. 补 PO 决策 #1/#2/#3
5. 再讨论产品层：宠物养成与"有记忆的教练人格"的主线冲突（`## 总体判断：定位成立.md` 第 5 节明确反对宠物式陪伴，但 `features/pet` 已是完整养成系统）；以及北极星指标"有效陪伴训练周数"目前**代码中无任何实现**，可由 `daily_adjustment` 决策记录 ∩ `workout_logs` 完成记录本地算出

---

## 10. 相关文档索引

| 文件 | 用途 | 时效 |
|---|---|---|
| `CONTEXT.md` | 领域词汇表 | 有效 |
| `README.md` | 功能总览 | **部分过期**（见 5.3） |
| `docs/智练TrainMate_项目计划书_V1.1_20260815.md` | 项目计划 | **数字过期、流程空转**（见 5.2） |
| `docs/plans/2026-08-10-trainmate-v1.1-change-log.md` | 变更记录 + M0 失败网格 | **网格作废** |
| `docs/plans/2026-08-13-trainmate-po-decisions-v1.1.md` | PO 决策 | 空模板 |
| `docs/design/trainmate_主标签_Indore_视觉规范.md` | 视觉规范 | **与代码冲突**（见 5.1） |
| `docs/superpowers/specs/2026-08-14-coachmate-brand-rename-design.md` | 品牌改名设计 | 有效 |
| `docs/architecture/ADR-000{1,2,3,4}*.md` | 架构决策 | 有效 |
| `14天自用验收清单.md` | Gate A 自用验收 | 有效，**尚未开始真实 14 天使用** |
| `../## 总体判断：定位成立.md` | 产品定位与 MVP 建议（PM 视角） | 参考 |
| `../# 🚴 CycleGo 健身应用 — 可执行设计方案包.md` | 外部视觉方案包，5.1 换色的来源 | 参考 |
| `../恢复说明.md` | 2026-08-01 灾后恢复记录 | 有效，含操作红线 |
