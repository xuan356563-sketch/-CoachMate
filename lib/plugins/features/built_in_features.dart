import '../core/plugin_core.dart';
import 'feature_service.dart';

class FeatureDefinition {
  const FeatureDefinition(
      {required this.directory,
      required this.id,
      required this.name,
      this.routes = const [],
      this.required = false,
      this.dependencies = const [],
      this.navigation});
  final String directory;
  final String id;
  final String name;
  final List<String> routes;
  final bool required;
  final List<String> dependencies;
  final NavigationContribution? navigation;
  List<FeatureContribution> get contributions => [
        for (var i = 0; i < routes.length; i++)
          RouteContribution(id: '$id.route.$i', label: name, path: routes[i]),
        if (navigation != null) navigation!,
        CardContribution(id: '$id.home', label: name, slot: 'dashboard'),
        FormContribution(id: '$id.actions', label: name, formId: directory),
        if (directory == 'weekly_report' || directory == 'growth')
          ReportContribution(
              id: '$id.saved_reports', label: name, reportId: directory),
      ];
}

/// 发行清单逐项覆盖真实 features 目录；测试直接与磁盘目录比较。
const builtInFeatures = <FeatureDefinition>[
  FeatureDefinition(directory: 'resource_library', id: 'feature.resource_library', name: '运动资源库', routes: ['/resources', '/resources/:id']),
  FeatureDefinition(
      directory: 'capabilities',
      id: 'core.capabilities',
      name: '运动与功能',
      routes: ['/capabilities'],
      required: true),
  FeatureDefinition(
      directory: 'activity_import',
      id: 'feature.activity_import',
      name: '活动导入',
      routes: ['/activity-import'],
      dependencies: ['feature.training_log']),
  FeatureDefinition(
      directory: 'ai_center',
      id: 'feature.ai_center',
      name: 'AI 中心',
      routes: ['/ai-center']),
  FeatureDefinition(
      directory: 'ai_coach',
      id: 'feature.ai_coach',
      name: 'AI 教练兼容入口',
      routes: ['/ai-coach']),
  FeatureDefinition(
      directory: 'auth',
      id: 'core.auth',
      name: '身份认证',
      routes: ['/auth-loading', '/login', '/account-switch'],
      required: true),
  FeatureDefinition(
      directory: 'cloud_sync',
      id: 'feature.cloud_sync',
      name: '云同步',
      routes: []),
  FeatureDefinition(
      directory: 'companion',
      id: 'feature.companion',
      name: '伙伴',
      routes: ['/companion'],
      navigation: NavigationContribution(
          id: 'feature.companion.navigation',
          label: '伙伴',
          routeId: '/companion',
          order: 2)),
  FeatureDefinition(
      directory: 'daily_adjustment',
      id: 'feature.daily_adjustment',
      name: '每日调整',
      routes: ['/daily-adjustment']),
  FeatureDefinition(
      directory: 'daily_check_in',
      id: 'feature.daily_check_in',
      name: '每日签到',
      routes: ['/daily-check-in']),
  FeatureDefinition(
      directory: 'dashboard',
      id: 'core.dashboard',
      name: '今日',
      routes: ['/dashboard'],
      required: true,
      navigation: NavigationContribution(
          id: 'core.dashboard.navigation',
          label: '今日',
          routeId: '/dashboard',
          order: 1)),
  FeatureDefinition(
      directory: 'data_center',
      id: 'feature.data_center',
      name: '身体数据',
      routes: ['/data-center']),
  FeatureDefinition(
      directory: 'data_rights',
      id: 'core.data_rights',
      name: '数据权利',
      routes: ['/data-privacy'],
      required: true),
  FeatureDefinition(
      directory: 'exercise_library',
      id: 'feature.exercise_library',
      name: '动作库',
      routes: ['/exercises'],
      navigation: NavigationContribution(
          id: 'feature.exercise_library.navigation',
          label: '动作库',
          routeId: '/exercises',
          order: 3)),
  FeatureDefinition(
      directory: 'first_run_onboarding',
      id: 'core.first_run_onboarding',
      name: '首次引导与会员',
      routes: [
        '/welcome/profile',
        '/welcome/training',
        '/welcome/cloud-consent',
        '/welcome/membership'
      ],
      required: true),
  FeatureDefinition(
      directory: 'growth',
      id: 'feature.growth',
      name: '成长',
      routes: ['/growth-evidence']),
  FeatureDefinition(
      directory: 'guided_workout',
      id: 'feature.guided_workout',
      name: '课程跟练',
      routes: [
        '/plans/jump-rope',
        '/plans/jump-rope/:courseId/session',
        '/exercises/circuits/:courseId/session'
      ],
      dependencies: [
        'feature.training_log'
      ]),
  FeatureDefinition(
      directory: 'knowledge_library',
      id: 'feature.knowledge_library',
      name: '知识库',
      routes: ['/knowledge']),
  FeatureDefinition(
      directory: 'meal_guide',
      id: 'feature.meal_guide',
      name: '饮食指导',
      routes: ['/meal-guide']),
  FeatureDefinition(
      directory: 'motion_check',
      id: 'feature.motion_check',
      name: '动作分析',
      routes: ['/motion-check', '/motion-check/running']),
  FeatureDefinition(
      directory: 'onboarding',
      id: 'core.onboarding',
      name: '训练画像',
      routes: ['/onboarding'],
      required: true),
  FeatureDefinition(
      directory: 'pet',
      id: 'feature.pet',
      name: '宠物',
      routes: ['/pet', '/pet/data']),
  FeatureDefinition(
      directory: 'pilot_validation',
      id: 'feature.pilot_validation',
      name: '试点验收',
      routes: ['/pilot-validation']),
  FeatureDefinition(
      directory: 'profile',
      id: 'core.profile',
      name: '我的',
      routes: ['/profile'],
      required: true,
      navigation: NavigationContribution(
          id: 'core.profile.navigation',
          label: '我的',
          routeId: '/profile',
          order: 4)),
  FeatureDefinition(
      directory: 'race_prep',
      id: 'feature.race_prep',
      name: '赛事',
      routes: ['/races']),
  FeatureDefinition(
      directory: 'rehab',
      id: 'support.rehab',
      name: '康复支持',
      routes: ['/rehab']),
  FeatureDefinition(
      directory: 'reminders',
      id: 'feature.reminders',
      name: '训练提醒',
      routes: ['/reminders']),
  FeatureDefinition(
      directory: 'rhythm',
      id: 'feature.rhythm',
      name: '身体节奏',
      routes: ['/rhythm-detail', '/progress-review']),
  FeatureDefinition(
      directory: 'self_use_acceptance',
      id: 'feature.self_use_acceptance',
      name: '自用验收',
      routes: ['/self-use-acceptance']),
  FeatureDefinition(
      directory: 'starter_program',
      id: 'feature.starter_program',
      name: '入门项目',
      routes: ['/starter-program', '/starter-graduation']),
  FeatureDefinition(
      directory: 'training_log',
      id: 'feature.training_log',
      name: '训练记录',
      routes: []),
  FeatureDefinition(
      directory: 'training_plan',
      id: 'feature.training_plan',
      name: '训练计划',
      routes: [
        '/plans',
        '/plans/generate',
        '/plans/:planId',
        '/plans/:planId/workouts/:workoutDayId',
      ],
      navigation: NavigationContribution(
          id: 'feature.training_plan.navigation',
          label: '计划',
          routeId: '/plans',
          order: 0)),
  FeatureDefinition(
      directory: 'user_insights',
      id: 'feature.user_insights',
      name: '个人洞察',
      routes: ['/user-insights']),
  FeatureDefinition(
      directory: 'weekly_report',
      id: 'feature.weekly_report',
      name: '周报',
      routes: ['/weekly-report']),
  FeatureDefinition(
      directory: 'workout_player',
      id: 'feature.workout_player',
      name: '训练播放器',
      routes: ['/workout-player'],
      dependencies: ['feature.training_log']),
];

class BuiltInFeaturePlugin extends TrainMatePlugin {
  BuiltInFeaturePlugin(this.feature, {this.delegate})
      : descriptor = PluginDescriptor(
          id: feature.id,
          type: feature.required
              ? PluginType.core
              : delegate?.descriptor.type ?? PluginType.feature,
          version: delegate?.descriptor.version ?? '1.0.0',
          name: feature.name,
          description: '内置${feature.name}与既有业务服务适配',
          isRequired: feature.required,
          skills: delegate?.descriptor.skills ?? const [],
          workflows: delegate?.descriptor.workflows ?? const [],
          dependencies: ['core.history', ...feature.dependencies],
          capabilities: [
            '${feature.id}.service',
            ...?delegate?.descriptor.capabilities
          ],
        );
  final FeatureDefinition feature;
  final TrainMatePlugin? delegate;
  @override
  final PluginDescriptor descriptor;
  @override
  Future<void> initialize(PluginContext context) async {
    await delegate?.initialize(context);
    context.registerCapability(
        '${feature.id}.service', FeatureService(context));
    for (final contribution in feature.contributions) {
      context.registerContribution(contribution);
    }
  }
}
