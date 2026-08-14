enum ImportedWorkoutSource {
  gpx,
  fitSummary,
}

extension ImportedWorkoutSourceLabel on ImportedWorkoutSource {
  String get label {
    switch (this) {
      case ImportedWorkoutSource.gpx:
        return 'GPX';
      case ImportedWorkoutSource.fitSummary:
        return 'FIT 摘要';
    }
  }

  String get jsonValue {
    switch (this) {
      case ImportedWorkoutSource.gpx:
        return 'gpx';
      case ImportedWorkoutSource.fitSummary:
        return 'fit_summary';
    }
  }
}

ImportedWorkoutSource importedWorkoutSourceFromJson(String? value) {
  switch (value) {
    case 'fit_summary':
      return ImportedWorkoutSource.fitSummary;
    case 'gpx':
    default:
      return ImportedWorkoutSource.gpx;
  }
}

enum TrainingEffectLabel {
  recovery,
  aerobic,
  anaerobic,
}

extension TrainingEffectLabelText on TrainingEffectLabel {
  String get label {
    switch (this) {
      case TrainingEffectLabel.recovery:
        return '恢复刺激';
      case TrainingEffectLabel.aerobic:
        return '有氧刺激';
      case TrainingEffectLabel.anaerobic:
        return '无氧刺激';
    }
  }

  String get jsonValue {
    switch (this) {
      case TrainingEffectLabel.recovery:
        return 'recovery';
      case TrainingEffectLabel.aerobic:
        return 'aerobic';
      case TrainingEffectLabel.anaerobic:
        return 'anaerobic';
    }
  }
}

TrainingEffectLabel trainingEffectLabelFromJson(String? value) {
  switch (value) {
    case 'anaerobic':
      return TrainingEffectLabel.anaerobic;
    case 'recovery':
      return TrainingEffectLabel.recovery;
    case 'aerobic':
    default:
      return TrainingEffectLabel.aerobic;
  }
}

class RouteShapePoint {
  const RouteShapePoint({
    required this.x,
    required this.y,
    required this.progress,
    required this.segmentIndex,
  });

  final double x;
  final double y;
  final double progress;
  final int segmentIndex;

  factory RouteShapePoint.fromJson(Map<String, dynamic> json) {
    return RouteShapePoint(
      x: ((json['x'] as num?)?.toDouble() ?? 0).clamp(0, 1).toDouble(),
      y: ((json['y'] as num?)?.toDouble() ?? 0).clamp(0, 1).toDouble(),
      progress:
          ((json['progress'] as num?)?.toDouble() ?? 0).clamp(0, 1).toDouble(),
      segmentIndex:
          ((json['segmentIndex'] as num?)?.toInt() ?? 0).clamp(0, 9999).toInt(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'x': x,
        'y': y,
        'progress': progress,
        'segmentIndex': segmentIndex,
      };
}

class ImportedWorkout {
  final String id;
  final ImportedWorkoutSource source;
  final String title;
  final DateTime startedAt;
  final double distanceKm;
  final int durationMinutes;
  final int elevationGainMeters;
  final int averageHeartRate;
  final TrainingEffectLabel trainingEffect;
  final String sourceFingerprint;
  final List<RouteShapePoint> routeShape;

  const ImportedWorkout({
    required this.id,
    required this.source,
    required this.title,
    required this.startedAt,
    required this.distanceKm,
    required this.durationMinutes,
    required this.elevationGainMeters,
    required this.averageHeartRate,
    required this.trainingEffect,
    this.sourceFingerprint = '',
    this.routeShape = const <RouteShapePoint>[],
  });

  bool get hasRouteShape => routeShape.length >= 2;

  String get dateLabel {
    return '${startedAt.year}-${startedAt.month.toString().padLeft(2, '0')}-${startedAt.day.toString().padLeft(2, '0')}';
  }

  String get paceLabel {
    if (distanceKm <= 0 || durationMinutes <= 0) {
      return '无配速';
    }
    final double paceMinutes = durationMinutes / distanceKm;
    final int minutes = paceMinutes.floor();
    final int seconds = ((paceMinutes - minutes) * 60).round();
    return '$minutes:${seconds.toString().padLeft(2, '0')} /km';
  }

  String get summary {
    final String durationLabel =
        durationMinutes > 0 ? '$durationMinutes 分钟' : '时长未提供';
    return '${distanceKm.toStringAsFixed(2)} km · $durationLabel · $paceLabel · ${trainingEffect.label}';
  }

  ImportedWorkout withoutRouteShape() {
    return ImportedWorkout(
      id: id,
      source: source,
      title: title,
      startedAt: startedAt,
      distanceKm: distanceKm,
      durationMinutes: durationMinutes,
      elevationGainMeters: elevationGainMeters,
      averageHeartRate: averageHeartRate,
      trainingEffect: trainingEffect,
      sourceFingerprint: sourceFingerprint,
    );
  }

  factory ImportedWorkout.fromJson(Map<String, dynamic> json) {
    return ImportedWorkout(
      id: json['id'] as String? ?? '',
      source: importedWorkoutSourceFromJson(json['source'] as String?),
      title: json['title'] as String? ?? '',
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? '') ??
          DateTime(2026),
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
      durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
      elevationGainMeters: (json['elevationGainMeters'] as num?)?.toInt() ?? 0,
      averageHeartRate: (json['averageHeartRate'] as num?)?.toInt() ?? 0,
      trainingEffect:
          trainingEffectLabelFromJson(json['trainingEffect'] as String?),
      sourceFingerprint: json['sourceFingerprint'] as String? ?? '',
      routeShape: List<RouteShapePoint>.unmodifiable(
        (json['routeShape'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(RouteShapePoint.fromJson),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'source': source.jsonValue,
      'title': title,
      'startedAt': startedAt.toIso8601String(),
      'distanceKm': distanceKm,
      'durationMinutes': durationMinutes,
      'elevationGainMeters': elevationGainMeters,
      'averageHeartRate': averageHeartRate,
      'trainingEffect': trainingEffect.jsonValue,
      if (sourceFingerprint.isNotEmpty) 'sourceFingerprint': sourceFingerprint,
      if (routeShape.isNotEmpty)
        'routeShape': routeShape
            .map((RouteShapePoint point) => point.toJson())
            .toList(growable: false),
    };
  }
}
