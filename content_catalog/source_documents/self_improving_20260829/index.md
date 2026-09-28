# Memory Index

> Auto-maintained by heartbeat. Last refresh: 2026-08-15 03:01 PDT

| File | Lines | Last Updated |
|------|-------|--------------|
| memory.md | 33 | 2026-08-12 (+R16/R17) |
| corrections.md | 10 | 2026-06-12 |
| heartbeat-state.md | 459 | 2026-08-15 |
| domains/agent-ops.md | 1699 | 2026-08-13 (+OP-097 INDEX_WINDOW_MISMATCH) |
| domains/agent-auto-review.md | 117 | 2026-06-12 |
| domains/cron-config.md | 15 | 2026-06-04 |
| domains/information-curation.md | 211 | 2026-06-22 |
| eval/ai-news-speed-report.md | 149 | - |
| templates/cron-prompt-template.md | 129 | - |

## 快速 Query 关键字

| 问什么 | 看哪里 |
|---|---|
| cron 失败 / 推送问题 / OP-XXX 失败记录 | domains/agent-ops.md |
| 自检 / 反馈循环 / 旋钮式自主性 | domains/agent-auto-review.md |
| AI 速报方法论 / 禁词 | domains/information-curation.md |
| 推送用户偏好 / 配置 cron / R1-R15 规则 | memory.md |
| 失败纠正历史 | corrections.md |
| cron prompt 模板 | templates/cron-prompt-template.md |

## ⚠️ 紧急关注（2026-08-15 更新）

- **W32 channel P0 + OP-077 v3 双轨 + prompt CASS 升级 三件大事已全部进入观察期** — OP-079/081/082/083/085/086/087/088 闭环 ✅, OP-094/095 announce mode 稳定 4d+ ✅, OP-091/092/096 CASS 双轨信源首日命中 ✅, OP-093 新 cron 9/1 自然 run 验证。
- **OP-097 INDEX_WINDOW_MISMATCH (8/13 18:15 PDT, 间隔 14d 较 OP-058 拉长)**: 同模式累计 16 次 (OP-010/024/026/028/029/030/034/035/038/041/046/047/049/052/058/097), 按 W26 阈值 ≥5 次才 🚨 单点不升级。修法/预防字段空缺 — auto-OP 历史模式, 不补。
- **agent-ops.md 1699 lines / 180KB 持续增长**: 历史 OP 条目累计, 尚未 compact (heartbeat 保守不动, follow-up 建议: 顶部加 OP 编号索引 + 把过期 OP 折叠到 `archive/OP-XXX-YYYY.md`)。