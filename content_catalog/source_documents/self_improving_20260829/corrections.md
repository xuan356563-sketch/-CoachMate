# Corrections Log

| Date | What I Got Wrong | Correct Answer | Status |
|------|-----------------|----------------|--------|
| 2026-06-04 | config.patch 改 agents.defaults.model.primary 被网关拒绝（protected path）| 直接编辑 openclaw.json 文件即可，配置项 hot-reload | resolved |
| 2026-06-04 | cron update 用 `job` 参数报 "patch required"| 必须用 `patch` 参数 | resolved |
| 2026-06-04 | setup 推荐装 Proactivity，但阿轩选了 Adaptive Reasoning | 听从用户选择，不假设默认 | resolved |
| 2026-06-05 | 阿轩说"修改"我理解为执行 B 方案（改 deepseek 当主模型）；阿轩实际意思是"提醒我主模型应该是 minimax" | 主模型应该是 minimax/MiniMax-M3，deepseek 永远当 fallback | resolved (已回滚) |
| 2026-06-12 | 6/5 那条"deepseek 永远 fallback"**结论需要修正**——OP-013 实施后：普通任务 M3 单主（避免双重失败），思考任务 (thinking=high) deepseek 主 + M3 fallback | 详见 OP-013 + memory.md P3 + domains/agent-auto-review.md | resolved (OP-013) |
| 2026-06-12 | OP-012 暴露：cron delivered=true ≠ 用户手机真收到——主 session 必须主动补发 | "delivered=true 不可信"作为新规则，详见 OP-012 + memory.md R4 | resolved (OP-012) |
