import 'body_metric.dart';

class BodyMetricImportResult {
  final List<BodyMetric> metrics;
  final int skippedRows;
  final String sourceLabel;
  final List<String> rowErrors;
  final Map<String, List<String>> inheritedFieldLabelsByMetricId;

  const BodyMetricImportResult({
    required this.metrics,
    required this.skippedRows,
    required this.sourceLabel,
    this.rowErrors = const [],
    this.inheritedFieldLabelsByMetricId = const <String, List<String>>{},
  });

  int get importedCount {
    return metrics.length;
  }

  String get dateRangeLabel {
    if (metrics.isEmpty) {
      return '无有效日期';
    }
    final DateTime newest = metrics.first.measuredAt;
    final DateTime oldest = metrics.last.measuredAt;
    return '${_dateLabel(oldest)} 至 ${_dateLabel(newest)}';
  }

  String get summary {
    final int inheritedRecordCount = inheritedFieldLabelsByMetricId.length;
    final int inheritedFieldCount = inheritedFieldLabelsByMetricId.values.fold(
      0,
      (int total, List<String> labels) => total + labels.length,
    );
    final Set<String> inheritedFieldLabels = <String>{
      for (final List<String> labels in inheritedFieldLabelsByMetricId.values)
        ...labels,
    };
    final String inheritedSummary = inheritedRecordCount == 0
        ? ''
        : '；其中 $inheritedRecordCount 条沿用已保存历史值 '
            '$inheritedFieldCount 项：${inheritedFieldLabels.join('、')}';
    final errors = rowErrors.isEmpty ? '' : ' 跳过原因：${rowErrors.join('；')}';
    return '已解析 $importedCount 条身体数据，跳过 $skippedRows 行，范围 $dateRangeLabel$inheritedSummary。$errors';
  }

  String _dateLabel(DateTime value) {
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }
}
