import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/meal_guide.dart';
import '../../../data/repositories/meal_preference_repository.dart';
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
    return ref.watch(mealPreferenceRepositoryProvider).getPreference();
  }

  /// 保存当前照吃场景。
  void saveScenario(MealScenario scenario) {
    state = ref.read(mealPreferenceRepositoryProvider).savePreference(
          MealPreference(scenario: scenario),
        );
  }

  /// 清除偏好后重新读取仓库默认场景。
  void clear() {
    final MealPreferenceRepository repository =
        ref.read(mealPreferenceRepositoryProvider);
    repository.clearPreference();
    state = repository.getPreference();
  }
}
