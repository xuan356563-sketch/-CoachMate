import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/body_metric_export.dart';
import 'package:trainflow_ai/data/repositories/body_metric_export_repository.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('身体数据导出仓库持久化记录、限制五十条并支持清除', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final PersistedBodyMetricExportRepository repository =
        PersistedBodyMetricExportRepository(storage);

    for (int index = 0; index < 55; index += 1) {
      repository.saveRecord(
        BodyMetricExportRecord(
          id: 'body-export-$index',
          format: index.isEven
              ? BodyMetricExportFormat.json
              : BodyMetricExportFormat.packageSummary,
          metricCount: 3,
          byteCount: 1024 + index,
          fileName: 'trainflow_body_metrics_$index.json',
          exportedAt: DateTime(2026, 7, 9, 8).add(Duration(minutes: index)),
        ),
      );
    }

    final PersistedBodyMetricExportRepository restored =
        PersistedBodyMetricExportRepository(storage);
    expect(restored.listRecords(), hasLength(50));
    expect(restored.listRecords().first.id, 'body-export-54');
    expect(restored.listRecords().last.id, 'body-export-5');

    restored.clearRecords();
    expect(
      PersistedBodyMetricExportRepository(storage).listRecords(),
      isEmpty,
    );
  });
}
