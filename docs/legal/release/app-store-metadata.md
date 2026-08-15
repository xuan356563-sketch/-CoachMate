# 练搭 CoachMate App Store 上架元数据（中英对照）

> 版本：1.0（待上线）
> 用途：App Store Connect / Google Play Console 的元数据填表参考
> 注意：以下为建议文案，最终以 App 实际功能与审核反馈为准。

---

## 一、应用基本信息

| 项目 | 中文 | English |
| --- | --- | --- |
| App 名称 | 练搭 CoachMate | CoachMate |
| 名称长度 | 6+9 = 15 字符（iOS 上限 30，通过） | 10 字符（通过） |
| 副标题 | 练，有人陪 | Train with a partner |
| 品类 | 健康健美 / 体育（Health & Fitness / Sports） | Health & Fitness |
| 价格 | 免费（含内购订阅） | Free (with IAP) |

## 二、描述（中文）

> 目标：≤4000 字符。突出"本地优先 + AI 陪伴 + 安全"。

**练搭 CoachMate —— 练，有人陪。**

一款长期陪伴的 AI 运动搭子，不只是课表。CoachMate 懂你的身体状态——疼痛、疲劳、恢复——并陪你一起坚持。

**为什么选择练搭？**

- 🧭 **先判断再练**：每日晨间报告、恢复倒计时、训练负荷曲线（CTL/ATL/TSB），先回答"今天该不该练、怎么练"。
- 🧑‍🏫 **AI 教练陪你练**：AI Trainer 解答训练问题、AI Motion 检查动作质量、AI Recovery 给出恢复建议。所有 AI 建议待你确认后才会生效，安全规则永远优先。
- 📋 **个性化训练计划**：五步流程跟练播放器（泡沫轴放松 → 动态拉伸 → 激活 → 正式训练 → 放松），支持真实倒计时、语音提示、太累了一键降级。
- 📊 **本地优先，数据是你的**：身体数据、训练记录默认只存在你的设备上，不卖数据、不做广告定向。支持数据导出与账号删除。
- 🏆 **坚持看得见**：30 天渐进引导、连击、成就徽章、自动周报，把坚持变成可见的回报。
- 📚 **每个建议都可追溯**：训练计划、动作、照吃卡都关联书籍与知识来源，不让你盲从。

**更多功能**：动作库（180+ 动作）、比赛备战周期反推、康复与疼痛记录、GPX 训练导入、照吃指令卡、身体数据 10 秒快录与趋势分析。

**免责声明**：本 App 为训练辅助工具，不构成医疗建议。训练前请评估自身状况，必要时咨询专业人士。

## 三、描述（English）

> Target: ≤4000 characters.

**CoachMate — Train with a partner.**

A long-term AI training companion, not just a workout calendar. CoachMate understands your body — pain, fatigue, recovery — and stays with you.

**Why CoachMate?**

- 🧭 **Decide before you train**: morning report, recovery countdown, training load curves (CTL/ATL/TSB) answer "should I train today, and how?"
- 🧑‍🏫 **An AI coach that stays**: AI Trainer answers training questions, AI Motion checks form, AI Recovery suggests recovery. All AI suggestions require your confirmation; safety rules always come first.
- 📋 **Personalized plans**: guided 5-step workout player (foam roll → dynamic stretch → activation → main set → cool down) with real countdowns, voice prompts, and one-tap de-escalation.
- 📊 **Local-first, your data is yours**: body metrics and workout logs stay on your device by default. No data selling, no ad targeting. Export and account deletion supported.
- 🏆 **Progress you can see**: 30-day starter program, streaks, achievement badges, automatic weekly reports.
- 📚 **Every suggestion is traceable**: plans, exercises, and meal cards cite book sources — no blind obedience.

**More**: 180+ exercise library, race prep periodization, pain & rehab logs, GPX import, meal instruction cards, 10-second body metric logging with trends.

**Disclaimer**: This app is a training aid, not medical advice. Assess your condition before training and consult a professional when needed.

## 四、关键词（Keyword，≤100 字符）

> iOS 只支持英文关键词。建议（约 70 字符）：

`fitness, workout, trainer, coach, running, gym, exercise, health, plan, AI, train, partner, recovery, habit, strength`

> 注：不要包含其他 App 名称、商标词或误导性词汇。

## 五、截图计划

> 要求：iPhone 6.7"（1290×2796）与 6.5"（1242×2688）各至少 2-3 张；App 内购买项目需有 1 张 IAP 截图（如需）。

建议 6 张截图（每张配一句文案，中英各一套）：

| # | 截图内容 | 中文文案 | English Caption |
| --- | --- | --- | --- |
| 1 | 今日训练页（五步流程 + 恢复倒计时） | 先判断再练：今天该练什么，一目了然 | Decide before you train |
| 2 | 跟练播放器（倒计时 + 步骤） | 有人陪你把每一步做完 | Guided step by step |
| 3 | AI 教练对话（待确认卡片） | AI 建议，你说了算 | AI advice, you decide |
| 4 | 训练计划 + 动作库 | 180+ 动作，计划可追溯 | Plans with traceable sources |
| 5 | 身体数据趋势（7/30/90 日） | 数据都在你手里 | Your data stays yours |
| 6 | 周报 + 成就徽章 | 坚持看得见 | See your progress |

> 建议：从 `test/goldens/baselines/` 复用页面渲染作为底稿，再补真实数据与真实设备截图；审核员会检查截图是否与 App 实际功能一致。

## 六、App 内购买项目（IAP / 订阅）

| 项目 | 值 |
| --- | --- |
| 产品 ID | `com.zhilian.trainmate.membership.monthly` |
| 显示名称（中文） | 练搭会员（月度） |
| 显示名称（英文） | CoachMate Membership (Monthly) |
| 类型 | 自动续期订阅（Auto-Renewable Subscription） |
| 价格 | 待定（建议 ¥18-30/月，按市场调研定） |
| 试用 | 建议提供 3 天或 7 天免费试用（App Store 要求试用期时长需明示） |
| 本地化 | 需在 App Store Connect 为所有上架地区配置订阅显示名称与描述 |

> 注：是否上线订阅由 PO 决策 #3 决定（V1.1 计划默认"排除订阅"）。若本轮不上订阅，则忽略本节，并在 App 内移除/隐藏会员入口，避免审核 2.1 与 3.1.1 违规。

## 七、地区与语言

| 项目 | 值 |
| --- | --- |
| 首发地区 | 中国大陆为主（需 ICP 备案）；可同时上架港澳台及海外 |
| 语言 | 简体中文（必）、English（建议） |
| 时区 | Asia/Shanghai |

## 八、App 图标与预览

| 项目 | 要求 |
| --- | --- |
| 图标 | 1024×1024 PNG，无圆角（系统自动裁剪）、无透明通道 |
| 预览视频 | 可选（App Preview，15-30 秒），建议后续制作 |

---

*本文件最后更新：[日期]*
