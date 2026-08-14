import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/pet_database_gateway.dart';
import '../../../data/models/daily_activity_summary.dart';
import '../../../data/repositories/daily_activity_summary_repository.dart';
import '../../../services/pet_goal_suggestion_service.dart';
import '../../profile/application/health_data_gateway_contract.dart';
import '../../profile/application/health_sync_controller.dart';

/// 启动层在 SQLite 宠物网关可用时覆盖；Web 和恢复模式保持为空。
final petDatabaseGatewayProvider = Provider<PetDatabaseGateway?>(
  (Ref ref) => null,
);

final dailyActivitySummaryRepositoryProvider =
    Provider<DailyActivitySummaryRepository?>((Ref ref) {
  final PetDatabaseGateway? database = ref.watch(petDatabaseGatewayProvider);
  return database == null ? null : DailyActivitySummaryRepository(database);
});

final petGoalSuggestionServiceProvider = Provider<PetGoalSuggestionService>(
  (Ref ref) => const PetGoalSuggestionService(),
);

final dailyActivitySyncClockProvider = Provider<DateTime Function()>(
  (Ref ref) => DateTime.now,
);

final dailyActivitySyncControllerProvider =
    AsyncNotifierProvider<DailyActivitySyncController, DailyActivitySyncState>(
  DailyActivitySyncController.new,
  retry: (int _, Object __) => null,
);

/// 每日活动摘要发生可结算变化时递增；不携带健康原文或授权状态。
final dailyActivityEnergyRefreshSignalProvider =
    NotifierProvider<DailyActivityEnergyRefreshSignal, int>(
  DailyActivityEnergyRefreshSignal.new,
);

class DailyActivityEnergyRefreshSignal extends Notifier<int> {
  @override
  int build() => 0;

  void requestRefresh() => state += 1;
}

class DailyActivitySyncState {
  DailyActivitySyncState({
    required this.supported,
    required this.syncing,
    required List<DailyActivitySummary> summaries,
    required this.suggestedGoals,
    required this.statusMessage,
  }) : summaries = List<DailyActivitySummary>.unmodifiable(summaries);

  final bool supported;
  final bool syncing;
  final List<DailyActivitySummary> summaries;
  final PetActivityGoals? suggestedGoals;
  final String statusMessage;

  DailyActivitySummary? get latest =>
      summaries.isEmpty ? null : summaries.first;
}

class DailyActivitySyncController
    extends AsyncNotifier<DailyActivitySyncState> {
  late HealthDataGateway _healthGateway;
  late DailyActivitySummaryRepository? _repository;
  late PetGoalSuggestionService _suggestionService;
  late DateTime Function() _clock;
  late String _athleteProfileId;

  @override
  Future<DailyActivitySyncState> build() async {
    _healthGateway = ref.watch(healthDataGatewayProvider);
    _repository = ref.watch(dailyActivitySummaryRepositoryProvider);
    _suggestionService = ref.watch(petGoalSuggestionServiceProvider);
    _clock = ref.watch(dailyActivitySyncClockProvider);
    _athleteProfileId = ref.watch(healthSyncAthleteIdProvider);
    ref.listen<int>(healthDailyActivityRefreshSignalProvider, (
      int? previous,
      int next,
    ) {
      if (previous == next) return;
      unawaited(refresh());
    });

    final DailyActivitySummaryRepository? repository = _repository;
    final List<DailyActivitySummary> summaries = repository == null
        ? const <DailyActivitySummary>[]
        : await repository.list(_athleteProfileId);
    return _buildState(
      summaries: summaries,
      syncing: false,
      statusMessage: _initialStatusMessage(summaries),
    );
  }

  Future<void> refresh({DateTime? start, DateTime? end}) async {
    final DailyActivitySyncState? current = state.value;
    if (current == null || current.syncing) return;
    final DailyActivitySummaryRepository? repository = _repository;
    if (repository == null) {
      state = AsyncData(_buildState(
        summaries: current.summaries,
        syncing: false,
        statusMessage: '宠物活动存储暂不可用，未写入任何数据。',
      ));
      return;
    }

    final DateTime queryEnd = end ?? _clock();
    final DateTime queryStart =
        start ?? queryEnd.subtract(const Duration(days: 30));
    if (queryStart.isAfter(queryEnd)) {
      state = AsyncData(_buildState(
        summaries: current.summaries,
        syncing: false,
        statusMessage: '活动摘要的开始时间不能晚于结束时间。',
      ));
      return;
    }

    state = AsyncData(_buildState(
      summaries: current.summaries,
      syncing: true,
      statusMessage: '正在同步每日活动摘要…',
    ));
    try {
      final List<HealthDailyActivitySummaryPayload> payloads =
          _healthGateway.isSupported
              ? List<HealthDailyActivitySummaryPayload>.from(
                  await _healthGateway.fetchDailyActivitySummaries(
                    start: queryStart,
                    end: queryEnd,
                  ),
                )
              : <HealthDailyActivitySummaryPayload>[];
      payloads.sort(
        (
          HealthDailyActivitySummaryPayload left,
          HealthDailyActivitySummaryPayload right,
        ) =>
            left.localDate.compareTo(right.localDate),
      );
      for (final HealthDailyActivitySummaryPayload payload in payloads) {
        final List<DailyActivitySummary> history =
            await repository.list(_athleteProfileId);
        await repository.mergeHealthKitSummary(
          _summaryFromPayload(
            payload,
            athleteProfileId: _athleteProfileId,
            goalSeed: _goalSeedForDate(history, payload.localDate),
          ),
        );
      }
      final List<DailyActivitySummary> summaries =
          await repository.list(_athleteProfileId);
      if (!ref.mounted) return;
      state = AsyncData(_buildState(
        summaries: summaries,
        syncing: false,
        statusMessage: !_healthGateway.isSupported
            ? '当前平台不支持 Apple 健康自动同步，可使用手动补录。'
            : payloads.isEmpty
                ? '本次未读取到每日活动摘要；系统不会据此推断具体授权状态。'
                : '已合并 ${payloads.length} 个自然日的活动摘要。',
      ));
      _requestEnergyRefresh();
    } catch (_) {
      if (!ref.mounted) return;
      final List<DailyActivitySummary> summaries =
          await repository.list(_athleteProfileId);
      state = AsyncData(_buildState(
        summaries: summaries,
        syncing: false,
        statusMessage: '每日活动摘要同步失败，请稍后重试。',
      ));
    }
  }

  Future<void> setManualValue(DailyActivityField field, num value) async {
    if (!_valueFields.contains(field)) {
      throw ArgumentError('该字段不是可补录的活动值。');
    }
    _validateManualNumber(field, value, goal: false);
    await _saveManualOverride(field, value, '已保存人工活动值。');
  }

  Future<void> setManualGoal(DailyActivityField field, num value) async {
    if (!_goalFields.contains(field)) {
      throw ArgumentError('该字段不是可调整的活动目标。');
    }
    _validateManualNumber(field, value, goal: true);
    await _saveManualOverride(field, value, '已确认个人活动目标。');
  }

  Future<void> restoreAutomatic(DailyActivityField field) async {
    final DailyActivitySummaryRepository repository = _requiredRepository();
    final DateTime now = _clock();
    final DailyActivitySummary summary = await _ensureTodaySummary(now);
    await repository.restoreAutomaticField(
      athleteProfileId: _athleteProfileId,
      localDate: summary.localDate,
      field: field,
      updatedAt: now,
    );
    if (!ref.mounted) return;
    await refresh(
      start: now.subtract(const Duration(days: 1)),
      end: now.add(const Duration(days: 1)),
    );
  }

  Future<void> _saveManualOverride(
    DailyActivityField field,
    num value,
    String statusMessage,
  ) async {
    final DailyActivitySummaryRepository repository = _requiredRepository();
    final DateTime now = _clock();
    final DailyActivitySummary summary = await _ensureTodaySummary(now);
    await repository.saveManualOverride(
      athleteProfileId: _athleteProfileId,
      localDate: summary.localDate,
      field: field,
      value: value,
      updatedAt: now,
    );
    if (!ref.mounted) return;
    final List<DailyActivitySummary> summaries =
        await repository.list(_athleteProfileId);
    state = AsyncData(_buildState(
      summaries: summaries,
      syncing: false,
      statusMessage: statusMessage,
    ));
    _requestEnergyRefresh();
  }

  void _requestEnergyRefresh() {
    ref
        .read(dailyActivityEnergyRefreshSignalProvider.notifier)
        .requestRefresh();
  }

  Future<DailyActivitySummary> _ensureTodaySummary(DateTime now) async {
    final DailyActivitySummaryRepository repository = _requiredRepository();
    final String localDate = _localDateKey(now);
    final DailyActivitySummary? existing = await repository.read(
      athleteProfileId: _athleteProfileId,
      localDate: localDate,
    );
    if (existing != null) return existing;

    final List<DailyActivitySummary> history =
        await repository.list(_athleteProfileId);
    final _GoalSeed seed = _goalSeedForDate(history, localDate);
    return repository.mergeHealthKitSummary(
      DailyActivitySummary(
        athleteProfileId: _athleteProfileId,
        localDate: localDate,
        timeZoneName: now.timeZoneName,
        timeZoneOffsetMinutes: now.timeZoneOffset.inMinutes,
        stepGoal: seed.goals.stepGoal,
        activeEnergyGoalKcal: seed.goals.activeEnergyGoalKcal,
        exerciseGoalMinutes: seed.goals.exerciseGoalMinutes,
        standGoalHours: seed.goals.standGoalHours,
        fieldSources: <DailyActivityField, ActivityFieldSource>{
          for (final DailyActivityField field in _valueFields)
            field: ActivityFieldSource.unavailable,
          for (final DailyActivityField field in _goalFields)
            field: seed.sourceFor(field),
        },
        syncedAt: now,
      ),
    );
  }

  DailyActivitySummaryRepository _requiredRepository() {
    final DailyActivitySummaryRepository? repository = _repository;
    if (repository == null) {
      throw StateError('宠物活动存储暂不可用，无法保存修改。');
    }
    return repository;
  }

  DailyActivitySyncState _buildState({
    required List<DailyActivitySummary> summaries,
    required bool syncing,
    required String statusMessage,
  }) {
    return DailyActivitySyncState(
      supported: _healthGateway.isSupported,
      syncing: syncing,
      summaries: summaries,
      suggestedGoals: _suggestionService.suggest(summaries),
      statusMessage: statusMessage,
    );
  }

  String _initialStatusMessage(List<DailyActivitySummary> summaries) {
    if (_repository == null) return '宠物活动存储暂不可用。';
    if (!_healthGateway.isSupported) {
      return '当前平台不支持 Apple 健康自动同步，可使用手动补录。';
    }
    return summaries.isEmpty ? '尚无每日活动摘要。' : '已读取每日活动摘要。';
  }
}

DailyActivitySummary _summaryFromPayload(
  HealthDailyActivitySummaryPayload payload, {
  required String athleteProfileId,
  required _GoalSeed goalSeed,
}) {
  final Set<String> available = payload.availableFields;
  bool has(String field, Object? value) =>
      value != null && available.contains(field);
  final bool hasActiveGoal = has(
    'activeEnergyGoalKcal',
    payload.activeEnergyGoalKcal,
  );
  final bool hasExerciseGoal = has(
    'exerciseGoalMinutes',
    payload.exerciseGoalMinutes,
  );
  final bool hasStandGoal = has('standGoalHours', payload.standGoalHours);

  return DailyActivitySummary(
    athleteProfileId: athleteProfileId,
    localDate: payload.localDate,
    timeZoneName: payload.timeZoneName,
    timeZoneOffsetMinutes: payload.timeZoneOffsetMinutes,
    steps: has('steps', payload.steps) ? payload.steps : null,
    stepGoal: goalSeed.goals.stepGoal,
    activeEnergyKcal: has('activeEnergyKcal', payload.activeEnergyKcal)
        ? payload.activeEnergyKcal
        : null,
    activeEnergyGoalKcal: hasActiveGoal
        ? payload.activeEnergyGoalKcal
        : goalSeed.goals.activeEnergyGoalKcal,
    exerciseMinutes: has('exerciseMinutes', payload.exerciseMinutes)
        ? payload.exerciseMinutes
        : null,
    exerciseGoalMinutes: hasExerciseGoal
        ? payload.exerciseGoalMinutes
        : goalSeed.goals.exerciseGoalMinutes,
    standHours:
        has('standHours', payload.standHours) ? payload.standHours : null,
    standGoalHours:
        hasStandGoal ? payload.standGoalHours : goalSeed.goals.standGoalHours,
    fieldSources: <DailyActivityField, ActivityFieldSource>{
      DailyActivityField.steps: has('steps', payload.steps)
          ? ActivityFieldSource.healthKit
          : ActivityFieldSource.unavailable,
      DailyActivityField.stepGoal:
          goalSeed.sourceFor(DailyActivityField.stepGoal),
      DailyActivityField.activeEnergyKcal:
          has('activeEnergyKcal', payload.activeEnergyKcal)
              ? ActivityFieldSource.healthKit
              : ActivityFieldSource.unavailable,
      DailyActivityField.activeEnergyGoalKcal: hasActiveGoal
          ? ActivityFieldSource.healthKit
          : goalSeed.sourceFor(DailyActivityField.activeEnergyGoalKcal),
      DailyActivityField.exerciseMinutes:
          has('exerciseMinutes', payload.exerciseMinutes)
              ? ActivityFieldSource.healthKit
              : ActivityFieldSource.unavailable,
      DailyActivityField.exerciseGoalMinutes: hasExerciseGoal
          ? ActivityFieldSource.healthKit
          : goalSeed.sourceFor(DailyActivityField.exerciseGoalMinutes),
      DailyActivityField.standHours: has('standHours', payload.standHours)
          ? ActivityFieldSource.healthKit
          : ActivityFieldSource.unavailable,
      DailyActivityField.standGoalHours: hasStandGoal
          ? ActivityFieldSource.healthKit
          : goalSeed.sourceFor(DailyActivityField.standGoalHours),
    },
    syncedAt: payload.syncedAt,
  );
}

_GoalSeed _goalSeedForDate(
  List<DailyActivitySummary> history,
  String localDate,
) {
  final List<DailyActivitySummary> eligible = history
      .where((DailyActivitySummary item) =>
          item.localDate.compareTo(localDate) <= 0)
      .toList()
    ..sort(
      (DailyActivitySummary left, DailyActivitySummary right) =>
          right.localDate.compareTo(left.localDate),
    );
  final DailyActivitySummary? latest = eligible.isEmpty ? null : eligible.first;

  ({num value, ActivityFieldSource source}) valueFor(
    DailyActivityField field,
    num? value,
    num fallback,
  ) {
    final ActivityFieldSource source =
        latest?.sourceFor(field) ?? ActivityFieldSource.unavailable;
    if (value != null &&
        (source == ActivityFieldSource.manualOverride ||
            source == ActivityFieldSource.derivedGoal)) {
      return (value: value, source: source);
    }
    return (value: fallback, source: ActivityFieldSource.derivedGoal);
  }

  final ({num value, ActivityFieldSource source}) steps = valueFor(
    DailyActivityField.stepGoal,
    latest?.stepGoal,
    PetGoalSuggestionService.defaultGoals.stepGoal,
  );
  final ({num value, ActivityFieldSource source}) stand = valueFor(
    DailyActivityField.standGoalHours,
    latest?.standGoalHours,
    PetGoalSuggestionService.defaultGoals.standGoalHours,
  );
  final ({num value, ActivityFieldSource source}) exercise = valueFor(
    DailyActivityField.exerciseGoalMinutes,
    latest?.exerciseGoalMinutes,
    PetGoalSuggestionService.defaultGoals.exerciseGoalMinutes,
  );
  final ({num value, ActivityFieldSource source}) active = valueFor(
    DailyActivityField.activeEnergyGoalKcal,
    latest?.activeEnergyGoalKcal,
    PetGoalSuggestionService.defaultGoals.activeEnergyGoalKcal,
  );
  return _GoalSeed(
    goals: PetActivityGoals(
      stepGoal: steps.value.toInt(),
      standGoalHours: stand.value.toInt(),
      exerciseGoalMinutes: exercise.value.toInt(),
      activeEnergyGoalKcal: active.value.toDouble(),
    ),
    sources: <DailyActivityField, ActivityFieldSource>{
      DailyActivityField.stepGoal: steps.source,
      DailyActivityField.standGoalHours: stand.source,
      DailyActivityField.exerciseGoalMinutes: exercise.source,
      DailyActivityField.activeEnergyGoalKcal: active.source,
    },
  );
}

class _GoalSeed {
  const _GoalSeed({
    required this.goals,
    required this.sources,
  });

  final PetActivityGoals goals;
  final Map<DailyActivityField, ActivityFieldSource> sources;

  ActivityFieldSource sourceFor(DailyActivityField field) =>
      sources[field] ?? ActivityFieldSource.derivedGoal;
}

const Set<DailyActivityField> _valueFields = <DailyActivityField>{
  DailyActivityField.steps,
  DailyActivityField.activeEnergyKcal,
  DailyActivityField.exerciseMinutes,
  DailyActivityField.standHours,
};

const Set<DailyActivityField> _goalFields = <DailyActivityField>{
  DailyActivityField.stepGoal,
  DailyActivityField.activeEnergyGoalKcal,
  DailyActivityField.exerciseGoalMinutes,
  DailyActivityField.standGoalHours,
};

const Set<DailyActivityField> _integerFields = <DailyActivityField>{
  DailyActivityField.steps,
  DailyActivityField.stepGoal,
  DailyActivityField.exerciseMinutes,
  DailyActivityField.exerciseGoalMinutes,
  DailyActivityField.standHours,
  DailyActivityField.standGoalHours,
};

void _validateManualNumber(
  DailyActivityField field,
  num value, {
  required bool goal,
}) {
  if (!value.isFinite || value < 0 || (goal && value <= 0)) {
    throw ArgumentError(goal ? '活动目标必须大于零。' : '活动值不能小于零。');
  }
  if (_integerFields.contains(field) &&
      value.roundToDouble() != value.toDouble()) {
    throw ArgumentError('该活动字段只接受整数。');
  }
}

String _localDateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
