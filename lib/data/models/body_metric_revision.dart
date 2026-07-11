import 'body_metric.dart';

class BodyMetricRevision {
  final String id;
  final BodyMetric previousMetric;
  final BodyMetric revisedMetric;
  final DateTime revisedAt;
  final String reason;

  const BodyMetricRevision({
    required this.id,
    required this.previousMetric,
    required this.revisedMetric,
    required this.revisedAt,
    required this.reason,
  });

  factory BodyMetricRevision.fromJson(Map<String, dynamic> json) {
    return BodyMetricRevision(
      id: json['id'] as String? ?? '',
      previousMetric: BodyMetric.fromJson(
        json['previousMetric'] as Map<String, dynamic>? ?? const {},
      ),
      revisedMetric: BodyMetric.fromJson(
        json['revisedMetric'] as Map<String, dynamic>? ?? const {},
      ),
      revisedAt: DateTime.tryParse(json['revisedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      reason: json['reason'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'previousMetric': previousMetric.toJson(),
      'revisedMetric': revisedMetric.toJson(),
      'revisedAt': revisedAt.toIso8601String(),
      'reason': reason,
    };
  }

  String get measuredDateLabel {
    return revisedMetric.measuredDateLabel;
  }

  String get revisedAtLabel {
    return '${revisedAt.year}-${revisedAt.month.toString().padLeft(2, '0')}-${revisedAt.day.toString().padLeft(2, '0')} ${revisedAt.hour.toString().padLeft(2, '0')}:${revisedAt.minute.toString().padLeft(2, '0')}';
  }

  String get weightChangeLabel {
    return '${previousMetric.weightKg.toStringAsFixed(1)} → ${revisedMetric.weightKg.toStringAsFixed(1)} kg';
  }

  String get restingHrChangeLabel {
    return '${previousMetric.restingHeartRate} → ${revisedMetric.restingHeartRate} bpm';
  }

  String get sourceChangeLabel {
    return '${previousMetric.source.label} → ${revisedMetric.source.label}';
  }
}
