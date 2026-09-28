import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/meal_guide.dart';
import '../../../data/repositories/meal_preference_repository.dart';
import '../../../plugins/application/feature_access.dart';
import '../../../plugins/application/feature_controller_binding.dart';
import '../../../plugins/application/plugin_runtime_provider.dart';
import '../../../services/local_storage_service.dart';

/// 提供当前本地存储对应的照吃偏好仓库。
final mealPreferenceRepositoryProvider = Provider<MealPreferenceRepository>(
  (Ref ref) => PersistedMealPreferenceRepository(
    ref.watch(localStorageServiceProvider),
  ),
);

/// 管理独立的照吃场景偏好。
final mealPreferenceControllerProvider =
    NotifierProvider<MealPreferenceController, MealPreference>(
  MealPreferenceController.new,
);

/// 负责读取、保存和清除照吃场景偏好。
class MealPreferenceController extends Notifier<MealPreference> {
  @override
  MealPreference build() {
    bindFeatureController(ref, 'feature.meal_guide', 'controller', this);
    return ref.watch(mealPreferenceRepositoryProvider).getPreference();
  }

  /// 保存当前照吃场景。
  Future<void> saveScenario(MealScenario scenario) {
    final FeatureOperation operation =
        ref.read(featureAccessProvider).beginOperation('feature.meal_guide');
    return operation.commit(() async {
      final MealPreference saved =
          ref.read(mealPreferenceRepositoryProvider).savePreference(
                MealPreference(scenario: scenario),
              );
      await ref.read(localStorageServiceProvider).flush();
      state = saved;
    });
  }

  /// 清除偏好后重新读取仓库默认场景。
  Future<void> clear() async {
    final MealPreferenceRepository repository =
        ref.read(mealPreferenceRepositoryProvider);
    repository.clearPreference();
    await ref.read(localStorageServiceProvider).flush();
    state = repository.getPreference();
  }
}
