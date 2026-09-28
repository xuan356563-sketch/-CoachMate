# TrainMate 插件化净变更清单

本清单以实施前快照 `/tmp/trainmate-plugin-implementation-20260904/baseline` 为比较起点；排除用户实施前已有差异，不使用 Git HEAD 统计本轮成果。

共 194 个源码、测试及合成夹具文件（124 个修改、70 个新增）。迁移期间新增后删除的两份 legacy 策略不计为最终新增文件；旧数据读取继续保留。

另有四份交付文档：源码对照方案顶部状态链接、实施与验收记录、插件维护指南及本清单。八张由本轮测试重写的诊断失败图已恢复实施前字节，当前验证证据保留在临时验收目录；黄金基准未改。

|文件|变更|原因|
|---|---|---|
|[backend/app/services/training_prescription.py](../../backend/app/services/training_prescription.py)|修改|六类后端提供方和调用委托，保持审核及公开协议等价|
|[backend/app/services/training_prescription_v2.py](../../backend/app/services/training_prescription_v2.py)|修改|六类后端提供方和调用委托，保持审核及公开协议等价|
|[backend/app/services/training_skills.py](../../backend/app/services/training_skills.py)|修改|六类后端提供方和调用委托，保持审核及公开协议等价|
|[backend/app/services/training_sport_providers.py](../../backend/app/services/training_sport_providers.py)|新增|六类后端提供方和调用委托，保持审核及公开协议等价|
|[backend/tests/test_training_sport_providers.py](../../backend/tests/test_training_sport_providers.py)|新增|验证六类提供方身份、注册冲突及现有策略等价|
|[ios/Runner/HealthKitPendingBatchStore.swift](../../ios/Runner/HealthKitPendingBatchStore.swift)|修改|HealthKit 无损暂停/恢复和暂停期间 ACK 守卫|
|[ios/Runner/HealthKitSyncCoordinator.swift](../../ios/Runner/HealthKitSyncCoordinator.swift)|修改|HealthKit 无损暂停/恢复和暂停期间 ACK 守卫|
|[ios/RunnerTests/RunnerTests.swift](../../ios/RunnerTests/RunnerTests.swift)|修改|验证 HealthKit 暂停、重启、ACK、队列与锚点保留|
|[lib/app/navigation/main_shell.dart](../../lib/app/navigation/main_shell.dart)|修改|插件贡献驱动路由/导航，保留核心与认证入口|
|[lib/app/navigation/trainmate_bottom_navigation_v2.dart](../../lib/app/navigation/trainmate_bottom_navigation_v2.dart)|修改|插件贡献驱动路由/导航，保留核心与认证入口|
|[lib/app/router/app_router.dart](../../lib/app/router/app_router.dart)|修改|插件贡献驱动路由/导航，保留核心与认证入口|
|[lib/app/router/app_routes.dart](../../lib/app/router/app_routes.dart)|修改|插件贡献驱动路由/导航，保留核心与认证入口|
|[lib/app/trainflow_app.dart](../../lib/app/trainflow_app.dart)|修改|插件贡献驱动路由/导航，保留核心与认证入口|
|[lib/data/models/generated_training_plan.dart](../../lib/data/models/generated_training_plan.dart)|修改|可选 PluginRef 元数据、旧计划兼容读取和草稿处理|
|[lib/data/repositories/generated_training_plan_repository.dart](../../lib/data/repositories/generated_training_plan_repository.dart)|修改|可选 PluginRef 元数据、旧计划兼容读取和草稿处理|
|[lib/features/activity_import/activity_import_page.dart](../../lib/features/activity_import/activity_import_page.dart)|修改|导入操作取得来源租约，等待记录持久化并处理失败|
|[lib/features/ai_center/ai_center_page.dart](../../lib/features/ai_center/ai_center_page.dart)|修改|复用 AI 服务和来源租约，拒绝迟到回复或产物写入|
|[lib/features/ai_center/application/ai_artifact_controller.dart](../../lib/features/ai_center/application/ai_artifact_controller.dart)|修改|复用 AI 服务和来源租约，拒绝迟到回复或产物写入|
|[lib/features/ai_center/application/ai_chat_controller.dart](../../lib/features/ai_center/application/ai_chat_controller.dart)|修改|复用 AI 服务和来源租约，拒绝迟到回复或产物写入|
|[lib/features/auth/application/account_switch_coordinator.dart](../../lib/features/auth/application/account_switch_coordinator.dart)|修改|账号换域恢复、清理只执行一次及对应中文提示|
|[lib/features/auth/application/auth_controller.dart](../../lib/features/auth/application/auth_controller.dart)|修改|账号换域恢复、清理只执行一次及对应中文提示|
|[lib/features/auth/presentation/auth_pages.dart](../../lib/features/auth/presentation/auth_pages.dart)|修改|账号换域恢复、清理只执行一次及对应中文提示|
|[lib/features/capabilities/capabilities_page.dart](../../lib/features/capabilities/capabilities_page.dart)|新增|管理开关、依赖确认、失败恢复和核心历史只读|
|[lib/features/capabilities/history_page.dart](../../lib/features/capabilities/history_page.dart)|新增|管理开关、依赖确认、失败恢复和核心历史只读|
|[lib/features/cloud_sync/application/cloud_sync_controller.dart](../../lib/features/cloud_sync/application/cloud_sync_controller.dart)|修改|同步分页和提交受租约控制，保留游标、授权与待同步记录|
|[lib/features/cloud_sync/application/cloud_sync_coordinator.dart](../../lib/features/cloud_sync/application/cloud_sync_coordinator.dart)|修改|同步分页和提交受租约控制，保留游标、授权与待同步记录|
|[lib/features/companion/application/coach_memory_controller.dart](../../lib/features/companion/application/coach_memory_controller.dart)|修改|伙伴消息与记忆写守卫、通知范围清理和单份订阅恢复|
|[lib/features/companion/application/companion_controller.dart](../../lib/features/companion/application/companion_controller.dart)|修改|伙伴消息与记忆写守卫、通知范围清理和单份订阅恢复|
|[lib/features/companion/application/companion_notification_scheduler.dart](../../lib/features/companion/application/companion_notification_scheduler.dart)|修改|伙伴消息与记忆写守卫、通知范围清理和单份订阅恢复|
|[lib/features/daily_adjustment/application/daily_adjustment_controller.dart](../../lib/features/daily_adjustment/application/daily_adjustment_controller.dart)|修改|每日调整写入到刷新完成的生命周期保护|
|[lib/features/daily_adjustment/daily_adjustment_page.dart](../../lib/features/daily_adjustment/daily_adjustment_page.dart)|修改|每日调整写入到刷新完成的生命周期保护|
|[lib/features/daily_check_in/daily_check_in_page.dart](../../lib/features/daily_check_in/daily_check_in_page.dart)|修改|签到与提醒真实异步写入口和中文错误处理|
|[lib/features/dashboard/today_training_page.dart](../../lib/features/dashboard/today_training_page.dart)|修改|按实际功能守卫共享动作、首页贡献和后台取消边界|
|[lib/features/dashboard/training_mvp_controller.dart](../../lib/features/dashboard/training_mvp_controller.dart)|修改|按实际功能守卫共享动作、首页贡献和后台取消边界|
|[lib/features/dashboard/widgets/today_health_overview.dart](../../lib/features/dashboard/widgets/today_health_overview.dart)|修改|按实际功能守卫共享动作、首页贡献和后台取消边界|
|[lib/features/dashboard/widgets/today_showcase_header.dart](../../lib/features/dashboard/widgets/today_showcase_header.dart)|修改|按实际功能守卫共享动作、首页贡献和后台取消边界|
|[lib/features/data_center/application/body_metric_controller.dart](../../lib/features/data_center/application/body_metric_controller.dart)|修改|身体数据、签到与数据权利的独立写入和清除边界|
|[lib/features/data_center/application/body_metric_export_controller.dart](../../lib/features/data_center/application/body_metric_export_controller.dart)|修改|身体数据、签到与数据权利的独立写入和清除边界|
|[lib/features/data_center/data_center_page.dart](../../lib/features/data_center/data_center_page.dart)|修改|身体数据、签到与数据权利的独立写入和清除边界|
|[lib/features/growth/application/growth_evidence_controller.dart](../../lib/features/growth/application/growth_evidence_controller.dart)|修改|成长事实与报告派生受控，停用后撤销不产生新派生|
|[lib/features/growth/application/growth_metrics_controller.dart](../../lib/features/growth/application/growth_metrics_controller.dart)|修改|成长事实与报告派生受控，停用后撤销不产生新派生|
|[lib/features/growth/application/local_training_fact_sync.dart](../../lib/features/growth/application/local_training_fact_sync.dart)|修改|成长事实与报告派生受控，停用后撤销不产生新派生|
|[lib/features/growth/application/run_context_controller.dart](../../lib/features/growth/application/run_context_controller.dart)|修改|成长事实与报告派生受控，停用后撤销不产生新派生|
|[lib/features/growth/application/strength_primary_exercise_controller.dart](../../lib/features/growth/application/strength_primary_exercise_controller.dart)|修改|成长事实与报告派生受控，停用后撤销不产生新派生|
|[lib/features/growth/application/training_metrics_provider.dart](../../lib/features/growth/application/training_metrics_provider.dart)|修改|成长事实与报告派生受控，停用后撤销不产生新派生|
|[lib/features/guided_workout/presentation/guided_workout_player_page.dart](../../lib/features/guided_workout/presentation/guided_workout_player_page.dart)|修改|课程执行资源清理及与训练日志共享保存租约|
|[lib/features/meal_guide/application/meal_preference_controller.dart](../../lib/features/meal_guide/application/meal_preference_controller.dart)|修改|饮食偏好持久化、撤销和可等待调用方|
|[lib/features/meal_guide/meal_guide_page.dart](../../lib/features/meal_guide/meal_guide_page.dart)|修改|饮食偏好持久化、撤销和可等待调用方|
|[lib/features/motion_check/application/motion_image_analysis_controller.dart](../../lib/features/motion_check/application/motion_image_analysis_controller.dart)|修改|图片与分析结果的迟到取消和临时资源清理|
|[lib/features/onboarding/onboarding_page.dart](../../lib/features/onboarding/onboarding_page.dart)|修改|停用运动选择提示与原画像兼容|
|[lib/features/pet/application/daily_activity_sync_controller.dart](../../lib/features/pet/application/daily_activity_sync_controller.dart)|修改|宠物与每日活动写守卫、只读构建和订阅恢复|
|[lib/features/pet/application/pet_controller.dart](../../lib/features/pet/application/pet_controller.dart)|修改|宠物与每日活动写守卫、只读构建和订阅恢复|
|[lib/features/pilot_validation/application/pilot_validation_service.dart](../../lib/features/pilot_validation/application/pilot_validation_service.dart)|新增|验收页写入统一进入可测试服务边界|
|[lib/features/pilot_validation/pilot_validation_page.dart](../../lib/features/pilot_validation/pilot_validation_page.dart)|修改|验收页写入统一进入可测试服务边界|
|[lib/features/profile/application/achievement_controller.dart](../../lib/features/profile/application/achievement_controller.dart)|修改|健康导入、成就、日程的能力归属以及管理和历史入口|
|[lib/features/profile/application/health_data_deletion_coordinator.dart](../../lib/features/profile/application/health_data_deletion_coordinator.dart)|修改|健康导入、成就、日程的能力归属以及管理和历史入口|
|[lib/features/profile/application/health_data_gateway_contract.dart](../../lib/features/profile/application/health_data_gateway_contract.dart)|修改|健康导入、成就、日程的能力归属以及管理和历史入口|
|[lib/features/profile/application/health_data_gateway_io.dart](../../lib/features/profile/application/health_data_gateway_io.dart)|修改|健康导入、成就、日程的能力归属以及管理和历史入口|
|[lib/features/profile/application/health_sync_controller.dart](../../lib/features/profile/application/health_sync_controller.dart)|修改|健康导入归属、无损暂停、ACK 后原操作贯穿成长派生|
|[lib/features/profile/application/native_healthkit_bridge_io.dart](../../lib/features/profile/application/native_healthkit_bridge_io.dart)|修改|健康导入、成就、日程的能力归属以及管理和历史入口|
|[lib/features/profile/application/native_healthkit_bridge_stub.dart](../../lib/features/profile/application/native_healthkit_bridge_stub.dart)|修改|健康导入、成就、日程的能力归属以及管理和历史入口|
|[lib/features/profile/application/training_schedule_controller.dart](../../lib/features/profile/application/training_schedule_controller.dart)|修改|健康导入、成就、日程的能力归属以及管理和历史入口|
|[lib/features/profile/profile_page.dart](../../lib/features/profile/profile_page.dart)|修改|健康导入、成就、日程的能力归属以及管理和历史入口|
|[lib/features/race_prep/application/race_image_recognition_controller.dart](../../lib/features/race_prep/application/race_image_recognition_controller.dart)|修改|赛事动作与图片识别迟到结果的守卫|
|[lib/features/reminders/application/reminder_settings_controller.dart](../../lib/features/reminders/application/reminder_settings_controller.dart)|修改|可等待设置保存、失败恢复和分范围通知取消|
|[lib/features/reminders/training_reminder_page.dart](../../lib/features/reminders/training_reminder_page.dart)|修改|可等待设置保存、失败恢复和分范围通知取消|
|[lib/features/rhythm/application/body_rhythm_controller.dart](../../lib/features/rhythm/application/body_rhythm_controller.dart)|修改|停用时历史只读、快照与饮食记录写租约|
|[lib/features/self_use_acceptance/application/self_use_acceptance_service.dart](../../lib/features/self_use_acceptance/application/self_use_acceptance_service.dart)|新增|直接服务写守卫及保存失败回滚和准确提示|
|[lib/features/self_use_acceptance/self_use_acceptance_page.dart](../../lib/features/self_use_acceptance/self_use_acceptance_page.dart)|修改|直接服务写守卫及保存失败回滚和准确提示|
|[lib/features/training_log/application/training_log_controller.dart](../../lib/features/training_log/application/training_log_controller.dart)|修改|记录保存覆盖到刷新结束，核心数据删除保持可用|
|[lib/features/training_log/presentation/training_record_editor.dart](../../lib/features/training_log/presentation/training_record_editor.dart)|修改|记录保存覆盖到刷新结束，核心数据删除保持可用|
|[lib/features/training_plan/application/adjustment_proposal_controller.dart](../../lib/features/training_plan/application/adjustment_proposal_controller.dart)|修改|公共策略与来源元数据、待确认草稿及激活守卫|
|[lib/features/training_plan/application/four_week_plan_controller.dart](../../lib/features/training_plan/application/four_week_plan_controller.dart)|修改|公共策略与来源元数据、待确认草稿及激活守卫|
|[lib/features/training_plan/application/plan_adjustment_controller.dart](../../lib/features/training_plan/application/plan_adjustment_controller.dart)|修改|公共策略与来源元数据、待确认草稿及激活守卫|
|[lib/features/training_plan/application/plan_revision_controller.dart](../../lib/features/training_plan/application/plan_revision_controller.dart)|修改|公共策略与来源元数据、待确认草稿及激活守卫|
|[lib/features/training_plan/application/training_plan_generation_controller.dart](../../lib/features/training_plan/application/training_plan_generation_controller.dart)|修改|公共策略与来源元数据、待确认草稿及激活守卫|
|[lib/features/training_plan/workout_detail_page.dart](../../lib/features/training_plan/workout_detail_page.dart)|修改|公共策略与来源元数据、待确认草稿及激活守卫|
|[lib/features/weekly_report/weekly_report_page.dart](../../lib/features/weekly_report/weekly_report_page.dart)|修改|报告实际生成和保存边界受控，历史阅读独立|
|[lib/features/workout_player/application/workout_player_assist_controller.dart](../../lib/features/workout_player/application/workout_player_assist_controller.dart)|修改|执行计时与辅助资源清理、保存串行化和失败重试|
|[lib/features/workout_player/workout_player_page.dart](../../lib/features/workout_player/workout_player_page.dart)|修改|执行计时与辅助资源清理、保存串行化和失败重试|
|[lib/main.dart](../../lib/main.dart)|修改|先读取账号设置再初始化装配，显式触发可用业务初始化|
|[lib/plugins/application/feature_access.dart](../../lib/plugins/application/feature_access.dart)|新增|真实服务与来源操作接口、明确生命周期失效类型|
|[lib/plugins/application/feature_controller_binding.dart](../../lib/plugins/application/feature_controller_binding.dart)|新增|真实服务消费、运行时租约、来源/账号epoch和界面贡献|
|[lib/plugins/application/plugin_routes.dart](../../lib/plugins/application/plugin_routes.dart)|新增|真实服务消费、运行时租约、来源/账号epoch和界面贡献|
|[lib/plugins/application/plugin_runtime.dart](../../lib/plugins/application/plugin_runtime.dart)|新增|注册运行、依赖与提交锁、来源及账号 epoch、启停恢复|
|[lib/plugins/application/plugin_runtime_provider.dart](../../lib/plugins/application/plugin_runtime_provider.dart)|新增|真实服务消费、运行时租约、来源/账号epoch和界面贡献|
|[lib/plugins/application/sport_contribution_label.dart](../../lib/plugins/application/sport_contribution_label.dart)|新增|真实服务消费、运行时租约、来源/账号epoch和界面贡献|
|[lib/plugins/assembly/built_in_distribution.dart](../../lib/plugins/assembly/built_in_distribution.dart)|新增|内置发行组合与可测试运动工厂注入|
|[lib/plugins/core/feature_contribution.dart](../../lib/plugins/core/feature_contribution.dart)|新增|插件描述、依赖/版本校验和可清理生命周期|
|[lib/plugins/core/plugin_context.dart](../../lib/plugins/core/plugin_context.dart)|新增|插件描述、依赖/版本校验和可清理生命周期|
|[lib/plugins/core/plugin_core.dart](../../lib/plugins/core/plugin_core.dart)|新增|插件描述、依赖/版本校验和可清理生命周期|
|[lib/plugins/core/plugin_descriptor.dart](../../lib/plugins/core/plugin_descriptor.dart)|新增|插件描述、依赖/版本校验和可清理生命周期|
|[lib/plugins/core/plugin_exception.dart](../../lib/plugins/core/plugin_exception.dart)|新增|插件描述、依赖/版本校验和可清理生命周期|
|[lib/plugins/core/plugin_ref.dart](../../lib/plugins/core/plugin_ref.dart)|新增|插件描述、依赖/版本校验和可清理生命周期|
|[lib/plugins/core/plugin_registry.dart](../../lib/plugins/core/plugin_registry.dart)|新增|插件描述、依赖/版本校验和可清理生命周期|
|[lib/plugins/core/trainmate_plugin.dart](../../lib/plugins/core/trainmate_plugin.dart)|新增|插件描述、依赖/版本校验和可清理生命周期|
|[lib/plugins/features/built_in_features.dart](../../lib/plugins/features/built_in_features.dart)|新增|原33业务与新增核心管理的注册和服务归属|
|[lib/plugins/features/feature_service.dart](../../lib/plugins/features/feature_service.dart)|新增|原33业务与新增核心管理的注册和服务归属|
|[lib/plugins/history/core_history.dart](../../lib/plugins/history/core_history.dart)|新增|跨插件停用后仍可用的纯仓储历史读取|
|[lib/plugins/settings/plugin_settings.dart](../../lib/plugins/settings/plugin_settings.dart)|新增|账号级本机设置、版本解析、持久化与换域恢复|
|[lib/plugins/settings/plugin_settings_controller.dart](../../lib/plugins/settings/plugin_settings_controller.dart)|新增|账号级本机设置、版本解析、持久化与换域恢复|
|[lib/plugins/settings/plugin_settings_repository.dart](../../lib/plugins/settings/plugin_settings_repository.dart)|新增|账号级本机设置、版本解析、持久化与换域恢复|
|[lib/plugins/sports/built_in_sport_plugins.dart](../../lib/plugins/sports/built_in_sport_plugins.dart)|新增|四项运动、两项目标和康复的策略、共享模板与展示契约|
|[lib/plugins/sports/fat_loss_plugin.dart](../../lib/plugins/sports/fat_loss_plugin.dart)|新增|四项运动、两项目标和康复的策略、共享模板与展示契约|
|[lib/plugins/sports/general_fitness_plugin.dart](../../lib/plugins/sports/general_fitness_plugin.dart)|新增|四项运动、两项目标和康复的策略、共享模板与展示契约|
|[lib/plugins/sports/hyrox_plugin.dart](../../lib/plugins/sports/hyrox_plugin.dart)|新增|四项运动、两项目标和康复的策略、共享模板与展示契约|
|[lib/plugins/sports/marathon_plugin.dart](../../lib/plugins/sports/marathon_plugin.dart)|新增|四项运动、两项目标和康复的策略、共享模板与展示契约|
|[lib/plugins/sports/rehab_plugin.dart](../../lib/plugins/sports/rehab_plugin.dart)|新增|四项运动、两项目标和康复的策略、共享模板与展示契约|
|[lib/plugins/sports/shared_workout_templates.dart](../../lib/plugins/sports/shared_workout_templates.dart)|新增|四项运动、两项目标和康复的策略、共享模板与展示契约|
|[lib/plugins/sports/sport_capability_directory.dart](../../lib/plugins/sports/sport_capability_directory.dart)|新增|四项运动、两项目标和康复的策略、共享模板与展示契约|
|[lib/plugins/sports/sport_display_capabilities.dart](../../lib/plugins/sports/sport_display_capabilities.dart)|新增|四项运动、两项目标和康复的策略、共享模板与展示契约|
|[lib/plugins/sports/sport_plan_strategy.dart](../../lib/plugins/sports/sport_plan_strategy.dart)|新增|四项运动、两项目标和康复的策略、共享模板与展示契约|
|[lib/plugins/sports/sport_strategy_plugin.dart](../../lib/plugins/sports/sport_strategy_plugin.dart)|新增|四项运动、两项目标和康复的策略、共享模板与展示契约|
|[lib/plugins/sports/sport_workout_template.dart](../../lib/plugins/sports/sport_workout_template.dart)|新增|四项运动、两项目标和康复的策略、共享模板与展示契约|
|[lib/plugins/sports/strength_plugin.dart](../../lib/plugins/sports/strength_plugin.dart)|新增|四项运动、两项目标和康复的策略、共享模板与展示契约|
|[lib/plugins/sports/trail_running_plugin.dart](../../lib/plugins/sports/trail_running_plugin.dart)|新增|四项运动、两项目标和康复的策略、共享模板与展示契约|
|[lib/services/four_week_plan_generator.dart](../../lib/services/four_week_plan_generator.dart)|修改|委托运动策略并保留公共计划编译与来源记录|
|[lib/services/local_report_generation_coordinator.dart](../../lib/services/local_report_generation_coordinator.dart)|修改|报告服务生成/保存的真实插件守卫|
|[lib/services/local_storage_service.dart](../../lib/services/local_storage_service.dart)|修改|精确设置白名单与损坏原文档保留支持|
|[lib/services/plan_context_digest_service.dart](../../lib/services/plan_context_digest_service.dart)|修改|本地插件来源指纹与网络请求摘要分离|
|[lib/services/system_training_notification_service.dart](../../lib/services/system_training_notification_service.dart)|修改|分范围与代际调度、串行平台变更、旧任务清理隔离|
|[test/app/startup/trainflow_bootstrap_app_test.dart](../../test/app/startup/trainflow_bootstrap_app_test.dart)|修改|验证启动顺序、页面装配和路由集合兼容|
|[test/app/trainmate_visual_route_matrix_test.dart](../../test/app/trainmate_visual_route_matrix_test.dart)|修改|验证启动顺序、页面装配和路由集合兼容|
|[test/data/local/database_local_storage_service_test.dart](../../test/data/local/database_local_storage_service_test.dart)|修改|验证本地设置复用文档表且不产生云同步变更|
|[test/data/repositories/generated_training_plan_repository_test.dart](../../test/data/repositories/generated_training_plan_repository_test.dart)|修改|验证来源元数据与旧计划仓储兼容|
|[test/features/ai_center/application/ai_chat_controller_test.dart](../../test/features/ai_center/application/ai_chat_controller_test.dart)|修改|回归验证：复用 AI 服务和来源租约，拒绝迟到回复或产物写入|
|[test/features/auth/account_switch_coordinator_test.dart](../../test/features/auth/account_switch_coordinator_test.dart)|修改|回归验证：账号换域恢复、清理只执行一次及对应中文提示|
|[test/features/auth/auth_controller_test.dart](../../test/features/auth/auth_controller_test.dart)|修改|回归验证：账号换域恢复、清理只执行一次及对应中文提示|
|[test/features/capabilities/capabilities_page_test.dart](../../test/features/capabilities/capabilities_page_test.dart)|新增|回归验证：管理开关、依赖确认、失败恢复和核心历史只读|
|[test/features/capabilities/history_page_test.dart](../../test/features/capabilities/history_page_test.dart)|新增|回归验证：管理开关、依赖确认、失败恢复和核心历史只读|
|[test/features/capabilities/onboarding_capability_test.dart](../../test/features/capabilities/onboarding_capability_test.dart)|新增|回归验证：管理开关、依赖确认、失败恢复和核心历史只读|
|[test/features/cloud_sync/cloud_sync_coordinator_test.dart](../../test/features/cloud_sync/cloud_sync_coordinator_test.dart)|修改|回归验证：同步分页和提交受租约控制，保留游标、授权与待同步记录|
|[test/features/companion/application/companion_lifecycle_test.dart](../../test/features/companion/application/companion_lifecycle_test.dart)|新增|回归验证：伙伴消息与记忆写守卫、通知范围清理和单份订阅恢复|
|[test/features/companion/application/companion_notification_scheduler_test.dart](../../test/features/companion/application/companion_notification_scheduler_test.dart)|修改|验证伙伴提醒代际隔离及旧平台安排的停用清理|
|[test/features/daily_adjustment/application/daily_adjustment_controller_test.dart](../../test/features/daily_adjustment/application/daily_adjustment_controller_test.dart)|修改|回归验证：每日调整写入到刷新完成的生命周期保护|
|[test/features/daily_adjustment/application/daily_adjustment_training_bridge_test.dart](../../test/features/daily_adjustment/application/daily_adjustment_training_bridge_test.dart)|修改|回归验证：每日调整写入到刷新完成的生命周期保护|
|[test/features/dashboard/activity_import_training_bridge_test.dart](../../test/features/dashboard/activity_import_training_bridge_test.dart)|修改|回归验证：按实际功能守卫共享动作、首页贡献和后台取消边界|
|[test/features/dashboard/skill_execution_lock_training_bridge_test.dart](../../test/features/dashboard/skill_execution_lock_training_bridge_test.dart)|修改|回归验证：按实际功能守卫共享动作、首页贡献和后台取消边界|
|[test/features/dashboard/training_mvp_health_boundary_test.dart](../../test/features/dashboard/training_mvp_health_boundary_test.dart)|修改|验证真实停用失效识别与仓储错误继续上报|
|[test/features/data_center/application/body_metric_controller_test.dart](../../test/features/data_center/application/body_metric_controller_test.dart)|修改|回归验证：身体数据、签到与数据权利的独立写入和清除边界|
|[test/features/data_center/application/body_metric_export_controller_test.dart](../../test/features/data_center/application/body_metric_export_controller_test.dart)|修改|回归验证：身体数据、签到与数据权利的独立写入和清除边界|
|[test/features/data_center/application/body_metric_export_training_bridge_test.dart](../../test/features/data_center/application/body_metric_export_training_bridge_test.dart)|修改|回归验证：身体数据、签到与数据权利的独立写入和清除边界|
|[test/features/data_center/application/body_metric_training_bridge_test.dart](../../test/features/data_center/application/body_metric_training_bridge_test.dart)|修改|回归验证：身体数据、签到与数据权利的独立写入和清除边界|
|[test/features/growth/application/growth_evidence_health_deletion_test.dart](../../test/features/growth/application/growth_evidence_health_deletion_test.dart)|修改|回归验证：成长事实与报告派生受控，停用后撤销不产生新派生|
|[test/features/growth/application/local_training_fact_sync_test.dart](../../test/features/growth/application/local_training_fact_sync_test.dart)|修改|回归验证：成长事实与报告派生受控，停用后撤销不产生新派生|
|[test/features/meal_guide/application/meal_preference_controller_test.dart](../../test/features/meal_guide/application/meal_preference_controller_test.dart)|修改|回归验证：饮食偏好持久化、撤销和可等待调用方|
|[test/features/meal_guide/application/meal_preference_training_bridge_test.dart](../../test/features/meal_guide/application/meal_preference_training_bridge_test.dart)|修改|回归验证：饮食偏好持久化、撤销和可等待调用方|
|[test/features/motion_check/application/motion_image_analysis_controller_test.dart](../../test/features/motion_check/application/motion_image_analysis_controller_test.dart)|修改|回归验证：图片与分析结果的迟到取消和临时资源清理|
|[test/features/pet/application/pet_controller_test.dart](../../test/features/pet/application/pet_controller_test.dart)|修改|回归验证：宠物与每日活动写守卫、只读构建和订阅恢复|
|[test/features/profile/application/achievement_controller_test.dart](../../test/features/profile/application/achievement_controller_test.dart)|修改|回归验证：健康导入、成就、日程的能力归属以及管理和历史入口|
|[test/features/profile/application/achievement_training_bridge_test.dart](../../test/features/profile/application/achievement_training_bridge_test.dart)|修改|回归验证：健康导入、成就、日程的能力归属以及管理和历史入口|
|[test/features/profile/application/health_data_deletion_coordinator_test.dart](../../test/features/profile/application/health_data_deletion_coordinator_test.dart)|修改|回归验证：健康导入、成就、日程的能力归属以及管理和历史入口|
|[test/features/profile/application/health_data_gateway_io_test.dart](../../test/features/profile/application/health_data_gateway_io_test.dart)|修改|回归验证：健康导入、成就、日程的能力归属以及管理和历史入口|
|[test/features/profile/application/health_sync_controller_test.dart](../../test/features/profile/application/health_sync_controller_test.dart)|修改|验证前后台 ACK 迟到、重开、换账号和派生提交锁|
|[test/features/profile/application/training_schedule_controller_test.dart](../../test/features/profile/application/training_schedule_controller_test.dart)|修改|回归验证：健康导入、成就、日程的能力归属以及管理和历史入口|
|[test/features/profile/application/user_profile_training_bridge_test.dart](../../test/features/profile/application/user_profile_training_bridge_test.dart)|修改|回归验证：健康导入、成就、日程的能力归属以及管理和历史入口|
|[test/features/race_prep/official_race_result_test.dart](../../test/features/race_prep/official_race_result_test.dart)|修改|回归验证：赛事动作与图片识别迟到结果的守卫|
|[test/features/race_prep/race_image_recognition_test.dart](../../test/features/race_prep/race_image_recognition_test.dart)|修改|回归验证：赛事动作与图片识别迟到结果的守卫|
|[test/features/reminders/application/reminder_settings_controller_test.dart](../../test/features/reminders/application/reminder_settings_controller_test.dart)|修改|回归验证：可等待设置保存、失败恢复和分范围通知取消|
|[test/features/reminders/application/reminder_settings_training_bridge_test.dart](../../test/features/reminders/application/reminder_settings_training_bridge_test.dart)|修改|回归验证：可等待设置保存、失败恢复和分范围通知取消|
|[test/features/training_log/application/training_log_controller_test.dart](../../test/features/training_log/application/training_log_controller_test.dart)|修改|回归验证：记录保存覆盖到刷新结束，核心数据删除保持可用|
|[test/features/training_log/application/training_log_training_bridge_test.dart](../../test/features/training_log/application/training_log_training_bridge_test.dart)|修改|回归验证：记录保存覆盖到刷新结束，核心数据删除保持可用|
|[test/features/training_log/application/training_record_save_test.dart](../../test/features/training_log/application/training_record_save_test.dart)|修改|回归验证：记录保存覆盖到刷新结束，核心数据删除保持可用|
|[test/features/training_plan/application/four_week_plan_controller_test.dart](../../test/features/training_plan/application/four_week_plan_controller_test.dart)|修改|回归验证：公共策略与来源元数据、待确认草稿及激活守卫|
|[test/features/training_plan/application/plan_adjustment_controller_test.dart](../../test/features/training_plan/application/plan_adjustment_controller_test.dart)|修改|回归验证：公共策略与来源元数据、待确认草稿及激活守卫|
|[test/features/training_plan/application/plan_adjustment_training_bridge_test.dart](../../test/features/training_plan/application/plan_adjustment_training_bridge_test.dart)|修改|回归验证：公共策略与来源元数据、待确认草稿及激活守卫|
|[test/features/training_plan/application/training_plan_generation_lifecycle_test.dart](../../test/features/training_plan/application/training_plan_generation_lifecycle_test.dart)|新增|回归验证：公共策略与来源元数据、待确认草稿及激活守卫|
|[test/features/workout_player/application/workout_player_assist_training_bridge_test.dart](../../test/features/workout_player/application/workout_player_assist_training_bridge_test.dart)|修改|回归验证：执行计时与辅助资源清理、保存串行化和失败重试|
|[test/fixtures/plugins/README.md](../../test/fixtures/plugins/README.md)|新增|固定迁移前 249 场景期望与合成资料说明，约束业务等价|
|[test/fixtures/plugins/migration_golden.json](../../test/fixtures/plugins/migration_golden.json)|新增|固定迁移前 249 场景期望与合成资料说明，约束业务等价|
|[test/plugins/assembly/core_history_test.dart](../../test/plugins/assembly/core_history_test.dart)|新增|验证发行、路由、动态导航、历史和运行时恢复|
|[test/plugins/assembly/navigation_assembly_test.dart](../../test/plugins/assembly/navigation_assembly_test.dart)|新增|验证发行、路由、动态导航、历史和运行时恢复|
|[test/plugins/assembly/plugin_resource_recovery_test.dart](../../test/plugins/assembly/plugin_resource_recovery_test.dart)|新增|验证发行、路由、动态导航、历史和运行时恢复|
|[test/plugins/assembly/plugin_runtime_test.dart](../../test/plugins/assembly/plugin_runtime_test.dart)|新增|验证发行、路由、动态导航、历史和运行时恢复|
|[test/plugins/assembly/router_assembly_test.dart](../../test/plugins/assembly/router_assembly_test.dart)|新增|验证发行、路由、动态导航、历史和运行时恢复|
|[test/plugins/core/plugin_ref_test.dart](../../test/plugins/core/plugin_ref_test.dart)|新增|验证注册、依赖、版本、初始化失败和清理|
|[test/plugins/core/plugin_registry_test.dart](../../test/plugins/core/plugin_registry_test.dart)|新增|验证注册、依赖、版本、初始化失败和清理|
|[test/plugins/lifecycle/acceptance_service_lifecycle_test.dart](../../test/plugins/lifecycle/acceptance_service_lifecycle_test.dart)|新增|验证真实控制器停用、迟到结果、提交锁和数据权利|
|[test/plugins/lifecycle/health_data_lifecycle_test.dart](../../test/plugins/lifecycle/health_data_lifecycle_test.dart)|新增|验证真实控制器停用、迟到结果、提交锁和数据权利|
|[test/plugins/lifecycle/plan_execution_lifecycle_test.dart](../../test/plugins/lifecycle/plan_execution_lifecycle_test.dart)|新增|验证真实控制器停用、迟到结果、提交锁和数据权利|
|[test/plugins/lifecycle/report_lifecycle_test.dart](../../test/plugins/lifecycle/report_lifecycle_test.dart)|新增|验证真实控制器停用、迟到结果、提交锁和数据权利|
|[test/plugins/settings/plugin_settings_sqlite_test.dart](../../test/plugins/settings/plugin_settings_sqlite_test.dart)|新增|验证版本、原始坏文档、SQLite/SP与账号级设置恢复|
|[test/plugins/settings/plugin_settings_test.dart](../../test/plugins/settings/plugin_settings_test.dart)|新增|验证版本、原始坏文档、SQLite/SP与账号级设置恢复|
|[test/plugins/sports/all_sport_consumption_test.dart](../../test/plugins/sports/all_sport_consumption_test.dart)|新增|验证七类策略、来源消费、249黄金与持久化回滚|
|[test/plugins/sports/all_sport_plugins_test.dart](../../test/plugins/sports/all_sport_plugins_test.dart)|新增|验证七类策略、来源消费、249黄金与持久化回滚|
|[test/plugins/sports/marathon_consumption_test.dart](../../test/plugins/sports/marathon_consumption_test.dart)|新增|验证七类策略、来源消费、249黄金与持久化回滚|
|[test/plugins/sports/migration_cases.dart](../../test/plugins/sports/migration_cases.dart)|新增|验证七类策略、来源消费、249黄金与持久化回滚|
|[test/plugins/sports/migration_golden_test.dart](../../test/plugins/sports/migration_golden_test.dart)|新增|验证七类策略、来源消费、249黄金与持久化回滚|
|[test/plugins/sports/sport_display_consumption_test.dart](../../test/plugins/sports/sport_display_consumption_test.dart)|新增|验证七类策略、来源消费、249黄金与持久化回滚|
|[test/plugins/sports/sport_distribution_persistence_rollback_test.dart](../../test/plugins/sports/sport_distribution_persistence_rollback_test.dart)|新增|验证七类策略、来源消费、249黄金与持久化回滚|
|[test/plugins/sports/sport_distribution_rollback_test.dart](../../test/plugins/sports/sport_distribution_rollback_test.dart)|新增|验证七类策略、来源消费、249黄金与持久化回滚|
|[test/plugins/sports/sport_strategy_test.dart](../../test/plugins/sports/sport_strategy_test.dart)|新增|验证七类策略、来源消费、249黄金与持久化回滚|
|[test/services/system_training_notification_service_test.dart](../../test/services/system_training_notification_service_test.dart)|修改|验证训练提醒旧权限、时区、安排迟到时的新代资源保留|
|[test/widget_test.dart](../../test/widget_test.dart)|修改|验证启动顺序、页面装配和路由集合兼容|

依赖与配置核对：`pubspec.yaml`、`pubspec.lock`、`analysis_options.yaml`、iOS Podfile/lock、Xcode 工程/共享 scheme、Info.plist 与 entitlements 均与实施前快照逐字节一致。完整测试状态与已知限制见[实施与验收记录](2026-09-04-trainmate-plugin-implementation.md)。
