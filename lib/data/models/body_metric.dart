enum BodyMetricSource {
  manual,
  screenshot,
  wearable,
  importFile,
}

extension BodyMetricSourceJson on BodyMetricSource {
  String get jsonValue {
    switch (this) {
      case BodyMetricSource.manual:
        return 'manual';
      case BodyMetricSource.screenshot:
        return 'screenshot';
      case BodyMetricSource.wearable:
        return 'wearable';
      case BodyMetricSource.importFile:
        return 'import_file';
    }
  }

  String get label {
    switch (this) {
      case BodyMetricSource.manual:
        return '手动录入';
      case BodyMetricSource.screenshot:
        return '截图识别';
      case BodyMetricSource.wearable:
        return '穿戴设备';
      case BodyMetricSource.importFile:
        return '文件导入';
    }
  }
}

BodyMetricSource bodyMetricSourceFromJson(String? value) {
  switch (value) {
    case 'manual':
      return BodyMetricSource.manual;
    case 'screenshot':
      return BodyMetricSource.screenshot;
    case 'wearable':
      return BodyMetricSource.wearable;
    case 'import_file':
      return BodyMetricSource.importFile;
    default:
      return BodyMetricSource.manual;
  }
}

class BodyMetric {
  final String id;
  final DateTime measuredAt;
  final double weightKg;
  final double bodyFatPercentage;
  final int restingHeartRate;
  final int hrvMs;
  final double sleepHours;
  final int fatigueLevel;
  final int sorenessLevel;
  final String moodLabel;
  final BodyMetricSource source;
  final String note;

  const BodyMetric({
    required this.id,
    required this.measuredAt,
    required this.weightKg,
    required this.bodyFatPercentage,
    required this.restingHeartRate,
    required this.hrvMs,
    required this.sleepHours,
    required this.fatigueLevel,
    required this.sorenessLevel,
    required this.moodLabel,
    required this.source,
    required this.note,
  });

  String get measuredDateLabel {
    return '${measuredAt.year}-${measuredAt.month.toString().padLeft(2, '0')}-${measuredAt.day.toString().padLeft(2, '0')}';
  }

  factory BodyMetric.fromJson(Map<String, dynamic> json) {
    return BodyMetric(
      id: json['id'] as String? ?? '',
      measuredAt: DateTime.tryParse(json['measuredAt'] as String? ?? '') ??
          DateTime(2026),
      weightKg: (json['weightKg'] as num?)?.toDouble() ?? 0,
      bodyFatPercentage: (json['bodyFatPercentage'] as num?)?.toDouble() ?? 0,
      restingHeartRate: json['restingHeartRate'] as int? ?? 0,
      hrvMs: json['hrvMs'] as int? ?? 0,
      sleepHours: (json['sleepHours'] as num?)?.toDouble() ?? 0,
      fatigueLevel: json['fatigueLevel'] as int? ?? 0,
      sorenessLevel: json['sorenessLevel'] as int? ?? 0,
      moodLabel: json['moodLabel'] as String? ?? '',
      source: bodyMetricSourceFromJson(json['source'] as String?),
      note: json['note'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'measuredAt': measuredAt.toIso8601String(),
      'weightKg': weightKg,
      'bodyFatPercentage': bodyFatPercentage,
      'restingHeartRate': restingHeartRate,
      'hrvMs': hrvMs,
      'sleepHours': sleepHours,
      'fatigueLevel': fatigueLevel,
      'sorenessLevel': sorenessLevel,
      'moodLabel': moodLabel,
      'source': source.jsonValue,
      'note': note,
    };
  }
}
