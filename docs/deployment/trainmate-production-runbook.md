# TrainMate 生产部署运行手册

## 1. 当前部署边界

本手册部署以下组件：

- 腾讯云 CVM 上的 FastAPI 业务 API、独立 Ops API、Ops Web 与 Nginx。
- 腾讯云托管 PostgreSQL 和 Redis。
- CODING 私有 Git、持续集成和腾讯云 TCR 不可变镜像。
- Flutter Web 构建验证，以及 iOS TestFlight 的交付准备。

本地 `backend/compose.yaml` 只用于开发联调。生产环境使用 `deploy/compose.production.yml`，不在 CVM 内启动 PostgreSQL 或 Redis。

## 2. 首次外部配置

### 2.1 CODING 与 TCR

1. 在 CODING 创建私有项目和代码仓库，将当前仓库推送为首个可追溯基线。
2. 创建持续集成构建计划，流水线来源选择仓库根目录的 `Jenkinsfile`。
3. 构建节点安装并锁定 Flutter `3.44.5`、Python `3.13`、Node `22`、Docker 和 Git，节点标签设为 `trainmate-builder`。
4. 在 CODING 凭据管理中配置 TCR 凭据，并仅向本构建计划授权。
5. 通过受保护变量注入：

   - `TRAINMATE_CI_API_BASE_URL`：CI Web 构建使用的 HTTPS 预发布 API 地址。
   - `TCR_REGISTRY`、`TCR_NAMESPACE`。
   - `TCR_USERNAME`、`TCR_PASSWORD`：必须使用 CODING 凭据，不得写入 Jenkinsfile。

6. 合并请求执行分析、测试和 Web 构建；只有 `main` 或 `v*` 标签构建才推送镜像。
7. 生产部署使用 CODING 受保护环境和人工审批，不允许普通代码推送直接更新生产 CVM。

CODING 官方文档确认其持续集成以 Jenkinsfile 为基本流水线单元，并支持通过凭据 ID/受控变量使用密钥及向 TCR 推送镜像：

- <https://coding.net/help/docs/devops/ci/start.html>
- <https://coding.net/help/docs/ci/credential.html>
- <https://coding.net/help/docs/ci/practice/artifacts/tcr.html>

### 2.2 腾讯云资源

1. 创建托管 PostgreSQL，启用自动备份和时间点恢复。
2. 创建托管 Redis；Redis 只承担缓存、验证码、限流和锁，不作为业务事实源。
3. CVM 安装 Docker Engine 与 Compose 插件，创建 `/opt/trainmate`。
4. 安全组只开放公网 `80/443`；`22` 仅允许管理 IP；禁止开放 `8000/8001/8081`。
5. 将正式域名解析到 CVM，准备 TLS 完整链和私钥。

从 macOS 外置磁盘复制部署文件时必须排除 AppleDouble 侧车文件：

```bash
COPYFILE_DISABLE=1 rsync -a --exclude='._*' --exclude='**/._*' \
  deploy/ <CVM用户>@<CVM地址>:/opt/trainmate/deploy/
```

后端和 Ops Web 的 `.dockerignore` 已再次排除这些文件，避免 Alembic 或构建工具把 `._*.py` 当成源码。

## 3. 服务器目录

```text
/opt/trainmate/
├── deploy/                    # 本仓库 deploy 目录的受控副本
│   ├── .env.deploy            # 非密钥部署元数据
│   ├── compose.production.yml
│   └── certs/
│       ├── fullchain.pem
│       └── privkey.pem
├── secrets/
│   └── production.env         # chmod 600，不进入 Git
└── state/                     # 非敏感部署回执
```

复制模板并填写：

```bash
cp deploy/.env.deploy.example deploy/.env.deploy
install -m 600 deploy/production.env.example /opt/trainmate/secrets/production.env
```

禁止直接使用模板占位值启动。`preflight.sh` 会拒绝占位值、开发配置、版本不一致或首批高风险开关被意外开启。

## 4. 首批功能开关

首批生产候选只开放知识目录和 V2 确定性处方：

```dotenv
KNOWLEDGE_CATALOG_ENABLED=true
TRAINING_PRESCRIPTION_V2_ENABLED=true
PROFILE_PROPOSAL_ENABLED=false
TRAINING_STRUCTURE_V1_ENABLED=false
PLAN_REVISION_ENABLED=false
SYNC_ENABLED=false
HEALTH_PROFILE_CLOUD_ENABLED=false
IOS_SUBSCRIPTION_ENABLED=false
PAID_PLAN_GENERATION_GATE_ENABLED=false
```

专项验收后需要放量时，将 `.env.deploy` 中 `ALLOW_RISKY_FLAGS=true`，一次只调整一个功能开关，并保留审批记录。该参数只跳过部署脚本的首批开关保护，不会绕过应用自身的生产密钥、协议或供应商配置校验。

## 5. 预发布与生产发布

### 5.1 发布前门禁

1. CI 全部通过并生成 `image-manifest.env`。
2. 在 TCR 确认镜像标签为完整 Git SHA；生产不得使用 `latest`。
3. 在腾讯云创建数据库备份或恢复点，将非敏感回执编号写入 `BACKUP_RECEIPT_ID`。
4. 把候选镜像地址和发布版本写入 `.env.deploy` 与 `production.env`。
5. 运行预检：

```bash
cd /opt/trainmate
./deploy/scripts/preflight.sh ./deploy/.env.deploy
```

### 5.2 执行发布

```bash
cd /opt/trainmate
./deploy/scripts/deploy.sh ./deploy/.env.deploy
```

脚本固定按以下顺序执行：

1. 校验生产配置、TLS 文件、备份回执和功能开关。
2. 拉取带 Git SHA 的镜像。
3. 单独执行一次 `alembic upgrade head`。
4. 更新 API，并等待 `/readyz` 通过。
5. 更新 Nginx、Ops API 与 Ops Web。
6. 通过公网 HTTPS 再次检查 `/readyz`。
7. 写入不含密钥的部署回执。

### 5.3 发布后冒烟测试

- `GET /healthz` 返回 `200`，只能证明进程存活。
- `GET /readyz` 返回 `200`，数据库、Redis 和迁移均为 `ok`。
- 验证真实邮箱验证码和测试账号登录。
- 验证知识目录、V2 训练处方生成、拒绝与确认流程。
- 验证 Ops Web 只能通过 SSH 隧道访问：

```bash
ssh -N -L 8081:127.0.0.1:8081 <CVM用户>@<CVM地址>
```

- 检查日志中没有邮箱、验证码、Token、提示词、图片、音频或健康字段。

## 6. 回滚

应用异常时先关闭相关功能开关，再执行镜像回滚：

```bash
./deploy/scripts/rollback.sh \
  <上一版API镜像完整地址> \
  <上一版Ops-Web镜像完整地址> \
  ./deploy/.env.deploy
```

回滚脚本只切换应用镜像，不执行 Alembic downgrade。数据库迁移必须保持向后兼容；数据恢复只在确认数据损坏后进行，并先恢复到新实例验证，禁止直接覆盖原生产实例。

## 7. 定时任务与运营台

- 使用受控调度器每小时运行以下一次性容器任务：

```bash
docker compose --project-name trainmate-production \
  --env-file /opt/trainmate/deploy/.env.deploy \
  --file /opt/trainmate/deploy/compose.production.yml \
  --profile jobs run --rm purge-deletions
```
- 调度器使用与 API 相同的镜像和生产环境变量，但不得暴露公网端口。
- Ops API 与 Ops Web 只绑定 `127.0.0.1`，不得加入公网 Nginx 路由。

## 8. Flutter 与 iOS 发布

Flutter Release 必须显式写入 HTTPS API 地址：

```bash
flutter build ipa --release \
  --dart-define=TRAINFLOW_API_BASE_URL=https://api.<正式域名>
```

上传 TestFlight 后必须在真实 iPhone 验证登录、本地语音、通知、HealthKit、AI 提议确认和计划回滚。Apple 订阅、服务器通知和权益恢复完成沙盒验收前，保持 `IOS_SUBSCRIPTION_ENABLED=false`。

Android 当前 Release 仍使用 Debug 签名，不属于本次生产发布；必须配置正式 Keystore 后再建立 Android 发布流水线。

## 9. 完成判定

只有同时具备以下证据，才可以称为“已部署”：

- CI 构建记录、Git SHA 和 TCR 镜像摘要。
- PostgreSQL 备份回执和 Alembic 当前版本。
- 公网 HTTPS `/healthz`、`/readyz` 的现场响应。
- 安全组端口检查和 Ops SSH 隧道访问结果。
- 冒烟测试记录与一次应用镜像回滚演练。
- TestFlight 安装到真实设备后的完整业务验证。
