# TrainMate 目标差距与 Token 优化实施记录

> 日期：2026-07-30  
> 方案版本：V2  
> 状态：代码实现与自动验证已完成；Android Debug 构建受本机 SDK 缺失阻断

## 1. 实施目标

本次实现把 Token 节省作为架构约束，调用顺序固定为：

1. 本地确定性处理；
2. 应用响应缓存；
3. DeepSeek 稳定前缀缓存；
4. 精简提示词；
5. 云端结构化生成。

健康、疼痛、身体指标、联系方式和原始语音不进入云端。画像、训练处方和周期重排均只生成 `pending` 提议，用户确认前不修改正式状态。

## 2. 修改前保护与基线

- 修改前分支：`codex/trainmate-ios-beta-readiness`
- 修改前提交：`3b541ff`
- 修改前工作树：约 594 项已有修改和未跟踪文件，本次未覆盖、提交或推送这些改动。
- 可恢复差异：
  - `../prechange-snapshots/trainmate-v2-before-20260730.patch`
  - SHA-256：`f8626508eac4069a2fd4048061f60ccecfde894a937332795eb69161e379d730`
- 可恢复归档：
  - `../prechange-snapshots/trainmate-v2-before-20260730.tar.gz`
  - SHA-256：`36c09d541a37235da9b5f9377dbaed127d081053238ac5485dfcc32f2f8abe15`
- 修改前验证：
  - `flutter analyze --no-pub`：通过。
  - Flutter 临时干净副本全量测试：633 项通过。
  - 后端全量测试：182 项通过，1 条第三方弃用警告。

当前没有真实 DeepSeek API 密钥的调用证据，因此本文只确认字符预算、模拟 usage、缓存和降级测试，不宣称真实 Token 降幅已经达到发布门禁。

## 3. 目标架构落地

```text
语音或文字
  │
  ▼
Flutter 本地隐私分流
  ├─ 健康、疼痛、恢复和本地计划查询 → 本地规则，0 Token
  ├─ 已完整提取的画像或唯一模板 → 本地编译，0 Token
  └─ 脱敏后仍有歧义的训练偏好
           │
           ▼
    PromptBudgetPolicy
    ├─ 字段白名单
    ├─ 最多 4 条原则和 1 套模板
    ├─ 稳定安全前缀
    └─ 摘要键、TTL 缓存与 single-flight
           │
      ┌────┴────┐
      ▼         ▼
   Redis      DeepSeek
      └────┬────┘
           ▼
    严格 Schema 与引用校验
           ▼
   差异展示 → 用户确认 → 生效
```

## 4. 接口契约

### 4.1 `GET /v1/knowledge/catalog`

- 仅返回状态为 `verified` 的自编原则、训练模板和五种人群模板。
- 当前目录版本：`2026.07.30-v1`。
- 首批内容：12 条原则、7 套训练模板、5 种低风险训练模式。
- 不返回书籍原文、草稿、存疑或停用条目。
- 功能开关：`KNOWLEDGE_CATALOG_ENABLED`。

### 4.2 `POST /v1/ai/profile-proposals`

- 输入：本地已脱敏的训练偏好、未确认字段代码和最多 5 个歧义短片段。
- 拒绝：年龄、身体指标、疼痛、伤病、联系方式及疑似敏感原文。
- 输出：字段提议、置信度、缺失字段代码和最多 5 个追问代码。
- 产物：`profile_proposal_v1`、`pending`。
- 功能开关：`PROFILE_PROPOSAL_ENABLED`。

### 4.3 `POST /v2/ai/training-prescriptions`

- V1 接口保持不变。
- V2 新增：`population_template_id`、知识快照版本和生成模式。
- 生成模式：
  - `local_template`
  - `cloud_adaptation`
  - `local_safe_fallback`
- 引用由服务端从检索结果回填；模型不能提交引用 ID。
- 接受产物前再次校验 Skill 版本、源哈希、运行时哈希、知识版本和引用状态。
- 功能开关：`TRAINING_PRESCRIPTION_V2_ENABLED`；总急停为 `TRAINING_PLAN_KILL_SWITCH`。

### 4.4 `POST /v1/ai/plan-revisions`

- 只接收剩余日期、完成摘要、日程与器械变化、安全约束代码和当前严格处方。
- 不接收健康原因或自由文本。
- 只返回剩余周期差异，并复用 `AiArtifact` 的待确认、版本和拒绝机制。
- 功能开关：`PLAN_REVISION_ENABLED`。

### 4.5 `POST /v1/ai/chat`

- 外部契约保持兼容。
- 云端最多接收最近 4 条消息，消息正文合计不超过 1200 字符。
- 健康、疼痛、恢复和本地状态查询由本地路由处理。
- 只按用户域和 `request_id` 做 5 分钟幂等缓存，不做跨用户语义缓存。

## 5. Token 预算与裁剪

| 能力 | 输入硬上限 | 输出上限 | 免云端条件 |
| --- | ---: | ---: | --- |
| 画像提议 | 1800 字符 | 320 tokens | 必填画像已由本地完整提取 |
| AI 对话 | 4 条消息、正文 1200 字符 | 420 tokens | 本地状态、计划查询、健康或规则解释 |
| 月度处方 | 4200 字符 | 650 tokens | 唯一模板满足硬条件 |
| 周期重排 | 2200 字符 | 650 tokens | 单日调整、仅降级或交换课程 |
| 动作分析 | 240 字符本地摘要 | 不新增调用 | 本地姿态规则足够 |
| Recovery | 0 | 0 | 始终本地处理 |

裁剪顺序为：可选备注 → 低排名原则 → 次运动说明 → 最早聊天消息。必填字段和安全规则不能被截断；仍然超限时回退本地安全方案。

## 6. 缓存与并发去重

缓存键只保存 SHA-256 摘要，组成包括：

- 能力；
- 模型；
- 提示词契约版本；
- Skill 内容哈希；
- 知识版本；
- 规范化上下文摘要；
- 画像和重排使用的用户域哈希。

策略：

| 能力 | 作用域 | TTL |
| --- | --- | ---: |
| V2 月度处方 | 完全枚举化上下文可跨用户 | 24 小时 |
| 画像提议 | 用户域 | 10 分钟 |
| 周期重排 | 用户域 | 10 分钟 |
| 对话 | 用户域 + `request_id` | 5 分钟 |

同一进程使用共享异步任务合并请求；跨进程使用 Redis 短期锁合并。Redis 连接、读取、写入或释放锁失败时旁路缓存，主生成流程继续；相同摘要的进程内并发测试只产生一次模型调用。

DeepSeek 提示词使用“稳定安全前缀在前、动态上下文在后”的结构，并记录 `prompt_cache_hit_tokens` 与 `prompt_cache_miss_tokens`。前缀缓存只作为运营指标，不作为正确性依赖。

默认模型已由 `deepseek-chat` 更新为 `deepseek-v4-flash`，仍可通过 `DEEPSEEK_MODEL` 覆盖。

## 7. 数据库迁移

### `20260730_0008_ai_token_observability`

给 `ai_usage_events` 增加可空字段：

- `capability`
- `prompt_contract_version`
- `prompt_cache_hit_tokens`
- `prompt_cache_miss_tokens`

不新增用户 ID、提示词、响应正文或健康字段。升级为增量加列；回滚只移除新增观测字段，不改历史业务产物。

### `20260730_0009_knowledge_catalog`

新增：

- `knowledge_principles`
- `training_templates`

内容使用版本、状态、标签、来源名称和章节定位管理。迁移不修改既有用户表、训练记录或 AI 产物表。回滚只删除新知识表；既有训练计划和记录保持不变。

## 8. Flutter 实现

- 对话式建档：接通 iOS 本地语音转文字、本地敏感片段分流、确定性字段抽取、动态追问和画像确认。
- 五种模式：久坐初学、低冲击减脂、力量进阶、跑步入门或备赛、HYROX 混合体能。
- 逐组记录：直接写现有 `strength_sets`；每组重量、次数、RPE 和用时可以不同，旧动作级汇总继续可读。
- 周期重排：只有连续漏练、两天以上日程变化、器械变化或剩余结构冲突进入云端；差异确认后才激活。
- 系统通知：使用 `flutter_local_notifications 22.2.0`、`timezone 0.11.1` 和 `flutter_timezone 5.1.0`；采用非精确闲置调度，不申请精确闹钟权限。
- 数据权利：新增 `/data-privacy`，接通账号导出、删除申请、删除状态和撤销接口；导出复用 `file_selector`。
- Android：`namespace` 和 `applicationId` 已统一为 `com.zhilian.trainmate`。

原计划指定的 `flutter_local_notifications 21.0.0` 与项目现有 `xml 7.x` 依赖约束冲突，因此采用兼容当前 Flutter 与依赖树的 22.2.0；没有降级 GPX 解析依赖。

## 9. 安全与确认边界

- AI 只能提出画像、计划和重排建议，不能静默确认、激活、暂停、取消或完成。
- 健康、疼痛、身体指标、联系方式和原始语音不进入 HTTP、Redis、缓存键或 AI 用量表。
- 本地安全规则在模型输出后再次审计。
- 无效引用、停用知识、知识版本不一致或 Skill 哈希不一致时拒绝确认云端产物。
- 账号删除必须使用当前邮箱验证码和二次确认；提交后会话失效，撤销需重新登录。
- 通知权限拒绝、Redis 故障、DeepSeek 故障或系统调度失败均有本地降级路径。

## 10. 验收状态

| 验收项 | 当前证据 |
| --- | --- |
| 后端全量测试 | `pytest`：208 项通过，1 条第三方弃用警告 |
| 后端静态检查 | `ruff check`：通过 |
| Flutter 全量测试 | 临时干净副本：651 项通过 |
| Flutter 静态分析 | `flutter analyze --no-pub`：通过，无问题 |
| iOS Simulator 构建 | `flutter build ios --simulator --debug`：通过，生成 `Runner.app` |
| Android Debug 构建 | 已执行但环境阻断：本机没有 Android SDK，Flutter 返回 `No Android SDK found`；未出现代码编译结果 |
| 真实 Token 降幅 | 未验证；没有真实 API 密钥和优化前 usage 语料基线 |
| Android 旧包数据 | 当前没有连接 Android 设备，无法检查已安装旧包；包 ID 变更不会自动迁移旧沙箱数据 |
| iOS 真机语音和通知 | 未验证 |
| Android 真机通知 | 未验证 |
| 线上 Redis single-flight | 未验证；已有故障旁路和模拟并发测试 |
| TestFlight / 商店发布 | 未执行，不以模拟器或 Debug 构建替代 |

Android 构建需要先安装 Android Studio 或命令行 SDK，并配置 Flutter 可识别的 SDK 路径后重跑。当前证据只证明 iOS Simulator 构建成功，不代表 iPhone 真机、签名、TestFlight 或线上服务已经完成。
