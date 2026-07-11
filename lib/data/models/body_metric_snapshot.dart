import 'body_metric.dart';

class BodyMetricSnapshotRecognitionResult {
  final BodyMetric metric;
  final int matchedFieldCount;
  final String sourceLabel;

  const BodyMetricSnapshotRecognitionResult({
    required this.metric,
    required this.matchedFieldCount,
    required this.sourceLabel,
  });

  String get confidenceLabel {
    if (matchedFieldCount >= 4) {
      return '高置信';
    }
    if (matchedFieldCount >= 2) {
      return '中置信';
    }
    return '低置信';
  }

  String get summary {
    return '已识别 $matchedFieldCount 项身体指标，$confidenceLabel，来源 $sourceLabel。';
  }
}
