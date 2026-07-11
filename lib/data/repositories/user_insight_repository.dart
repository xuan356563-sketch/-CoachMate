import '../models/user_insight.dart';
import '../models/user_profile.dart';
import '../../services/local_storage_service.dart';

abstract class UserInsightRepository {
  UserInsightTableState getTableState();

  UserInsightTableState saveWeeklySnapshot({
    required UserProfile profile,
    required List<ProfileEvent> profileEvents,
    required List<UserProfileInsight> userProfiles,
    required List<PredictionLog> predictionLogs,
  });

  void clearSnapshots();
}

class PersistedUserInsightRepository implements UserInsightRepository {
  static const String storageKey = 'trainflow.user_insight_tables.v1';
  static const int _maxWeeklyTasks = 12;

  final LocalStorageService _storageService;
  UserInsightTableState _state = const UserInsightTableState.empty();

  PersistedUserInsightRepository(this._storageService) {
    _hydrate();
  }

  @override
  UserInsightTableState getTableState() {
    return _state;
  }

  @override
  UserInsightTableState saveWeeklySnapshot({
    required UserProfile profile,
    required List<ProfileEvent> profileEvents,
    required List<UserProfileInsight> userProfiles,
    required List<PredictionLog> predictionLogs,
  }) {
    final DateTime now = DateTime.now();
    final String weekLabel = _weekLabel(now);
    final UserInsightWeeklyTask task = UserInsightWeeklyTask(
      id: 'user-insight-task-${now.millisecondsSinceEpoch}',
      weekLabel: weekLabel,
      generatedAt: now,
      profileEventCount: profileEvents.length,
      userProfileCount: userProfiles.length,
      predictionLogCount: predictionLogs.length,
      statusLabel: '已生成',
    );
    final List<UserInsightWeeklyTask> weeklyTasks = [
      task,
      ..._state.weeklyTasks.where(
        (UserInsightWeeklyTask item) => item.weekLabel != weekLabel,
      ),
    ];
    if (weeklyTasks.length > _maxWeeklyTasks) {
      weeklyTasks.removeRange(_maxWeeklyTasks, weeklyTasks.length);
    }

    _state = UserInsightTableState(
      profileSnapshot: profile,
      profileEvents: List<ProfileEvent>.unmodifiable(profileEvents),
      userProfiles: List<UserProfileInsight>.unmodifiable(userProfiles),
      predictionLogs: List<PredictionLog>.unmodifiable(predictionLogs),
      weeklyTasks: List<UserInsightWeeklyTask>.unmodifiable(weeklyTasks),
    );
    _persist();
    return _state;
  }

  @override
  void clearSnapshots() {
    _state = const UserInsightTableState.empty();
    _persist();
  }

  void _hydrate() {
    final Map<String, dynamic>? storedState =
        _storageService.readJson(storageKey);
    if (storedState == null) {
      return;
    }
    _state = UserInsightTableState.fromJson(storedState);
  }

  void _persist() {
    _storageService.saveJson(storageKey, {
      'schemaVersion': 1,
      ..._state.toJson(),
    });
  }

  String _weekLabel(DateTime date) {
    final DateTime weekStart = DateTime(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(days: date.weekday - 1));
    final DateTime weekEnd = weekStart.add(const Duration(days: 6));
    return '${weekStart.month}/${weekStart.day} - ${weekEnd.month}/${weekEnd.day}';
  }
}
