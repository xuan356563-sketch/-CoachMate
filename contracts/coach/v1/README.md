# TrainMate Coach V1 契约说明

本目录是 Flutter 本地端与 Python 后端共同遵守的 Coach V1 契约基线。首期只运行确定性规则；DeepSeek 不参与训练、安全、记忆检索或动作选择。

## 权力矩阵

| 层级 | 可以做 | 不可以做 | 失败口径 |
| --- | --- | --- | --- |
| 训练引擎 | 从 `TrainingStateReader` 生成的结构化快照中产出允许动作、强度上限、时长上限和理由码 | 接受页面拼装快照；读取关系记忆替代训练事实；直接修改计划 | 缺少、过期、跨日、摘要错误或关键事实缺失时返回空动作集合 |
| 安全层 | 删除动作、降低强度或时长、提高风险、增加阻断项 | 增加动作、提高上限、降低风险、移除既有禁止项 | 疼痛红线、伤病红旗或空交集时不提供训练入口 |
| 陪伴层 | 从允许集合选择动作；选择语气、时机；按需引用已确认记忆 | 生成新动作、新数字、医疗结论；把训练目标、负荷、恢复或伤病写成关系记忆 | 记忆不可用时忽略记忆，不阻塞本地静态回复 |
| 渲染层 | 渲染白名单事实、动作编号和最多两条可提及记忆 | 参与训练或安全决策；生成新的动作、数字或事实 | 断言失败即使用固定安全文案 |
| 双端合并 | 动作取交集，强度和时长取低，风险取高，禁止项取并集 | 客户端优先、服务端优先或接受迟到的放宽结果 | 版本或摘要不一致时停止合并并清空训练入口 |

所有计划、提醒和训练调整只能形成待确认操作，不能绕过既有用户确认流程。

## 规范化序列化与摘要

1. 输入只能由 JSON 基础类型组成。
2. 对象键按 Unicode 字符串升序递归排序；数组顺序保持不变；`null` 保留。
3. 使用 UTF-8、非 ASCII 字符原样编码、无多余空白的 JSON。
4. 对上述字节计算小写十六进制 SHA-256。
5. 时间在生成结构化对象前统一为 UTC ISO-8601；摘要校验不得在解析后改写客户端原始 JSON。

契约版本为 `1`，规则版本为 `coach-rules-1.0.0`，当前契约哈希为：

`8970f0e215ddc5b54709eb5febeef2ca506b823e4095f54be9b9d31956e078e0`

跨端一致性由 `fixtures/canonical-digest-cases.json` 和 `fixtures/decision-cases.json` 共同验证。夹具中的 20 个场景在 Dart 与 Python 各执行四类断言，形成每端不少于 80 项确定性检查。

## 稳定错误码

### 本地契约与理由码

- 快照：`snapshot_contract_mismatch`、`snapshot_identity_missing`、`snapshot_local_date_invalid`、`snapshot_generated_in_future`、`snapshot_expired`、`snapshot_ttl_exceeded`、`snapshot_source_required`、`snapshot_source_digest_invalid`、`snapshot_source_digest_mismatch`、`snapshot_pain_invalid`、`snapshot_critical_fact_missing`。
- 记忆：`memory_source_required`、`memory_distinct_evidence_required`、`memory_confidence_invalid`、`memory_valid_until_required`、`memory_until_revoked_boundary_only`、`memory_confirmation_required`、`memory_sync_requires_confirmed_active`。
- 仲裁：`contract_mismatch`、`snapshot_mismatch`、`memory_mismatch`、`pain_redline`、`existing_plan_missing`、`existing_adjustment_required`、`existing_plan_available`。

### 云端 API 错误码

- 请求：`coach_request_invalid`。
- 授权与开关：`coach_cloud_projection_disabled`、`coach_cloud_projection_consent_required`。
- 投影：`coach_projection_missing`、`coach_projection_version_conflict`、`coach_projection_version_mismatch`。
- 一致性：`coach_contract_mismatch`、`coach_snapshot_expired`、`coach_snapshot_mismatch`、`coach_memory_mismatch`。

客户端遇到未知 Coach 错误码时必须按不可用处理，不能据此放宽任何限制。

## 文件职责

- `contract-manifest.json`：权力范围、强制不变量、记忆类别与保留期限。
- `coach-contract.schema.json`：本地完整快照、关系记忆、评估请求和决策信封的 JSON Schema。
- `fixtures/canonical-digest-cases.json`：Dart/Python 规范化摘要一致性夹具。
- `fixtures/decision-cases.json`：从参考包迁入并结构化的确定性训练与安全场景。

