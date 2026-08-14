import '../data/models/achievement.dart';
import '../data/models/daily_check_in_record.dart';
import '../data/models/growth_evidence.dart';
import '../data/models/growth_timeline.dart';
import '../data/models/race.dart';
import '../data/models/weekly_report.dart';

class GrowthTimelineService {
  List<GrowthTimelineEntry> build({
    required List<GrowthEvidenceEvent> evidenceEvents,
    required List<DailyCheckInRecord> checkIns,
    required List<AchievementRecord> achievements,
    required List<WeeklyReport> weeklyReports,
    required List<RacePlan> races,
    bool includeRevokedEvidence = false,
  }) {
    final Map<String, GrowthTimelineEntry> entries =
        <String, GrowthTimelineEntry>{};

    for (final GrowthEvidenceEvent event in evidenceEvents) {
      if (event.isRevoked && !includeRevokedEvidence) continue;
      final GrowthTimelineEntryType type =
          event.eventType == GrowthEventType.training
              ? GrowthTimelineEntryType.training
              : GrowthTimelineEntryType.health;
      _putLatest(
        entries,
        GrowthTimelineEntry(
          id: 'evidence:${event.eventId}',
          type: type,
          occurredAt: event.occurredAt,
          title: event.title,
          description: event.description,
          sourceLabel: '${event.sourceTable} · ${event.sourceId}',
          xp: event.rawXp,
          isRevoked: event.isRevoked,
          evidenceEvent: event,
        ),
      );
    }

    for (final DailyCheckInRecord record in checkIns) {
      _putLatest(
        entries,
        GrowthTimelineEntry(
          id: 'check-in:${record.id}',
          type: GrowthTimelineEntryType.checkIn,
          occurredAt: record.confirmedAt,
          title: record.continuityKind.label,
          description: record.continuityKind.description,
          sourceLabel: '每日主动确认 · ${record.source.label}',
          destination: GrowthTimelineDestination.dailyCheckIn,
        ),
      );
    }

    for (final AchievementRecord record in achievements) {
      _putLatest(
        entries,
        GrowthTimelineEntry(
          id: 'achievement:${record.id}',
          type: GrowthTimelineEntryType.achievement,
          occurredAt: record.unlockedAt,
          title: record.title,
          description: record.description,
          sourceLabel: record.sourceLabel,
        ),
      );
    }

    for (final WeeklyReport report in weeklyReports) {
      _putLatest(
        entries,
        GrowthTimelineEntry(
          id: 'weekly-report:${report.id}',
          type: GrowthTimelineEntryType.weeklyReport,
          occurredAt: report.generatedAt,
          title: '周报 · ${report.weekLabel}',
          description:
              '完成 ${report.completedWorkouts}/${report.plannedWorkouts} 次训练，完成率 ${report.completionRateLabel}。',
          sourceLabel: '已保存周报归档',
          destination: GrowthTimelineDestination.weeklyReport,
        ),
      );
    }

    for (final RacePlan race in races) {
      final OfficialRaceResult? result = race.officialRaceResult;
      if (result == null || !result.isActive) continue;
      _putLatest(
        entries,
        GrowthTimelineEntry(
          id: 'race:${race.id}:${result.trainingLogId}',
          type: GrowthTimelineEntryType.race,
          occurredAt: result.confirmedAt,
          title: '正式赛果 · ${race.name}',
          description: '${race.type.label} · ${result.durationLabel}',
          sourceLabel: '已关联训练事实 ${result.trainingLogId}',
          destination: GrowthTimelineDestination.racePrep,
        ),
      );
    }

    final List<GrowthTimelineEntry> result = entries.values.toList()
      ..sort((GrowthTimelineEntry first, GrowthTimelineEntry second) {
        final int byTime = second.occurredAt.compareTo(first.occurredAt);
        if (byTime != 0) return byTime;
        final int byType = first.type.index.compareTo(second.type.index);
        if (byType != 0) return byType;
        return first.id.compareTo(second.id);
      });
    return List<GrowthTimelineEntry>.unmodifiable(result);
  }

  void _putLatest(
    Map<String, GrowthTimelineEntry> entries,
    GrowthTimelineEntry candidate,
  ) {
    final GrowthTimelineEntry? existing = entries[candidate.id];
    if (existing == null || candidate.occurredAt.isAfter(existing.occurredAt)) {
      entries[candidate.id] = candidate;
    }
  }
}
