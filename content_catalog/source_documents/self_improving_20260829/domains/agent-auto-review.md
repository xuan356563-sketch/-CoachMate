# Agent Auto-Review（操作前自检机制 v2）

> 受 Cursor "Auto-review 分类器"启发（2026-06-12 阅读）
> 原文：https://cursor.com/cn/blog/agent-autonomy-auto-review
> 关联 OP：OP-012（delivered=true ≠ 用户收到）、OP-013（模型策略 pivot）
> 关联 SKILL：self-improving 1.2.16（不修改其 SKILL.md，仅沉淀补充规则）

---

## 核心理念：旋钮式自主性

agent 自主性不是开关（要么全自由要么全问），是**旋钮**（按风险连续调节）。

| 风险档 | 例子 | 动作 |
|---|---|---|
| **低** | 读文件、查 cron 状态、查 memory | 自由走（无自检） |
| **中** | 写 memory、写 domain 沉淀、改 cron 配置 | 操作前评估"是否符合用户意图" |
| **高** | 删数据、发外部消息、改 protected config、发外部 push | 暂停，反馈给主 session 或问阿轩 |

---

## 关键改造 1：反馈循环（不是弹窗）

**旧模式**：发现失败 → 发"⚠️ 失败"通知给阿轩 → 等指示
**新模式**：发现失败 → 反馈给主 session → 主 session 主动补救

**为什么不是弹窗**：
- 批准疲劳 = 反复提示后用户不再认真读，批准流程失去意义
- 主 session（糕小胖）有完整 context 主动补救，不必打扰阿轩

**应用案例**：
- OP-012：8:00 视频日报 delivered=true 但阿轩没收到 → 主 session 主动补发
- OP-013：M3 卡死时不让 deepseek 自动救场（避免双重失败）→ 阿轩拍板模型策略

**反馈路径速查**：

| 拦截类型 | 反馈给 |
|---|---|
| delivered=true 但用户没收到 | 主 session → 主动补发 |
| M3 早高峰卡死 + deepseek 也卡死 | 沉淀 OP-NEW，触发模型策略 pivot |
| 用户决策变更 | 沉淀 OP-NEW，更新 memory.md |
| cron 任务连续失败 ≥3 | cron-health-check 升级通知 |

---

## 关键改造 2：意外发现"低推理不一定更快"

Cursor 发现：低推理模型在难判断时反而更慢更差（因为反复搜索/试错）。
**糕小胖的同类洞察**：
- cron-health-check 跑得通的关键不是"低推理"，而是"少 token 占用"（OP-009 修法）
- 判断类任务需要"小 + 够推理"，不是"低推理"

**新规则：thinking 参数选择**：

| 任务类型 | thinking | 模型 | 例 |
|---|---|---|---|
| 简单统计（OK/ERROR 计数） | off | M3 | cron-health-check |
| 模板生成（速报/日报） | medium | M3 | 8:00/8:30 cron |
| 难判断（"是否符合用户意图"） | low/medium | M3 | 沉淀 OP / 改 cron 配置 |
| 复杂推理（自我进化/内容流水线） | high | **deepseek 主 + M3 fallback** | loop / content-pipeline |

---

## 关键改造 3：评估集迭代

旧 lessons 不一定永远对。策略变化时**重新评估**已有规则（自我纠正，防腐化）。

**应当 demote 的 lessons**（2026-06-12 更新）：
- ❌ "M3 + deepseek fallback" → OP-013 改为"普通任务 M3 单主 + 思考任务 deepseek 主"
- ❌ "delivered=true = 推送成功" → OP-012 改为"delivered=true 需主 session 主动验证"

**promote 候选**（待 3x 验证后升级到 memory.md）：
- 旋钮式自主性（3 档风险）— 已用 1 次（OP-012/013），等明早验证
- 反馈循环 ≠ 弹窗 — 已用 1 次，等重复
- 自检类任务要"小 + 够推理" — 已沉淀（OP-009），等 3x

---

## 关键改造 4：拦截率指标

跟踪"打扰率"作为自检质量指标（Cursor 基准：4% 操作拦截 / 7% 对话打断）。

| 类别 | 目标 | 当前 |
|---|---|---|
| 低风险操作拦截率 | 0% | 待统计 |
| 中风险操作自检率 | 100% | 待统计 |
| 高风险操作反馈率 | 100% | OP-012 100% ✅ |
| cron 推送打扰率 | < 10% | OP-013 后可观察 |

**核心 KPI**：高风险反馈率必须 100%，低风险拦截率必须 0%。

---

## 应用 SOP（每次操作前）

```
1. 当前操作属于哪一档风险？（查上表）
2. 如果中/高风险：用 HOT memory.md 自检——"这是阿轩想让我做的吗？"
3. 如果发现风险（不一定是错误）：反馈给主 session 让它补救
4. 不弹窗问阿轩（除非真正不可逆：删数据 / 发外部 push）
```

---

## 关联文件

- `~/self-improving/memory.md` R3/R4：旋钮式自主性 + delivered=true 不可信
- `~/self-improving/corrections.md` 6/12 两条：修正 6/5 结论 + OP-012 新规则
- `~/self-improving/domains/agent-ops.md` OP-012/013/014
- `~/self-improving/index.md`：可查询

## 关联 OP

- OP-012 DELIVERY_MISMATCH
- OP-013 MODEL_STRATEGY_PIVOT
- OP-014 AUTO_REVIEW_INSPIRED（本文件）
- (未来) OP-NEW：自检机制本身失败案例
