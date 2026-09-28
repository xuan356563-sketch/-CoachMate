import '../core/plugin_core.dart';
import 'sport_plan_strategy.dart';

/// 独立运动、目标与支持插件共用登记过程，不承载专项算法。
abstract class SportStrategyPlugin extends TrainMatePlugin {
  SportStrategyPlugin(this.strategy);
  final SportPlanStrategy strategy;

  @override
  Future<void> initialize(PluginContext context) async {
    if (descriptor.ref != strategy.definition.pluginRef) {
      throw StateError('插件与运动策略来源不一致：${descriptor.id}');
    }
    context.registerCapability<SportPlanStrategy>(
        '${descriptor.id}.strategy', strategy);
    for (final contribution in strategy.definition.display?.contributions ??
        const <FeatureContribution>[]) {
      context.registerContribution(contribution);
    }
  }
}
