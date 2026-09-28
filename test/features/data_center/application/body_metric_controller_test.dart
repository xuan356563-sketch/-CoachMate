import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/body_metric.dart';
import 'package:trainflow_ai/data/models/body_metric_import.dart';
import 'package:trainflow_ai/data/models/daily_check_in_record.dart';
import 'package:trainflow_ai/data/repositories/body_metric_repository.dart';
import 'package:trainflow_ai/data/seed/seed_body_metrics.dart';
import 'package:trainflow_ai/features/data_center/application/body_metric_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  ProviderContainer createContainer(InMemoryLocalStorageService storage) {
    return ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
  }

  void seedStorage(InMemoryLocalStorageService storage) {
    final PersistedBodyMetricRepository repository =
        PersistedBodyMetricRepository(storage);
    for (final BodyMetric metric in seedBodyMetrics) {
      repository.saveMetric(metric, reason: '测试基线');
    }
  }

  test('初始状态不生成身体种子数据', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);

    final BodyMetricState state = container.read(bodyMetricControllerProvider);

    expect(state.metrics, isEmpty);
    expect(state.latestMetric, isNull);
    expect(state.revisions, isEmpty);
    expect(state.pendingMetric, isNull);
    expect(
      state.manualStatusMessage,
      '尚无身体记录。首次录入请使用包含完整字段的截图或 CSV，系统不会补造缺失值。',
    );
    expect(
      state.snapshotStatusMessage,
      '可粘贴体脂秤、手表或健康 App 截图中的文字，识别后需确认入库。',
    );
    expect(state.importStatusMessage, '可粘贴 Apple 健康、手表或表格导出的身体数据 CSV。');
    expect(state.dailyCheckInStatusMessage, '尚无昨日记录，不能使用预填签到。');
    expect(state.persistenceVersion, 0);
  });

  test('计划休息只写连续成长记录且不生成身体指标', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);

    await container
        .read(bodyMetricControllerProvider.notifier)
        .recordContinuityDay(DailyContinuityKind.plannedRest);

    final BodyMetricState state = container.read(bodyMetricControllerProvider);
    expect(state.metrics, isEmpty);
    expect(state.checkInStreak.currentStreak, 1);
    expect(state.dailyCheckInStatusMessage, contains('按计划恢复'));
    expect(
      container
          .read(dailyCheckInRepositoryProvider)
          .getSnapshot()
          .records
          .single
          .continuityKind,
      DailyContinuityKind.plannedRest,
    );
  });

  test('保存和重启会保留指标与同日修订', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    seedStorage(storage);
    final ProviderContainer first = createContainer(storage);
    final BodyMetric initial =
        first.read(bodyMetricControllerProvider).metrics.first;

    await first.read(bodyMetricControllerProvider.notifier).saveManualMetric(
          weightKg: initial.weightKg + 1.0,
          restingHeartRate: initial.restingHeartRate + 2,
          hrvMs: initial.hrvMs,
          sleepHours: initial.sleepHours,
          fatigueLevel: initial.fatigueLevel,
          measuredAt: initial.measuredAt,
        );

    final BodyMetricState saved = first.read(bodyMetricControllerProvider);
    expect(saved.revisions, hasLength(1));
    expect(saved.revisions.first.reason, '10 秒快录覆盖同日记录');
    expect(saved.persistenceVersion, 1);
    first.dispose();

    final ProviderContainer restored = createContainer(storage);
    addTearDown(restored.dispose);
    final BodyMetricState restoredState =
        restored.read(bodyMetricControllerProvider);
    expect(restoredState.revisions, hasLength(1));
    expect(restoredState.latestMetric?.weightKg, initial.weightKg + 1.0);
  });

  test('异常值先进入待确认且版本不变确认后写入并递增版本', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    seedStorage(storage);
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);
    final BodyMetric initial =
        container.read(bodyMetricControllerProvider).metrics.first;

    await container
        .read(bodyMetricControllerProvider.notifier)
        .saveManualMetric(
          weightKg: initial.weightKg + 3.1,
          restingHeartRate: initial.restingHeartRate + 25,
          hrvMs: initial.hrvMs,
          sleepHours: initial.sleepHours,
          fatigueLevel: initial.fatigueLevel,
          measuredAt: initial.measuredAt.add(const Duration(days: 1)),
        );

    BodyMetricState state = container.read(bodyMetricControllerProvider);
    expect(state.pendingMetric, isNotNull);
    expect(state.metrics.first.id, initial.id);
    expect(state.persistenceVersion, 0);
    expect(
      state.manualStatusMessage,
      contains('异常值确认：体重较最近记录变化 3.1 kg，超过 2 kg'),
    );
    expect(state.manualStatusMessage, contains('静息心率较 7 日均值偏离 24 bpm'));

    await container
        .read(bodyMetricControllerProvider.notifier)
        .confirmPendingMetric();

    state = container.read(bodyMetricControllerProvider);
    expect(state.pendingMetric, isNull);
    expect(state.metrics.first.weightKg, initial.weightKg + 3.1);
    expect(state.revisions, isEmpty);
    expect(state.persistenceVersion, 1);
    expect(
      state.manualStatusMessage,
      '已确认并保存异常值：${state.metrics.first.measuredDateLabel} 的身体数据。',
    );
  });

  test('没有待确认数据时只更新提示不递增版本', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);

    await container
        .read(bodyMetricControllerProvider.notifier)
        .confirmPendingMetric();

    final BodyMetricState state = container.read(bodyMetricControllerProvider);
    expect(state.persistenceVersion, 0);
    expect(state.manualStatusMessage, '没有待确认的身体数据。');
    expect(state.snapshotStatusMessage, '没有待确认的截图识别数据。');
  });

  test('截图识别只进入待确认确认后才写入仓库', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);

    container.read(bodyMetricControllerProvider.notifier).recognizeSnapshotText(
          'Apple 健康 2026-07-10\n体重 72.9\n体脂率 18.1\n静息心率 57\nHRV 55\n睡眠 7.5\n疲劳 3\n酸痛 2',
        );

    BodyMetricState state = container.read(bodyMetricControllerProvider);
    expect(state.pendingMetric?.source, BodyMetricSource.screenshot);
    expect(state.pendingMetric?.weightKg, 72.9);
    expect(state.snapshotStatusMessage, contains('请确认后写入 body_metrics。'));
    expect(state.persistenceVersion, 0);

    await container
        .read(bodyMetricControllerProvider.notifier)
        .confirmPendingMetric();

    state = container.read(bodyMetricControllerProvider);
    expect(state.pendingMetric, isNull);
    expect(state.metrics.first.source, BodyMetricSource.screenshot);
    expect(state.persistenceVersion, 1);
    expect(
      state.snapshotStatusMessage,
      '已确认截图识别数据：${state.metrics.first.measuredDateLabel} 已写入 body_metrics。',
    );
  });

  test('无历史记录时截图缺少必填值会显示清晰错误并清除旧待确认', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);

    container.read(bodyMetricControllerProvider.notifier).recognizeSnapshotText(
          'Apple 健康 2026-07-10\n体重 72.9\n体脂率 18.1\n静息心率 57\nHRV 55\n睡眠 7.5\n疲劳 3\n酸痛 2',
        );
    expect(
      container.read(bodyMetricControllerProvider).pendingMetric,
      isNotNull,
    );

    container.read(bodyMetricControllerProvider.notifier).recognizeSnapshotText(
          'Apple 健康 2026-07-10\n体重 72.9\n静息心率 57',
        );

    final BodyMetricState state = container.read(bodyMetricControllerProvider);
    expect(state.pendingMetric, isNull);
    expect(state.persistenceVersion, 0);
    expect(
      state.snapshotStatusMessage,
      '识别失败：缺少必填身体指标：体脂率、HRV、睡眠、疲劳、酸痛。请补全后重试；系统不会使用示例值补齐。',
    );
  });

  test('有历史记录时截图缺失字段只沿用旧值并在待确认文案中明确标识', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    seedStorage(storage);
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);
    final BodyMetric fallback =
        container.read(bodyMetricControllerProvider).latestMetric!;

    container.read(bodyMetricControllerProvider.notifier).recognizeSnapshotText(
          'Apple 健康 2026-07-10\n体重 72.9\n静息心率 57\n疲劳 7',
        );

    final BodyMetricState state = container.read(bodyMetricControllerProvider);
    expect(state.pendingMetric?.weightKg, 72.9);
    expect(
      state.pendingMetric?.bodyFatPercentage,
      fallback.bodyFatPercentage,
    );
    expect(state.pendingMetric?.hrvMs, fallback.hrvMs);
    expect(state.pendingMetric?.sleepHours, fallback.sleepHours);
    expect(state.pendingMetric?.sorenessLevel, fallback.sorenessLevel);
    expect(
      state.snapshotStatusMessage,
      contains('沿用上次 4 项：体脂率、HRV、睡眠、酸痛'),
    );
    expect(state.snapshotStatusMessage, contains('请确认后写入 body_metrics。'));
    expect(state.persistenceVersion, 0);
  });

  test('截图识别失败不会写入待确认也不会递增版本', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);

    container
        .read(bodyMetricControllerProvider.notifier)
        .recognizeSnapshotText('没有任何身体指标');

    final BodyMetricState state = container.read(bodyMetricControllerProvider);
    expect(state.pendingMetric, isNull);
    expect(state.persistenceVersion, 0);
    expect(state.snapshotStatusMessage, '识别失败：没有找到可用的身体指标。');
  });

  test('有效 CSV 会写入仓库记录导入结果并递增版本', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);

    await container.read(bodyMetricControllerProvider.notifier).importCsv('''
date,weight_kg,body_fat_percentage,resting_heart_rate,hrv_ms,sleep_hours,fatigue_level,soreness_level
2026-07-10,73.4,18.2,56,54,7.2,4,2
错误日期,73.2,18.1,57,53,7.0,4,3
''');

    final BodyMetricState state = container.read(bodyMetricControllerProvider);
    expect(state.metrics.first.source, BodyMetricSource.importFile);
    expect(state.importResults, hasLength(1));
    expect(state.importResults.first.importedCount, 1);
    expect(state.importResults.first.skippedRows, 1);
    expect(state.persistenceVersion, 1);
    expect(
      state.importStatusMessage,
      '${state.importResults.first.summary} 已写入 body_metrics，并会刷新趋势、质量和指标目标。',
    );
  });

  test('CSV 只有在存在历史记录时才沿用缺失字段并明确标识', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    seedStorage(storage);
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);
    final BodyMetric fallback =
        container.read(bodyMetricControllerProvider).latestMetric!;

    await container.read(bodyMetricControllerProvider.notifier).importCsv('''
date,weight_kg,resting_heart_rate,hrv_ms
2026-07-10,73.4,56,54
''');

    final BodyMetricState state = container.read(bodyMetricControllerProvider);
    final BodyMetric imported = state.metrics.first;
    expect(imported.weightKg, 73.4);
    expect(imported.bodyFatPercentage, fallback.bodyFatPercentage);
    expect(imported.sleepHours, fallback.sleepHours);
    expect(imported.fatigueLevel, fallback.fatigueLevel);
    expect(imported.sorenessLevel, fallback.sorenessLevel);
    expect(
      state.importStatusMessage,
      contains('沿用已保存历史值 4 项：体脂率、睡眠、疲劳、酸痛'),
    );
    expect(state.persistenceVersion, 1);
  });

  test('无效 CSV 只更新错误提示不写入也不递增版本', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);

    await container.read(bodyMetricControllerProvider.notifier).importCsv('''
date,weight_kg,resting_heart_rate,hrv_ms
错误日期,错误体重,错误心率,错误 HRV
''');

    final BodyMetricState state = container.read(bodyMetricControllerProvider);
    expect(state.importResults, isEmpty);
    expect(state.persistenceVersion, 0);
    expect(state.importStatusMessage, '导入失败：第 2 行：日期格式错误。');
  });

  test('每日签到和昨天一样会使用昨日指标写入今日记录', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final now = DateTime.now();
    storage.saveJson('trainflow.body_metrics.v1', {'metrics': [
      {...seedBodyMetrics.first.toJson(), 'measuredAt': DateTime(now.year, now.month, now.day - 1, 7).toIso8601String()}
    ]});
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);
    final BodyMetric latest =
        container.read(bodyMetricControllerProvider).latestMetric!;

    await container
        .read(bodyMetricControllerProvider.notifier)
        .confirmDailyCheckInSameAsYesterday();

    final BodyMetricState state = container.read(bodyMetricControllerProvider);
    expect(state.metrics.first.weightKg, latest.weightKg);
    expect(state.metrics.first.note, contains('本人确认沿用昨日记录'));
    expect(state.metrics, hasLength(2));
    expect(state.dailyCheckInStatusMessage, '已按昨日记录完成今日签到：和昨天一样（本人确认沿用，非重新测量）。');
    expect(state.persistenceVersion, 1);
  });

  test('每日偏累签到无历史指标时不生成虚构身体数据', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);
    await container
        .read(bodyMetricControllerProvider.notifier)
        .recordTiredDailyCheckIn();

    final BodyMetricState state = container.read(bodyMetricControllerProvider);
    expect(state.metrics, isEmpty);
    expect(
      state.dailyCheckInStatusMessage,
      '已完成今日主观签到：偏累；未生成或改写体重、体脂、静息心率、HRV、睡眠等身体指标。',
    );
    expect(state.persistenceVersion, 0);
  });

  test('每日偏累签到有历史指标时也不生成或改写客观身体样本', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    seedStorage(storage);
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);
    final List<BodyMetric> before = List<BodyMetric>.of(
        container.read(bodyMetricControllerProvider).metrics);

    await container
        .read(bodyMetricControllerProvider.notifier)
        .recordTiredDailyCheckIn();

    final BodyMetricState state = container.read(bodyMetricControllerProvider);
    expect(state.metrics.map((BodyMetric metric) => metric.id),
        before.map((BodyMetric metric) => metric.id));
    expect(state.metrics.first.hrvMs, before.first.hrvMs);
    expect(state.metrics.first.sleepHours, before.first.sleepHours);
    expect(state.metrics.first.fatigueLevel, before.first.fatigueLevel);
    expect(state.metrics.first.sorenessLevel, before.first.sorenessLevel);
    expect(
      state.dailyCheckInStatusMessage,
      '已完成今日主观签到：偏累；未生成或改写体重、体脂、静息心率、HRV、睡眠等身体指标。',
    );
    expect(state.persistenceVersion, 0);
  });

  test('清除指标和修订但保留本次会话 CSV 导入历史', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);

    await container.read(bodyMetricControllerProvider.notifier).importCsv('''
date,weight_kg,body_fat_percentage,resting_heart_rate,hrv_ms,sleep_hours,fatigue_level,soreness_level
2026-07-10,73.4,18.2,56,54,7.2,4,2
''');
    final BodyMetricImportResult result =
        container.read(bodyMetricControllerProvider).importResults.first;

    await container.read(bodyMetricControllerProvider.notifier).clear();

    final BodyMetricState state = container.read(bodyMetricControllerProvider);
    expect(state.metrics, isEmpty);
    expect(state.revisions, isEmpty);
    expect(state.importResults, [result]);
    expect(state.persistenceVersion, 2);
    expect(state.importStatusMessage, '身体数据已清除，CSV 导入历史仍保留在本次会话状态中。');
  });
}
