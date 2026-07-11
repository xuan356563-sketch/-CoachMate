import '../models/user_profile.dart';
import '../../services/local_storage_service.dart';

abstract class UserProfileRepository {
  UserProfile getProfile();

  bool isProfileCompleted();

  UserProfile saveProfile(UserProfile profile);

  void clearProfile();
}

class InMemoryUserProfileRepository implements UserProfileRepository {
  static final UserProfile defaultProfile = UserProfile(
    id: 'user-local-demo',
    name: '训练者',
    gender: Gender.unknown,
    age: 32,
    heightCm: 172,
    weightKg: 68,
    trainingGoal: '提升耐力和力量基础',
    mainSports: const [MainSport.hyrox, MainSport.marathon],
    weeklyTrainingDays: 4,
    dailyAvailableMinutes: 45,
    injuryHistory: const ['膝盖偶发不适'],
    workScheduleType: WorkScheduleType.regularOffice,
    equipmentAccessType: EquipmentAccessType.gym,
    workerProfileType: WorkerProfileType.sedentaryOffice,
    createdAt: DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 1),
  );

  UserProfile _profile = defaultProfile;
  bool _profileCompleted = false;

  @override
  UserProfile getProfile() {
    return _profile;
  }

  @override
  bool isProfileCompleted() {
    return _profileCompleted;
  }

  @override
  UserProfile saveProfile(UserProfile profile) {
    _profile = profile.copyWith(updatedAt: DateTime.now());
    _profileCompleted = true;
    return _profile;
  }

  @override
  void clearProfile() {
    _profile = defaultProfile;
    _profileCompleted = false;
  }
}

class PersistedUserProfileRepository implements UserProfileRepository {
  static const String storageKey = 'trainflow.user_profile.v1';

  final LocalStorageService _storageService;
  UserProfile _profile = InMemoryUserProfileRepository.defaultProfile;
  bool _profileCompleted = false;

  PersistedUserProfileRepository(this._storageService) {
    _hydrate();
  }

  @override
  UserProfile getProfile() {
    return _profile;
  }

  @override
  bool isProfileCompleted() {
    return _profileCompleted;
  }

  @override
  UserProfile saveProfile(UserProfile profile) {
    _profile = profile.copyWith(updatedAt: DateTime.now());
    _profileCompleted = true;
    _persist();
    return _profile;
  }

  @override
  void clearProfile() {
    _profile = InMemoryUserProfileRepository.defaultProfile;
    _profileCompleted = false;
    _persist();
  }

  void _hydrate() {
    final Map<String, dynamic>? storedState =
        _storageService.readJson(storageKey);
    if (storedState == null) {
      return;
    }
    final Object? profileJson = storedState['profile'];
    if (profileJson is Map<String, dynamic>) {
      _profile = UserProfile.fromJson(profileJson);
      _profileCompleted = storedState.containsKey('profileCompleted')
          ? storedState['profileCompleted'] == true
          : true;
    } else {
      _profileCompleted = storedState['profileCompleted'] == true;
    }
  }

  void _persist() {
    _storageService.saveJson(storageKey, {
      'schemaVersion': 1,
      'profileCompleted': _profileCompleted,
      'profile': _profile.toJson(),
    });
  }
}
