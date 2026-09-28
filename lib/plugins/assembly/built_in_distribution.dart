import '../core/plugin_core.dart';
import '../features/built_in_features.dart';
import '../features/motion_check_plugin.dart';
import '../features/resource_library_plugin.dart';
import '../features/feature_service.dart';
import '../sports/built_in_sport_plugins.dart';

/// 仅发行层可替换入口，用于故障与兼容回滚演练；界面不公开调试开关。
List<TrainMatePlugin> builtInDistribution(
    {Map<String, TrainMatePlugin> replacements = const {},
    List<TrainMatePlugin> Function()? sportPluginFactory}) {
  final sports = (sportPluginFactory ?? builtInSportPlugins)();
  final plugins = <TrainMatePlugin>[
    for (final entry in const {
      'core.storage': '本地存储',
      'core.identity': '身份与授权',
      'core.safety': '安全审计与用户确认',
      'core.navigation': '基础导航',
      'core.history': '历史读取',
    }.entries)
      _CorePlugin(entry.key, entry.value),
    for (final feature in builtInFeatures)
      BuiltInFeaturePlugin(feature,
          delegate: feature.id == 'support.rehab'
              ? sports.singleWhere((p) => p.descriptor.id == feature.id)
              : feature.id == 'feature.motion_check'
                  ? MotionCheckPlugin()
                  : feature.id == ResourceLibraryPlugin.id
                      ? ResourceLibraryPlugin()
                      : null),
    ...sports.where((p) => p.descriptor.id != 'support.rehab'),
  ];
  for (final id in replacements.keys) {
    if (!plugins.any((p) => p.descriptor.id == id) ||
        replacements[id]!.descriptor.id != id) {
      throw StateError('发行替换标识无效：$id');
    }
  }
  return List.unmodifiable(
      plugins.map((p) => replacements[p.descriptor.id] ?? p));
}

class _CorePlugin extends TrainMatePlugin {
  _CorePlugin(String id, String name)
      : descriptor = PluginDescriptor(
          id: id,
          type: PluginType.core,
          version: '1.0.0',
          name: name,
          description: '常驻$name服务入口',
          isRequired: true,
          capabilities: ['$id.service'],
          dependencies:
              id == 'core.history' ? ['core.storage', 'core.identity'] : [],
        );
  @override
  final PluginDescriptor descriptor;
  @override
  Future<void> initialize(PluginContext context) async {
    context.registerCapability(
        '${descriptor.id}.service', FeatureService(context));
    if (descriptor.id == 'core.history') {
      context.registerContribution(const RouteContribution(id: 'core.history.assessments', label: '基础评估历史', path: '/history/assessments'));
      context.registerContribution(const RouteContribution(
          id: 'core.history.running',
          label: '跑姿报告历史',
          path: '/history/running'));
      context.registerContribution(const RouteContribution(
          id: 'core.history.route', label: '历史记录', path: '/history'));
    }
  }
}
