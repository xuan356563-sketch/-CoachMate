# 运动资源库实施与验证记录

日期：2026-09-12。以下为资源库原阶段记录。后续已获得动作绑定例外授权并补充实现；当前阻断已转为默认减量周与完整审核不兼容，最新结果见[专业训练闭环实施记录](2026-09-12-training-loop-implementation.md)。整套计划尚未完成验收。

## 已实现

- 8个内置运动资源、同源内容目录、真实本地技能及四项运动可选引用。
- 我的入口、资源分类和详情、基础评估填写与事实汇总、手动保存、删除及核心只读历史。
- 独立本地草稿、来源指纹、安全复查、训练锁检查及本地版本提交代码。默认模板缺少动作关联，实际审核会阻止启用，不能宣称本地计划闭环通过。
- 旧照片、跑姿报告、云端草稿结构保持兼容；新增个人资料键不进入同步。

## 实测结果

|验证|结果|说明|
|---|---|---|
|修改前插件与训练计划基线|420通过、1失败|周期重排等待中的来源失效测试，单独保留|
|修改前历史测试独立副本|3通过、1失败|历史页面滚动查找 `Bad state: No element`，原快照复现|
|阶段1资源与插件|359通过|含来源、重复ID、审核状态、失效能力对象和运动引用|
|阶段2资源及评估|10通过|含两种存储、真实SQLite、失败恢复、手动确认、停用历史和账号清理|
|跨模块回归诊断|473通过、5失败|2项既有失败，3项新增启用路径失败；不能作为验收通过|
|最终定向测试|22通过、3失败|资源、导出器和计划版本仓储；新增19项中16通过、3失败|
|内容目录Python单测|9通过|既有目录契约测试|
|内容目录只读校验|通过|6个分域快照，新增资源纳入Flutter域|
|Flutter静态分析|无问题|使用clean-copy脚本；以最新日志为准|
|模拟器、真机及线上|未执行本次验收|本地启用阶段未通过，未进入下一阶段，未部署|

三项新增失败为：本地草稿确认后持久化来源、激活写入失败后的重试、停用重开后激活。这些测试在真实默认策略上被动作／媒体关联审核阻断；未删除测试、跳过审核或降低断言。

冲突及待确认选择见[ADR-0008](../architecture/ADR-0008-运动资源库与本地草稿.md)：默认模板保持原样时缺少动作关联；补齐关联会超出原“只新增来源元数据”的等价范围。该绑定例外现已获用户批准；后续发现减量周时长冲突，尚未获准修改时长，详见上述最新记录。

## 验证命令与本机证据

```bash
scripts/run_flutter_tests_clean_copy.sh test/features/resource_library test/plugins test/features/training_plan test/features/motion_check test/features/capabilities --reporter expanded --timeout 45s
scripts/run_flutter_tests_clean_copy.sh test/features/resource_library test/tool/content_catalog_export_test.dart test/data/repositories/generated_training_plan_repository_test.dart --reporter expanded
scripts/run_flutter_analyze_clean_copy.sh
scripts/verify_content_catalog.sh
backend/.venv/bin/python -m unittest discover -s scripts/tests -p test_content_catalog.py
```

本机临时证据可能被系统清理，不随仓库分发：

- `/tmp/trainmate-resources-current.txt`：修改前快照及本次文件差异目录指针。
- `/tmp/trainmate-resources-baseline-corrected.log`：修改前插件／计划基线。首次命令误含尚未建立的资源测试目录，已以此纠正后的运行作为基线。
- `/tmp/trainmate-resources-history-baseline.log`：原代码副本的历史失败复现。
- `/tmp/trainmate-resources-stage1-retry.log`、`/tmp/trainmate-resources-stage2-pass.log`：前两阶段通过证据。
- `/tmp/trainmate-resources-integration.log`：跨模块回归诊断。
- `/tmp/trainmate-resources-final-focused.log`：最终定向结果。
- `/tmp/trainmate-resources-analyze-verified.log`：最终静态分析。
- `/tmp/trainmate-resources-catalog-verify-final.log`、`/tmp/trainmate-resources-python-tests.log`：目录校验。

开始时工作区已有344条未提交状态，本次通过文件快照区分原改动。依赖声明和锁文件最终与修改前一致；未修改数据库表、创建分支、提交、推送或部署。

## 本次修改文件

相对于任务开始前快照，共49个文件；不把原未提交改动计为本次实现。

|文件|修改原因|
|---|---|
|`content_catalog/README.md`|中文维护说明、阶段结果及未解决的启用阻断|
|`content_catalog/catalog.index.json`|目录版本刷新；Flutter域登记8个运动资源，其余域随统一版本更新|
|`content_catalog/snapshots/agent_knowledge.json`|目录版本刷新；Flutter域登记8个运动资源，其余域随统一版本更新|
|`content_catalog/snapshots/ai_skills.json`|目录版本刷新；Flutter域登记8个运动资源，其余域随统一版本更新|
|`content_catalog/snapshots/backend.json`|目录版本刷新；Flutter域登记8个运动资源，其余域随统一版本更新|
|`content_catalog/snapshots/fixtures.json`|目录版本刷新；Flutter域登记8个运动资源，其余域随统一版本更新|
|`content_catalog/snapshots/flutter.json`|目录版本刷新；Flutter域登记8个运动资源，其余域随统一版本更新|
|`content_catalog/snapshots/source_receipts.json`|目录版本刷新；Flutter域登记8个运动资源，其余域随统一版本更新|
|`docs/architecture/ADR-0008-运动资源库与本地草稿.md`|中文维护说明、阶段结果及未解决的启用阻断|
|`docs/plans/2026-09-12-resource-library-implementation.md`|中文维护说明、阶段结果及未解决的启用阻断|
|`lib/app/router/app_router.dart`|资源与核心评估历史路由|
|`lib/data/models/generated_training_plan.dart`|可选资源来源、历史兼容和筛查要求|
|`lib/data/models/resource_ref.dart`|资源版本与内容指纹契约|
|`lib/data/repositories/generated_training_plan_repository.dart`|准备带本地来源的版本单键提交，不伪造云端产物|
|`lib/data/seed/seed_sport_resources.dart`|8个内置资源的唯一权威内容源|
|`lib/features/capabilities/assessment_history_page.dart`|资源引用展示或只读评估历史入口|
|`lib/features/capabilities/history_page.dart`|资源引用展示或只读评估历史入口|
|`lib/features/capabilities/plugin_skills_dialog.dart`|资源引用展示或只读评估历史入口|
|`lib/features/dashboard/training_mvp_controller.dart`|新本地资源版本沿用执行期间筛查保护|
|`lib/features/profile/profile_page.dart`|我的页面增加运动资源库入口|
|`lib/features/resource_library/assessment_record.dart`|资源检索、评估记录或本地草稿的对应模型、服务、生命周期与页面|
|`lib/features/resource_library/assessment_record_repository.dart`|资源检索、评估记录或本地草稿的对应模型、服务、生命周期与页面|
|`lib/features/resource_library/local_plan_controller.dart`|资源检索、评估记录或本地草稿的对应模型、服务、生命周期与页面|
|`lib/features/resource_library/local_plan_draft.dart`|资源检索、评估记录或本地草稿的对应模型、服务、生命周期与页面|
|`lib/features/resource_library/local_plan_panel.dart`|资源检索、评估记录或本地草稿的对应模型、服务、生命周期与页面|
|`lib/features/resource_library/local_plan_service.dart`|资源检索、评估记录或本地草稿的对应模型、服务、生命周期与页面|
|`lib/features/resource_library/resource_catalog.dart`|资源检索、评估记录或本地草稿的对应模型、服务、生命周期与页面|
|`lib/features/resource_library/resource_library_controller.dart`|资源检索、评估记录或本地草稿的对应模型、服务、生命周期与页面|
|`lib/features/resource_library/resource_library_page.dart`|资源检索、评估记录或本地草稿的对应模型、服务、生命周期与页面|
|`lib/features/resource_library/resource_plan_preview.dart`|资源检索、评估记录或本地草稿的对应模型、服务、生命周期与页面|
|`lib/features/training_plan/application/four_week_plan_controller.dart`|新本地版本沿用筛查失效与历史回退检查|
|`lib/plugins/application/plugin_runtime.dart`|公开只读业务使用锁，供本地计划确认复查|
|`lib/plugins/assembly/built_in_distribution.dart`|真实资源技能装配、目录归属或核心历史读取|
|`lib/plugins/features/built_in_features.dart`|真实资源技能装配、目录归属或核心历史读取|
|`lib/plugins/features/resource_library_plugin.dart`|真实资源技能装配、目录归属或核心历史读取|
|`lib/plugins/history/core_history.dart`|真实资源技能装配、目录归属或核心历史读取|
|`lib/plugins/sports/hyrox_plugin.dart`|新增指向资源库的可选流程引用，运动算法不变|
|`lib/plugins/sports/marathon_plugin.dart`|新增指向资源库的可选流程引用，运动算法不变|
|`lib/plugins/sports/strength_plugin.dart`|新增指向资源库的可选流程引用，运动算法不变|
|`lib/plugins/sports/trail_running_plugin.dart`|新增指向资源库的可选流程引用，运动算法不变|
|`lib/services/local_storage_service.dart`|新增评估与本地草稿业务白名单键|
|`scripts/content_catalog.py`|把同一资源权威源纳入现有内容导出与校验链路|
|`test/features/motion_check/running/running_controller_test.dart`|新增真实边界验证，或调整新增目录与可选引用的明确预期|
|`test/features/resource_library/assessment_test.dart`|新增真实边界验证，或调整新增目录与可选引用的明确预期|
|`test/features/resource_library/local_plan_test.dart`|新增真实边界验证，或调整新增目录与可选引用的明确预期|
|`test/features/resource_library/resource_catalog_test.dart`|新增真实边界验证，或调整新增目录与可选引用的明确预期|
|`test/plugins/assembly/plugin_runtime_test.dart`|新增真实边界验证，或调整新增目录与可选引用的明确预期|
|`test/tool/content_catalog_export_test.dart`|新增真实边界验证，或调整新增目录与可选引用的明确预期|
|`tool/content_catalog_export.dart`|把同一资源权威源纳入现有内容导出与校验链路|

## 2026-09-13 后续状态

用户已允许本地默认计划第 4 周减量。动作关联、跑步专项模块和 `resource-local-v3` 编译已修复，之前三项激活失败不再复现；最新验证与尚未完成的模拟器门槛见[专业训练闭环实施记录](2026-09-12-training-loop-implementation.md)。此前测试数字保留为历史记录，不代表当前重跑结果。
