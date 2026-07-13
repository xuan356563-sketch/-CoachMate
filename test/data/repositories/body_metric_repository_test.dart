import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/body_metric.dart';
import 'package:trainflow_ai/data/repositories/body_metric_repository.dart';
import 'package:trainflow_ai/data/seed/seed_body_metrics.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('没有本地 JSON 时身体数据仓库读取默认种子指标', () {
    final PersistedBodyMetricRepository repository =
        PersistedBodyMetricRepository(InMemoryLocalStorageService());

    expect(repository.listMetrics(), hasLength(seedBodyMetrics.length));
    expect(repository.listMetrics().first.id, seedBodyMetrics.first.id);
    expect(repository.listRevisions(), isEmpty);
  });

  test('身体数据仓库会兼容缺少指标和修订列表的旧 JSON', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    storage.saveJson('trainflow.body_metrics.v1', {
      'schemaVersion': 1,
      'revisions': <dynamic>[],
    });

    PersistedBodyMetricRepository repository =
        PersistedBodyMetricRepository(storage);
    expect(repository.listMetrics(), isEmpty);
    expect(repository.listRevisions(), isEmpty);

    storage.saveJson('trainflow.body_metrics.v1', {
      'schemaVersion': 1,
      'metrics': [seedBodyMetrics.first.toJson()],
    });
    repository = PersistedBodyMetricRepository(storage);
    expect(repository.listMetrics(), hasLength(1));
    expect(repository.listMetrics().first.id, seedBodyMetrics.first.id);
    expect(repository.listRevisions(), isEmpty);
  });

  test('身体数据仓库会持久化指标和修订留痕并支持清除', () {
    final InMemoryLocalStorageService storageService =
        InMemoryLocalStorageService();
    final PersistedBodyMetricRepository repository =
        PersistedBodyMetricRepository(storageService);
    final BodyMetric originalMetric = repository.listMetrics().first;
    final BodyMetric revisedMetric = BodyMetric(
      id: 'body-metric-test-revised',
      measuredAt: originalMetric.measuredAt,
      weightKg: originalMetric.weightKg + 1.2,
      bodyFatPercentage: originalMetric.bodyFatPercentage,
      restingHeartRate: originalMetric.restingHeartRate + 3,
      hrvMs: originalMetric.hrvMs,
      sleepHours: originalMetric.sleepHours,
      fatigueLevel: originalMetric.fatigueLevel,
      sorenessLevel: originalMetric.sorenessLevel,
      moodLabel: '测试修订',
      source: BodyMetricSource.manual,
      note: '测试持久化覆盖',
    );

    repository.saveMetric(revisedMetric, reason: '测试同日覆盖');

    final PersistedBodyMetricRepository restoredRepository =
        PersistedBodyMetricRepository(storageService);
    expect(
      restoredRepository.listMetrics().first.weightKg,
      revisedMetric.weightKg,
    );
    expect(restoredRepository.listRevisions(), hasLength(1));
    expect(restoredRepository.listRevisions().first.reason, '测试同日覆盖');

    restoredRepository.clearMetrics();

    final PersistedBodyMetricRepository clearedRepository =
        PersistedBodyMetricRepository(storageService);
    expect(clearedRepository.listMetrics(), isEmpty);
    expect(clearedRepository.listRevisions(), isEmpty);
  });
}
