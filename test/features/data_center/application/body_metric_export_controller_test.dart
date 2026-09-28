import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/body_metric.dart';
import 'package:trainflow_ai/data/models/body_metric_export.dart';
import 'package:trainflow_ai/data/repositories/body_metric_repository.dart';
import 'package:trainflow_ai/data/seed/seed_body_metrics.dart';
import 'package:trainflow_ai/features/data_center/application/body_metric_export_controller.dart';
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
      repository.saveMetric(metric, reason: '测试导出基线');
    }
  }

  test('初始状态、三种导出和重新读取保持原有行为', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    seedStorage(storage);
    final ProviderContainer first = createContainer(storage);

    expect(first.read(bodyMetricExportControllerProvider).records, isEmpty);
    expect(
      first.read(bodyMetricExportControllerProvider).statusMessage,
      contains('尚未登记身体数据导出'),
    );

    final BodyMetricExportController controller =
        first.read(bodyMetricExportControllerProvider.notifier);
    await controller.recordJsonExport('{"name":"训练"}');
    await controller.recordCsvExport('date,weight\n2026-07-12,72.5');
    await controller.recordPackageExport('TrainFlow 导出包摘要');

    final BodyMetricExportState saved =
        first.read(bodyMetricExportControllerProvider);
    expect(saved.records, hasLength(3));
    expect(saved.records.first.format, BodyMetricExportFormat.packageSummary);
    expect(saved.records.every((record) => record.metricCount == 7), isTrue);
    expect(saved.records.last.byteCount, greaterThan('{"name":""}'.length));
    expect(saved.records.last.fileName, endsWith('.json'));
    expect(saved.statusMessage, contains('已登记导出包摘要'));
    first.dispose();

    final ProviderContainer restored = createContainer(storage);
    addTearDown(restored.dispose);
    expect(
      restored.read(bodyMetricExportControllerProvider).records,
      hasLength(3),
    );
    expect(
      restored.read(bodyMetricExportControllerProvider).statusMessage,
      '已登记 3 条身体数据导出记录。',
    );
  });

  test('导出记录可以清除', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);
    final BodyMetricExportController controller =
        container.read(bodyMetricExportControllerProvider.notifier);

    await controller.recordJsonExport('{"index":1}');
    expect(container.read(bodyMetricExportControllerProvider).records,
        hasLength(1));

    await controller.clear();
    final BodyMetricExportState cleared =
        container.read(bodyMetricExportControllerProvider);
    expect(cleared.records, isEmpty);
    expect(cleared.statusMessage, '已清除本地身体数据导出记录。');
  });
}
