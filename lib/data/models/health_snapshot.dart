class HealthSnapshot {
  final String id;
  final DateTime date;
  final double? sleepHours;
  final int? restingHeartRate;
  final int? hrvMs;
  final double? weightKg;
  final double? bodyFatPercentage;
  final DateTime syncedAt;

  /// 用于兼容摘要删除传播的 HealthKit 样本 UUID 集合。
  ///
  /// 字段名为历史兼容保留，不得写入来源应用 bundle/source ID。
  final List<String> sourceIds;
  final int sourceLineageVersion;

  const HealthSnapshot({
    required this.id,
    required this.date,
    required this.sleepHours,
    required this.restingHeartRate,
    required this.hrvMs,
    required this.weightKg,
    required this.bodyFatPercentage,
    required this.syncedAt,
    this.sourceIds = const <String>[],
    this.sourceLineageVersion = 1,
  });

  factory HealthSnapshot.fromJson(Map<String, dynamic> json) => HealthSnapshot(
        id: json['id'] as String? ?? '',
        date:
            DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime(2026),
        sleepHours: (json['sleepHours'] as num?)?.toDouble(),
        restingHeartRate: (json['restingHeartRate'] as num?)?.round(),
        hrvMs: (json['hrvMs'] as num?)?.round(),
        weightKg: (json['weightKg'] as num?)?.toDouble(),
        bodyFatPercentage: (json['bodyFatPercentage'] as num?)?.toDouble(),
        syncedAt: DateTime.tryParse(json['syncedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        sourceIds: (json['sourceIds'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<String>()
            .toList(growable: false),
        sourceLineageVersion:
            (json['sourceLineageVersion'] as num?)?.toInt() ?? 1,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': DateTime(date.year, date.month, date.day).toIso8601String(),
        'sleepHours': sleepHours,
        'restingHeartRate': restingHeartRate,
        'hrvMs': hrvMs,
        'weightKg': weightKg,
        'bodyFatPercentage': bodyFatPercentage,
        'syncedAt': syncedAt.toIso8601String(),
        'sourceIds': sourceIds,
        'sourceLineageVersion': sourceLineageVersion,
      };
}
