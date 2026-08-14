# TrainFlow 账号与赛事识别后端

这是 TrainFlow 的大陆后端基础。它与 Flutter 本地优先架构并存，已接通邮箱/手机号验证码登录、会话轮换、白名单云同步、账号导出与延迟删除、AI 聚合用量记录、受登录保护的 MiniMax-M3 赛事图片识别，以及 DeepSeek 驱动的 AI 训练卡片。云同步默认关闭，登录不会自动上传既有训练数据。

## 本地运行

1. 复制环境变量模板：`cp .env.example .env`。
2. 使用 Python 3.11 至 3.14 创建虚拟环境。
3. 安装开发依赖：`python -m pip install -e ".[dev]"`。
4. 执行单元测试：`python -m pytest`。
5. 启动 API：`python -m uvicorn app.main:app --reload`。

存活检查地址为 `http://127.0.0.1:8000/healthz`，就绪检查地址为 `http://127.0.0.1:8000/readyz`，OpenAPI 契约为 `http://127.0.0.1:8000/openapi.json`。`/readyz` 只有在 PostgreSQL、Redis 和 Alembic 迁移版本全部匹配时才返回 `200`。

本地隔离性能基线使用完整 HTTP、Pydantic 和 SQLite 代码路径：

```bash
python scripts/verify_core_performance.py
```

它验证 20 并发非 AI API 的 p95 小于 500ms，以及 100 条同步批次的 p95 小于 2 秒。该结果不能替代腾讯云部署后的真实网络和托管 PostgreSQL 验收。

### DeepSeek Key 轮换验收

`/healthz` 只能证明进程存活，不能证明 DeepSeek Key 已更换。完成控制台新建 Key、写入被忽略的 `.env`、撤销旧 Key并启动服务后，使用环境变量提供本地访问令牌，再运行：

```bash
DEEPSEEK_OLD_KEY_REVOKED=true \
TRAINMATE_ACCESS_TOKEN="仅放在当前终端环境中" \
python scripts/verify_deepseek_rotation.py \
  --receipt ../outputs/security/deepseek-rotation-receipt.json
```

脚本依次验证配置、`HttpDeepSeekClient` 的最小合成请求和受登录保护的真实 AI 生成接口。回执只包含布尔状态、稳定错误码和验证时间，不包含 Key、访问令牌、请求正文或供应商原始响应；任一环节缺失时退出码为 `2`，不得宣称轮换完成。

## 已实现接口

- `POST /v1/auth/sms-challenges`：申请短信验证码，响应不包含验证码。
- `POST /v1/auth/email-challenges`：申请邮箱验证码，响应不包含邮箱或验证码。
- `GET /v1/auth/public-config`：返回当前协议版本、短信模式和邮件模式，不返回验证码或密钥。
- `POST /v1/auth/sessions`：邮箱和手机号必须且只能提交一个；新账号或缺少当前协议版本的旧账号必须提交服务协议和隐私政策版本。服务端只保存登录标识 HMAC 摘要、手机号末四位或脱敏邮箱。
- `POST /v1/auth/tokens/refresh`：轮换刷新令牌。发现旧令牌重放时撤销整个会话族。
- `GET /v1/auth/me` 与 `DELETE /v1/auth/sessions/current`：读取最小账号信息与退出当前会话。
- `POST /v1/races/image-recognition`：接收登录用户上传的 JPEG、PNG、GIF 或 WebP 赛事图片，返回严格校验后的可编辑字段。
- `POST /v1/ai/generations`：生成 AI Trainer 或 AI Recovery 的结构化卡片；请求上下文和输出均经过 Pydantic 校验。
- `GET /v1/ai/training-prescriptions/capabilities`：读取已审核的内置训练 Skill 版本、覆盖标签和完整性哈希，不返回 Skill 正文。
- `POST /v1/ai/training-prescriptions`：根据枚举化的非健康训练条件生成 `training_prescription_v1`；AI 只返回课程蓝图，Flutter 本地编译和安全审计后才允许激活四周计划。
- `GET /v1/knowledge/catalog`：读取 12 条已审核自编原则、7 套训练模板和 5 种低风险人群模板，不返回版权正文。
- `POST /v1/ai/profile-proposals`：只根据已脱敏训练偏好生成待确认画像字段和追问代码。
- `POST /v2/ai/training-prescriptions`：优先使用唯一模板本地编译，存在歧义时才使用知识检索结果进行云端适配。
- `POST /v1/ai/plan-revisions`：只根据枚举化日程、器械、完成摘要和安全约束生成待确认的剩余周期差异。
- `POST /v1/ai/chat`：健康内容由服务端再次拒绝，云端历史最多 4 条且正文合计不超过 1200 字符。
- `POST /v1/ai/motion-analysis`：接收确认上传的动作图片，内存内清洗元数据后调用 MiniMax-M3，返回 AI Motion 评分卡。
- `GET /v1/ai/artifacts`、`POST /v1/ai/artifacts/{id}/decision`、`DELETE /v1/ai/artifacts/{id}`：读取、确认/拒绝和删除已生成卡片。
- `GET /v1/sync/snapshot`、`POST /v1/sync/mutations`、`GET /v1/sync/changes`：同步五类旧白名单投影和新增密文用户档案，支持版本冲突、幂等写入和游标分页。
- `PUT /v1/account/consents/health-profile-cloud`：单独授予或撤回身高、体重和伤病的云同步授权；撤回会重新加密已清除健康字段的档案。
- `user_profile` 同步实体：只接收用户确认后的结构化字段，整份档案使用 AES-256-GCM 应用层加密，原始输入和转写稿不属于接口契约。
- `GET /v1/billing/entitlement`、`POST /v1/billing/apple/transactions/verify`、`POST /v1/billing/apple/notifications`：读取服务端权益、验证苹果交易和幂等处理 Server Notifications V2。
- `GET /v1/account/export`：导出当前账号的最小账号信息和允许同步的数据。
- `POST /v1/account/deletion-challenges`、`POST /v1/account/deletion-requests`、`POST /v1/account/deletion-cancellations`、`GET /v1/account/deletion-status`：处理邮箱复核、会话撤销、七天撤销期和删除状态。

独立 Ops 应用提供 `/ops/v1/summary`、`/ops/v1/sync-health`、`/ops/v1/ai-usage` 和 `/ops/v1/deletion-jobs`。它不挂载到业务 API，必须设置 `OPS_ENABLED=true` 并仅绑定私网或 `127.0.0.1`。

开发环境默认 `SMS_PROVIDER=development`、`EMAIL_PROVIDER=development`，内部测试码均固定为 `246810`。验证码不会出现在接口响应或日志中，开发邮件模式不会实际发送邮件。生产环境启动时会拒绝 development 模式。内部测试协议版本为 `internal-test-2026-07-13.1`，生产环境同样会拒绝内部测试版本。

## SMTP 邮件启用前置条件

生产环境必须设置 `EMAIL_PROVIDER=smtp`，并通过部署平台的密钥管理功能配置 `SMTP_HOST`、`SMTP_PORT`、`SMTP_USERNAME`、`SMTP_PASSWORD` 和 `SMTP_FROM_EMAIL`。`SMTP_SECURITY=starttls` 使用 587 等 STARTTLS 端口，`SMTP_SECURITY=ssl` 使用 465 等隐式 TLS 端口。邮件仅包含登录验证码和有效分钟数，完整邮箱与验证码不会写入数据库或业务日志。

## 腾讯云短信启用前置条件

将 `SMS_PROVIDER` 设置为 `tencent` 前，必须通过部署平台的密钥管理功能配置：

- `TENCENT_SECRET_ID`、`TENCENT_SECRET_KEY`
- `TENCENT_SMS_SDK_APP_ID`、`TENCENT_SMS_SIGN_NAME`、`TENCENT_SMS_TEMPLATE_ID`
- 发送模板的两个参数依次为验证码和有效分钟数

生产环境可以关闭旧短信通道；启用短信时必须使用腾讯云。生产环境必须启用 SMTP 邮件，并替换所有 `development-only-*` 签名密钥。应用启动会拒绝示例密钥、不完整的腾讯云/SMTP 配置、内部测试协议版本、缺少 MiniMax 密钥或缺少 DeepSeek 密钥的配置。

## AI 训练卡片

- AI Trainer 默认调用大陆 DeepSeek 地址 `https://api.deepseek.com` 与 `deepseek-v4-flash`；AI Recovery 默认只在客户端本地处理。AI Motion 和赛事图片识别默认调用大陆 MiniMax 地址 `https://api.minimaxi.com` 与 `MiniMax-M3`。模型仍可通过环境变量覆盖。
- 服务端只保存经过 Schema 校验的结构化卡片、上下文摘要哈希、模型和用户确认状态。不会保存原始提示词、原始图片、音频、EXIF、HealthKit 原始样本或设备标识。
- AI 产物默认 `pending`，Flutter 必须在用户明确确认后才把训练计划、动作纠错或恢复建议映射到本地状态；本地疼痛和安全规则优先于 AI 建议。
- AI 生成默认每用户每 10 分钟最多 20 次。生产依赖 Redis 且 Redis 故障时拒绝生成；开发可降级为进程内限流。
- 图片在单次请求内完成方向修正和重新编码，不写磁盘、PostgreSQL 或业务日志。iPhone 语音入口仅本地转写，服务端只接收用户确认后的文本。

## Skill 训练处方

- 唯一主 Skill 为 `training-plan-builder 1.2.0`。模型只接收通过哈希和静态内容校验的 `RUNTIME.md`；力量、马拉松、越野跑和 HYROX 按主运动确定性加载各自的审核片段。
- 用户提供的训练技能包以 `source-catalog.json` 登记 50 个唯一 ID、归档路径和 SHA-256，其中 21 项只以完全改写后的受限规则进入运行时，23 项仅登记，6 项明确阻断。另有 1 条 ABC 循环渐进法外部来源收据，仅以审核重写后的力量片段进入运行时；原文和图片不打包。启用来源 ID 必须与审核规则标记一一对应；越野跑当前只映射为泛化耐力结构。来源包缺少 LICENSE，原始 `SKILL.md` 不随服务发布、不会进入提示词，也不能作为科学证据。
- 训练处方不接受自由文本，也不接受姓名、身体数据、伤病、疼痛、健康筛查、HealthKit 或训练日志。请求只允许目标、主次运动、训练经验、每周可用天数、单次分钟数、器械代码和可选赛事倒计时。
- 即使用户每周七天都有空，处方也最多返回六节课程并保留至少一天休息。模型不得返回动作、负重、配速、证据引用或医学判断。
- 返回结果沿用现有 `ai_generation_jobs` 和 `ai_artifacts`，默认状态为 `pending`，不新增数据库表。缓存摘要包含请求契约、模型、Skill 版本、源文件/运行时/专项片段哈希、来源目录哈希和实际适用的来源模块 ID。
- 接受 `training_prescription_v1` 前会再次核对当前 Skill 的 ID、版本、源文件/运行时/专项片段哈希及选择原因；Skill 被替换、撤销或关闭时拒绝接受并要求重新生成。重复接受同一产物为幂等操作。
- `TRAINING_PLAN_KILL_SWITCH=true` 会关闭能力发现中的可用状态，并拒绝新处方生成和待确认处方的接受；已有已接受产物仍可读取，本地规则计划不受影响。该开关默认关闭。
- 服务日志只记录请求 ID、Skill ID/版本与哈希、契约版本、模型、缓存、Token、耗时和结果码，不记录请求正文、身份或健康数据。
- V2 处方的完全枚举化结果可跨用户缓存 24 小时；画像与重排按用户域缓存 10 分钟；聊天只按用户域和 `request_id` 幂等缓存 5 分钟。缓存键包含模型、提示词版本、Skill 哈希、知识版本和上下文摘要，不包含正文。
- Redis 缓存和锁均为尽力而为；故障时旁路缓存并继续主流程。进程内共享任务与 Redis 锁共同保证同一摘要并发请求只执行一次模型生成。
- `KNOWLEDGE_CATALOG_ENABLED`、`PROFILE_PROPOSAL_ENABLED`、`TRAINING_PRESCRIPTION_V2_ENABLED` 和 `PLAN_REVISION_ENABLED` 可分别关闭新增能力；关闭时客户端应回退本地流程。
- `TRAINING_STRUCTURE_V1_ENABLED` 默认关闭；开启后由服务端确定性回填五维与腿部四要素标签，不将这些规则加入模型提示词。

## MiniMax 赛事图片识别

- 真实 `MINIMAX_API_KEY` 只写入被 Git 忽略的 `backend/.env`，不得写入 Flutter、Git、日志或测试快照。
- 默认调用大陆地址 `https://api.minimaxi.com` 和模型 `MiniMax-M3`，可以通过环境变量覆盖。
- 单图最大 10MB，只接受 JPEG、PNG、GIF 和 WebP；HEIC 会返回中文格式提示。
- 图片只在单次请求内使用，不写入磁盘、PostgreSQL 或业务日志；Flutter 只接收服务端校验后的字段。
- 每个用户默认每 10 分钟最多识别 10 次。生产环境依赖 Redis 且故障时拒绝识别；开发环境可以回退到进程内限流。

## Docker 开发环境

Docker 可用时，在本目录执行：

```bash
cp .env.example .env
docker compose up --build
```

`api` 服务会先执行 `alembic upgrade head`，再启动 HTTP 服务。PostgreSQL 和 Redis 不暴露给宿主机；业务 API、Ops API 和 Ops Web 分别仅绑定 `127.0.0.1:8000`、`127.0.0.1:8001` 和 `127.0.0.1:8081`。启用运营台前须在 `.env` 设置 `OPS_ENABLED=true`。

到期删除任务由受控调度器运行：

```bash
python -m app.jobs.purge_deletions
```

任务只输出本次清理数量。生产部署、备份恢复、SSH 隧道和放量步骤见 `docs/architecture/trainmate-internal-backend-deployment.md`。

## 迁移纪律

- `20260712_0001` 只建立迁移历史基线，不创建业务表。
- `20260713_0002` 创建 `users`、`user_consents`、`devices`、`sms_challenges` 和 `auth_sessions`。该迁移假设尚无线上业务数据；已投入生产后禁止直接降级，必须先完成会话撤销、数据导出和影响评估。
- `20260713_0003` 创建 `ai_generation_jobs` 和 `ai_artifacts`。其中只记录产物、模型、摘要哈希和确认状态，不新增原始媒体或原始提示词字段。
- `20260716_0004` 增量增加邮箱身份与 `email_challenges`，保留旧手机号用户和会话；该迁移禁止自动降级，生产回滚应先关闭邮箱入口并回退应用，数据处理须经人工评估和备份。
- `20260728_0005` 增加五类云端投影、同步幂等记录和增量游标。
- `20260728_0006` 增加导出记录、删除复核、七天撤销期和匿名删除回执。
- `20260728_0007` 增加不含用户标识或请求正文的 AI 聚合用量记录。
- `20260730_0008` 为 AI 聚合用量增加能力、提示词版本、应用缓存命中和 DeepSeek 前缀缓存 Token；字段保持可空，不保存正文。
- `20260730_0009` 新增训练原则和训练模板表；只有 `verified` 内容进入生成检索池。
- `20260731_0010` 新增 `cloud_user_profiles` 密文档案表，不修改旧同步实体含义。
- `20260731_0011` 新增苹果订阅权益和通知幂等表；账号删除通过外键级联覆盖权益数据。
- 账号、健康数据、云同步和 AI 审计表必须分别建立迁移、兼容方案、回滚方案和测试后才能进入数据库。
- 不得将 DeepSeek、短信或数据库生产密钥写入 Flutter、Git 或日志。
