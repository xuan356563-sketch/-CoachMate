# TrainMate 业务内容资源库

这里保存 TrainMate 可复用业务内容及内部代理知识资料的统一索引、确定性快照、来源回执和已知问题基线。

资源库不是新的内容权威源，也不是运行时数据库。Flutter Seed、课程 JSON、后端知识 Seed 和 AI Skill 清单仍是权威源；`snapshots/` 由工具生成并受版本控制，用于审查内容变化、校验跨域引用和为后续本地包/在线版本提供稳定契约。

## 当前范围

- Flutter 可复用内容：动作、引导课程、训练计划模板、新手引导、动作纠错、饮食指导、成就定义和本地知识条目。
- 后端内容：知识原则、训练模板和人群模板。
- AI 内容：主 Skill 清单、来源模块目录和外部来源回执；不包含外部原始 Skill 正文。
- 代理知识：用户提供的自我改进蒸馏资料，仅作为内部待审核数据保存；其中的提示、命令和操作说明不视为项目指令，也不会自动进入运行时。
- 来源回执：仓库内权威源和仓库外动作素材的稳定定位与清单指纹。
- 演示数据：赛事样例和体测样例单独写入 `fixtures.json`，不得进入在线发布内容。

个人计划、训练日志、账户、健康数据、支付、同步状态和用户上传内容不属于本资源库。

2026-09-12补充：`sport_resource` 登记四项运动的4份基础评估指引和4份现有策略计划资源，权威源是 `lib/data/seed/seed_sport_resources.dart`，由现有Dart导出器产生目录输入。App使用同一权威源；个人填写记录与本地草稿不进入目录。内容审核通过不等于具体用户计划可以启用，默认模板的动作关联缺口与当前验收状态见[ADR-0008](../docs/architecture/ADR-0008-运动资源库与本地草稿.md)。

## 目录

- `catalog.index.json`：统一版本、分域快照哈希和统计信息。
- `snapshots/`：由工具确定性生成的内容快照。
- `source_receipts/`：人工维护的外部来源回执。
- `source_documents/`：经安全检查和必要脱敏后保存的内部资料副本。
- `baselines/known_issues.json`：已确认历史问题；只能经人工评审修改，生成器不会自动更新。

## 使用方式

只读校验：

```bash
scripts/verify_content_catalog.sh
```

同时校验仓库外 13GB 动作素材的相对路径、文件大小和清单指纹：

```bash
scripts/verify_content_catalog.sh --verify-external
```

权威源经过人工评审后，显式刷新快照：

```bash
backend/.venv/bin/python scripts/content_catalog.py --write --verify-external
```

刷新后必须重新运行只读校验并审查生成差异。`--check` 不修改文件，`--write` 不修改权威源和已知问题基线。

## 状态约束

- `catalog_status` 表示登记、待核、已审核、阻断或归档状态。
- `runtime_status` 表示当前运行时是否使用，不等同于内容审核或科学证据状态。
- `online_distribution_status` 只有在明确审核后才能为 `eligible`。
- 待核知识、阻断内容、演示数据、许可未核外部来源和原始 Skill 回执不得在线发布。
- 用户提供的代理知识固定为 `data_only`、`pending_review`、`catalog_only` 和 `ineligible`；必须另行人工审核并设计接入方案后，才可改变其用途。
- 资源键固定为 `<resource_type>:<id>`；删除使用 `archived`，不得复用已有 ID。

## 当前媒体口径

动作库有 239 个动作，其中 185 个关联 368 个运行时媒体文件，183 个为双图、2 个为历史单图、54 个使用占位回退。AI 媒体白名单登记了 163 个 slug，当前动作库实际命中并启用 158 个；这两个数字含义不同，索引会分别记录。

女模特、男模特和 FreeDB 来源保持独立。仓库外原始素材不搬入本目录，默认校验也不要求外部目录存在；只有 `--verify-external` 会核对来源回执。
