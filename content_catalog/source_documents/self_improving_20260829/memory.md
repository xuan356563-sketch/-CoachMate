# Memory (HOT Tier)

## Preferences

- (P1) 阿轩用萨洛蒙越野鞋尺码 44，比日常 43 大半码（标准越野跑选择）

## Patterns

- (P2) 定时任务 (cron) 改动配置时，记住 cron 准时触发——如果 9:00 触发，改完配置已经晚于 9:00，next run 才能生效
- (P3) **修正**（2026-06-12 OP-013）：推送类任务**主模型 M3 单主**（移除 deepseek fallback 避免双重失败）；**思考类任务** (thinking=high) 用 **deepseek 主 + M3 fallback**

## Rules

- (R1) 用户讲中文时，全程中文回复
- (R2) cron 提醒类任务优先用 isolated session + announce delivery（main session 不支持 deliver-by-channel）
- (R3) **新增**（2026-06-12 借鉴 Cursor Auto-review）：agent 自主性按**风险档**调节——低风险自由走、中风险自检、高风险反馈给主 session（不是弹窗）。详见 `domains/agent-auto-review.md`
- (R4) **新增**（2026-06-12 OP-012）：cron delivered=true 不可信，主 session 主动补发是默认动作
- (R5) **新增**（2026-06-21 W25）：M3 早高峰 8:00 窗口六连 fail（OP-002/007/009/011/012/022），pivot 单主+错峰仍未根治。治本需错峰 7:30 或仅 8:00 窗口加 deepseek fallback
- (R6) **新增**（2026-06-21 W25）：Shell heredoc 多行中文被吞 → cron message 先写文件再 `--message "$(cat file)"` 传入（OP-019）
- (R7) **新增**（2026-06-21 W25）：阿轩叫停的工具立即搁置，不纠缠、不催促、标记状态等他再提（Agent-Reach 模式）
- (R8) **新增**（2026-07-05 W27）：外置项目接入前必须先 `lsof -i :PORT` + 读实际运行代码双向核对，不能拍脑袋认 MEMORY 或 unzip 接管（OP-032 教训）
- (R9) **新增**（2026-07-05 W27）：cron 失败不能只看 delivered true/false，必须读 run history 里实际 CMD 长什么样。OP-031/032 "transient 网络波动"定性是错的（OP-033 教训）
- (R10) **新增**（2026-07-05 W27）：拖欠任务（memory_search 修复）超过 2 周就算严重失职，必须在下次自进化前完成
- (R11) **新增**（2026-07-29 W30）：收到部署/版本文件时，先 `find` + `diff -rq` 勘察 workspace 实际状态再判断，**不能凭 zip 解压结果脑补部署状态**——workspace 可能已经部署过，zip 只是漏拷的副本。教训：v1.1 zip 我脱口说「workspace 没有 pages」，实际 14 文件早已齐全，是错的

- (R12) **新增**（2026-07-31 W30）：以后任何 DeepSeek 模型调用，默认用 **Flash** 版本（deepseek-v4-flash / deepseek/deepseek-v4-flash），不用 Pro。原因：V4-Flash 2026/7/31 正式版上线公测，Agent 能力已超 V4-Pro-Preview，且成本/速度更优。覆盖范围：(P3) 中"deepseek 主 + M3 fallback"未指定 deepseek 版本的部分，默认按 Flash 处理；未来任何 cron / fallback / 直调 deepseek 时都按这条走。
- (R13) **新增**（2026-08-07 W31）：P0 类问题（cron delivery / 投递可靠性 / P0 健康监测）同类复发 ≥3 次 = 自动进入「自主修复」通道，不再等用户拍板，直接动手设计 v3 架构。教训：OP-012 P0 从 7/3 拖延到 8/7 = 16 天 / 6 次复发 = 不可接受的失职（详见 OP-077）
- (R14) **新增**（2026-08-07 W31）：weekly self-improvement 必须强制 review OP 编号表，凡 `修法: <待主 session LLM 补>` / `预防: <待主 session LLM 补>` 空缺字段 = 当周失职，必须当周补完。教训：W31 OP-074/075 修法字段空缺直到 W31 周报才补（详见 OP-077）
- (R15) **新增**（2026-08-07 W31）：故障链路假设要标注「有效期」。例如 OP-073「cron isolated ≠ main session」只在 8/5-8/6 有效，8/7 main session 也失败（OP-076）后必须立即升级假设，不要二次犯同样的乐观错误。任何「XX 路径独立可用」类结论都要写明「失效条件 = XX」

- (R16) **新增**（2026-08-09 W32 实战）：heartbeat 遇到 P0 ≥3 次同根因复发 + 存在内置 auto-fix 命令（`openclaw doctor --fix` 类）→ 自主跑修复 + 手动 trigger 验证 cron + 通知用户 三件套。教训：8/9 W32 周末累计 8+ 次同根因 channel 故障，8/9 11:56 PDT heartbeat 跑 `doctor --fix` (R13 触发) + 手动 `cron run` 验证 status 从 error(2x) 跳 ok，**实测成功**。沉淀：heartbeat 不只是 "do nothing"，R13 升级为可操作 SOP：识别 P0 + 跑 auto-fix + 验证 + 通知，下次同类故障 5 分钟内闭环。覆盖 R13 "自主修复通道" 抽象规则。

- (R17) **新增**（2026-08-12 W33）：录入既有系统的字段（分类/标签/状态名等）前，**先查历史最近 5-10 条同类型数据，复用现有枚举值**，不要凭直觉造新词。教训：阿轩 8/12 ¥29.50 美食研究所 我直接 POST 用 "餐饮" 分类，事后发现历史全是 "吃饭"，月度汇总多出孤儿分类污染账目。修正方式：API 无 UPDATE 接口时直接 `UPDATE table SET field=... WHERE id=...` 改 sqlite，不要为了 API 不支持就凑合。覆盖范围：所有有「既有枚举值」的录入场景（Huaikuai / Notion DB / 小红书标签等），先 `SELECT DISTINCT category ... ORDER BY id DESC LIMIT 10` 摸清命名习惯再写。
