import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/body_metric.dart';
import '../../../data/models/body_metric_import.dart';
import '../../../data/models/body_metric_revision.dart';
import '../../../data/models/body_metric_snapshot.dart';
import '../../../data/repositories/body_metric_repository.dart';
import '../../../services/body_metric_import_service.dart';
import '../../../services/body_metric_snapshot_service.dart';
import '../../../services/local_storage_service.dart';
import '../../profile/application/user_profile_controller.dart';

const Object _unchanged = Object();

final bodyMetricRepositoryProvider = Provider<BodyMetricRepository>(
  (Ref ref) => PersistedBodyMetricRepository(
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
  final int persistenceVersion;

  const BodyMetricState({
    required this.metrics,
    required this.revisions,
    required this.pendingMetric,
    required this.manualStatusMessage,
    required this.snapshotStatusMessage,
    required this.importResults,
    required this.importStatusMessage,
    required this.dailyCheckInStatusMessage,
    required this.persistenceVersion,
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
    int? persistenceVersion,
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
      persistenceVersion: persistenceVersion ?? this.persistenceVersion,
    );
  }
}

class BodyMetricController extends Notifier<BodyMetricState> {
  final BodyMetricImportService _importService = BodyMetricImportService();
  final BodyMetricSnapshotRecognitionService _snapshotService =
      BodyMetricSnapshotRecognitionService();

  @override
  BodyMetricState build() {
    final BodyMetricRepository repository =
        ref.read(bodyMetricRepositoryProvider);
    return BodyMetricState(
      metrics: repository.listMetrics(),
      revisions: repository.listRevisions(),
      pendingMetric: null,
      manualStatusMessage: '默认预填上次值；可选择今天、昨天或前天补录。',
      snapshotStatusMessage: '可粘贴体脂秤、手表或健康 App 截图中的文字，识别后需确认入库。',
      importResults: const [],
      importStatusMessage: '可粘贴 Apple 健康、手表或表格导出的身体数据 CSV。',
      dailyCheckInStatusMessage: '根据当前画像，今天可以先使用预填签到。',
      persistenceVersion: 0,
    );
  }

  void saveManualMetric({
    required double weightKg,
    required int restingHeartRate,
    required int hrvMs,
    required double sleepHours,
    required int fatigueLevel,
    DateTime? measuredAt,
    bool forceSave = false,
  }) {
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
      bodyFatPercentage: state.latestMetric?.bodyFatPercentage ?? 18.6,
      restingHeartRate: restingHeartRate,
      hrvMs: hrvMs,
      sleepHours: sleepHours,
      fatigueLevel: fatigueLevel,
      sorenessLevel: state.latestMetric?.sorenessLevel ?? 3,
      moodLabel: fatigueLevel >= 7 ? '偏疲劳' : '稳定',
      source: BodyMetricSource.manual,
      note: '数据中心 10 秒快录',
    );

    final List<String> warnings = _bodyMetricOutlierWarnings(metric);
    if (warnings.isNotEmpty && !forceSave) {
      state = state.copyWith(
        pendingMetric: metric,
        manualStatusMessage: '异常值确认：${warnings.join('；')}。请确认不是手误后再保存。',
      );
      return;
    }

    _saveMetricAndRefresh(
      metric,
      reason: forceSave ? '确认异常值覆盖同日记录' : '10 秒快录覆盖同日记录',
      nextState: state.copyWith(
        pendingMetric: null,
        manualStatusMessage: forceSave
            ? '已确认并保存异常值：${metric.measuredDateLabel} 的身体数据。'
            : '已保存 ${metric.measuredDateLabel} 的身体数据；质量、趋势和目标已刷新。',
      ),
    );
  }

  void confirmPendingMetric() {
    final BodyMetric? metric = state.pendingMetric;
    if (metric == null) {
      state = state.copyWith(
        manualStatusMessage: '没有待确认的身体数据。',
        snapshotStatusMessage: '没有待确认的截图识别数据。',
      );
      return;
    }

    final bool isScreenshot = metric.source == BodyMetricSource.screenshot;
    _saveMetricAndRefresh(
      metric,
      reason: isScreenshot ? '截图识别确认覆盖同日记录' : '确认异常值覆盖同日记录',
      nextState: state.copyWith(
        pendingMetric: null,
        manualStatusMessage: isScreenshot
            ? state.manualStatusMessage
            : '已确认并保存异常值：${metric.measuredDateLabel} 的身体数据。',
        snapshotStatusMessage: isScreenshot
            ? '已确认截图识别数据：${metric.measuredDateLabel} 已写入 body_metrics。'
            : state.snapshotStatusMessage,
      ),
    );
  }

  void recognizeSnapshotText(String rawText) {
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
      state = state.copyWith(snapshotStatusMessage: error.message);
    } catch (_) {
      state = state.copyWith(snapshotStatusMessage: '识别失败：请检查截图文字。');
    }
  }

  void confirmDailyCheckInSameAsYesterday() {
    final BodyMetric? latestMetric = state.latestMetric;
    if (latestMetric == null) {
      state = state.copyWith(
        dailyCheckInStatusMessage: '还没有可预填的身体数据，请先完成一次完整签到。',
      );
      return;
    }

    final DateTime now = DateTime.now();
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
      note: '精简签到：和昨天一样',
    );
    _saveMetricAndRefresh(
      metric,
      reason: '精简签到确认覆盖同日记录',
      nextState: state.copyWith(
        dailyCheckInStatusMessage: '已按画像预填完成今日签到：和昨天一样。',
      ),
    );
  }

  void recordTiredDailyCheckIn() {
    final BodyMetric? latestMetric = state.latestMetric;
    final DateTime now = DateTime.now();
    final int fatigueLevel =
        ((latestMetric?.fatigueLevel ?? 6) + 2).clamp(1, 10).toInt();
    final double fallbackWeight =
        ref.read(userProfileControllerProvider).profile.weightKg;
    final BodyMetric metric = BodyMetric(
      id: 'daily-check-in-tired-${now.millisecondsSinceEpoch}',
      measuredAt: now,
      weightKg: latestMetric?.weightKg ?? fallbackWeight,
      bodyFatPercentage: latestMetric?.bodyFatPercentage ?? 18.6,
      restingHeartRate: latestMetric?.restingHeartRate ?? 62,
      hrvMs: ((latestMetric?.hrvMs ?? 48) - 4).clamp(25, 85).toInt(),
      sleepHours:
          ((latestMetric?.sleepHours ?? 6.4) - 0.8).clamp(4.0, 9.0).toDouble(),
      fatigueLevel: fatigueLevel,
      sorenessLevel:
          ((latestMetric?.sorenessLevel ?? 4) + 1).clamp(1, 10).toInt(),
      moodLabel: '偏疲劳',
      source: BodyMetricSource.manual,
      note: '精简签到：今天偏累，建议轻松版',
    );
    _saveMetricAndRefresh(
      metric,
      reason: '精简签到偏累覆盖同日记录',
      nextState: state.copyWith(
        dailyCheckInStatusMessage: '已记录偏累，今日建议切轻松版；晨报和提醒会按新身体数据更新。',
      ),
    );
  }

  void importCsv(String rawText) {
    try {
      final BodyMetricImportResult result = _importService.parseCsv(rawText);
      final BodyMetricRepository repository =
          ref.read(bodyMetricRepositoryProvider);
      for (final BodyMetric metric in result.metrics) {
        repository.saveMetric(
          metric,
          reason: 'CSV 导入覆盖同日记录',
        );
      }
      _refreshAfterPersistence(
        state.copyWith(
          importResults: [result, ...state.importResults],
          importStatusMessage:
              '${result.summary} 已写入 body_metrics，并会刷新趋势、质量和指标目标。',
        ),
      );
    } on FormatException catch (error) {
      state = state.copyWith(importStatusMessage: error.message);
    } catch (_) {
      state = state.copyWith(importStatusMessage: '导入失败：请检查 CSV 字段。');
    }
  }

  void clear() {
    ref.read(bodyMetricRepositoryProvider).clearMetrics();
    _refreshAfterPersistence(
      state.copyWith(
        importStatusMessage: '身体数据已清除，CSV 导入历史仍保留在本次会话状态中。',
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

  void _saveMetricAndRefresh(
    BodyMetric metric, {
    required String reason,
    required BodyMetricState nextState,
  }) {
    ref.read(bodyMetricRepositoryProvider).saveMetric(metric, reason: reason);
    _refreshAfterPersistence(nextState);
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
