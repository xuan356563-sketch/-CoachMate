# Domain: Cron & OpenClaw Config

## Gateway Tooling

- `gateway config.patch` 会拒绝改 protected paths（包括 `primary`、`*.enabled`、`apiKey` 等）；遇到这种路径需要直接编辑 `~/.openclaw/openclaw.json` 文件
- 直接编辑 json 文件后，网关会自动 hot-reload（不需要重启），但需重新查询校验：`gateway config.get` 看 `"valid": true`
- `cron update` 调 API 必须用 `patch` 参数，不能用 `job` 参数（后者会报 "patch required"）

## Cron + 模型

- cron 准点触发——改完配置 3 分钟后才生效的，手动重跑用 `cron.run` force 验证
- cron 的 delivery 推送只能在 `sessionTarget: "isolated"` 下用 channel 方式；main session 不支持 deliver-by-channel
- 模型对比（以阿轩的使用场景）:
  - deepseek-v4-pro: 质量好但早高峰容易超时（6+ 分钟失败）
  - MiniMax M3: 推送类任务 20s 完成，稳定
