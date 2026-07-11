import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/profile/application/user_profile_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('通过资料控制器保存后训练状态同步资料完成标记和教练建议', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    final TrainingMvpState initialState = container.read(trainingMvpProvider);
    final UserProfile profile =
        container.read(userProfileControllerProvider).profile.copyWith(
              name: '桥接训练者',
              weeklyTrainingDays: 5,
            );

    container.read(userProfileControllerProvider.notifier).save(profile);

    final TrainingMvpState state = container.read(trainingMvpProvider);
    expect(state.profileCompleted, isTrue);
    expect(state.profile.name, '桥接训练者');
    expect(state.coachAdvices, isNot(initialState.coachAdvices));
    expect(state.coachAdvices, contains('你每周计划训练 5 天，建议至少保留 1 天完全恢复。'));
  });
}
