# 信息策展方法论 (Information Curation)

> **本文件用途**: 沉淀"如何从多源信息中提取、加工、合成高质量简报"的方法论。
> **来源**: 2026-06-08 阿轩分享 `mvanhorn/last30days-skill`（GitHub 11K+ stars, Trending #1）触发深度研究；之前 8:00/8:30 cron 也有"反 AI 套话 + 重视角"诉求。
> **应用对象**: 8:00 AI 视频创意日报、8:30 AI 行业速报、taskflow:content-pipeline 选题调研、未来其他"信息摄入 + 加工"任务。
>
> **何时 read 本文件**:
> - 改 8:00/8:30 cron prompt 前
> - 评估"信息源/打分/合成"质量时
> - 用户对 cron 输出质量吐槽时
> - 设计新 cron 或新 skill 涉及"信息摄入"环节时

---

## 核心方法论 8 条

### M1. 互动信号打分 > SEO 排名

**last30days 做法**: 12+ 平台并行扫，按 upvote/like/odds 排序——Reddit 1500 赞 > 没人读的博客；TikTok 360 万播放 > 软文；Polymarket 6.6 万美元盘口 > 专家猜测。

**为什么**: SEO 排名被编辑/算法污染，互动信号来自"人的真实注意力"——更接近"业内怎么看"。

**如何迁移**:
- 8:30 AI 行业速报：搜索时**显式加入 X/Reddit/HN 关键词**（"AI industry site:twitter.com OR site:reddit.com"）
- 排序时**优先采纳带高互动量**的源（点赞/评论/转推数）
- 加权重：30% 权重给"业内真实讨论"（X/Reddit/HN），70% 给"权威媒体"（36氪/量子位/TechCrunch）

---

### M2. 零配置门槛 + 渐进解锁

**last30days 做法**: `metadata.openclaw.requires.env: []`（必需 0 个）。Reddit/HN/Polymarket/GitHub 不用 key 直接跑；其他用 key 在 setup wizard 30s 解锁。

**为什么**: 降低"试一次"的摩擦。必需 key 越多，越没人用。

**如何迁移**:
- 我们 cron **不依赖任何付费 API key**（避免 OP-003 类 preflight 拒绝）
- 8:00/8:30 搜索源优先级：**先用 web_search（零成本）**，再视情况加 X/Reddit 专项搜索
- 避免引入"必须有 X API key 才能跑"的设计

---

### M3. 强格式合同（LAW 1-5+）

**last30days 做法**: 5+ 条格式化 LAWs 写死在 SKILL.md 里，**非协商**：
- LAW 1: 不要 `Sources:` 块
- LAW 2: 不要 invented title line（除 COMPARISON 例外）
- LAW 3: 不要 em-dash / en-dash
- LAW 4: 不要 `##` / `###` section headers（除 COMPARISON 例外）
- LAW 5: 必须 pass-through engine footer

每次有 LLM 跑出"AI 套话"（如"The headline" / "Why he is everywhere" / 各种 ## 段头），就被这条 LAWs 抓回格式。

**为什么**: LLM 默认会"漂到 blog 风格"（v3.0.6 公开 0/8 regression 实证）。硬规则 > 软建议。

**如何迁移**:
- 8:00/8:30 prompt 已经部分有"❌ 不用 AI 套话"——**升级为具体禁词清单**：
  - ❌ 重磅、炸裂、家人们、绝绝子、划重点、一文读懂
  - ❌ `—` `–`（em-dash/en-dash）→ 用 ` - `
  - ❌ `## ` 段头（在 8:30 推送这种 5-8 条结构里不需要）→ 用 emoji 编号 `## 🔥 TOP 1`
  - ❌ "人工智能时代已经到来"等空话开头
- 硬规则 + 例证 = 减少 LLM 漂移（参考 last30days 2026-04-18 教训）

---

### M4. 首行身份锚 (BADGE 强制头)

**last30days 做法**: 每次输出第一行必须是 `🌐 last30days v{VERSION} · synced {YYYY-MM-DD}`，不可省不可改。

**为什么**: 防止 LLM 漂到 blog 风格（`# {Topic}` 标题 / `The headline` 自创标题）。**结构锚**比"建议"有效 10x。

**如何迁移**:
- 8:30 推送已有 `# 🌐 AI 行业速报 | M月D日（周X）` — ✅ 已符合精神
- 8:00 推送已有 `# 🎬 AI 视频创意日报 | M月D日（周X）` — ✅ 已符合精神
- **升级点**：第一行加**结构锚子串**（`已扫 5 平台 · 候选 28 条 · 入选 7 条`），让 LLM/阿轩一眼看到"本次报告的输入规模"
- 强化"第一行不可加任何其他内容"的硬规则

---

### M5. 与工具默认行为主动对抗

**last30days 做法**: WebSearch 工具 description 总是在末尾 push `Sources:` 块。last30days 主动写 LAW 1 supersede 这个行为。

**为什么**: 工具的"标准输出格式"不一定是**任务需要**的格式。如果任务需要简化，工具默认反而是噪音。

**如何迁移**:
- 我们 8:00/8:30 反而**需要** Sources（阿轩要看"这条新闻从哪来"+ 可信度）
- **反面迁移**：不要被"工具默认格式"绑架，但**当工具默认对任务有利时**要保留
- 8:30 prompt 的"每条带来源"是**主动设计**，不是工具默认 — 区分清楚

---

### M6. 去 AI 套话具体化（em-dash / ## header / 列表化）

**last30days 做法**: 把"少用 AI 套话"这个软建议，**具体化到 3 条硬规则**：
- `—` `–` 是 AI 套话最可靠信号 → 强制用 ` - `
- `## ` 段头是 blog 风 → 改用 bold lead-in paragraph + 列表
- 不要 invented title → 用 prose label `What I learned:`

**为什么**: 软建议"别写得像 AI"对 LLM 无效。具体规则有效。

**如何迁移**:
- 8:00/8:30 prompt 升级"❌ 不用 AI 套话"为**具体禁词表**：
  - 见 M3
- 加"参考样本"：给出 1-2 个"好的输出样本"和"差的输出样本"，让 LLM 模仿

---

### M7. Pre-research 状态透明化

**last30days 做法**: 跑前先看哪些 platform 缺 key，跑出 `## Pre-Research Status` 块**显式列出**"扫了 X 平台 / 缺 Y 平台 / fallback Z"。

**为什么**: 透明化"我有什么、没什么"——用户/阿轩能判断"今天报告是不是打了折扣"。

**如何迁移**:
- 8:30/8:00 推送末尾加**简短状态条**：
  ```
  📊 本次扫描：web_search × 5 关键词 / X(无API，部分) / 36氪 + 量子位
  ⚠️ 今日仅 7 条（行业平静日），平时 12-15 条
  ```
- 让阿轩一眼判断"今天是不是收少了/收多了"
- 同时帮未来 debug（如果某天 0 条，可对照状态条看出"是不是 web 挂了"）

---

### M8. 多 query type 分支（不"一套模板吃所有"）

**last30days 做法**: QUERY_TYPE 分 GENERAL / NEWS / PROMPTING / RECOMMENDATIONS / COMPARISON，**每个用不同结构**：
- GENERAL/NEWS/PROMPTING/RECOMMENDATIONS → `What I learned:` + bold lead-in + KEY PATTERNS list
- COMPARISON → `{A} vs {B} [vs {C}]` 标题 + Quick Verdict + 实体段 + Head-to-Head + Bottom Line

**为什么**: 强行用一套格式会牺牲任务特定价值。

**如何迁移**:
- 8:00 视频日报（垂直深度）vs 8:30 行业速报（横向广度）**应该有不同的结构和字数**
- 当前已经分别写——✅ 已符合精神
- **升级点**：每个 cron prompt 加"为什么这个 cron 长这样"的一句话说明（让 LLM 知道 format 不是任意选的）
- 未来如果新增 cron（小红书日报/装备评测日报），**用专门的 prompt template**，不要直接复制 8:00/8:30

---

## 落地路线图

### 第一优先级（最高 ROI）—— 改 8:30 cron prompt

**目标**：从"通用 AI 速报" → "用互动信号打分的 AI 速报"

具体改动（待阿轩拍板再动）：
1. M3 强化：把"不用 AI 套话"升级为**具体禁词清单 + em-dash 规则**
2. M4 升级：推送首行加 `已扫 N 平台 · 候选 X 条 · 入选 Y 条` 结构锚
3. M6 加分：给 1 个"好样本"+ 1 个"差样本"让 LLM 模仿
4. M7 加分：推送末尾加 `📊 扫描状态` 状态条

### 第二优先级 —— 改 8:00 cron prompt

**目标**：8:00 视频日报用 M1（互动信号）+ M8（query type 边界）强化

具体改动：
1. M1 升级：搜索时显式加"X/Reddit/YouTube 视频圈真实讨论"维度
2. M3 强化：跟 8:30 同步，禁词清单统一
3. M6 加分：好样本/差样本（视频日报的样本）

### 第三优先级 —— 沉淀 cron prompt 模板库

**目标**：未来新增 cron 不用从零写

具体动作：
- 把 8:00/8:30 改完的 prompt **抽象成 template** 存到 `~/self-improving/templates/cron-prompt-template.md`
- Template 含：本文件 8 条方法论 + 通用质量约束 + query type 分支

### 第四优先级（可选）—— 引入 last30days 作为研究工具

**当且仅当**：
- 阿轩明确想用 RED（小红书）数据 → 装 last30days + 配 SCRAPECREATORS_API_KEY
- 8:00/8:30 prompt 跑 2 周后质量仍不达标 → 考虑用 last30days 作为"搜索引擎层"
- 提醒：**不要**直接装到 OpenClaw skill 库——会覆盖现有 8:30 格式（LAW 1-5 太严格）

---

## 自检（每次新 cron 设计前问自己 4 个问题）

1. **互动信号覆盖了吗？** (M1) — 能不能搜 X/Reddit/HN 真实讨论，而不是只靠 36氪？
2. **零配置吗？** (M2) — 有没有强制要求 API key 才能跑？
3. **禁词清单具体吗？** (M3+M6) — "不用 AI 套话"是软建议还是具体清单？
4. **格式有结构锚吗？** (M4+M7) — 第一行是不是身份锚？末尾有没有状态条？

---

## 未来 read 时关注

- last30days 后续 v3.4+ 是否有新方法论可学（关注 GitHub releases）
- 8:00/8:30 改完后的实际输出质量（阿轩满意度 + 互动量）
- 是否需要新增"小红书/RED 平台专项"方法论（如果装 last30days 后）
- LLM 模型升级（M3 → M4？）后，LAW 1-5 是否还需要这么严

---

_最后更新: 2026-06-08_
_来源: last30days v3.3.2 SKILL.md + README + 14K 字符研究_

---

#### [OP-2026-06-22] NORMAL_RUN | AI视频创意日报 v3 第二次推送（手动 @ 2026-06-22 08:03）
- 触发: cron 正常触发
- 工具: anysearch batch_search × 4 关键词 + social_media Reddit 补扫 1 次，全部成功
- 入选: 5 条（工具 1 + 横评 1 + 案例 2 + 小红书 1）
- 头条: 小红书 RED 精选计划 —— 阿轩 1353 粉账号卡在最大红利窗口
- 互动信号: Reddit r/SoraAi 实测贴有效补充 Sora 2 Cameo 时效性证据
- 观察: 行业平静日，无重大模型发布；anysearch extract 在新华网失败（all proxies exhausted），但搜索摘要已够用
- 改进点: extract 失败时回退到 web_fetch 拿全文，下次 cron 加 fallback 链
- 状态: ✅ 已推送
