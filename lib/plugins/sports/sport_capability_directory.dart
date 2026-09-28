import '../../data/models/user_profile.dart';
import '../core/plugin_core.dart';
import 'sport_plan_strategy.dart';
import 'built_in_sport_plugins.dart';
import 'sport_display_capabilities.dart';

/// 只读能力快照，可由宿主的已启用注册表构造；不读取设置或 Riverpod。
class SportCapabilityDirectory {
  SportCapabilityDirectory(Iterable<SportPlanStrategy> strategies)
      : strategies = List.unmodifiable(strategies) {
    final sports = <MainSport>{};
    final ids = <String>{};
    for (final strategy in this.strategies) {
      if (!sports.add(strategy.definition.sport) ||
          !ids.add(strategy.definition.pluginRef.id)) {
        throw const FormatException('运动策略身份重复');
      }
    }
  }
  final List<SportPlanStrategy> strategies;
  SportPlanStrategy? find(MainSport sport) {
    for (final strategy in strategies) {
      if (strategy.definition.sport == sport &&
          strategy.definition.localSupported) {
        return strategy;
      }
    }
    return null;
  }

  SportPlanStrategy require(MainSport sport) =>
      find(sport) ?? (throw StateError('${sport.label}策略未启用或不可用，请启用后重新生成。'));
  List<PluginRef>? resolveRefs(List<PluginRef>? previous) {
    if (previous == null || previous.isEmpty) return null;
    final current = <PluginRef>[];
    for (final ref in previous) {
      final matches = strategies.where((s) =>
          s.definition.pluginRef.id == ref.id && s.definition.localSupported);
      if (matches.isEmpty) return null;
      current.add(matches.single.definition.pluginRef);
    }
    return List.unmodifiable(current);
  }

  /// 公共跟练、周报与专项入口按声明消费，无需再次分支判断运动枚举。
  SportDisplayCapabilities? displayFor(MainSport sport) =>
      find(sport)?.definition.display;

  factory SportCapabilityDirectory.builtIn() => SportCapabilityDirectory(
      builtInSportPlugins().map((plugin) => plugin.strategy));

  /// 注册失败或停用的策略不会进入目录。
  factory SportCapabilityDirectory.fromRegistry(PluginRegistry registry) =>
      SportCapabilityDirectory([
        for (final definition in SportCapabilityDirectory.builtIn()
            .strategies
            .map((s) => s.definition))
          if (registry.readCapability<SportPlanStrategy>(
                  '${definition.pluginRef.id}.strategy')
              case final strategy?)
            strategy,
      ]);
}
