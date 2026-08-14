import 'growth_evidence.dart';

enum GrowthTimelineEntryType {
  training,
  health,
  checkIn,
  achievement,
  weeklyReport,
  race,
}

extension GrowthTimelineEntryTypeLabel on GrowthTimelineEntryType {
  String get label => switch (this) {
        GrowthTimelineEntryType.training => '训练',
        GrowthTimelineEntryType.health => '健康',
        GrowthTimelineEntryType.checkIn => '签到',
        GrowthTimelineEntryType.achievement => '成就',
        GrowthTimelineEntryType.weeklyReport => '周报',
        GrowthTimelineEntryType.race => '比赛',
      };
}

enum GrowthTimelineDestination {
  dailyCheckIn,
  weeklyReport,
  racePrep,
}

class GrowthTimelineEntry {
  const GrowthTimelineEntry({
    required this.id,
    required this.type,
    required this.occurredAt,
    required this.title,
    required this.description,
    required this.sourceLabel,
    this.xp = 0,
    this.isRevoked = false,
    this.evidenceEvent,
    this.destination,
  });

  final String id;
  final GrowthTimelineEntryType type;
  final DateTime occurredAt;
  final String title;
  final String description;
  final String sourceLabel;
  final int xp;
  final bool isRevoked;
  final GrowthEvidenceEvent? evidenceEvent;
  final GrowthTimelineDestination? destination;

  String get dateLabel {
    final String month = occurredAt.month.toString().padLeft(2, '0');
    final String day = occurredAt.day.toString().padLeft(2, '0');
    final String hour = occurredAt.hour.toString().padLeft(2, '0');
    final String minute = occurredAt.minute.toString().padLeft(2, '0');
    return '${occurredAt.year}-$month-$day $hour:$minute';
  }
}
