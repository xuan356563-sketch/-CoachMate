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
  });

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
    return '${distanceKm.toStringAsFixed(2)} km · $durationMinutes 分钟 · $paceLabel · ${trainingEffect.label}';
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
    };
  }
}
