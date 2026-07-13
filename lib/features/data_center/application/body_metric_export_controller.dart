import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/body_metric_export.dart';
import '../../../data/repositories/body_metric_export_repository.dart';
import '../../../services/local_storage_service.dart';
import 'body_metric_controller.dart';

final bodyMetricExportRepositoryProvider = Provider<BodyMetricExportRepository>(
  (Ref ref) => PersistedBodyMetricExportRepository(
    ref.watch(localStorageServiceProvider),
  ),
);

final bodyMetricExportControllerProvider =
    NotifierProvider<BodyMetricExportController, BodyMetricExportState>(
  BodyMetricExportController.new,
);

class BodyMetricExportState {
  final List<BodyMetricExportRecord> records;
  final String statusMessage;

  const BodyMetricExportState({
    required this.records,
    required this.statusMessage,
  });
}

class BodyMetricExportController extends Notifier<BodyMetricExportState> {
  @override
  BodyMetricExportState build() {
    final List<BodyMetricExportRecord> records =
        ref.read(bodyMetricExportRepositoryProvider).listRecords();
    return BodyMetricExportState(
      records: records,
      statusMessage: records.isEmpty
          ? '尚未登记身体数据导出；导出 JSON、CSV 或导出包后会写入本地记录。'
          : '已登记 ${records.length} 条身体数据导出记录。',
    );
  }

  void recordJsonExport(String content) {
    _save(
      format: BodyMetricExportFormat.json,
      byteCount: utf8.encode(content).length,
      extension: 'json',
    );
  }

  void recordCsvExport(String content) {
    _save(
      format: BodyMetricExportFormat.csv,
      byteCount: utf8.encode(content).length,
      extension: 'csv',
    );
  }

  void recordPackageExport(String content) {
    _save(
      format: BodyMetricExportFormat.packageSummary,
      byteCount: utf8.encode(content).length,
      extension: 'txt',
    );
  }

  void clear() {
    final BodyMetricExportRepository repository =
        ref.read(bodyMetricExportRepositoryProvider);
    repository.clearRecords();
    state = BodyMetricExportState(
      records: repository.listRecords(),
      statusMessage: '已清除本地身体数据导出记录。',
    );
  }

  void _save({
    required BodyMetricExportFormat format,
    required int byteCount,
    required String extension,
  }) {
    final DateTime now = DateTime.now();
    final BodyMetricExportRecord record = BodyMetricExportRecord(
      id: 'body-metric-export-${format.jsonValue}-${now.millisecondsSinceEpoch}',
      format: format,
      metricCount: ref.read(bodyMetricControllerProvider).metrics.length,
      byteCount: byteCount,
      fileName: _fileName(format, extension, now),
      exportedAt: now,
    );
    final BodyMetricExportRepository repository =
        ref.read(bodyMetricExportRepositoryProvider);
    repository.saveRecord(record);
    final String statusPrefix = format == BodyMetricExportFormat.packageSummary
        ? '已登记导出包摘要'
        : '已登记 ${record.format.label} 导出';
    state = BodyMetricExportState(
      records: repository.listRecords(),
      statusMessage:
          '$statusPrefix：${record.metricCount} 条，${record.sizeLabel}，后续可接系统保存或分享。',
    );
  }
}

String _fileName(
  BodyMetricExportFormat format,
  String extension,
  DateTime now,
) {
  final String month = now.month.toString().padLeft(2, '0');
  final String day = now.day.toString().padLeft(2, '0');
  return 'trainflow_body_metrics_${format.jsonValue}_${now.year}$month$day.$extension';
}
