import '../../../data/models/training_log.dart';

enum TrainingRecordSource { planned, extra }

class TrainingRecordSaveRequest {
  const TrainingRecordSaveRequest({
    required this.source,
    required this.workoutDayId,
    required this.date,
    required this.activityType,
    required this.actualDurationMinutes,
    required this.completionPercentage,
    required this.rpe,
    this.planItemId,
    this.customActivityName,
    this.energyKcal,
    this.energySource,
    this.deviceWorkoutId,
    this.averageHeartRate = 0,
    this.averagePaceSecondsPerKm = 0,
    this.plannedSetCount = 0,
    this.completedSetCount = 0,
    this.exerciseRecords = const <ExerciseExecutionRecord>[],
    this.interruptionReason,
    this.userNote,
    this.abortedByUser = false,
    this.sessionFeel,
    this.focusQuality,
  });

  final TrainingRecordSource source;
  final String workoutDayId;
  final String? planItemId;
  final DateTime date;
  final TrainingActivityType activityType;
  final String? customActivityName;
  final int actualDurationMinutes;
  final int completionPercentage;
  final int rpe;
  final double? energyKcal;
  final TrainingEnergySource? energySource;
  final String? deviceWorkoutId;
  final int averageHeartRate;
  final int averagePaceSecondsPerKm;
  final int plannedSetCount;
  final int completedSetCount;
  final List<ExerciseExecutionRecord> exerciseRecords;
  final String? interruptionReason;
  final String? userNote;
  final bool abortedByUser;
  final SessionFeel? sessionFeel;
  final int? focusQuality;

  void validate() {
    if (workoutDayId.trim().isEmpty) {
      throw const FormatException('训练记录缺少训练标识。');
    }
    if (actualDurationMinutes < 5 || actualDurationMinutes > 360) {
      throw const FormatException('实际时长需在 5 到 360 分钟之间。');
    }
    if (completionPercentage < 0 || completionPercentage > 100) {
      throw const FormatException('完成度需在 0% 到 100% 之间。');
    }
    if (rpe < 1 || rpe > 10) {
      throw const FormatException('RPE 需在 1 到 10 之间。');
    }
    if (activityType == TrainingActivityType.custom &&
        (customActivityName?.trim().isEmpty ?? true)) {
      throw const FormatException('请输入自定义运动项目名称。');
    }
    if (energyKcal != null &&
        (!energyKcal!.isFinite || energyKcal! < 0 || energyKcal! > 5000)) {
      throw const FormatException('消耗热量需在 0 到 5000 千卡之间。');
    }
    if (energyKcal == null && energySource != null) {
      throw const FormatException('热量来源不能脱离已确认的热量数值。');
    }
    if (energyKcal != null && energySource == null) {
      throw const FormatException('请确认消耗热量的来源。');
    }
    if (averageHeartRate < 0 || averageHeartRate > 260) {
      throw const FormatException('平均心率需在 0 到 260 之间。');
    }
    if (averagePaceSecondsPerKm < 0 || averagePaceSecondsPerKm > 3600) {
      throw const FormatException('平均配速秒数需在 0 到 3600 之间。');
    }
    if (plannedSetCount < 0 || plannedSetCount > 99) {
      throw const FormatException('计划组数需在 0 到 99 之间。');
    }
    if (completedSetCount < 0 || completedSetCount > plannedSetCount) {
      throw const FormatException('完成组数不能超过计划组数。');
    }
    for (final ExerciseExecutionRecord exercise in exerciseRecords) {
      _validateExercise(exercise);
    }
    if (focusQuality != null && (focusQuality! < 1 || focusQuality! > 5)) {
      throw const FormatException('专注度需在 1 到 5 之间。');
    }
  }
}

void _validateExercise(ExerciseExecutionRecord exercise) {
  if (exercise.exerciseName.trim().isEmpty) {
    throw const FormatException('动作名称不能为空。');
  }
  if (exercise.plannedSetCount < 0 || exercise.plannedSetCount > 99) {
    throw FormatException('${exercise.exerciseName}的计划组数需在 0 到 99 之间。');
  }
  if (exercise.completedSetCount < 0 || exercise.completedSetCount > 99) {
    throw FormatException('${exercise.exerciseName}的完成组数需在 0 到 99 之间。');
  }
  if (exercise.plannedSetCount > 0 &&
      exercise.completedSetCount > exercise.plannedSetCount) {
    throw FormatException('${exercise.exerciseName}的完成组数不能超过计划组数。');
  }
  if (exercise.repetitionsPerSet < 0 || exercise.repetitionsPerSet > 999) {
    throw FormatException('${exercise.exerciseName}的次数需在 0 到 999 之间。');
  }
  if (!exercise.weightKg.isFinite ||
      exercise.weightKg < 0 ||
      exercise.weightKg > 500) {
    throw FormatException('${exercise.exerciseName}的重量需在 0 到 500 kg 之间。');
  }
  for (final StrengthSetExecutionRecord set in exercise.sets) {
    if (set.repetitions < 0 || set.repetitions > 999) {
      throw FormatException(
        '${exercise.exerciseName}第 ${set.setIndex} 组次数需在 0 到 999 之间。',
      );
    }
    if (!set.weightKg.isFinite || set.weightKg < 0 || set.weightKg > 500) {
      throw FormatException(
        '${exercise.exerciseName}第 ${set.setIndex} 组重量需在 0 到 500 kg 之间。',
      );
    }
    if (set.rpe != null && (set.rpe! < 1 || set.rpe! > 10)) {
      throw FormatException(
        '${exercise.exerciseName}第 ${set.setIndex} 组 RPE 需在 1 到 10 之间。',
      );
    }
    if (set.durationSeconds != null &&
        (set.durationSeconds! < 1 || set.durationSeconds! > 3600)) {
      throw FormatException(
        '${exercise.exerciseName}第 ${set.setIndex} 组用时需在 1 到 3600 秒之间。',
      );
    }
  }
}
