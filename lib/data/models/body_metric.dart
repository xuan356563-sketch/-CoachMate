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
  final Set<String>? recordedFields;
  final bool sourceVerified;

  bool hasValue(String field) {
    if (!sourceVerified || (recordedFields != null && !recordedFields!.contains(field))) return false;
    return switch (field) {
      'weightKg' => weightKg.isFinite && weightKg > 0,
      'bodyFatPercentage' => bodyFatPercentage.isFinite && bodyFatPercentage > 0,
      'sleepHours' => sleepHours.isFinite && sleepHours > 0,
      'hrvMs' => hrvMs > 0,
      'restingHeartRate' => restingHeartRate > 0,
      'fatigueLevel' => fatigueLevel >= 0 && fatigueLevel <= 10,
      'sorenessLevel' => sorenessLevel >= 0 && sorenessLevel <= 10,
      _ => false,
    };
  }

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
    this.recordedFields,
    this.sourceVerified = true,
  });

  String get measuredDateLabel {
    return '${measuredAt.year}-${measuredAt.month.toString().padLeft(2, '0')}-${measuredAt.day.toString().padLeft(2, '0')}';
  }

  factory BodyMetric.fromJson(Map<String, dynamic> json) {
    // 字段清单只是声明；缺值或类型损坏不能被兼容默认值补成有效观测。
    const integerFields = {
      'restingHeartRate', 'hrvMs', 'fatigueLevel', 'sorenessLevel',
    };
    final actualFields = json.keys.where((key) {
      final value = json[key];
      return value is num && value.isFinite &&
          (!integerFields.contains(key) || value is int);
    }).toSet();
    final declaredFields = json['recordedFields'];
    final availableFields = declaredFields is List
        ? declaredFields.whereType<String>().toSet().intersection(actualFields)
        : actualFields;
    int integer(String key) => json[key] is int ? json[key] as int : 0;
    double decimal(String key) => json[key] is num ? (json[key] as num).toDouble() : 0;
    return BodyMetric(
      id: json['id'] as String? ?? '',
      sourceVerified: json['sourceVerified'] != false && BodyMetricSource.values.any((s) => s.jsonValue == json['source']),
      recordedFields: availableFields,
      measuredAt: DateTime.tryParse(json['measuredAt'] as String? ?? '') ??
          DateTime(2026),
      weightKg: decimal('weightKg'),
      bodyFatPercentage: decimal('bodyFatPercentage'),
      restingHeartRate: integer('restingHeartRate'),
      hrvMs: integer('hrvMs'),
      sleepHours: decimal('sleepHours'),
      fatigueLevel: integer('fatigueLevel'),
      sorenessLevel: integer('sorenessLevel'),
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
      if (recordedFields != null) 'recordedFields': recordedFields!.toList()..sort(),
      if (!sourceVerified) 'sourceVerified': false,
    };
  }
}
