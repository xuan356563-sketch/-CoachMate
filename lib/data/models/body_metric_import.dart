import 'body_metric.dart';

class BodyMetricImportResult {
  final List<BodyMetric> metrics;
  final int skippedRows;
  final String sourceLabel;

  const BodyMetricImportResult({
    required this.metrics,
    required this.skippedRows,
    required this.sourceLabel,
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
    return '已解析 $importedCount 条身体数据，跳过 $skippedRows 行，范围 $dateRangeLabel。';
  }

  String _dateLabel(DateTime value) {
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }
}
