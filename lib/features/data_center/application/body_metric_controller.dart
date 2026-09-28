import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/body_metric.dart';
import '../../../data/models/body_metric_import.dart';
import '../../../data/models/body_metric_revision.dart';
import '../../../data/models/body_metric_snapshot.dart';
import '../../../data/models/daily_check_in_record.dart';
import '../../../data/repositories/body_metric_repository.dart';
import '../../../data/repositories/daily_check_in_repository.dart';
import '../../../plugins/application/feature_access.dart';
import '../../../plugins/application/feature_controller_binding.dart';
import '../../../plugins/application/plugin_runtime_provider.dart';
import '../../../services/body_metric_import_service.dart';
import '../../../services/body_metric_snapshot_service.dart';
import '../../../services/local_storage_service.dart';
import '../../../services/confirmed_local_document_write.dart';
import '../../../services/daily_check_in_service.dart';

const Object _unchanged = Object();

final bodyMetricRepositoryProvider = Provider<BodyMetricRepository>(
  (Ref ref) => PersistedBodyMetricRepository(
    ref.watch(localStorageServiceProvider),
  ),
);

final dailyCheckInRepositoryProvider = Provider<DailyCheckInRepository>(
  (Ref ref) => PersistedDailyCheckInRepository(
    ref.watch(localStorageServiceProvider),
  ),
);

final bodyMetricControllerProvider =
    NotifierProvider<BodyMetricController, BodyMetricState>(
  BodyMetricController.new,
);

class BodyMetricState {
  final List<BodyMetric> metrics;
  final List<BodyMetricRevision> revisions;
  final BodyMetric? pendingMetric;
  final String manualStatusMessage;
  final String snapshotStatusMessage;
  final List<BodyMetricImportResult> importResults;
  final String importStatusMessage;
  final String dailyCheckInStatusMessage;
  final CheckInStreakState checkInStreak;
  final List<CheckInCelebrationReceipt> checkInCelebrations;
  final int persistenceVersion;
  final bool isConfirmingMetric;
  final bool isImportingCsv;
  final bool isSavingCheckIn;
  final bool isSavingManualMetric;

  bool get isSavingBodyMetrics =>
      isConfirmingMetric || isImportingCsv || isSavingCheckIn || isSavingManualMetric;

  const BodyMetricState({
    required this.metrics,
    required this.revisions,
    required this.pendingMetric,
    required this.manualStatusMessage,
    required this.snapshotStatusMessage,
    required this.importResults,
    required this.importStatusMessage,
    required this.dailyCheckInStatusMessage,
    required this.checkInStreak,
    required this.checkInCelebrations,
    required this.persistenceVersion,
    this.isConfirmingMetric = false,
    this.isImportingCsv = false,
    this.isSavingCheckIn = false,
    this.isSavingManualMetric = false,
  });

  BodyMetric? get latestMetric {
    if (metrics.isEmpty) {
      return null;
    }
    return metrics.first;
  }

  BodyMetricState copyWith({
    List<BodyMetric>? metrics,
    List<BodyMetricRevision>? revisions,
    Object? pendingMetric = _unchanged,
    String? manualStatusMessage,
    String? snapshotStatusMessage,
    List<BodyMetricImportResult>? importResults,
    String? importStatusMessage,
    String? dailyCheckInStatusMessage,
    CheckInStreakState? checkInStreak,
    List<CheckInCelebrationReceipt>? checkInCelebrations,
    int? persistenceVersion,
    bool? isConfirmingMetric,
    bool? isImportingCsv,
    bool? isSavingCheckIn,
    bool? isSavingManualMetric,
  }) {
    return BodyMetricState(
      metrics: metrics ?? this.metrics,
      revisions: revisions ?? this.revisions,
      pendingMetric: identical(pendingMetric, _unchanged)
          ? this.pendingMetric
          : pendingMetric as BodyMetric?,
      manualStatusMessage: manualStatusMessage ?? this.manualStatusMessage,
      snapshotStatusMessage:
          snapshotStatusMessage ?? this.snapshotStatusMessage,
      importResults: importResults ?? this.importResults,
      importStatusMessage: importStatusMessage ?? this.importStatusMessage,
      dailyCheckInStatusMessage:
          dailyCheckInStatusMessage ?? this.dailyCheckInStatusMessage,
      checkInStreak: checkInStreak ?? this.checkInStreak,
      checkInCelebrations: checkInCelebrations ?? this.checkInCelebrations,
      persistenceVersion: persistenceVersion ?? this.persistenceVersion,
      isConfirmingMetric: isConfirmingMetric ?? this.isConfirmingMetric,
      isImportingCsv: isImportingCsv ?? this.isImportingCsv,
      isSavingCheckIn: isSavingCheckIn ?? this.isSavingCheckIn,
      isSavingManualMetric: isSavingManualMetric ?? this.isSavingManualMetric,
    );
  }
}

class BodyMetricController extends Notifier<BodyMetricState> {
  Object _generation = Object();
  final BodyMetricImportService _importService = BodyMetricImportService();
  final BodyMetricSnapshotRecognitionService _snapshotService =
      BodyMetricSnapshotRecognitionService();

  @override
  BodyMetricState build() {
    _generation = Object();
    bindFeatureController(ref, 'feature.data_center', 'bodyMetric', this);
    bindFeatureController(ref, 'feature.daily_check_in', 'checkIn', this);
    final BodyMetricRepository repository =
        ref.read(bodyMetricRepositoryProvider);
    final List<BodyMetric> metrics = repository.listMetrics();
    final DailyCheckInSnapshot checkInSnapshot =
        ref.read(dailyCheckInRepositoryProvider).getSnapshot();
    final bool hasHistory = metrics.isNotEmpty;
    return BodyMetricState(
      metrics: metrics,
      revisions: repository.listRevisions(),
      pendingMetric: null,
      manualStatusMessage: hasHistory
          ? '默认预填上次值；可选择今天、昨天或前天补录。'
          : '尚无身体记录。首次录入请使用包含完整字段的截图或 CSV，系统不会补造缺失值。',
      snapshotStatusMessage: '可粘贴体脂秤、手表或健康 App 截图中的文字，识别后需确认入库。',
      importResults: const [],
      importStatusMessage: '可粘贴 Apple 健康、手表或表格导出的身体数据 CSV。',
      dailyCheckInStatusMessage:
          DailyCheckInService.yesterdayMetric(metrics, DateTime.now()) != null
              ? '已有昨日记录，请核对内容后确认是否沿用。' : '尚无昨日记录，不能使用预填签到。',
      checkInStreak: checkInSnapshot.streak,
      checkInCelebrations: checkInSnapshot.unseenCelebrations,
      persistenceVersion: 0,
    );
  }

  Future<void> saveManualMetric({
    required double weightKg,
    required int restingHeartRate,
    required int hrvMs,
    required double sleepHours,
    required int fatigueLevel,
    DateTime? measuredAt,
    bool forceSave = false,
  }) {
    _checkPendingConfirmation();
    final access = ref.read(featureAccessProvider);
    final includeCheckIn = access.isWritable('feature.daily_check_in');
    final operation = access.beginOperation('feature.data_center',
        dependencies: [if (includeCheckIn) 'feature.daily_check_in']);
    final BodyMetric? latestMetric = state.latestMetric;
    if (latestMetric == null) {
      state = state.copyWith(
        manualStatusMessage: '首次快录缺少体脂和酸痛等字段，未保存；请先用完整截图或 CSV 建立基线。',
      );
      return Future<void>.value();
    }

    final DateTime selectedDate = _dateOnly(measuredAt ?? DateTime.now());
    final DateTime now = DateTime.now();
    final DateTime capturedAt = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      now.hour,
      now.minute,
    );
    final BodyMetric metric = BodyMetric(
      id: 'body-metric-${now.millisecondsSinceEpoch}',
      measuredAt: capturedAt,
      weightKg: weightKg,
      bodyFatPercentage: latestMetric.bodyFatPercentage,
      restingHeartRate: restingHeartRate,
      hrvMs: hrvMs,
      sleepHours: sleepHours,
      fatigueLevel: fatigueLevel,
      sorenessLevel: latestMetric.sorenessLevel,
      moodLabel: fatigueLevel >= 7 ? '偏疲劳' : '稳定',
      source: BodyMetricSource.manual,
      note: '数据中心 10 秒快录',
      recordedFields: const {'weightKg', 'restingHeartRate', 'hrvMs', 'sleepHours', 'fatigueLevel'},
    );

    final List<String> warnings = _bodyMetricOutlierWarnings(metric);
    if (warnings.isNotEmpty && !forceSave) {
      state = state.copyWith(
        pendingMetric: metric,
        manualStatusMessage: '异常值确认：${warnings.join('；')}。请确认不是手误后再保存。',
      );
      return Future<void>.value();
    }

    return _commitBodyAndCheckIn(metric, operation: operation,
      checkInAt: includeCheckIn ? now : null,
      reason: forceSave ? '确认异常值覆盖同日记录' : '10 秒快录覆盖同日记录',
      manualMessage: forceSave
          ? '已确认并保存异常值：${metric.measuredDateLabel} 的身体数据。'
          : '已保存 ${metric.measuredDateLabel} 的身体数据；质量、趋势和目标已刷新。',
      clearPending: true,
    );
  }

  Future<void> confirmPendingMetric() async {
    _checkPendingConfirmation();
    final ownerRef = ref;
    final generation = _generation;
    bool isCurrent() => ownerRef.mounted && identical(generation, _generation);
    final FeatureOperation operation =
        ref.read(featureAccessProvider).beginOperation('feature.data_center');
    final BodyMetric? metric = state.pendingMetric;
    if (metric == null) {
      state = state.copyWith(
        manualStatusMessage: '没有待确认的身体数据。',
        snapshotStatusMessage: '没有待确认的截图识别数据。',
      );
      return;
    }
    final repository = ref.read(bodyMetricRepositoryProvider);
    final bool isScreenshot = metric.source == BodyMetricSource.screenshot;
    state = state.copyWith(
      isConfirmingMetric: true,
      manualStatusMessage: isScreenshot ? null : '正在保存身体数据，请稍候。',
      snapshotStatusMessage: isScreenshot ? '正在保存身体数据，请稍候。' : null,
    );
    try {
      await operation.commit(() async {
        await repository.saveConfirmedMetric(metric,
            reason: isScreenshot ? '截图识别确认覆盖同日记录' : '确认异常值覆盖同日记录');
        if (!isCurrent()) return;
        _refreshAfterPersistence(state.copyWith(
          pendingMetric: null,
          manualStatusMessage: isScreenshot
              ? null : '已确认并保存异常值：${metric.measuredDateLabel} 的身体数据。',
          snapshotStatusMessage: isScreenshot
              ? '已确认截图识别数据：${metric.measuredDateLabel} 已写入 body_metrics。' : null,
        ));
      });
    } catch (error) {
      if (isCurrent()) {
        final message = error is StateError
            ? error.message : '身体数据保存失败，请保留当前内容并重试。';
        state = state.copyWith(
          manualStatusMessage: isScreenshot ? null : message,
          snapshotStatusMessage: isScreenshot ? message : null,
        );
      }
      rethrow;
    } finally {
      if (isCurrent()) state = state.copyWith(isConfirmingMetric: false);
    }
  }

  void _checkPendingConfirmation() {
    if (state.isSavingCheckIn) {
      throw StateError('签到正在保存，请等待完成后再操作。');
    }
    if (state.isSavingBodyMetrics) {
      throw StateError('身体数据正在保存，请等待完成后再操作。');
    }
  }

  void recognizeSnapshotText(String rawText) {
    _checkPendingConfirmation();
    ref.read(featureAccessProvider).requireEnabled('feature.data_center');
    try {
      final BodyMetricSnapshotRecognitionResult result =
          _snapshotService.recognize(
        rawText,
        fallback: state.latestMetric,
      );
      state = state.copyWith(
        pendingMetric: result.metric,
        snapshotStatusMessage: '${result.summary} 请确认后写入 body_metrics。',
      );
    } on FormatException catch (error) {
      state = state.copyWith(
        pendingMetric: null,
        snapshotStatusMessage: error.message,
      );
    } catch (_) {
      state = state.copyWith(
        pendingMetric: null,
        snapshotStatusMessage: '识别失败：请检查截图文字。',
      );
    }
  }

  Future<void> confirmDailyCheckInSameAsYesterday({String? expectedFingerprint}) {
    _checkPendingConfirmation();
    final FeatureOperation operation = ref
        .read(featureAccessProvider)
        .beginOperation('feature.daily_check_in',
            dependencies: const ['feature.data_center']);
    final DateTime now = DateTime.now();
    final BodyMetric? latestMetric = DailyCheckInService.yesterdayMetric(state.metrics, now);
    if (expectedFingerprint != null && (latestMetric == null ||
        expectedFingerprint != DailyCheckInService.yesterdayFingerprint(latestMetric, now))) {
      throw StateError('昨日记录或日期已变化，请刷新并重新核对后确认。');
    }
    if (latestMetric == null) {
      state = state.copyWith(
        dailyCheckInStatusMessage: '没有可用的昨日记录；请填写今天的状态，不会沿用今日或更早记录。',
      );
      return Future<void>.value();
    }

    final BodyMetric metric = BodyMetric(
      id: 'daily-check-in-${now.millisecondsSinceEpoch}',
      measuredAt: now,
      weightKg: latestMetric.weightKg,
      bodyFatPercentage: latestMetric.bodyFatPercentage,
      restingHeartRate: latestMetric.restingHeartRate,
      hrvMs: latestMetric.hrvMs,
      sleepHours: latestMetric.sleepHours,
      fatigueLevel: latestMetric.fatigueLevel,
      sorenessLevel: latestMetric.sorenessLevel,
      moodLabel: latestMetric.moodLabel,
      source: BodyMetricSource.manual,
      note: '精简签到：本人确认沿用昨日记录 ${latestMetric.measuredAt.toLocal().toIso8601String()}，来源 ${latestMetric.id}（${latestMetric.source.label}），非重新测量。',
      recordedFields: latestMetric.recordedFields,
      sourceVerified: latestMetric.sourceVerified,
    );
    return _commitBodyAndCheckIn(metric, operation: operation,
      checkInAt: now, reason: '精简签到确认覆盖同日记录',
      checkInMessage: '已按昨日记录完成今日签到：和昨天一样（本人确认沿用，非重新测量）。',
    );
  }

  Future<void> _commitBodyAndCheckIn(BodyMetric metric, {
    required FeatureOperation operation,
    required DateTime? checkInAt,
    required String reason,
    String? manualMessage,
    bool clearPending = false,
    String? checkInMessage,
  }) async {
    final ownerRef = ref;
    final generation = _generation;
    bool isCurrent() => ownerRef.mounted && identical(generation, _generation);
    final bodyRepository = ref.read(bodyMetricRepositoryProvider);
    final checkInRepository = checkInAt == null
        ? null : ref.read(dailyCheckInRepositoryProvider);
    final storage = ref.read(localStorageServiceProvider);
    final isNewCheckIn = checkInAt != null && !checkInRepository!.getSnapshot()
        .records.any((item) => _isSameDate(item.localDate, checkInAt));
    state = state.copyWith(isSavingManualMetric: true,
      manualStatusMessage: manualMessage == null ? null : '正在保存身体数据，请稍候。',
      dailyCheckInStatusMessage: checkInAt == null ? null : '正在保存身体数据与签到，请稍候。',
    );
    try {
      await operation.commit(() async {
        final writes = <PreparedLocalDocumentWrite>[];
        try {
          writes.add(bodyRepository.prepareConfirmedMetrics([metric], reason: reason));
          if (checkInAt != null) {
            writes.add(checkInRepository!.prepareConfirmedRecord(
                localDate: checkInAt, confirmedAt: checkInAt,
                source: DailyCheckInSource.prefilled));
          }
          await commitLocalDocumentWrites(storage, writes,
              label: checkInAt == null ? '身体数据' : '身体数据与签到');
        } finally {
          // 后一候选准备失败时，仍须释放已取得的前一仓储锁。
          for (final write in writes) { write.release(); }
        }
        if (!isCurrent()) return;
        final checkIn = checkInRepository?.getSnapshot();
        _refreshAfterPersistence(state.copyWith(
          pendingMetric: clearPending ? null : state.pendingMetric,
          manualStatusMessage: manualMessage,
          dailyCheckInStatusMessage: checkIn == null ? null : isNewCheckIn
              ? (checkInMessage ?? '已按画像预填完成今日签到：和昨天一样。')
              : '今日签到已记录，同一天重复操作不会增加连续天数。',
          checkInStreak: checkIn?.streak,
          checkInCelebrations: checkIn?.unseenCelebrations,
        ));
      });
    } catch (error) {
      if (isCurrent()) {
        final message = error is StateError ? error.message
            : '身体数据与签到保存失败，请保留当前输入并重试。';
        state = state.copyWith(
          manualStatusMessage: manualMessage == null ? null : message,
          dailyCheckInStatusMessage: checkInAt == null ? null : message,
        );
      }
      rethrow;
    } finally {
      if (isCurrent()) state = state.copyWith(isSavingManualMetric: false);
    }
  }

  Future<void> recordTiredDailyCheckIn() => _saveConfirmedCheckIn(
    source: DailyCheckInSource.subjectiveTired,
    successMessage: '已完成今日主观签到：偏累；未生成或改写体重、体脂、静息心率、HRV、睡眠等身体指标。',
  );

  Future<void> recordContinuityDay(DailyContinuityKind continuityKind) {
    final isSafetyPause = continuityKind == DailyContinuityKind.safetyPause;
    return _saveConfirmedCheckIn(
      source: isSafetyPause
          ? DailyCheckInSource.subjectiveTired : DailyCheckInSource.prefilled,
      continuityKind: continuityKind,
      successMessage: isSafetyPause
          ? '已记录今天的安全暂停：连续成长受到保护；未生成训练完成、身体指标或训练 XP。'
          : '已记录今天按计划恢复：连续成长受到保护；未生成训练完成、身体指标或训练 XP。',
    );
  }

  Future<void> _saveConfirmedCheckIn({
    required DailyCheckInSource source,
    DailyContinuityKind continuityKind = DailyContinuityKind.standard,
    required String successMessage,
  }) {
    final now = DateTime.now();
    return _commitCheckIn((repository) async {
      final result = await repository.recordConfirmed(
        localDate: now, confirmedAt: now, source: source,
        continuityKind: continuityKind,
      );
      return result.created ? successMessage
          : '今日签到已记录，同一天重复操作不会增加连续天数。';
    });
  }

  Future<void> markCheckInCelebrationSeen(String id) =>
      _commitCheckIn((repository) async {
        await repository.markCelebrationSeenConfirmed(id, seenAt: DateTime.now());
        return '成就收取状态已保存，不会重复增加签到天数。';
      });

  Future<void> _commitCheckIn(
      Future<String> Function(DailyCheckInRepository repository) write) async {
    _checkPendingConfirmation();
    final ownerRef = ref;
    final generation = _generation;
    bool isCurrent() => ownerRef.mounted && identical(generation, _generation);
    final operation =
        ref.read(featureAccessProvider).beginOperation('feature.daily_check_in');
    final repository = ref.read(dailyCheckInRepositoryProvider);
    state = state.copyWith(isSavingCheckIn: true,
        dailyCheckInStatusMessage: '正在保存签到，请稍候。');
    try {
      await operation.commit(() async {
        final message = await write(repository);
        if (!isCurrent()) return;
        final snapshot = repository.getSnapshot();
        state = state.copyWith(
          checkInStreak: snapshot.streak,
          checkInCelebrations: snapshot.unseenCelebrations,
          dailyCheckInStatusMessage: message,
        );
      });
    } catch (error) {
      if (isCurrent()) {
        state = state.copyWith(dailyCheckInStatusMessage: error is StateError
            ? error.message : '签到保存失败，请保留当前内容并重试。');
      }
      rethrow;
    } finally {
      if (isCurrent()) state = state.copyWith(isSavingCheckIn: false);
    }
  }

  Future<void> importCsv(String rawText) async {
    _checkPendingConfirmation();
    final ownerRef = ref;
    final generation = _generation;
    bool isCurrent() => ownerRef.mounted && identical(generation, _generation);
    final operation =
        ref.read(featureAccessProvider).beginOperation('feature.data_center');
    final BodyMetricImportResult result;
    try {
      result = _importService.parseCsv(rawText,
          historicalFallback: state.latestMetric);
    } on FormatException catch (error) {
      state = state.copyWith(importStatusMessage: error.message);
      return;
    }
    final repository = ref.read(bodyMetricRepositoryProvider);
    state = state.copyWith(
      isImportingCsv: true,
      importStatusMessage: '正在保存本次 CSV 的有效记录，请稍候。',
    );
    try {
      await operation.commit(() async {
        await repository.saveConfirmedMetrics(result.metrics,
            reason: 'CSV 导入覆盖同日记录');
        if (!isCurrent()) return;
        _refreshAfterPersistence(state.copyWith(
          importResults: [result, ...state.importResults],
          importStatusMessage: '${result.summary} 已写入 body_metrics，并会刷新趋势、质量和指标目标。',
        ));
      });
    } catch (error) {
      if (isCurrent()) {
        state = state.copyWith(
          importStatusMessage: error is StateError
              ? error.message : 'CSV 保存失败，请保留当前内容并重试。',
        );
      }
      rethrow;
    } finally {
      if (isCurrent()) state = state.copyWith(isImportingCsv: false);
    }
  }

  Future<void> clear() async {
    _checkPendingConfirmation();
    ref.read(bodyMetricRepositoryProvider).clearMetrics();
    await ref.read(localStorageServiceProvider).flush();
    _refreshAfterPersistence(
      state.copyWith(
        importStatusMessage: '身体数据已清除，CSV 导入历史仍保留在本次会话状态中。',
        manualStatusMessage: '尚无身体记录。首次录入请使用包含完整字段的截图或 CSV，系统不会补造缺失值。',
        dailyCheckInStatusMessage: '尚无昨日记录，不能使用预填签到。',
      ),
    );
  }

  List<String> _bodyMetricOutlierWarnings(BodyMetric metric) {
    final List<BodyMetric> baselines = state.metrics
        .where(
          (BodyMetric item) => !_isSameDate(item.measuredAt, metric.measuredAt),
        )
        .take(7)
        .toList();
    if (baselines.isEmpty) {
      return const [];
    }

    final List<String> warnings = [];
    final BodyMetric reference = baselines.first;
    final double weightDelta = metric.weightKg - reference.weightKg;
    if (weightDelta.abs() > 2.0) {
      warnings.add(
        '体重较最近记录变化 ${weightDelta.toStringAsFixed(1)} kg，超过 2 kg',
      );
    }

    final double averageRestingHr = baselines
            .map((BodyMetric item) => item.restingHeartRate)
            .reduce((int total, int value) => total + value) /
        baselines.length;
    final double restingHrDelta = metric.restingHeartRate - averageRestingHr;
    if (restingHrDelta.abs() >= 20) {
      warnings.add(
        '静息心率较 7 日均值偏离 ${restingHrDelta.toStringAsFixed(0)} bpm',
      );
    }
    return warnings;
  }

  void _refreshAfterPersistence(BodyMetricState nextState) {
    final BodyMetricRepository repository =
        ref.read(bodyMetricRepositoryProvider);
    state = nextState.copyWith(
      metrics: repository.listMetrics(),
      revisions: repository.listRevisions(),
      persistenceVersion: state.persistenceVersion + 1,
    );
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  bool _isSameDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}
