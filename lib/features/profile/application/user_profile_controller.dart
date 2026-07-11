import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/user_profile.dart';
import '../../../data/repositories/user_profile_repository.dart';
import '../../../services/local_storage_service.dart';

/// 提供当前本地存储对应的用户资料仓库。
final userProfileRepositoryProvider = Provider<UserProfileRepository>(
  (Ref ref) => PersistedUserProfileRepository(
    ref.watch(localStorageServiceProvider),
  ),
);

/// 管理独立用户资料状态。
final userProfileControllerProvider =
    NotifierProvider<UserProfileController, UserProfileState>(
  UserProfileController.new,
);

/// 用户资料及其完成状态。
class UserProfileState {
  final UserProfile profile;
  final bool isCompleted;

  const UserProfileState({
    required this.profile,
    required this.isCompleted,
  });
}

/// 负责读取、保存和清除用户资料。
class UserProfileController extends Notifier<UserProfileState> {
  @override
  UserProfileState build() {
    return _readState();
  }

  /// 保存资料，并使用仓库实际返回的资料更新状态。
  void save(UserProfile profile) {
    final UserProfile savedProfile =
        ref.read(userProfileRepositoryProvider).saveProfile(profile);
    state = UserProfileState(
      profile: savedProfile,
      isCompleted: true,
    );
  }

  /// 清除资料后重新读取仓库中的默认状态。
  void clear() {
    final UserProfileRepository repository =
        ref.read(userProfileRepositoryProvider);
    repository.clearProfile();
    state = _readState();
  }

  UserProfileState _readState() {
    final UserProfileRepository repository =
        ref.read(userProfileRepositoryProvider);
    return UserProfileState(
      profile: repository.getProfile(),
      isCompleted: repository.isProfileCompleted(),
    );
  }
}
