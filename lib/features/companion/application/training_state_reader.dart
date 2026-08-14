import 'package:trainflow_ai/data/models/body_data_quality.dart';
import 'package:trainflow_ai/data/models/pain_log.dart';
import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/data/models/training_schedule.dart';
import 'package:trainflow_ai/features/companion/domain/coach_contracts.dart';
import 'package:trainflow_ai/features/profile/application/training_schedule_controller.dart';

abstract interface class TrainingStateReader {
  TrainingStateSnapshotV1 readCurrent({
    required String athleteProfileId,
    required DateTime now,
  });
}

/// 从已加载的结构化仓储状态构造 Coach 快照。
///
/// 它不接受页面传入的 profile 或 snapshot，也不读取聊天文本。
class LocalTrainingStateReader implements TrainingStateReader {
  const LocalTrainingStateReader({
    required this.schedule,
    required this.trainingLogs,
    required this.painLogs,
    required this.bodyDataQuality,
  });

  final TrainingScheduleState schedule;
  final List<TrainingLog> trainingLogs;
  final List<PainLog> painLogs;
  final BodyDataQualityReport bodyDataQuality;

  @override
  TrainingStateSnapshotV1 readCurrent({
    required String athleteProfileId,
    required DateTime now,
  }) {
    if (athleteProfileId.trim().isEmpty) {
      throw ArgumentError.value(
          athleteProfileId, 'athleteProfileId', '运动员账号不能为空');
    }
    final DateTime localNow = now.toLocal();
    final DateTime startToday =
        DateTime(localNow.year, localNow.month, localNow.day);
    final DateTime startSevenDaysAgo =
        startToday.subtract(const Duration(days: 6));
    final ScheduledWorkout? planned = schedule.workoutFor(localNow);
    final List<TrainingLog> recentLogs = trainingLogs
        .where((TrainingLog item) =>
            !item.date.toLocal().isBefore(startSevenDaysAgo) &&
            item.date
                .toLocal()
                .isBefore(startToday.add(const Duration(days: 1))))
        .toList(growable: false);
    final List<PainLog> orderedPain = List<PainLog>.from(painLogs)
      ..sort((PainLog left, PainLog right) =>
          right.createdAt.compareTo(left.createdAt));
    final PainLog? latestPain = orderedPain.isEmpty ? null : orderedPain.first;
    final int latestPainAgeDays = latestPain == null
        ? 0
        : startToday
            .difference(DateTime(
              latestPain.date.year,
              latestPain.date.month,
              latestPain.date.day,
            ))
            .inDays;
    final bool painIsCurrent = latestPain != null &&
        (latestPainAgeDays <= 14 || latestPain.timing == PainTiming.ongoing);
    final int? maxPainScore = painIsCurrent ? latestPain.painLevel : null;
    final bool severePain = painIsCurrent &&
        (latestPain.painLevel >= 7 ||
            (latestPain.timing == PainTiming.ongoing &&
                latestPainAgeDays > 14));
    final List<CoachSourceRef> sources = <CoachSourceRef>[
      if (planned != null)
        CoachSourceRef(
          sourceKind: 'scheduled_workout',
          sourceLocalId: planned.id,
          sourceDigest: CoachDigest.sha256(planned.toJson()),
          observedAt: DateTime(
            planned.scheduledDate.year,
            planned.scheduledDate.month,
            planned.scheduledDate.day,
          ).add(Duration(minutes: planned.startMinute)),
          summaryKey: '今日既有计划',
        ),
      ...recentLogs.map(
        (TrainingLog item) => CoachSourceRef(
          sourceKind: 'training_log',
          sourceLocalId: item.id,
          sourceDigest: CoachDigest.sha256(<String, Object?>{
            'id': item.id,
            'date': item.date.toUtc().toIso8601String(),
            'completed': item.completed,
            'duration_minutes': item.actualDurationMinutes,
          }),
          observedAt: item.createdAt,
          summaryKey: '近七日训练记录',
        ),
      ),
      if (painIsCurrent)
        CoachSourceRef(
          sourceKind: 'pain_log',
          sourceLocalId: latestPain.id,
          sourceDigest: CoachDigest.sha256(<String, Object?>{
            'id': latestPain.id,
            'score': latestPain.painLevel,
            'timing': latestPain.timing.jsonValue,
            'date': latestPain.date.toUtc().toIso8601String(),
          }),
          observedAt: latestPain.createdAt,
          summaryKey: '最近一次疼痛记录',
        ),
    ];
    final CoachRecoveryBand recoveryBand = bodyDataQuality.issues.any(
      (BodyDataQualityIssue issue) =>
          issue.severity == BodyDataQualitySeverity.risk,
    )
        ? CoachRecoveryBand.red
        : bodyDataQuality.issues.any(
            (BodyDataQualityIssue issue) =>
                issue.severity == BodyDataQualitySeverity.warning,
          )
            ? CoachRecoveryBand.amber
            : CoachRecoveryBand.green;
    final DateTime sixHoursLater = now.add(const Duration(hours: 6));
    final DateTime nextLocalDay = startToday.add(const Duration(days: 1));
    final DateTime validUntil = sixHoursLater.toLocal().isBefore(nextLocalDay)
        ? sixHoursLater
        : nextLocalDay;
    final int completed =
        recentLogs.where((TrainingLog item) => item.completed).length;
    final int missed = _missedSessions(
      schedule: schedule,
      logs: trainingLogs,
      now: localNow,
    );
    final List<String> missing = <String>[
      if (planned == null) 'planned_action',
      if (sources.isEmpty) 'structured_sources',
    ];
    final List<String> qualityCodes = <String>[
      if (bodyDataQuality.issues.isEmpty) 'body_data_available',
      ...bodyDataQuality.issues.map(
        (BodyDataQualityIssue issue) => 'body_data_${issue.severity.name}',
      ),
    ];
    final String localDate = _localDate(localNow);
    final String sourceSeed = CoachDigest.sha256(<String, Object?>{
      'athlete_profile_id': athleteProfileId,
      'local_date': localDate,
      'sources': sources.map((CoachSourceRef item) => item.toJson()).toList(),
    });
    return TrainingStateSnapshotV1.create(
      snapshotId: 'coach-$localDate-${sourceSeed.substring(0, 16)}',
      athleteProfileId: athleteProfileId,
      generatedAt: now,
      validUntil: validUntil,
      localDate: localDate,
      timeZoneName:
          localNow.timeZoneName.isEmpty ? 'local' : localNow.timeZoneName,
      sourceRefs: sources,
      plannedActionId: planned == null ? null : 'follow-existing-plan',
      plannedDurationMinutes: planned?.allocatedMinutes,
      availableMinutes: planned?.allocatedMinutes,
      maxPainScore: maxPainScore,
      severePain: severePain,
      recoveryBand: recoveryBand,
      completedSessions7d: completed,
      missedSessions7d: missed,
      safetyFlags: <String>[
        if (severePain) 'severe_pain',
        if (painIsCurrent && (maxPainScore ?? 0) >= 4)
          'pain_requires_adjustment',
      ],
      qualityCodes: qualityCodes,
      missingFields: missing,
    );
  }
}

int _missedSessions({
  required TrainingScheduleState schedule,
  required List<TrainingLog> logs,
  required DateTime now,
}) {
  int missed = 0;
  for (int offset = 1; offset <= 7; offset += 1) {
    final DateTime day = DateTime(now.year, now.month, now.day - offset);
    if (schedule.workoutFor(day) == null) continue;
    final bool completed = logs.any(
      (TrainingLog item) =>
          item.completed && _sameDate(item.date.toLocal(), day),
    );
    if (!completed) missed += 1;
  }
  return missed;
}

bool _sameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String _localDate(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
