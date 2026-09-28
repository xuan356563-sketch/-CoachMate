import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/body_metric_export.dart';
import '../../../data/repositories/body_metric_export_repository.dart';
import '../../../plugins/application/feature_controller_binding.dart';
import '../../../plugins/application/plugin_runtime_provider.dart';
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
  final bool isSaving;

  const BodyMetricExportState({
    required this.records,
    required this.statusMessage,
    this.isSaving = false,
  });
}

class BodyMetricExportController extends Notifier<BodyMetricExportState> {
  Object _generation = Object();
  @override
  BodyMetricExportState build() {
    _generation = Object();
    bindFeatureController(ref, 'core.data_rights', 'bodyMetricExport', this);
    final List<BodyMetricExportRecord> records =
        ref.read(bodyMetricExportRepositoryProvider).listRecords();
    return BodyMetricExportState(
      records: records,
      statusMessage: records.isEmpty
          ? '尚未登记身体数据导出；导出 JSON、CSV 或导出包后会写入本地记录。'
          : '已登记 ${records.length} 条身体数据导出记录。',
    );
  }

  Future<void> recordJsonExport(String content) {
    return _save(
      format: BodyMetricExportFormat.json,
      byteCount: utf8.encode(content).length,
      extension: 'json',
    );
  }

  Future<void> recordCsvExport(String content) {
    return _save(
      format: BodyMetricExportFormat.csv,
      byteCount: utf8.encode(content).length,
      extension: 'csv',
    );
  }

  Future<void> recordPackageExport(String content) {
    return _save(
      format: BodyMetricExportFormat.packageSummary,
      byteCount: utf8.encode(content).length,
      extension: 'txt',
    );
  }

  Future<void> clear() async {
    final BodyMetricExportRepository repository =
        ref.read(bodyMetricExportRepositoryProvider);
    await _commit(
        repository, repository.clearConfirmedRecords, '已清除本地身体数据导出记录。');
  }

  Future<void> _save({
    required BodyMetricExportFormat format,
    required int byteCount,
    required String extension,
  }) async {
    final DateTime now = DateTime.now();
    final BodyMetricExportRecord record = BodyMetricExportRecord(
      id: 'body-metric-export-${format.jsonValue}-${now.microsecondsSinceEpoch}',
      format: format,
      metricCount: ref.read(bodyMetricControllerProvider).metrics.length,
      byteCount: byteCount,
      fileName: _fileName(format, extension, now),
      exportedAt: now,
    );
    final BodyMetricExportRepository repository =
        ref.read(bodyMetricExportRepositoryProvider);
    final String statusPrefix = format == BodyMetricExportFormat.packageSummary
        ? '已登记导出包摘要'
        : '已登记 ${record.format.label} 导出';
    await _commit(repository, () => repository.saveConfirmedRecord(record),
        '$statusPrefix：${record.metricCount} 条，${record.sizeLabel}，后续可接系统保存或分享。');
  }

  Future<void> _commit(BodyMetricExportRepository repository,
      Future<void> Function() write, String successMessage) async {
    if (state.isSaving) throw StateError('导出登记正在保存，请勿重复操作。');
    final ownerRef = ref;
    final generation = _generation;
    bool isCurrent() => ownerRef.mounted && identical(generation, _generation);
    final operation =
        ref.read(featureAccessProvider).beginOperation('core.data_rights');
    final records = state.records;
    state = BodyMetricExportState(
        records: records, statusMessage: '正在保存导出登记，请稍候。', isSaving: true);
    try {
      await operation.commit(() async {
        await write();
        if (!isCurrent()) return;
        state = BodyMetricExportState(
            records: repository.listRecords(), statusMessage: successMessage);
      });
    } catch (error) {
      if (isCurrent()) {
        state = BodyMetricExportState(
            records: records,
            statusMessage:
                error is StateError ? error.message : '导出登记保存失败，请保留当前预览并重试。');
      }
      rethrow;
    }
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
