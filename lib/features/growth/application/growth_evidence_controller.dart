import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/body_metric.dart';
import '../../../data/models/growth_evidence.dart';
import '../../../data/models/pain_log.dart';
import '../../../data/models/training_log.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/models/workout_day.dart';
import '../../../data/repositories/growth_evidence_repository.dart';
import '../../../services/growth_engine.dart';
import '../../../services/local_storage_service.dart';

final growthEvidenceRepositoryProvider = Provider<GrowthEvidenceRepository>(
  (Ref ref) => PersistedGrowthEvidenceRepository(
    ref.watch(localStorageServiceProvider),
  ),
);

final growthEvidenceControllerProvider =
    NotifierProvider<GrowthEvidenceController, GrowthEvidenceState>(
  GrowthEvidenceController.new,
);

class GrowthEvidenceState {
  const GrowthEvidenceState({
    required this.athleteProfileId,
    required this.events,
    required this.levelState,
    required this.weeklyReports,
    required this.latestReceipt,
    required this.statusMessage,
    required this.isSynchronizing,
  });

  const GrowthEvidenceState.empty()
      : athleteProfileId = '',
        events = const <GrowthEvidenceEvent>[],
        levelState = const GrowthLevelState(peakXp: 0, peakLevel: 1),
        weeklyReports = const <WeeklyGrowthReport>[],
        latestReceipt = null,
        statusMessage = '完成一次有效训练后，将建立成长基线。',
        isSynchronizing = false;

  final String athleteProfileId;
  final List<GrowthEvidenceEvent> events;
  final GrowthLevelState levelState;
  final List<WeeklyGrowthReport> weeklyReports;
  final TrainingGrowthReceipt? latestReceipt;
  final String statusMessage;
  final bool isSynchronizing;

  GrowthEvidenceState copyWith({
    String? athleteProfileId,
    List<GrowthEvidenceEvent>? events,
    GrowthLevelState? levelState,
    List<WeeklyGrowthReport>? weeklyReports,
    Object? latestReceipt = _growthUnchanged,
    String? statusMessage,
    bool? isSynchronizing,
  }) {
    return GrowthEvidenceState(
      athleteProfileId: athleteProfileId ?? this.athleteProfileId,
      events: events ?? this.events,
      levelState: levelState ?? this.levelState,
      weeklyReports: weeklyReports ?? this.weeklyReports,
      latestReceipt: identical(latestReceipt, _growthUnchanged)
          ? this.latestReceipt
          : latestReceipt as TrainingGrowthReceipt?,
      statusMessage: statusMessage ?? this.statusMessage,
      isSynchronizing: isSynchronizing ?? this.isSynchronizing,
    );
  }
}

class GrowthEvidenceController extends Notifier<GrowthEvidenceState> {
  final GrowthEngine _engine = GrowthEngine();

  @override
  GrowthEvidenceState build() => const GrowthEvidenceState.empty();

  void acknowledgeLatestReceipt(String eventId) {
    if (state.latestReceipt?.event.eventId != eventId) return;
    state = state.copyWith(latestReceipt: null);
  }

  Future<void> reconcile({
    required UserProfile profile,
    required List<TrainingLog> logs,
    required List<BodyMetric> bodyMetrics,
    required List<PainLog> painLogs,
    required Map<String, WorkoutDay> workoutsById,
    required WorkoutDay fallbackWorkout,
  }) async {
    if (profile.id.isEmpty) return;
    state = state.copyWith(
      athleteProfileId: profile.id,
      isSynchronizing: true,
      statusMessage: '正在核对训练、健康记录和成长证据。',
    );
    try {
      final GrowthEvidenceRepository repository =
          ref.read(growthEvidenceRepositoryProvider);
      final List<GrowthEvidenceEvent> existing = await _loadAllEvents(
        repository,
        profile.id,
      );
      if (!ref.mounted) return;
      final Map<String, GrowthEvidenceEvent> bySource =
          <String, GrowthEvidenceEvent>{
        for (final GrowthEvidenceEvent event in existing)
          '${event.sourceTable}:${event.sourceId}': event,
      };
      for (final TrainingLog log in logs) {
        if (!log.isSessionRecord) continue;
        final GrowthEvidenceEvent? existingEvent =
            bySource['training_logs:${log.id}'];
        if (existingEvent?.isRevoked == true) {
          continue;
        }
        final WorkoutDay workout =
            workoutsById[log.workoutDayId] ?? fallbackWorkout;
        final GrowthEvidenceEvent event = _engine.buildTrainingEvent(
          athleteProfileId: profile.id,
          log: log,
          workout: workout,
          painLog: _painForTrainingLog(log, painLogs),
          existingEvent: existingEvent,
        );
        await repository.saveEvent(event);
        if (!ref.mounted) return;
      }
      for (final BodyMetric metric in bodyMetrics) {
        final GrowthEvidenceEvent event = _engine.buildHealthEvent(
          athleteProfileId: profile.id,
          metric: metric,
          existingEvent: bySource['health_snapshots:${metric.id}'],
        );
        await repository.saveEvent(event);
        if (!ref.mounted) return;
      }
      await _refresh(
        profileId: profile.id,
        statusMessage: '成长证据已根据真实训练和健康记录更新。',
      );
    } catch (_) {
      if (!ref.mounted) return;
      state = state.copyWith(
        isSynchronizing: false,
        statusMessage: '训练记录已保留，但成长证据暂未生成，将在下次启动时自动补全。',
      );
    }
  }

  Future<void> syncTrainingLog({
    required UserProfile profile,
    required TrainingLog log,
    required WorkoutDay workout,
    PainLog? painLog,
  }) async {
    if (!log.isSessionRecord || profile.id.isEmpty) return;
    try {
      final GrowthEvidenceRepository repository =
          ref.read(growthEvidenceRepositoryProvider);
      final GrowthEvidenceEvent? existing = await repository.findBySource(
        athleteProfileId: profile.id,
        sourceTable: 'training_logs',
        sourceId: log.id,
      );
      if (existing?.isRevoked == true) {
        await _refresh(
          profileId: profile.id,
          statusMessage: '该训练来源已撤销，未重新计入成长证据。',
        );
        return;
      }
      final GrowthEvidenceEvent event = _engine.buildTrainingEvent(
        athleteProfileId: profile.id,
        log: log,
        workout: workout,
        painLog: painLog,
        existingEvent: existing,
      );
      await repository.saveEvent(event);
      final List<GrowthEvidenceEvent> events = await _loadAllEvents(
        repository,
        profile.id,
      );
      final GrowthLevelState levelState = await _settleLevel(
        repository: repository,
        athleteProfileId: profile.id,
        events: events,
      );
      final DailyXpSettlement daily = _engine.settleDailyXp(
        occurredOn: event.occurredOn,
        events: events,
      );
      final TrainingGrowthReceipt receipt = TrainingGrowthReceipt(
        event: event,
        awardedXp: daily.awardFor(event.eventId),
        longTermMeaning: _longTermMeaning(workout),
        message: _receiptMessage(event),
      );
      final List<WeeklyGrowthReport> reports =
          await repository.listWeeklyReports(athleteProfileId: profile.id);
      state = state.copyWith(
        athleteProfileId: profile.id,
        events: events,
        levelState: levelState,
        weeklyReports: reports,
        latestReceipt: receipt,
        statusMessage: '成长回执已生成，可查看本次训练的真实证据。',
        isSynchronizing: false,
      );
    } catch (_) {
      state = state.copyWith(
        statusMessage: '训练已保存，但成长证据暂未生成，将在下次启动时自动补全。',
        isSynchronizing: false,
      );
    }
  }

  Future<void> syncBodyMetric({
    required UserProfile profile,
    required BodyMetric metric,
  }) async {
    if (profile.id.isEmpty) return;
    try {
      final GrowthEvidenceRepository repository =
          ref.read(growthEvidenceRepositoryProvider);
      final GrowthEvidenceEvent? existing = await repository.findBySource(
        athleteProfileId: profile.id,
        sourceTable: 'health_snapshots',
        sourceId: metric.id,
      );
      await repository.saveEvent(
        _engine.buildHealthEvent(
          athleteProfileId: profile.id,
          metric: metric,
          existingEvent: existing,
        ),
      );
      await _refresh(
        profileId: profile.id,
        statusMessage: '恢复与健康记录已写入成长证据。',
      );
    } catch (_) {
      state = state.copyWith(
        statusMessage: '健康记录已保存，但成长证据将在下次启动时补全。',
      );
    }
  }

  Future<void> revokeTrainingLog({
    required String athleteProfileId,
    required String logId,
  }) async {
    final GrowthEvidenceRepository repository =
        ref.read(growthEvidenceRepositoryProvider);
    await repository.revokeSource(
      athleteProfileId: athleteProfileId,
      sourceTable: 'training_logs',
      sourceId: logId,
      revokedAt: DateTime.now(),
    );
    await _refresh(
      profileId: athleteProfileId,
      statusMessage: '来源已删除，对应成长证据已撤销。',
    );
  }

  /// 撤销当前运动员由健康数据产生的成长证据，并重算当前有效 XP。
  ///
  /// 训练日志证据不会被触碰；峰值等级仍按既有激励徽章语义保留。
  Future<int> revokeHealthSources({
    required String athleteProfileId,
  }) async {
    if (athleteProfileId.isEmpty) return 0;
    final GrowthEvidenceRepository repository =
        ref.read(growthEvidenceRepositoryProvider);
    final List<GrowthEvidenceEvent> events = await _loadAllEvents(
      repository,
      athleteProfileId,
    );
    final List<GrowthEvidenceEvent> healthEvents = events
        .where(
          (GrowthEvidenceEvent event) =>
              event.isActive &&
              (event.sourceTable == 'health_snapshots' ||
                  event.sourceTable == 'health_observations'),
        )
        .toList();
    final DateTime revokedAt = DateTime.now();
    for (final GrowthEvidenceEvent event in healthEvents) {
      await repository.revokeSource(
        athleteProfileId: athleteProfileId,
        sourceTable: event.sourceTable,
        sourceId: event.sourceId,
        revokedAt: revokedAt,
      );
    }
    if (healthEvents.isNotEmpty) {
      final List<GrowthEvidenceEvent> remaining = await _loadAllEvents(
        repository,
        athleteProfileId,
      );
      final GrowthLevelProgress rebuilt = _engine.buildLevelProgress(
        events: remaining,
        previous: const GrowthLevelState(peakXp: 0, peakLevel: 1),
      );
      await repository.saveLevelState(
        athleteProfileId: athleteProfileId,
        state: GrowthLevelState(
          peakXp: rebuilt.peakXp,
          peakLevel: rebuilt.level,
          modelVersion: GrowthEngine.currentModelVersion,
        ),
        updatedAt: revokedAt,
      );
    }
    await _refresh(
      profileId: athleteProfileId,
      statusMessage: healthEvents.isEmpty
          ? '当前没有需要撤销的健康成长证据。'
          : '健康来源已删除，关联成长证据和当前有效 XP 已重算。',
    );
    return healthEvents.length;
  }

  /// SQLite 已在健康批次事务中完成撤销后，重新载入事件并结算当前有效 XP。
  Future<void> refreshPersistedAthleteState({
    required String athleteProfileId,
  }) async {
    if (athleteProfileId.isEmpty) return;
    await _refresh(
      profileId: athleteProfileId,
      statusMessage: '健康来源变化已同步，成长证据和当前有效 XP 已重新核对。',
    );
  }

  /// 用户删除本地健康数据或切换账号时，清除全部成长派生数据和激励峰值。
  Future<void> clearAthleteData({
    required String athleteProfileId,
    bool persistenceAlreadyCleared = false,
  }) async {
    if (athleteProfileId.isEmpty) return;
    if (!persistenceAlreadyCleared) {
      await ref
          .read(growthEvidenceRepositoryProvider)
          .clearAthleteData(athleteProfileId);
    }
    state = GrowthEvidenceState(
      athleteProfileId: athleteProfileId,
      events: const <GrowthEvidenceEvent>[],
      levelState: const GrowthLevelState(peakXp: 0, peakLevel: 1),
      weeklyReports: const <WeeklyGrowthReport>[],
      latestReceipt: null,
      statusMessage: '当前运动员的成长证据、等级峰值和兼容周报已清除。',
      isSynchronizing: false,
    );
  }

  Future<List<GrowthEvidenceEvent>> loadMore({
    required String athleteProfileId,
    required int offset,
    bool includeRevoked = false,
  }) {
    return ref.read(growthEvidenceRepositoryProvider).listEvents(
          athleteProfileId: athleteProfileId,
          includeRevoked: includeRevoked,
          limit: 30,
          offset: offset,
        );
  }

  Future<void> _refresh({
    required String profileId,
    required String statusMessage,
  }) async {
    final GrowthEvidenceRepository repository =
        ref.read(growthEvidenceRepositoryProvider);
    final List<GrowthEvidenceEvent> events = await _loadAllEvents(
      repository,
      profileId,
    );
    if (!ref.mounted) return;
    final GrowthLevelState levelState = await _settleLevel(
      repository: repository,
      athleteProfileId: profileId,
      events: events,
    );
    if (!ref.mounted) return;
    final List<WeeklyGrowthReport> reports =
        await repository.listWeeklyReports(athleteProfileId: profileId);
    if (!ref.mounted) return;
    final List<WeeklyGrowthReport> lockedReports =
        await _lockExpiredReports(repository, reports);
    if (!ref.mounted) return;
    state = state.copyWith(
      athleteProfileId: profileId,
      events: events,
      levelState: levelState,
      weeklyReports: lockedReports,
      statusMessage: statusMessage,
      isSynchronizing: false,
    );
  }

  Future<List<GrowthEvidenceEvent>> _loadAllEvents(
    GrowthEvidenceRepository repository,
    String profileId,
  ) async {
    final List<GrowthEvidenceEvent> result = <GrowthEvidenceEvent>[];
    int offset = 0;
    while (true) {
      final List<GrowthEvidenceEvent> page = await repository.listEvents(
        athleteProfileId: profileId,
        includeRevoked: true,
        limit: 100,
        offset: offset,
      );
      result.addAll(page);
      if (page.length < 100) return result;
      offset += page.length;
    }
  }

  Future<GrowthLevelState> _settleLevel({
    required GrowthEvidenceRepository repository,
    required String athleteProfileId,
    required List<GrowthEvidenceEvent> events,
  }) async {
    final GrowthLevelState existing =
        await repository.readLevelState(athleteProfileId);
    final GrowthLevelProgress progress = _engine.buildLevelProgress(
      events: events,
      previous: existing,
    );
    final GrowthLevelState next = GrowthLevelState(
      peakXp: progress.peakXp,
      peakLevel: progress.level,
      modelVersion: GrowthEngine.currentModelVersion,
    );
    await repository.saveLevelState(
      athleteProfileId: athleteProfileId,
      state: next,
      updatedAt: DateTime.now(),
    );
    return next;
  }

  Future<List<WeeklyGrowthReport>> _lockExpiredReports(
    GrowthEvidenceRepository repository,
    List<WeeklyGrowthReport> reports,
  ) async {
    final DateTime currentWeekStart = growthWeekStart(DateTime.now());
    bool changed = false;
    final List<WeeklyGrowthReport> next = <WeeklyGrowthReport>[];
    for (final WeeklyGrowthReport report in reports) {
      if (!report.isLocked && report.weekStartsOn.isBefore(currentWeekStart)) {
        final WeeklyGrowthReport locked = report.copyWith(
          lockedAt: growthAddCalendarDays(report.weekStartsOn, 7),
        );
        await repository.saveWeeklyReport(locked);
        next.add(locked);
        changed = true;
      } else {
        next.add(report);
      }
    }
    if (!changed) return reports;
    next.sort(
      (WeeklyGrowthReport first, WeeklyGrowthReport second) =>
          second.weekStartsOn.compareTo(first.weekStartsOn),
    );
    return List<WeeklyGrowthReport>.unmodifiable(next);
  }

  PainLog? _painForTrainingLog(
    TrainingLog log,
    List<PainLog> painLogs,
  ) {
    for (final PainLog painLog in painLogs) {
      if (growthIsSameDay(painLog.date, log.date)) {
        return painLog;
      }
    }
    return null;
  }

  String _longTermMeaning(WorkoutDay workout) {
    return switch (workout.trainingType) {
      TrainingType.hyrox => '这次训练在为 HYROX 的跑步与功能力量衔接积累证据。',
      TrainingType.strength => '这次力量训练为长期稳定输出和专项动作打下基础。',
      TrainingType.tempoRun ||
      TrainingType.intervalRun ||
      TrainingType.longRun ||
      TrainingType.easyRun =>
        '这次跑步训练为有氧能力和目标配速积累可追溯证据。',
      TrainingType.rehab || TrainingType.mobility => '这次恢复与动作质量训练在保护长期训练连续性。',
      TrainingType.crossTraining => '这次交叉训练补充了主目标之外的身体适应。',
      TrainingType.rest => '按计划恢复同样是长期成长的一部分。',
    };
  }

  String _receiptMessage(GrowthEvidenceEvent event) {
    if (event.xpComponents.any(
      (GrowthXpComponent item) =>
          item.type == GrowthXpComponentType.safetyDecision,
    )) {
      return '你选择了安全优先；这条记录证明你在保护长期训练连续性。';
    }
    if (event.xpComponents.every(
      (GrowthXpComponent item) => item.type != GrowthXpComponentType.completion,
    )) {
      return '本次有效训练刺激不足，系统保留真实记录，不虚构成长。';
    }
    return '本次训练已转化为可追溯成长证据。';
  }
}

const Object _growthUnchanged = Object();
