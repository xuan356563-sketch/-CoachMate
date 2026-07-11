enum TrainingLogKind {
  manual('manual'),
  playerStep('playerStep'),
  sessionReview('sessionReview'),
  activityImport('activityImport');

  final String jsonValue;

  const TrainingLogKind(this.jsonValue);

  static TrainingLogKind fromJson(String? value, String? userNote) {
    for (final TrainingLogKind kind in TrainingLogKind.values) {
      if (kind.jsonValue == value) {
        return kind;
      }
    }
    if (userNote?.startsWith('[跟练执行]') ?? false) {
      return TrainingLogKind.playerStep;
    }
    return TrainingLogKind.manual;
  }
}

class ExerciseExecutionRecord {
  final String? exerciseId;
  final String exerciseName;
  final int plannedSetCount;
  final int completedSetCount;
  final int repetitionsPerSet;
  final double weightKg;

  const ExerciseExecutionRecord({
    required this.exerciseId,
    required this.exerciseName,
    required this.plannedSetCount,
    required this.completedSetCount,
    required this.repetitionsPerSet,
    required this.weightKg,
  });

  factory ExerciseExecutionRecord.fromJson(Map<String, dynamic> json) {
    return ExerciseExecutionRecord(
      exerciseId: json['exerciseId'] as String?,
      exerciseName: json['exerciseName'] as String? ?? '未命名动作',
      plannedSetCount: ((json['plannedSetCount'] as num?)?.toInt() ?? 0)
          .clamp(0, 99)
          .toInt(),
      completedSetCount: ((json['completedSetCount'] as num?)?.toInt() ?? 0)
          .clamp(0, 99)
          .toInt(),
      repetitionsPerSet: ((json['repetitionsPerSet'] as num?)?.toInt() ?? 0)
          .clamp(0, 999)
          .toInt(),
      weightKg: ((json['weightKg'] as num?)?.toDouble() ?? 0)
          .clamp(0, 500)
          .toDouble(),
    );
  }

  String get setSummary {
    final String setLabel = plannedSetCount > 0
        ? '$completedSetCount/$plannedSetCount 组'
        : '$completedSetCount 组';
    final List<String> items = [setLabel];
    if (repetitionsPerSet > 0) {
      items.add('$repetitionsPerSet 次/组');
    }
    if (weightKg > 0) {
      items.add('${weightKg.toStringAsFixed(1)} kg');
    }
    return items.join(' · ');
  }

  Map<String, dynamic> toJson() {
    return {
      'exerciseId': exerciseId,
      'exerciseName': exerciseName,
      'plannedSetCount': plannedSetCount,
      'completedSetCount': completedSetCount,
      'repetitionsPerSet': repetitionsPerSet,
      'weightKg': weightKg,
    };
  }
}

class TrainingLog {
  final String id;
  final String workoutDayId;
  final DateTime date;
  final bool completed;
  final int rpe;
  final int fatigueLevel;
  final int sleepQuality;
  final String? painNote;
  final String? userNote;
  final DateTime createdAt;
  final TrainingLogKind kind;
  final int actualDurationMinutes;
  final int completionPercentage;
  final int averageHeartRate;
  final int averagePaceSecondsPerKm;
  final int plannedSetCount;
  final int completedSetCount;
  final String? interruptionReason;
  final List<ExerciseExecutionRecord> exerciseRecords;

  const TrainingLog({
    required this.id,
    required this.workoutDayId,
    required this.date,
    required this.completed,
    required this.rpe,
    required this.fatigueLevel,
    required this.sleepQuality,
    required this.painNote,
    required this.userNote,
    required this.createdAt,
    this.kind = TrainingLogKind.manual,
    this.actualDurationMinutes = 0,
    this.completionPercentage = 0,
    this.averageHeartRate = 0,
    this.averagePaceSecondsPerKm = 0,
    this.plannedSetCount = 0,
    this.completedSetCount = 0,
    this.interruptionReason,
    this.exerciseRecords = const [],
  });

  factory TrainingLog.fromJson(Map<String, dynamic> json) {
    final String? userNote = json['userNote'] as String?;
    final List<dynamic> exerciseRecordsJson =
        json['exerciseRecords'] as List<dynamic>? ?? [];
    return TrainingLog(
      id: json['id'] as String? ?? '',
      workoutDayId: json['workoutDayId'] as String? ?? '',
      date: DateTime.tryParse(json['date'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      completed: json['completed'] as bool? ?? false,
      rpe: (json['rpe'] as num?)?.toInt() ?? 0,
      fatigueLevel: (json['fatigueLevel'] as num?)?.toInt() ?? 0,
      sleepQuality: (json['sleepQuality'] as num?)?.toInt() ?? 0,
      painNote: json['painNote'] as String?,
      userNote: userNote,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      kind: TrainingLogKind.fromJson(json['logKind'] as String?, userNote),
      actualDurationMinutes:
          ((json['actualDurationMinutes'] as num?)?.toInt() ?? 0)
              .clamp(0, 360)
              .toInt(),
      completionPercentage:
          ((json['completionPercentage'] as num?)?.toInt() ?? 0)
              .clamp(0, 100)
              .toInt(),
      averageHeartRate: ((json['averageHeartRate'] as num?)?.toInt() ?? 0)
          .clamp(0, 260)
          .toInt(),
      averagePaceSecondsPerKm:
          ((json['averagePaceSecondsPerKm'] as num?)?.toInt() ?? 0)
              .clamp(0, 3600)
              .toInt(),
      plannedSetCount: ((json['plannedSetCount'] as num?)?.toInt() ?? 0)
          .clamp(0, 99)
          .toInt(),
      completedSetCount: ((json['completedSetCount'] as num?)?.toInt() ?? 0)
          .clamp(0, 99)
          .toInt(),
      interruptionReason: json['interruptionReason'] as String?,
      exerciseRecords: List<ExerciseExecutionRecord>.unmodifiable(
        exerciseRecordsJson
            .whereType<Map<String, dynamic>>()
            .map(ExerciseExecutionRecord.fromJson),
      ),
    );
  }

  bool get isSessionRecord => kind != TrainingLogKind.playerStep;

  bool get isSessionReview => kind == TrainingLogKind.sessionReview;

  int get normalizedCompletionPercentage {
    if (completionPercentage > 0 || !completed) {
      return completionPercentage;
    }
    return 100;
  }

  String get averagePaceLabel {
    if (averagePaceSecondsPerKm <= 0) {
      return '未记录';
    }
    final int minutes = averagePaceSecondsPerKm ~/ 60;
    final int seconds = averagePaceSecondsPerKm % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')} /km';
  }

  String get sessionReviewSummary {
    final List<String> items = [
      '实际 $actualDurationMinutes 分钟',
      '$normalizedCompletionPercentage% 完成',
      'RPE $rpe',
    ];
    if (averageHeartRate > 0) {
      items.add('均心 $averageHeartRate');
    }
    if (averagePaceSecondsPerKm > 0) {
      items.add(averagePaceLabel);
    }
    if (plannedSetCount > 0) {
      items.add('组数 $completedSetCount/$plannedSetCount');
    }
    if (exerciseRecords.isNotEmpty) {
      items.add('动作 ${exerciseRecords.length} 项');
    }
    return items.join(' · ');
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'workoutDayId': workoutDayId,
      'date': date.toIso8601String(),
      'completed': completed,
      'rpe': rpe,
      'fatigueLevel': fatigueLevel,
      'sleepQuality': sleepQuality,
      'painNote': painNote,
      'userNote': userNote,
      'createdAt': createdAt.toIso8601String(),
      'logKind': kind.jsonValue,
      'actualDurationMinutes': actualDurationMinutes,
      'completionPercentage': completionPercentage,
      'averageHeartRate': averageHeartRate,
      'averagePaceSecondsPerKm': averagePaceSecondsPerKm,
      'plannedSetCount': plannedSetCount,
      'completedSetCount': completedSetCount,
      'interruptionReason': interruptionReason,
      'exerciseRecords': exerciseRecords
          .map((ExerciseExecutionRecord item) => item.toJson())
          .toList(),
    };
  }
}
