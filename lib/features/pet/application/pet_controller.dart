import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/pet_database_gateway.dart';
import '../../../data/models/daily_activity_summary.dart';
import '../../../data/models/daily_adjustment.dart';
import '../../../data/models/pet.dart';
import '../../../data/models/training_log.dart';
import '../../../data/repositories/daily_activity_summary_repository.dart';
import '../../../data/repositories/daily_context_repository.dart';
import '../../../data/repositories/pet_repository.dart';
import '../../../data/repositories/training_log_repository.dart';
import '../../../services/local_storage_service.dart';
import '../../../services/pet_energy_calculator.dart';
import '../../daily_adjustment/application/daily_adjustment_controller.dart';
import '../../profile/application/health_sync_controller.dart';
import '../../training_log/application/training_log_controller.dart';
import 'daily_activity_sync_controller.dart';
import 'pet_training_bridge.dart';

enum PetStateStatus {
  needsFirstEgg,
  ready,
  storageUnavailable,
  readOnly,
}

/// 一次可由界面消费的正差额结算。
class PetPendingSettlement {
  const PetPendingSettlement({
    required this.localDate,
    required this.result,
  });

  final String localDate;
  final PetSettlementResult result;

  String? get recipientPetId => result.recipientPetId;
  int get calculatedTotal => result.calculatedTotal;
  int get awardedTotal => result.awardedTotal;
  int get awardedDelta => result.awardedDelta;
}

/// 结算使用的当前自然日与时区上下文。
///
/// 测试可以覆盖该 Provider，生产环境则只在调用瞬间读取系统本地时间。
class PetLocalDayContext {
  const PetLocalDayContext({
    required this.now,
    required this.localDate,
    required this.timeZoneName,
    required this.timeZoneOffsetMinutes,
  });

  factory PetLocalDayContext.systemNow() {
    final DateTime now = DateTime.now();
    return PetLocalDayContext(
      now: now,
      localDate: _localDateKey(now),
      timeZoneName: now.timeZoneName,
      timeZoneOffsetMinutes: now.timeZoneOffset.inMinutes,
    );
  }

  final DateTime now;
  final String localDate;
  final String timeZoneName;
  final int timeZoneOffsetMinutes;
}

final petLocalDayContextProvider = Provider<PetLocalDayContext Function()>(
  (Ref ref) => PetLocalDayContext.systemNow,
);

final petControllerProvider = AsyncNotifierProvider<PetController, PetState>(
  PetController.new,
  retry: (int _, Object __) => null,
);

class PetState {
  PetState({
    required this.status,
    required this.profile,
    required this.activeCompanion,
    required this.todayActivitySummary,
    required this.todayEnergy,
    required List<PetDailyEnergy> energyHistory,
    required this.pendingSettlement,
    required this.statusMessage,
  }) : energyHistory = List<PetDailyEnergy>.unmodifiable(energyHistory);

  factory PetState.needsFirstEgg() => PetState(
        status: PetStateStatus.needsFirstEgg,
        profile: null,
        activeCompanion: null,
        todayActivitySummary: null,
        todayEnergy: null,
        energyHistory: const <PetDailyEnergy>[],
        pendingSettlement: null,
        statusMessage: '选择第一颗伙伴蛋后，日常活动和训练才会开始积累能量。',
      );

  factory PetState.storageUnavailable({String? message}) => PetState(
        status: PetStateStatus.storageUnavailable,
        profile: null,
        activeCompanion: null,
        todayActivitySummary: null,
        todayEnergy: null,
        energyHistory: const <PetDailyEnergy>[],
        pendingSettlement: null,
        statusMessage: message ?? '宠物本地存储暂不可用，未写入任何养成数据。',
      );

  factory PetState.readOnly() => PetState(
        status: PetStateStatus.readOnly,
        profile: null,
        activeCompanion: null,
        todayActivitySummary: null,
        todayEnergy: null,
        energyHistory: const <PetDailyEnergy>[],
        pendingSettlement: null,
        statusMessage: '当前处于本地数据只读恢复状态，暂不能结算或切换伙伴。',
      );

  final PetStateStatus status;
  final PetProfile? profile;
  final PetCompanion? activeCompanion;
  final DailyActivitySummary? todayActivitySummary;
  final PetDailyEnergy? todayEnergy;
  final List<PetDailyEnergy> energyHistory;
  final PetPendingSettlement? pendingSettlement;
  final String statusMessage;

  PetState copyWith({
    PetStateStatus? status,
    Object? profile = _petStateUnchanged,
    Object? activeCompanion = _petStateUnchanged,
    Object? todayActivitySummary = _petStateUnchanged,
    Object? todayEnergy = _petStateUnchanged,
    List<PetDailyEnergy>? energyHistory,
    Object? pendingSettlement = _petStateUnchanged,
    String? statusMessage,
  }) {
    return PetState(
      status: status ?? this.status,
      profile: identical(profile, _petStateUnchanged)
          ? this.profile
          : profile as PetProfile?,
      activeCompanion: identical(activeCompanion, _petStateUnchanged)
          ? this.activeCompanion
          : activeCompanion as PetCompanion?,
      todayActivitySummary: identical(todayActivitySummary, _petStateUnchanged)
          ? this.todayActivitySummary
          : todayActivitySummary as DailyActivitySummary?,
      todayEnergy: identical(todayEnergy, _petStateUnchanged)
          ? this.todayEnergy
          : todayEnergy as PetDailyEnergy?,
      energyHistory: energyHistory ?? this.energyHistory,
      pendingSettlement: identical(pendingSettlement, _petStateUnchanged)
          ? this.pendingSettlement
          : pendingSettlement as PetPendingSettlement?,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}

const Object _petStateUnchanged = Object();

class PetController extends AsyncNotifier<PetState> {
  static const int _energyModelVersion = 1;
  static const int _maximumTrainingLogs = 200;
  static const int _maximumAppliedDecisionDays = 90;

  final PetEnergyCalculator _energyCalculator = const PetEnergyCalculator();
  final PetTrainingBridge _trainingBridge = const PetTrainingBridge();

  late PetRepository _petRepository;
  late DailyActivitySummaryRepository _activityRepository;
  late TrainingLogRepository _trainingLogRepository;
  late DailyContextRepository _dailyContextRepository;
  late PetLocalDayContext Function() _localDayContext;
  late String _athleteProfileId;
  bool _hasDatabase = false;

  @override
  Future<PetState> build() async {
    final LocalStorageService storage = ref.watch(localStorageServiceProvider);
    final PetDatabaseGateway? database = ref.watch(petDatabaseGatewayProvider);
    if (database == null) {
      return storage is ReadOnlyRecoveryLocalStorageService
          ? PetState.readOnly()
          : PetState.storageUnavailable();
    }

    _petRepository = PetRepository(database);
    _activityRepository = DailyActivitySummaryRepository(database);
    _trainingLogRepository = ref.watch(trainingLogRepositoryProvider);
    _dailyContextRepository = ref.watch(dailyContextRepositoryProvider);
    _localDayContext = ref.watch(petLocalDayContextProvider);
    _athleteProfileId = ref.watch(healthSyncAthleteIdProvider);
    _hasDatabase = true;
    ref.listen<int>(dailyActivityEnergyRefreshSignalProvider, (
      int? previous,
      int next,
    ) {
      if (previous == next) return;
      unawaited(refreshToday());
    });

    try {
      final PetProfile? profile =
          await _petRepository.loadProfile(_athleteProfileId);
      if (profile?.activePetId == null) return PetState.needsFirstEgg();
      final PetPendingSettlement? pending =
          await _reconcileKnownDatesFor(profile!);
      return _loadReadyState(
        pendingSettlement: pending,
        statusMessage:
            pending == null ? '伙伴状态已就绪。' : '已补发 ${pending.awardedDelta} 点伙伴能量。',
      );
    } catch (_) {
      return PetState.storageUnavailable(
        message: '宠物本地数据读取失败，训练和每日调整仍可继续使用。',
      );
    }
  }

  Future<void> chooseFirstEgg(PetSpecies species) async {
    if (!_hasDatabase) return;
    final PetLocalDayContext context = _localDayContext();
    final DateTime now = context.now;
    final String petId =
        'pet-$_athleteProfileId-${species.id}-${now.toUtc().microsecondsSinceEpoch}';
    try {
      await _petRepository.chooseFirstEgg(
        PetFirstEggWrite(
          companion: PetCollectionWrite(
            petId: petId,
            athleteProfileId: _athleteProfileId,
            species: species,
            nickname: _defaultNickname(species),
            unlockedAt: now,
            bornAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        ),
      );
      final PetProfile profile =
          (await _petRepository.loadProfile(_athleteProfileId))!;
      final PetPendingSettlement? pending =
          await _reconcileKnownDatesFor(profile);
      if (!ref.mounted) return;
      state = AsyncData(
        await _loadReadyState(
          pendingSettlement: pending,
          statusMessage: '${_defaultNickname(species)}已成为你的训练伙伴。',
        ),
      );
    } catch (error) {
      _setOperationFailure('首蛋选择失败，请稍后重试。');
      rethrow;
    }
  }

  /// 核对当前自然日；异常只落到宠物状态，不向训练业务抛出。
  Future<void> refreshToday() async {
    if (!_hasDatabase) return;
    try {
      final PetProfile? profile =
          await _petRepository.loadProfile(_athleteProfileId);
      if (profile?.activePetId == null) {
        if (ref.mounted) state = AsyncData(PetState.needsFirstEgg());
        return;
      }
      final PetLocalDayContext context = _localDayContext();
      final List<TrainingLog> logs = _limitedTrainingLogs();
      final List<AppliedDailyDecisionFact> decisions =
          _limitedAppliedDecisions();
      final List<PetDailyEnergy> existing =
          await _petRepository.listDailyEnergy(
        athleteProfileId: _athleteProfileId,
      );
      final PetDailyEnergy? oldLedger =
          _energyForDate(existing, context.localDate);
      final DailyActivitySummary? summary = await _activityRepository.read(
        athleteProfileId: _athleteProfileId,
        localDate: context.localDate,
      );
      final PetSettlementResult result = await _settleDate(
        profile: profile!,
        localDate: context.localDate,
        summary: summary,
        oldLedger: oldLedger,
        logs: logs,
        decisions: decisions,
        currentContext: context,
      );
      if (!ref.mounted) return;
      final PetPendingSettlement? pending = result.awardedDelta > 0
          ? PetPendingSettlement(
              localDate: context.localDate,
              result: result,
            )
          : state.value?.pendingSettlement;
      state = AsyncData(
        await _loadReadyState(
          pendingSettlement: pending,
          statusMessage: result.awardedDelta > 0
              ? '今日伙伴能量增加 ${result.awardedDelta} 点。'
              : '今日伙伴能量已核对，没有重复发放。',
        ),
      );
    } catch (_) {
      _setOperationFailure('宠物能量刷新失败，训练记录和每日调整仍已保留。');
    }
  }

  /// 对摘要、训练事实和恢复事实的日期并集执行幂等补算。
  Future<void> reconcileKnownDates() async {
    if (!_hasDatabase) return;
    try {
      final PetProfile? profile =
          await _petRepository.loadProfile(_athleteProfileId);
      if (profile?.activePetId == null) {
        if (ref.mounted) state = AsyncData(PetState.needsFirstEgg());
        return;
      }
      final PetPendingSettlement? newPending =
          await _reconcileKnownDatesFor(profile!);
      if (!ref.mounted) return;
      state = AsyncData(
        await _loadReadyState(
          pendingSettlement: newPending ?? state.value?.pendingSettlement,
          statusMessage: newPending == null
              ? '已核对历史活动与训练记录，没有重复发放。'
              : '已补发 ${newPending.awardedDelta} 点伙伴能量。',
        ),
      );
    } catch (_) {
      _setOperationFailure('宠物历史能量补算失败，将在下次刷新时重试。');
    }
  }

  Future<void> switchActivePet(String petId) async {
    if (!_hasDatabase) return;
    final String normalized = petId.trim();
    if (normalized.isEmpty) throw ArgumentError('宠物编号不能为空');
    try {
      await _petRepository.switchActivePet(
        athleteProfileId: _athleteProfileId,
        petId: normalized,
        updatedAt: _localDayContext().now,
      );
      await refreshToday();
    } catch (error) {
      _setOperationFailure('伙伴切换失败，请稍后重试。');
      rethrow;
    }
  }

  void acknowledgeSettlement() {
    final PetState? current = state.value;
    if (current == null || current.pendingSettlement == null) return;
    state = AsyncData(current.copyWith(pendingSettlement: null));
  }

  Future<PetPendingSettlement?> _reconcileKnownDatesFor(
    PetProfile profile,
  ) async {
    final PetLocalDayContext context = _localDayContext();
    final List<DailyActivitySummary> summaries =
        await _activityRepository.list(_athleteProfileId);
    final Map<String, DailyActivitySummary> summaryByDate =
        <String, DailyActivitySummary>{
      for (final DailyActivitySummary summary in summaries)
        summary.localDate: summary,
    };
    final List<TrainingLog> logs = _limitedTrainingLogs();
    final List<AppliedDailyDecisionFact> decisions = _limitedAppliedDecisions();
    final Set<String> dates = <String>{
      ...summaryByDate.keys,
      ...logs.map((TrainingLog log) => _localDateKey(log.date.toLocal())),
      ...decisions.map((AppliedDailyDecisionFact fact) => fact.localDate),
    };
    final List<String> orderedDates = dates.toList()..sort();
    final List<PetDailyEnergy> existing = await _petRepository.listDailyEnergy(
      athleteProfileId: _athleteProfileId,
    );
    final Map<String, PetDailyEnergy> ledgerByDate = <String, PetDailyEnergy>{
      for (final PetDailyEnergy item in existing) item.localDate: item,
    };
    PetPendingSettlement? pending;
    for (final String localDate in orderedDates) {
      final PetSettlementResult result = await _settleDate(
        profile: profile,
        localDate: localDate,
        summary: summaryByDate[localDate],
        oldLedger: ledgerByDate[localDate],
        logs: logs,
        decisions: decisions,
        currentContext: context,
      );
      if (result.awardedDelta > 0) {
        pending = PetPendingSettlement(localDate: localDate, result: result);
      }
    }
    return pending;
  }

  Future<PetSettlementResult> _settleDate({
    required PetProfile profile,
    required String localDate,
    required DailyActivitySummary? summary,
    required PetDailyEnergy? oldLedger,
    required List<TrainingLog> logs,
    required List<AppliedDailyDecisionFact> decisions,
    required PetLocalDayContext currentContext,
  }) {
    final PetTrainingDayFacts facts = _trainingBridge.factsForDate(
      localDate: localDate,
      trainingLogs: logs,
      appliedDecisions: decisions,
    );
    final PetEnergyBreakdown breakdown = _energyCalculator.calculate(
      PetEnergyInput(
        steps: summary?.steps,
        stepGoal: summary?.stepGoal,
        standHours: summary?.standHours,
        standGoalHours: summary?.standGoalHours,
        exerciseMinutes: summary?.exerciseMinutes,
        exerciseGoalMinutes: summary?.exerciseGoalMinutes,
        activeEnergyKcal: summary?.activeEnergyKcal,
        activeEnergyGoalKcal: summary?.activeEnergyGoalKcal,
        hasValidTraining: facts.hasValidTraining,
        hasAcceptedRecoveryDecision: facts.hasAcceptedRecoveryDecision,
      ),
    );
    final _PinnedTimeZone timeZone = _timeZoneFor(
      oldLedger: oldLedger,
      summary: summary,
      currentContext: currentContext,
    );
    return _petRepository.settleDay(
      PetSettlementWrite(
        summary: summary,
        athleteProfileId: summary == null ? _athleteProfileId : null,
        localDate: summary == null ? localDate : null,
        activePetId: profile.activePetId!,
        breakdown: breakdown,
        sourceSnapshot: <String, Object?>{
          'localDate': localDate,
          'timeZoneName': timeZone.name,
          'timeZoneOffsetMinutes': timeZone.offsetMinutes,
          'activity': <String, Object?>{
            'steps': summary?.steps,
            'stepGoal': summary?.stepGoal,
            'standHours': summary?.standHours,
            'standGoalHours': summary?.standGoalHours,
            'exerciseMinutes': summary?.exerciseMinutes,
            'exerciseGoalMinutes': summary?.exerciseGoalMinutes,
            'activeEnergyKcal': summary?.activeEnergyKcal,
            'activeEnergyGoalKcal': summary?.activeEnergyGoalKcal,
          },
          'training': <String, Object?>{
            'hasValidTraining': facts.hasValidTraining,
            'hasAcceptedRecoveryDecision': facts.hasAcceptedRecoveryDecision,
          },
        },
        modelVersion: _energyModelVersion,
        settledAt: currentContext.now,
      ),
    );
  }

  Future<PetState> _loadReadyState({
    required PetPendingSettlement? pendingSettlement,
    required String statusMessage,
  }) async {
    final PetLocalDayContext context = _localDayContext();
    final PetProfile? profile =
        await _petRepository.loadProfile(_athleteProfileId);
    if (profile?.activePetId == null) return PetState.needsFirstEgg();
    final List<PetDailyEnergy> history = await _petRepository.listDailyEnergy(
      athleteProfileId: _athleteProfileId,
    );
    final PetCompanion? activeCompanion =
        await _petRepository.loadCompanionState(
      athleteProfileId: _athleteProfileId,
      localDate: context.localDate,
    );
    if (activeCompanion == null) {
      throw StateError('当前出战伙伴不存在');
    }
    return PetState(
      status: PetStateStatus.ready,
      profile: profile,
      activeCompanion: activeCompanion,
      todayActivitySummary: await _activityRepository.read(
        athleteProfileId: _athleteProfileId,
        localDate: context.localDate,
      ),
      todayEnergy: _energyForDate(history, context.localDate),
      energyHistory: history,
      pendingSettlement: pendingSettlement,
      statusMessage: statusMessage,
    );
  }

  List<TrainingLog> _limitedTrainingLogs() {
    return _trainingLogRepository
        .listLogs()
        .take(_maximumTrainingLogs)
        .toList(growable: false);
  }

  List<AppliedDailyDecisionFact> _limitedAppliedDecisions() {
    final List<AppliedDailyDecisionFact> facts =
        _dailyContextRepository.getContext().appliedDecisions;
    if (facts.length <= _maximumAppliedDecisionDays) return facts;
    return facts.sublist(facts.length - _maximumAppliedDecisionDays);
  }

  void _setOperationFailure(String message) {
    if (!ref.mounted) return;
    final PetState? current = state.value;
    if (current == null) {
      state = AsyncData(PetState.storageUnavailable(message: message));
      return;
    }
    state = AsyncData(current.copyWith(statusMessage: message));
  }
}

class _PinnedTimeZone {
  const _PinnedTimeZone(this.name, this.offsetMinutes);

  final String name;
  final int offsetMinutes;
}

_PinnedTimeZone _timeZoneFor({
  required PetDailyEnergy? oldLedger,
  required DailyActivitySummary? summary,
  required PetLocalDayContext currentContext,
}) {
  final Object? oldName = oldLedger?.sourceSnapshot['timeZoneName'];
  final Object? oldOffset = oldLedger?.sourceSnapshot['timeZoneOffsetMinutes'];
  if (oldName is String && oldName.trim().isNotEmpty && oldOffset is num) {
    return _PinnedTimeZone(oldName, oldOffset.toInt());
  }
  if (summary != null) {
    return _PinnedTimeZone(
      summary.timeZoneName,
      summary.timeZoneOffsetMinutes,
    );
  }
  return _PinnedTimeZone(
    currentContext.timeZoneName,
    currentContext.timeZoneOffsetMinutes,
  );
}

PetDailyEnergy? _energyForDate(
  Iterable<PetDailyEnergy> values,
  String localDate,
) {
  for (final PetDailyEnergy value in values) {
    if (value.localDate == localDate) return value;
  }
  return null;
}

String _defaultNickname(PetSpecies species) {
  return switch (species) {
    PetSpecies.windFox => '风步狐',
    PetSpecies.jumpRabbit => '跃动兔',
    PetSpecies.steadyTurtle => '立稳龟',
    PetSpecies.energyDragon => '燃能龙',
    PetSpecies.strengthBear => '力练熊',
    PetSpecies.balanceRaccoon => '衡衡狸',
  };
}

String _localDateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
