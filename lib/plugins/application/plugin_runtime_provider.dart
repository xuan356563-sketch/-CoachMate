import '../../data/models/user_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../data/repositories/generated_training_plan_repository.dart';
import '../../data/repositories/user_profile_repository.dart';
import '../../services/local_storage_service.dart';
import '../assembly/built_in_distribution.dart';
import '../core/plugin_core.dart';
import '../sports/sport_capability_directory.dart';
import 'feature_access.dart';
import 'plugin_runtime.dart';

final pluginRuntimeProvider = ChangeNotifierProvider<PluginRuntime>((ref) {
  final runtime = PluginRuntime(PluginRegistry(plugins: builtInDistribution()),
      compatibilityMode: true);
  registerPersistedSportLocks(
      runtime, () => ref.read(localStorageServiceProvider));
  return runtime;
});

final featureAccessProvider =
    Provider<FeatureAccess>((ref) => ref.watch(pluginRuntimeProvider));

/// 后台资源订阅此布尔值；只响应自身启停，避免重建整个业务聚合控制器。
final featureEnabledProvider = Provider.family<bool, String>((ref, id) => ref
    .watch(pluginRuntimeProvider.select((runtime) => runtime.isEnabled(id))));

/// 按钮等可写入口使用此布尔值；切换期间暂时不可写。
final featureWritableProvider = Provider.family<bool, String>((ref, id) => ref
    .watch(pluginRuntimeProvider.select((runtime) => runtime.isWritable(id))));

/// 只在停用预检时读取仓储，不启动会补写计划/日程的聚合控制器。
void registerPersistedSportLocks(
    PluginRuntime runtime, LocalStorageService Function() storage) {
  final definitions = SportCapabilityDirectory.builtIn()
      .strategies
      .map((s) => s.definition)
      .toList();
  for (final definition in definitions) {
    runtime.registerDisableLock(definition.pluginRef.id, () {
      final local = storage();
      final profile = PersistedUserProfileRepository(local).getProfile();
      if (profile.mainSports.contains(definition.sport)) {
        return '${definition.sport.label}仍是当前主运动或次运动，请先修改训练画像。';
      }
      final repository = GeneratedTrainingPlanRepository(local);
      final active = repository.getHistory().activeVersion;
      final plan = active?.plan ?? repository.getPlan();
      if (plan?.sportType == definition.sport ||
          (active?.pluginRefs
                  ?.any((ref) => ref.id == definition.pluginRef.id) ??
              false)) {
        return '当前有效计划仍使用${definition.sport.label}，请先切换有效计划。';
      }
      return null;
    });
  }
}
