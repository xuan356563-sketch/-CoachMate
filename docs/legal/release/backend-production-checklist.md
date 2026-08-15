# 练搭 CoachMate 后端生产部署与外部依赖联调验收清单

> 版本：1.0（待上线）
> 依据：`backend/README.md`、`docs/plans/2026-08-10-trainmate-external-dependencies-v1.1.md`、`docs/deployment/trainmate-production-runbook.md`
> 规则：健康检查只证明进程存活，不能替代供应商联调；**全部通过才可宣称生产就绪**。

---

## 一、部署环境

- [ ] 生产域名已解析（DNS A/CNAME 生效）
- [ ] TLS 证书有效（Let's Encrypt 或云厂商证书，HTTPS 可访问）
- [ ] CVM/容器运行环境就绪（参照 `deploy/compose.production.yml`）
- [ ] PostgreSQL 生产实例就绪（含备份策略、每日快照）
- [ ] Redis 生产实例就绪（TTL 缓存，参照 V2 Token 优化）
- [ ] 环境变量注入完成（`.env` 不入库，通过密钥管理/部署环境注入）

## 二、服务端密钥清单（从环境注入，绝不入库）

- [ ] 六项服务端签名/摘要密钥（JWT、HMAC 等）
- [ ] SMTP 主机、账号、密码、发件邮箱
- [ ] DeepSeek API Key
- [ ] MiniMax API Key
- [ ] App Store 服务端 API Key（订阅校验，`app-store-server-library`）
- [ ] 腾讯云短信密钥（如启用）

## 三、部署验证顺序

```bash
# 1. 数据库迁移
cd backend
.venv/bin/alembic upgrade head

# 2. 健康检查
curl -f https://你的域名/healthz   # 存活
curl -f https://你的域名/readyz    # 就绪（PG/Redis/Alembic 版本全匹配 → 200）

# 3. OpenAPI 契约
curl -f https://你的域名/openapi.json
```

## 四、外部依赖联调（每项附最小验收记录）

### 4.1 SMTP 邮件验证码

- [ ] 真实邮箱收到验证码邮件
- [ ] 验证码有效期正确（过期失效）
- [ ] 失败提示合理，日志脱敏（不打印完整邮箱/验证码）

### 4.2 腾讯云短信（如启用）

- [ ] 短信验证码可发送
- [ ] 模板已审核通过
- [ ] 限流策略生效

### 4.3 DeepSeek（文本 AI）

- [ ] 生产 Key 可用
- [ ] 超时处理：超时后返回结构化错误或本地降级
- [ ] 限流处理：限流时优雅降级
- [ ] 输出 Schema 校验：非法输出被拒绝，不持久化
- [ ] 提示词经安全审计

### 4.4 MiniMax（图片识别）

- [ ] 生产 Key 可用
- [ ] 赛事图片识别返回校验字段，用户确认后才导入
- [ ] 图片不落盘（或按设计短暂处理后删除）
- [ ] 上传失败/超时降级为手动导入

### 4.5 PostgreSQL / Redis

- [ ] 迁移后 `/readyz` 为 200
- [ ] 数据库、Redis 与 Alembic 版本同时就绪
- [ ] Redis TTL 缓存生效（同摘要 single-flight 正常）

## 五、账号与安全联调

- [ ] 邮箱验证码登录、刷新、退出、重登录、账号切换
- [ ] 令牌重放撤销（refresh token rotation）
- [ ] 协议版本校验（旧客户端提示升级）
- [ ] 账号导出 / 删除 / 延迟删除流程
- [ ] AI 产物仅保存结构化结果 + 摘要哈希（不保存原始提示词/图片/音频/HealthKit 样本）
- [ ] 云同步默认关闭；登录不自动上传既有数据

## 六、性能基线（隔离环境）

- [ ] 20 并发非 AI API p95 < 500ms
- [ ] 100 条同步批次 p95 < 2s
- [ ] 结果记录到验收文档（不能替代腾讯云真实网络验收）

## 七、监控与运维

- [ ] 日志脱敏配置（不打印令牌、验证码、健康数据）
- [ ] 告警通道（服务宕机/磁盘/数据库）
- [ ] 备份恢复演练（PostgreSQL 恢复验证）
- [ ] 回滚方案（`deploy/scripts/rollback.sh`）

---

## 验收记录

| 项 | 结果 | 记录位置 |
| --- | --- | --- |
| SMTP | □ 通过 □ 失败 | |
| 短信（如启用） | □ 通过 □ 失败 | |
| DeepSeek | □ 通过 □ 失败 | |
| MiniMax | □ 通过 □ 失败 | |
| PostgreSQL/Redis | □ 通过 □ 失败 | |
| 性能基线 | □ 通过 □ 失败 | |
| 验收人 / 日期 | | |

> 真实 SMTP、短信、DeepSeek、MiniMax 和生产 PG/Redis 联调依赖被忽略的 `backend/.env`；未联调不得宣称生产就绪（V1.1 外部依赖登记表规则）。

---

*本文件最后更新：[日期]*
