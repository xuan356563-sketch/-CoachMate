import 'workout_day.dart';
import 'training_metrics.dart';

enum TrainingTimePeriod { morning, midday, evening, lateNight }

extension TrainingTimePeriodLabel on TrainingTimePeriod {
  String get label => switch (this) {
        TrainingTimePeriod.morning => '早晨',
        TrainingTimePeriod.midday => '午间',
        TrainingTimePeriod.evening => '晚间',
        TrainingTimePeriod.lateNight => '深夜',
      };
}

enum ScheduledWorkoutVersion { full, compact, recovery }

extension ScheduledWorkoutVersionLabel on ScheduledWorkoutVersion {
  String get label => switch (this) {
        ScheduledWorkoutVersion.full => '完整版',
        ScheduledWorkoutVersion.compact => '压缩版',
        ScheduledWorkoutVersion.recovery => '恢复版',
      };
}

class TrainingAvailabilitySlot {
  final String id;
  final DateTime date;
  final int startMinute;
  final int endMinute;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TrainingAvailabilitySlot({
    required this.id,
    required this.date,
    required this.startMinute,
    required this.endMinute,
    required this.createdAt,
    required this.updatedAt,
  });

  int get durationMinutes => endMinute - startMinute;
  String get timeLabel =>
      '${_minuteLabel(startMinute)}-${_minuteLabel(endMinute)}';
  TrainingTimePeriod get period => trainingTimePeriodFor(startMinute);

  factory TrainingAvailabilitySlot.fromJson(Map<String, dynamic> json) {
    return TrainingAvailabilitySlot(
      id: json['id'] as String? ?? '',
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime(2026),
      startMinute: (json['startMinute'] as num?)?.toInt() ?? 0,
      endMinute: (json['endMinute'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': _dateOnly(date).toIso8601String(),
        'startMinute': startMinute,
        'endMinute': endMinute,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}

class ScheduledWorkout {
  final String id;
  final String workoutDayId;
  final DateTime scheduledDate;
  final int startMinute;
  final int allocatedMinutes;
  final TrainingTimePeriod period;
  final ScheduledWorkoutVersion version;
  final WorkoutDiscipline? discipline;
  final CompletionTargetKind? primaryTargetKind;
  final int? targetMinutes;

  const ScheduledWorkout({
    required this.id,
    required this.workoutDayId,
    required this.scheduledDate,
    required this.startMinute,
    required this.allocatedMinutes,
    required this.period,
    required this.version,
    this.discipline,
    this.primaryTargetKind,
    this.targetMinutes,
  });

  String get timeLabel => _minuteLabel(startMinute);

  factory ScheduledWorkout.fromJson(Map<String, dynamic> json) {
    return ScheduledWorkout(
      id: json['id'] as String? ?? '',
      workoutDayId: json['workoutDayId'] as String? ?? '',
      scheduledDate:
          DateTime.tryParse(json['scheduledDate'] as String? ?? '') ??
              DateTime(2026),
      startMinute: (json['startMinute'] as num?)?.toInt() ?? 0,
      allocatedMinutes: (json['allocatedMinutes'] as num?)?.toInt() ?? 0,
      period: TrainingTimePeriod.values.firstWhere(
        (TrainingTimePeriod value) => value.name == json['period'],
        orElse: () => TrainingTimePeriod.evening,
      ),
      version: ScheduledWorkoutVersion.values.firstWhere(
        (ScheduledWorkoutVersion value) => value.name == json['version'],
        orElse: () => ScheduledWorkoutVersion.full,
      ),
      discipline: _workoutDisciplineFromJson(json['discipline']),
      primaryTargetKind:
          _completionTargetKindFromJson(json['primaryTargetKind']),
      targetMinutes: (json['targetMinutes'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'workoutDayId': workoutDayId,
        'scheduledDate': _dateOnly(scheduledDate).toIso8601String(),
        'startMinute': startMinute,
        'allocatedMinutes': allocatedMinutes,
        'period': period.name,
        'version': version.name,
        'discipline': discipline?.name,
        'primaryTargetKind': primaryTargetKind?.name,
        'targetMinutes': targetMinutes,
      };
}

WorkoutDiscipline? _workoutDisciplineFromJson(Object? value) {
  if (value is! String) return null;
  for (final WorkoutDiscipline discipline in WorkoutDiscipline.values) {
    if (discipline.name == value) return discipline;
  }
  return null;
}

CompletionTargetKind? _completionTargetKindFromJson(Object? value) {
  if (value is! String) return null;
  for (final CompletionTargetKind kind in CompletionTargetKind.values) {
    if (kind.name == value) return kind;
  }
  return null;
}

TrainingTimePeriod trainingTimePeriodFor(int startMinute) {
  if (startMinute >= 5 * 60 && startMinute < 11 * 60) {
    return TrainingTimePeriod.morning;
  }
  if (startMinute >= 11 * 60 && startMinute < 16 * 60) {
    return TrainingTimePeriod.midday;
  }
  if (startMinute >= 16 * 60 && startMinute < 21 * 60) {
    return TrainingTimePeriod.evening;
  }
  return TrainingTimePeriod.lateNight;
}

WorkoutDay applyScheduledWorkout(
  WorkoutDay workout,
  ScheduledWorkout scheduled,
) {
  if (scheduled.version == ScheduledWorkoutVersion.full) {
    return workout.copyWith(estimatedMinutes: scheduled.allocatedMinutes);
  }
  final List<String> mainSets = workout.mainSets.isEmpty
      ? const <String>[]
      : workout.mainSets
          .take(scheduled.version == ScheduledWorkoutVersion.recovery ? 1 : 2)
          .toList();
  return workout.copyWith(
    title: '${workout.title} · ${scheduled.version.label}',
    decisionType: scheduled.version == ScheduledWorkoutVersion.recovery
        ? TrainingDecisionType.recovery
        : workout.decisionType,
    estimatedMinutes: scheduled.allocatedMinutes,
    intensity: scheduled.version == ScheduledWorkoutVersion.recovery
        ? 'RPE 2-3'
        : workout.intensity,
    mainSets: mainSets,
    accessoryWork: const <String>[],
    coachNotes:
        '${workout.coachNotes}\n已根据${scheduled.period.label} ${scheduled.timeLabel} 的可用时间调整为${scheduled.version.label}。',
  );
}

String _minuteLabel(int minute) {
  final int safeMinute = minute.clamp(0, 24 * 60).toInt();
  final int hour = safeMinute ~/ 60;
  final int value = safeMinute % 60;
  return '${hour.toString().padLeft(2, '0')}:${value.toString().padLeft(2, '0')}';
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
