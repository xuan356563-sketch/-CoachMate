import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/features/profile/application/user_profile_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  ProviderContainer createContainer(InMemoryLocalStorageService storage) {
    return ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
  }

  test('初始状态读取默认资料和未完成标记', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);

    final UserProfileState state =
        container.read(userProfileControllerProvider);

    expect(state.profile.name, '训练者');
    expect(state.isCompleted, isFalse);
  });

  test('保存使用仓库返回值更新状态', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);
    final UserProfile originalProfile =
        container.read(userProfileControllerProvider).profile;
    final UserProfile requestedProfile = originalProfile.copyWith(
      name: '新训练者',
      dailyAvailableMinutes: 30,
      updatedAt: DateTime(2000),
    );

    container
        .read(userProfileControllerProvider.notifier)
        .save(requestedProfile);

    final UserProfileState state =
        container.read(userProfileControllerProvider);
    expect(state.profile.name, '新训练者');
    expect(state.profile.dailyAvailableMinutes, 30);
    expect(state.profile.updatedAt, isNot(DateTime(2000)));
    expect(state.isCompleted, isTrue);
  });

  test('保存后的资料可在新容器中恢复', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer firstContainer = createContainer(storage);
    final UserProfile profile =
        firstContainer.read(userProfileControllerProvider).profile.copyWith(
              name: '持久化训练者',
              trainingGoal: '完成本地恢复验证',
            );

    firstContainer.read(userProfileControllerProvider.notifier).save(profile);
    firstContainer.dispose();

    final ProviderContainer restoredContainer = createContainer(storage);
    addTearDown(restoredContainer.dispose);
    final UserProfileState state =
        restoredContainer.read(userProfileControllerProvider);

    expect(state.profile.name, '持久化训练者');
    expect(state.profile.trainingGoal, '完成本地恢复验证');
    expect(state.isCompleted, isTrue);
  });

  test('清除后恢复默认资料和未完成标记', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);
    final UserProfile profile =
        container.read(userProfileControllerProvider).profile.copyWith(
              name: '待清除训练者',
            );

    container.read(userProfileControllerProvider.notifier).save(profile);
    container.read(userProfileControllerProvider.notifier).clear();

    final UserProfileState state =
        container.read(userProfileControllerProvider);
    expect(state.profile.name, '训练者');
    expect(state.isCompleted, isFalse);
  });

  test('旧 JSON 缺少新增字段时可恢复兼容资料', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final Map<String, dynamic> legacyProfile = Map<String, dynamic>.from(
      InMemoryUserProfileRepository.defaultProfile.toJson(),
    )
      ..remove('equipmentAccessType')
      ..remove('workerProfileType')
      ..remove('maxHeartRate');
    storage.saveJson(PersistedUserProfileRepository.storageKey, {
      'profileCompleted': true,
      'profile': legacyProfile,
    });
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);

    final UserProfileState state =
        container.read(userProfileControllerProvider);

    expect(state.isCompleted, isTrue);
    expect(state.profile.equipmentAccessType, EquipmentAccessType.gym);
    expect(state.profile.workerProfileType, WorkerProfileType.general);
    expect(state.profile.maxHeartRate, isNull);
  });
}
