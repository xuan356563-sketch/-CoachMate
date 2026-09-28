import 'exercise_prescription.dart';

enum TrainingLogKind {
  manual('manual'),
  playerStep('playerStep'),
  sessionReview('sessionReview'),
  guidedWorkout('guidedWorkout'),
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

enum TrainingActivityType {
  strength('strength', '力量'),
  running('running', '跑步'),
  fastWalking('fast_walking', '快走'),
  hiking('hiking', '徒步'),
  cycling('cycling', '骑行'),
  swimming('swimming', '游泳'),
  rowing('rowing', '划船机'),
  elliptical('elliptical', '椭圆机'),
  stairClimbing('stair_climbing', '爬楼梯'),
  hiit('hiit', 'HIIT'),
  jumpRope('jump_rope', '跳绳'),
  boxing('boxing', '拳击'),
  basketball('basketball', '篮球'),
  badminton('badminton', '羽毛球'),
  football('football', '足球'),
  tennis('tennis', '网球'),
  tableTennis('table_tennis', '乒乓球'),
  climbing('climbing', '攀岩'),
  skiing('skiing', '滑雪'),
  dance('dance', '舞蹈'),
  yoga('yoga', '瑜伽'),
  pilates('pilates', '普拉提'),
  stretching('stretching', '拉伸'),
  custom('custom', '自定义');

  const TrainingActivityType(this.jsonValue, this.label);

  final String jsonValue;
  final String label;

  static TrainingActivityType? fromJson(String? value) {
    for (final TrainingActivityType item in TrainingActivityType.values) {
      if (item.jsonValue == value) return item;
    }
    return null;
  }
}

enum TrainingEnergySource {
  manual('manual'),
  healthKitConfirmed('health_kit_confirmed');

  const TrainingEnergySource(this.jsonValue);

  final String jsonValue;

  static TrainingEnergySource? fromJson(String? value) {
    for (final TrainingEnergySource item in TrainingEnergySource.values) {
      if (item.jsonValue == value) return item;
    }
    return null;
  }
}

enum SessionFeel {
  veryPoor('very_poor', '很差'),
  poor('poor', '偏差'),
  neutral('neutral', '正常'),
  good('good', '好'),
  veryGood('very_good', '很好');

  const SessionFeel(this.jsonValue, this.label);

  final String jsonValue;
  final String label;

  static SessionFeel? fromJson(String? value) {
    for (final SessionFeel item in SessionFeel.values) {
      if (item.jsonValue == value) return item;
    }
    return null;
  }
}

enum LandingQuality {
  stable('stable', '稳定'),
  wobbly('wobbly', '晃动'),
  pain('pain', '疼痛');

  const LandingQuality(this.jsonValue, this.label);

  final String jsonValue;
  final String label;

  static LandingQuality? fromJson(String? value) {
    for (final LandingQuality item in LandingQuality.values) {
      if (item.jsonValue == value) return item;
    }
    return null;
  }
}

class StrengthSetExecutionRecord {
  final int setIndex;
  final int repetitions;
  final double weightKg;
  final double? rpe;
  final int? durationSeconds;

  const StrengthSetExecutionRecord({
    required this.setIndex,
    required this.repetitions,
    required this.weightKg,
    this.rpe,
    this.durationSeconds,
  });

  factory StrengthSetExecutionRecord.fromJson(Map<String, dynamic> json) {
    final double? rawRpe = (json['rpe'] as num?)?.toDouble();
    final int? rawDuration = (json['durationSeconds'] as num?)?.toInt();
    return StrengthSetExecutionRecord(
      setIndex: ((json['setIndex'] as num?)?.toInt() ?? 1).clamp(1, 99).toInt(),
      repetitions:
          ((json['repetitions'] as num?)?.toInt() ?? 0).clamp(0, 999).toInt(),
      weightKg: ((json['weightKg'] as num?)?.toDouble() ?? 0)
          .clamp(0, 500)
          .toDouble(),
      rpe: rawRpe == null || rawRpe < 1 || rawRpe > 10 ? null : rawRpe,
      durationSeconds:
          rawDuration == null || rawDuration < 1 || rawDuration > 3600
              ? null
              : rawDuration,
    );
  }

  String get summary {
    final List<String> values = <String>[
      if (weightKg > 0) '${weightKg.toStringAsFixed(1)} kg',
      if (repetitions > 0) '$repetitions 次',
      if (rpe != null) 'RPE ${rpe!.toStringAsFixed(rpe! % 1 == 0 ? 0 : 1)}',
      if (durationSeconds != null) '$durationSeconds 秒',
    ];
    return values.isEmpty ? '已完成' : values.join(' × ');
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'setIndex': setIndex,
        'repetitions': repetitions,
        'weightKg': weightKg,
        'rpe': rpe,
        'durationSeconds': durationSeconds,
      };
}

class ExerciseExecutionRecord {
  final String? exerciseId;
  final String exerciseName;
  final int plannedSetCount;
  final int completedSetCount;
  final int repetitionsPerSet;
  final double weightKg;
  final List<StrengthSetExecutionRecord> sets;
  final LandingQuality? landingQuality;
  final ExerciseRepetitionUnit repetitionUnit;

  const ExerciseExecutionRecord({
    required this.exerciseId,
    required this.exerciseName,
    required this.plannedSetCount,
    required this.completedSetCount,
    required this.repetitionsPerSet,
    required this.weightKg,
    this.sets = const <StrengthSetExecutionRecord>[],
    this.landingQuality,
    this.repetitionUnit = ExerciseRepetitionUnit.total,
  });

  factory ExerciseExecutionRecord.fromJson(Map<String, dynamic> json) {
    final List<StrengthSetExecutionRecord> sets =
        (json['sets'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(StrengthSetExecutionRecord.fromJson)
            .toList(growable: false);
    final int legacyCompleted =
        ((json['completedSetCount'] as num?)?.toInt() ?? 0)
            .clamp(0, 99)
            .toInt();
    final double legacyWeight =
        ((json['weightKg'] as num?)?.toDouble() ?? 0).clamp(0, 500).toDouble();
    return ExerciseExecutionRecord(
      exerciseId: json['exerciseId'] as String?,
      exerciseName: json['exerciseName'] as String? ?? '未命名动作',
      plannedSetCount: ((json['plannedSetCount'] as num?)?.toInt() ?? 0)
          .clamp(0, 99)
          .toInt(),
      completedSetCount: sets.isEmpty ? legacyCompleted : sets.length,
      repetitionsPerSet: ((json['repetitionsPerSet'] as num?)?.toInt() ?? 0)
          .clamp(0, 999)
          .toInt(),
      weightKg: sets.isEmpty
          ? legacyWeight
          : sets.map((StrengthSetExecutionRecord item) => item.weightKg).reduce(
              (double first, double second) => first > second ? first : second),
      sets: List<StrengthSetExecutionRecord>.unmodifiable(sets),
      landingQuality:
          LandingQuality.fromJson(json['landingQuality'] as String?),
      repetitionUnit:
          exerciseRepetitionUnitFromJson(json['repetitionUnit'] as String?),
    );
  }

  String get setSummary {
    if (sets.isNotEmpty) {
      return sets
          .map(
            (StrengthSetExecutionRecord item) =>
                '第 ${item.setIndex} 组 ${item.summary}',
          )
          .join('；');
    }
    final String setLabel = plannedSetCount > 0
        ? '$completedSetCount/$plannedSetCount 组'
        : '$completedSetCount 组';
    final List<String> items = [setLabel];
    if (repetitionsPerSet > 0) {
      items.add(repetitionUnit == ExerciseRepetitionUnit.perSide
          ? '每侧 $repetitionsPerSet 次/组'
          : '$repetitionsPerSet 次/组');
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
      'sets': sets
          .map((StrengthSetExecutionRecord item) => item.toJson())
          .toList(growable: false),
      if (landingQuality != null) 'landingQuality': landingQuality!.jsonValue,
      if (repetitionUnit != ExerciseRepetitionUnit.total)
        'repetitionUnit': repetitionUnit.jsonValue,
    };
  }
}

class TrainingLog {
  final String id;
  final String workoutDayId;
  final String? planItemId;
  final DateTime date;
  final bool completed;
  final int rpe;
  final int fatigueLevel;
  final int sleepQuality;
  final String? painNote;
  final String? userNote;
  final DateTime createdAt;
  final TrainingLogKind kind;
  /// 本机恢复估算的来源校验；不改变旧记录展示或云端摘要字段。
  final bool recoveryEvidenceVerified;
  final int actualDurationMinutes;
  final double distanceKm;
  final int completionPercentage;
  final int averageHeartRate;
  final int averagePaceSecondsPerKm;
  final int plannedSetCount;
  final int completedSetCount;
  final String? interruptionReason;
  final bool downgradeAccepted;
  final bool abortedByUser;
  final List<ExerciseExecutionRecord> exerciseRecords;
  final SessionFeel? sessionFeel;
  final int? focusQuality;
  final TrainingActivityType? activityType;
  final String? customActivityName;
  final double? energyKcal;
  final TrainingEnergySource? energySource;
  final String? deviceWorkoutId;

  const TrainingLog({
    required this.id,
    required this.workoutDayId,
    this.planItemId,
    required this.date,
    required this.completed,
    required this.rpe,
    required this.fatigueLevel,
    required this.sleepQuality,
    required this.painNote,
    required this.userNote,
    required this.createdAt,
    this.kind = TrainingLogKind.manual,
    this.recoveryEvidenceVerified = true,
    this.actualDurationMinutes = 0,
    this.distanceKm = 0,
    this.completionPercentage = 0,
    this.averageHeartRate = 0,
    this.averagePaceSecondsPerKm = 0,
    this.plannedSetCount = 0,
    this.completedSetCount = 0,
    this.interruptionReason,
    this.downgradeAccepted = false,
    this.abortedByUser = false,
    this.exerciseRecords = const [],
    this.sessionFeel,
    this.focusQuality,
    this.activityType,
    this.customActivityName,
    this.energyKcal,
    this.energySource,
    this.deviceWorkoutId,
  });

  factory TrainingLog.fromJson(Map<String, dynamic> json) {
    final String? userNote = json['userNote'] as String?;
    final List<dynamic> exerciseRecordsJson =
        json['exerciseRecords'] as List<dynamic>? ?? [];
    final double? rawEnergyKcal = (json['energyKcal'] as num?)?.toDouble();
    final double? energyKcal = rawEnergyKcal == null ||
            !rawEnergyKcal.isFinite ||
            rawEnergyKcal < 0 ||
            rawEnergyKcal > 5000
        ? null
        : rawEnergyKcal;
    return TrainingLog(
      id: json['id'] as String? ?? '',
      workoutDayId: json['workoutDayId'] as String? ?? '',
      planItemId: json['planItemId'] as String?,
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
      recoveryEvidenceVerified: (json['recoveryEvidenceVerified'] == null ||
              json['recoveryEvidenceVerified'] == true) &&
          TrainingLogKind.values.any((kind) => kind.jsonValue == json['logKind']) &&
          json['rpe'] is num &&
          (json['rpe'] as num).isFinite &&
          json['rpe'] == (json['rpe'] as num).toInt(),
      actualDurationMinutes:
          ((json['actualDurationMinutes'] as num?)?.toInt() ?? 0)
              .clamp(0, 360)
              .toInt(),
      distanceKm: ((json['distanceKm'] as num?)?.toDouble() ?? 0)
          .clamp(0, 500)
          .toDouble(),
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
      downgradeAccepted: json['downgradeAccepted'] == true,
      abortedByUser: json['abortedByUser'] == true,
      sessionFeel: SessionFeel.fromJson(json['sessionFeel'] as String?),
      focusQuality: _optionalScaleValue(json['focusQuality'], max: 5),
      activityType:
          TrainingActivityType.fromJson(json['activityType'] as String?),
      customActivityName:
          _nullableTrimmedString(json['customActivityName'] as String?),
      energyKcal: energyKcal,
      energySource: energyKcal == null
          ? null
          : TrainingEnergySource.fromJson(json['energySource'] as String?),
      deviceWorkoutId:
          _nullableTrimmedString(json['deviceWorkoutId'] as String?),
      exerciseRecords: List<ExerciseExecutionRecord>.unmodifiable(
        exerciseRecordsJson
            .whereType<Map<String, dynamic>>()
            .map(ExerciseExecutionRecord.fromJson),
      ),
    );
  }

  bool get isSessionRecord => kind != TrainingLogKind.playerStep;

  bool get isSessionReview => kind == TrainingLogKind.sessionReview;

  /// 步骤默认值、导入推算 RPE 和没有实际执行的反馈不作为恢复证据。
  bool canEstimateRecoveryAt(DateTime now) =>
      recoveryEvidenceVerified &&
      isSessionRecord &&
      kind != TrainingLogKind.activityImport &&
      rpe >= 1 && rpe <= 10 &&
      (completed || actualDurationMinutes > 0 || completionPercentage > 0 ||
          completedSetCount > 0) &&
      date.millisecondsSinceEpoch > 0 &&
      !date.isAfter(now) &&
      !createdAt.isAfter(now) &&
      !createdAt.isBefore(date);

  /// 正式比赛成绩只能关联到一条已经完成且包含实际训练量的会话记录。
  bool get canConfirmOfficialRaceResult {
    return completed &&
        isSessionRecord &&
        !abortedByUser &&
        workoutDayId.trim().isNotEmpty &&
        (actualDurationMinutes > 0 || distanceKm > 0);
  }

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
      if (activityType != null)
        activityType == TrainingActivityType.custom &&
                (customActivityName?.isNotEmpty ?? false)
            ? customActivityName!
            : activityType!.label,
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
    if (distanceKm > 0) {
      items.add('${distanceKm.toStringAsFixed(2)} km');
    }
    if (energyKcal != null) {
      items.add('${energyKcal!.round()} 千卡');
    }
    if (plannedSetCount > 0) {
      items.add('组数 $completedSetCount/$plannedSetCount');
    }
    if (exerciseRecords.isNotEmpty) {
      items.add('动作 ${exerciseRecords.length} 项');
    }
    if (sessionFeel != null) {
      items.add('感受 ${sessionFeel!.label}');
    }
    if (focusQuality != null) {
      items.add('专注 $focusQuality/5');
    }
    return items.join(' · ');
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'workoutDayId': workoutDayId,
      'planItemId': planItemId,
      'date': date.toIso8601String(),
      'completed': completed,
      'rpe': rpe,
      'fatigueLevel': fatigueLevel,
      'sleepQuality': sleepQuality,
      'painNote': painNote,
      'userNote': userNote,
      'createdAt': createdAt.toIso8601String(),
      'logKind': kind.jsonValue,
      if (!recoveryEvidenceVerified) 'recoveryEvidenceVerified': false,
      'actualDurationMinutes': actualDurationMinutes,
      'distanceKm': distanceKm,
      'completionPercentage': completionPercentage,
      'averageHeartRate': averageHeartRate,
      'averagePaceSecondsPerKm': averagePaceSecondsPerKm,
      'plannedSetCount': plannedSetCount,
      'completedSetCount': completedSetCount,
      'interruptionReason': interruptionReason,
      'downgradeAccepted': downgradeAccepted,
      'abortedByUser': abortedByUser,
      'sessionFeel': sessionFeel?.jsonValue,
      'focusQuality': focusQuality,
      'activityType': activityType?.jsonValue,
      'customActivityName': customActivityName,
      'energyKcal': energyKcal,
      'energySource': energySource?.jsonValue,
      'deviceWorkoutId': deviceWorkoutId,
      'exerciseRecords': exerciseRecords
          .map((ExerciseExecutionRecord item) => item.toJson())
          .toList(),
    };
  }
}

String? _nullableTrimmedString(String? value) {
  final String normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

int? _optionalScaleValue(Object? value, {required int max}) {
  final int? parsed = (value as num?)?.toInt();
  if (parsed == null || parsed < 1 || parsed > max) return null;
  return parsed;
}
