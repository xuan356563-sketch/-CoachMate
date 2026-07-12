import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/body_metric.dart';
import 'package:trainflow_ai/data/models/body_metric_import.dart';
import 'package:trainflow_ai/features/data_center/application/body_metric_controller.dart';
import 'package:trainflow_ai/features/profile/application/user_profile_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  ProviderContainer createContainer(InMemoryLocalStorageService storage) {
    return ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
  }

  test('初始状态读取默认种子和原身体记录文案', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);

    final BodyMetricState state = container.read(bodyMetricControllerProvider);

    expect(state.metrics, hasLength(7));
    expect(state.latestMetric?.id, 'body-metric-2026-07-09');
    expect(state.revisions, isEmpty);
    expect(state.pendingMetric, isNull);
    expect(state.manualStatusMessage, '默认预填上次值；可选择今天、昨天或前天补录。');
    expect(
      state.snapshotStatusMessage,
      '可粘贴体脂秤、手表或健康 App 截图中的文字，识别后需确认入库。',
    );
    expect(state.importStatusMessage, '可粘贴 Apple 健康、手表或表格导出的身体数据 CSV。');
    expect(state.dailyCheckInStatusMessage, '根据当前画像，今天可以先使用预填签到。');
    expect(state.persistenceVersion, 0);
  });

  test('保存和重启会保留指标与同日修订', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer first = createContainer(storage);
    final BodyMetric initial =
        first.read(bodyMetricControllerProvider).metrics.first;

    first.read(bodyMetricControllerProvider.notifier).saveManualMetric(
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

  test('异常值先进入待确认且版本不变确认后写入并递增版本', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);
    final BodyMetric initial =
        container.read(bodyMetricControllerProvider).metrics.first;

    container.read(bodyMetricControllerProvider.notifier).saveManualMetric(
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

    container
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

  test('没有待确认数据时只更新提示不递增版本', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);

    container
        .read(bodyMetricControllerProvider.notifier)
        .confirmPendingMetric();

    final BodyMetricState state = container.read(bodyMetricControllerProvider);
    expect(state.persistenceVersion, 0);
    expect(state.manualStatusMessage, '没有待确认的身体数据。');
    expect(state.snapshotStatusMessage, '没有待确认的截图识别数据。');
  });

  test('截图识别只进入待确认确认后才写入仓库', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);

    container.read(bodyMetricControllerProvider.notifier).recognizeSnapshotText(
          'Apple 健康 2026-07-10\n体重 72.9\n静息心率 57\nHRV 55\n睡眠 7.5\n疲劳 3',
        );

    BodyMetricState state = container.read(bodyMetricControllerProvider);
    expect(state.pendingMetric?.source, BodyMetricSource.screenshot);
    expect(state.pendingMetric?.weightKg, 72.9);
    expect(state.snapshotStatusMessage, contains('请确认后写入 body_metrics。'));
    expect(state.persistenceVersion, 0);

    container
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

  test('有效 CSV 会写入仓库记录导入结果并递增版本', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);

    container.read(bodyMetricControllerProvider.notifier).importCsv('''
date,weight_kg,resting_heart_rate,hrv_ms,sleep_hours,fatigue_level
2026-07-10,73.4,56,54,7.2,4
错误日期,73.2,57,53,7.0,4
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

  test('无效 CSV 只更新错误提示不写入也不递增版本', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);

    container.read(bodyMetricControllerProvider.notifier).importCsv('''
date,weight_kg,resting_heart_rate,hrv_ms
错误日期,错误体重,错误心率,错误 HRV
''');

    final BodyMetricState state = container.read(bodyMetricControllerProvider);
    expect(state.importResults, isEmpty);
    expect(state.persistenceVersion, 0);
    expect(state.importStatusMessage, '导入失败：没有解析到有效身体数据。');
  });

  test('每日签到和昨天一样会使用最新指标写入今日记录', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);
    final BodyMetric latest =
        container.read(bodyMetricControllerProvider).latestMetric!;

    container
        .read(bodyMetricControllerProvider.notifier)
        .confirmDailyCheckInSameAsYesterday();

    final BodyMetricState state = container.read(bodyMetricControllerProvider);
    expect(state.metrics.first.weightKg, latest.weightKg);
    expect(state.metrics.first.note, '精简签到：和昨天一样');
    expect(state.dailyCheckInStatusMessage, '已按画像预填完成今日签到：和昨天一样。');
    expect(state.persistenceVersion, 1);
  });

  test('每日偏累签到无历史指标时从用户画像读取体重兜底', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);
    final double profileWeight =
        container.read(userProfileControllerProvider).profile.weightKg;

    container.read(bodyMetricControllerProvider.notifier).clear();
    container
        .read(bodyMetricControllerProvider.notifier)
        .recordTiredDailyCheckIn();

    final BodyMetricState state = container.read(bodyMetricControllerProvider);
    expect(state.metrics.first.weightKg, profileWeight);
    expect(state.metrics.first.moodLabel, '偏疲劳');
    expect(state.metrics.first.note, '精简签到：今天偏累，建议轻松版');
    expect(
      state.dailyCheckInStatusMessage,
      '已记录偏累，今日建议切轻松版；晨报和提醒会按新身体数据更新。',
    );
    expect(state.persistenceVersion, 2);
  });

  test('清除指标和修订但保留本次会话 CSV 导入历史', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);

    container.read(bodyMetricControllerProvider.notifier).importCsv('''
date,weight_kg,resting_heart_rate,hrv_ms
2026-07-10,73.4,56,54
''');
    final BodyMetricImportResult result =
        container.read(bodyMetricControllerProvider).importResults.first;

    container.read(bodyMetricControllerProvider.notifier).clear();

    final BodyMetricState state = container.read(bodyMetricControllerProvider);
    expect(state.metrics, isEmpty);
    expect(state.revisions, isEmpty);
    expect(state.importResults, [result]);
    expect(state.persistenceVersion, 2);
    expect(state.importStatusMessage, '身体数据已清除，CSV 导入历史仍保留在本次会话状态中。');
  });
}
